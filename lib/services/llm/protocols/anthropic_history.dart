import 'dart:convert';

import '../image_compression.dart';
import '../llm_types.dart';
import 'anthropic_wire.dart';

/// The `system` prompt and `messages[]` of an Anthropic request, separated.
class AnthropicHistory {
  /// Hoisted out of [messages]: ④ has no system *role*, only a top-level
  /// field. Null when the conversation carries no system prompt.
  final String? system;
  final List<Map<String, dynamic>> messages;

  const AnthropicHistory(this.system, this.messages);
}

/// The label put in front of author text that joins a user message already
/// carrying `tool_result` blocks — see [buildAnthropicHistory].
const String anthropicAuthorTextLabel = '[User message]';

/// Text that already opens with a bracketed tag (`[view_image result] …`)
/// names its own source and needs no label.
final RegExp _selfDescribingText = RegExp(r'^\[[^\]\n]{1,60}\]');

/// [blocks] with [anthropicAuthorTextLabel] in front of the first text block,
/// unless there is none or it already describes itself. Copies rather than
/// mutates: the blocks may be the caller's.
List<Map<String, dynamic>> _labelAuthorText(List<Map<String, dynamic>> blocks) {
  final i = blocks.indexWhere((b) => b['type'] == 'text');
  if (i == -1) return blocks;
  final text = blocks[i]['text'];
  if (text is! String || _selfDescribingText.hasMatch(text)) return blocks;
  return [
    ...blocks.sublist(0, i),
    {...blocks[i], 'text': '$anthropicAuthorTextLabel\n$text'},
    ...blocks.sublist(i + 1),
  ];
}

/// Converts the app's flat message list into ④'s shape.
///
/// Three rewrites happen here, each of which is a 400 from the API if skipped:
///
///  * **system is hoisted.** `{"role": "system"}` is not a thing in ④.
///    Several system turns are joined rather than dropped.
///  * **tool results become user turns.** ④ has no tool role; a result is a
///    `tool_result` block inside a normal user message.
///  * **consecutive same-role turns are merged.** ④ requires the roles to
///    alternate. This matters most for an agent loop: a batch of parallel
///    tool calls arrives as N tool messages, and all N results have to travel
///    in *one* user message immediately after the assistant turn that asked
///    for them.
///
/// The merge has a cost of its own: the user's words and the tools' output
/// both live in `role: "user"`, so a "continue" typed after a stop mid-batch
/// lands in the envelope the model reads as tool output — and is replayed on
/// every later turn as if it were a standing instruction. Author text that
/// joins a message already carrying `tool_result` blocks is therefore
/// labelled [anthropicAuthorTextLabel] (protocol 02 §2.1 rule 4, pitfalls 11
/// §21). A message that already names itself (the assistant's
/// `[view_image result]` note) is left alone.
AnthropicHistory buildAnthropicHistory(List<LLMMessage> history, {String? modelId}) {
  final systemParts = <String>[];
  final messages = <Map<String, dynamic>>[];

  void append(String role, List<Map<String, dynamic>> blocks) {
    // An empty content array is rejected too, so a turn that produced no
    // blocks (an assistant message with neither text nor tool calls) is
    // simply not sent.
    if (blocks.isEmpty) return;
    if (messages.isNotEmpty && messages.last['role'] == role) {
      final existing = messages.last['content'] as List;
      // Only the tool branch appends `tool_result` blocks, and those carry no
      // text — so the label can only ever land on author text.
      final joinsResults =
          role == 'user' && existing.any((b) => b is Map && b['type'] == 'tool_result');
      existing.addAll(joinsResults ? _labelAuthorText(blocks) : blocks);
      return;
    }
    messages.add({'role': role, 'content': blocks});
  }

  for (final msg in history) {
    if (msg.role == LLMRole.system) {
      if (msg.content.isNotEmpty) systemParts.add(msg.content);
      continue;
    }

    if (msg.role == LLMRole.tool) {
      append('user', [
        {
          'type': 'tool_result',
          'tool_use_id': msg.toolCallId ?? '',
          // A text block may not be empty, and a tool legitimately returning
          // nothing is not an error — say so instead of sending "".
          'content': msg.content.isEmpty ? '(no output)' : msg.content,
        },
      ]);
      continue;
    }

    if (msg.role == LLMRole.assistant) {
      // A server-tool turn is replayed whole, exactly as it arrived: the
      // result blocks carry an `encrypted_content` the API decrypts to
      // recover what the model read (modified or missing → 400), and a
      // `pause_turn` continuation is defined as "send the assistant message
      // back unchanged". Rebuilding from text + tool calls, as below, would
      // drop the search blocks and with them the search. Model-scoped like
      // the thinking blocks: another model ignores them and bills them.
      final rawContent = msg.rawContentBlocks;
      if (rawContent != null &&
          rawContent.isNotEmpty &&
          (modelId == null || msg.rawThinkingModelId == modelId)) {
        // Shallow copies, so a cache breakpoint stamped on the last block
        // later does not write into the persisted history.
        append('assistant', [for (final block in rawContent) Map<String, dynamic>.of(block)]);
        continue;
      }

      final blocks = <Map<String, dynamic>>[];
      // Thinking goes back first, verbatim when the raw blocks were captured
      // (thinking + redacted_thinking, original order and content — the only
      // history ④ accepts as complete). Replay is model-scoped: blocks from
      // a different model are not rejected upstream, they are silently
      // ignored and still billed as input, so a mismatch drops the group.
      final rawBlocks = msg.rawThinkingBlocks;
      if (rawBlocks != null && rawBlocks.isNotEmpty) {
        if (modelId == null || msg.rawThinkingModelId == modelId) {
          blocks.addAll(rawBlocks);
        }
      } else if (msg.reasoningContent != null &&
          msg.reasoningSignature != null &&
          (modelId == null ||
              msg.rawThinkingModelId == null ||
              msg.rawThinkingModelId == modelId)) {
        // Legacy path (histories persisted before raw-block capture): a
        // sealed thinking block reconstructed from the display fields —
        // model-scoped like the raw blocks, except that a turn with no
        // recorded producer (the truly old ones) is still replayed. With
        // thinking on, ④ rejects a replayed tool-calling turn whose thinking
        // block is missing or unsigned — and it must precede the text and
        // tool_use blocks it led to. An unsigned one is dropped rather than
        // sent: the API would refuse it anyway, and a refused request is
        // worse than a turn the model has to re-derive.
        blocks.add({
          'type': 'thinking',
          'thinking': msg.reasoningContent,
          'signature': msg.reasoningSignature,
        });
      }
      if (msg.content.isNotEmpty) {
        blocks.add({'type': 'text', 'text': msg.content});
      }
      for (final call in msg.toolCalls) {
        blocks.add({'type': 'tool_use', 'id': call.id, 'name': call.name, 'input': call.arguments});
      }
      append('assistant', blocks);
      continue;
    }

    append('user', anthropicUserBlocks(msg));
  }

  return AnthropicHistory(systemParts.isEmpty ? null : systemParts.join('\n\n'), messages);
}

/// Text + image blocks of one user turn.
List<Map<String, dynamic>> anthropicUserBlocks(LLMMessage msg) {
  final blocks = <Map<String, dynamic>>[];
  if (msg.content.isNotEmpty) {
    blocks.add({'type': 'text', 'text': msg.content});
  }
  for (final attachment in msg.attachments) {
    if (attachment.path == null && attachment.bytes == null) continue;
    final read = ImageCompressor.readForApi(attachment);
    final resolved = ImageCompressor.coerceMediaType(
      read.bytes,
      read.mimeType,
      anthropicImageMediaTypes,
    );
    blocks.add({
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': resolved.mimeType,
        'data': base64Encode(resolved.bytes),
      },
    });
  }
  return blocks;
}
