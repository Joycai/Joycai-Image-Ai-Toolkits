import 'dart:typed_data';

import 'llm_types.dart';
import 'protocols/anthropic_chat_protocol.dart'
    show anthropicPauseFinishReason, anthropicTurnIncompleteKey;

/// Continuing a turn the host stopped in the middle.
///
/// "One request = one complete answer" does not hold once a server-side tool
/// is in play. The host may run the search, hand the results back and stop
/// there, and it says so in one of two ways — only one of them out loud:
///
///  * **`stop_reason: pause_turn`** (official ④). The protocol publishes it
///    as `finish_reason: pause`. The remedy is the API's own: send the
///    assistant message back *unchanged* and ask again; the model picks up
///    the same turn.
///  * **`end_turn` on a result block with no text after it** (MiniMax's ④
///    face, observed live). No field says anything is missing; the protocol
///    flags the shape as `turn_incomplete`. The remedy cannot be the same,
///    because that host rejects its own `server_tool_use` blocks when they
///    come back (`tool result's tool id … not found`) — so the results are
///    rendered as plain text and sent as a user turn, and the model is asked
///    to go on from there. The citation machinery is lost; the answer is not.
///
/// Pure and IO-free so the two rules can be pinned without a socket. The
/// service applies them: [continuationFor] says what to append to the
/// history before asking again, [mergeTurnParts] folds the partial replies
/// into the one the caller sees.

/// How many times a single request may be continued before the partial
/// answer is handed back as-is. Each continuation is a billed request; a
/// host that pauses forever must not be followed forever.
const int maxTurnContinuations = 3;

/// The history entries to append before asking the host to continue
/// [response], or null when [response] is a finished turn.
///
/// [modelId] scopes the verbatim replay: the payload builder drops a raw
/// content group whose producer does not match the model it is sent to.
List<LLMMessage>? continuationFor(LLMResponse response, String modelId) {
  final metadata = response.metadata;
  final paused = metadata['finish_reason'] == anthropicPauseFinishReason;
  final incomplete = metadata[anthropicTurnIncompleteKey] == true;
  if (!paused && !incomplete) return null;

  final raw = response.rawContentBlocks;
  if (paused && raw != null && raw.isNotEmpty) {
    // The API's own continuation: the assistant message, unchanged.
    return [
      LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
        reasoningContent: response.reasoningContent,
        reasoningSignature: response.reasoningSignature,
        rawThinkingBlocks: response.rawThinkingBlocks,
        rawThinkingModelId: modelId,
        rawContentBlocks: raw,
      ),
    ];
  }

  // The plain-text fallback: what the model said so far as its turn, what
  // the host found as ours. Also the path for a `pause` whose blocks were
  // somehow not captured — a text continuation beats no continuation.
  return [
    if (response.text.trim().isNotEmpty)
      LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
        reasoningContent: response.reasoningContent,
        reasoningSignature: response.reasoningSignature,
        rawThinkingBlocks: response.rawThinkingBlocks,
        rawThinkingModelId: response.rawThinkingModelId,
      ),
    LLMMessage(
      role: LLMRole.user,
      content: renderServerToolRuns(metadata['server_tool_runs']),
    ),
  ];
}

/// The `server_tool_runs` metadata as a user-facing text block: one section
/// per search with its query and its sources, then the instruction to
/// continue. Plain text on purpose — it has to be accepted by a host that
/// does not accept its own search blocks back.
String renderServerToolRuns(Object? runs) {
  final buffer = StringBuffer();
  if (runs is List) {
    for (final run in runs) {
      if (run is! Map) continue;
      final name = run['name']?.toString() ?? 'web_search';
      final query = run['query']?.toString() ?? '';
      buffer.writeln('[$name${query.isEmpty ? '' : ': "$query"'}]');
      final error = run['error'];
      if (error != null) {
        buffer.writeln('  (failed: $error)');
      }
      final sources = run['sources'];
      if (sources is List) {
        if (sources.isEmpty && error == null) buffer.writeln('  (no results)');
        for (final source in sources) {
          if (source is! Map) continue;
          final title = source['title']?.toString() ?? '';
          final url = source['url']?.toString() ?? '';
          buffer.writeln('  - ${title.isEmpty ? url : '$title — $url'}');
        }
      }
    }
  }
  if (buffer.isEmpty) buffer.writeln('[the search returned nothing]');
  buffer.write(
    'The search above was run by the server as part of your turn. '
    'Continue your answer from here; do not repeat what you already said.',
  );
  return buffer.toString();
}

/// One response out of a turn that took several requests: the texts joined
/// as paragraphs, the tool calls and replay carriers of the *last* part (a
/// paused part has none — it stopped at a search), usage summed, and the
/// content arrays concatenated so the whole turn replays as one assistant
/// message next time.
LLMResponse mergeTurnParts(List<LLMResponse> parts) {
  if (parts.length == 1) return parts.single;
  final last = parts.last;

  final text = parts
      .map((p) => p.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n\n');
  final reasoning = parts
      .map((p) => p.reasoningContent?.trim() ?? '')
      .where((t) => t.isNotEmpty)
      .join('\n\n');
  final images = <Uint8List>[for (final p in parts) ...p.generatedImages];

  final rawContent = <Map<String, dynamic>>[];
  var anyRawContent = false;
  for (final p in parts) {
    final blocks = p.rawContentBlocks;
    if (blocks != null && blocks.isNotEmpty) {
      anyRawContent = true;
      rawContent.addAll(blocks);
    }
  }
  final rawThinking = <Map<String, dynamic>>[];
  for (final p in parts) {
    final blocks = p.rawThinkingBlocks;
    if (blocks != null) rawThinking.addAll(blocks);
  }

  return LLMResponse(
    text: text,
    generatedImages: images,
    videoUri: last.videoUri,
    operationName: last.operationName,
    metadata: _mergeUsage(parts.map((p) => p.metadata).toList()),
    reasoningContent: reasoning.isEmpty ? null : reasoning,
    reasoningFieldName: last.reasoningFieldName,
    reasoningSignature: last.reasoningSignature,
    rawThinkingBlocks: rawThinking.isEmpty ? null : rawThinking,
    rawThinkingModelId: last.rawThinkingModelId,
    rawContentBlocks: anyRawContent ? rawContent : null,
    toolCalls: last.toolCalls,
  );
}

/// The last part's metadata with every token counter replaced by the sum
/// across parts, and the server-tool runs of every part concatenated. The
/// pause/incomplete markers come from the last part alone — it is the one
/// that finished.
Map<String, dynamic> _mergeUsage(List<Map<String, dynamic>> all) {
  const counters = {
    'input_tokens',
    'output_tokens',
    'prompt_tokens',
    'completion_tokens',
    'cache_read_input_tokens',
    'cache_creation_input_tokens',
    'total_tokens',
  };
  final merged = Map<String, dynamic>.of(all.last);
  for (final key in counters) {
    var sum = 0;
    var seen = false;
    for (final m in all) {
      final v = m[key];
      if (v is num) {
        sum += v.toInt();
        seen = true;
      }
    }
    if (seen) merged[key] = sum;
  }
  final runs = [
    for (final m in all)
      if (m['server_tool_runs'] is List) ...(m['server_tool_runs'] as List),
  ];
  if (runs.isNotEmpty) merged['server_tool_runs'] = runs;
  merged['continuations'] = all.length - 1;
  return merged;
}
