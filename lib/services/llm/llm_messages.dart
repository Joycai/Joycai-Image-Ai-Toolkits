import 'dart:io';

import 'package:flutter/foundation.dart';

enum LLMRole { system, user, assistant, tool }

enum LLMReferenceType {
  media,
  asset,
  firstFrame,
  lastFrame,

  /// The model only looks at this attachment to describe it in text — it is
  /// never fed into image generation/editing. Eligible for lossy
  /// recompression when oversized; see [ImageCompressor].
  viewOnly,
}

class LLMAttachment {
  final String? path;
  final Uint8List? bytes;
  final String mimeType;
  final LLMReferenceType referenceType;

  LLMAttachment.fromFile(File file, this.mimeType, {this.referenceType = LLMReferenceType.media})
    : path = file.path,
      bytes = null;
  LLMAttachment.fromBytes(this.bytes, this.mimeType, {this.referenceType = LLMReferenceType.media})
    : path = null;

  /// Persistence: only file-backed attachments are serialized (bytes are
  /// intentionally not stored — the file is re-read on demand at replay time).
  Map<String, dynamic>? toJson() =>
      path == null ? null : {'path': path, 'mime': mimeType, 'ref': referenceType.name};

  static LLMAttachment? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null) return null;
    return LLMAttachment.fromFile(
      File(path),
      json['mime'] as String? ?? 'image/jpeg',
      referenceType: LLMReferenceType.values.asNameMap()[json['ref']] ?? LLMReferenceType.media,
    );
  }
}

/// A tool (function) the model is allowed to call.
///
/// [parameters] is a JSON-Schema object describing the arguments, e.g.
/// `{"type": "object", "properties": {...}, "required": [...]}`.
class LLMTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  LLMTool({required this.name, required this.description, required this.parameters});
}

/// A tool invocation emitted by the model.
class LLMToolCall {
  /// Provider-assigned call id (OpenAI). Synthesized for providers that don't
  /// supply one (Google).
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// Gemini thought signature attached to the functionCall part. Must be
  /// echoed back verbatim when the call is replayed into history, or the API
  /// rejects the request with INVALID_ARGUMENT.
  final String? thoughtSignature;

  LLMToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.thoughtSignature,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    // Gemini rejects replayed histories whose thought signatures are
    // missing, so it must round-trip through persistence.
    if (thoughtSignature != null) 'thoughtSignature': thoughtSignature,
  };

  factory LLMToolCall.fromJson(Map<String, dynamic> json) => LLMToolCall(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? {},
    thoughtSignature: json['thoughtSignature'] as String?,
  );
}

class LLMMessage {
  final LLMRole role;
  final String content;
  final List<LLMAttachment> attachments;

  /// Chain-of-thought text carried by an assistant message, for OpenAI-family
  /// vendors that expose one (DeepSeek's `reasoning_content`, OpenRouter's
  /// `reasoning`, or an inline `<think>…</think>` span some relays emit).
  ///
  /// DeepSeek rejects a tool-calling conversation with 400 when the reasoning
  /// of a tool-call-bearing assistant turn is not replayed, so this must
  /// round-trip through history and persistence — the ① family sibling of
  /// [LLMToolCall.thoughtSignature].
  final String? reasoningContent;

  /// The wire field name [reasoningContent] arrived under
  /// (`reasoning_content` / `reasoning`), or null when it was extracted from
  /// an inline `<think>` span or absent. Echo-back uses this exact name —
  /// "return it under the name you received it" survives vendors the app has
  /// never heard of, unlike hardcoding one spelling. Inline reasoning carries
  /// no echo obligation and is never sent back.
  final String? reasoningFieldName;

  /// ④'s cryptographic seal over [reasoningContent], present only on the
  /// Anthropic Messages surface.
  ///
  /// Where ① echoes reasoning as a *field* named by [reasoningFieldName], ④
  /// echoes it as a whole `thinking` **block**, and the API verifies this
  /// signature before accepting it. A tool-calling turn produced with thinking
  /// on is rejected when its thinking block is missing or unsealed — the ④
  /// sibling of [LLMToolCall.thoughtSignature] and of ①'s echo-back rule.
  ///
  /// Its presence is also what marks reasoning as ④-shaped: [reasoningFieldName]
  /// stays null there, so the ① payload builder never invents a field for it.
  final String? reasoningSignature;

  /// ④'s thinking-class blocks **verbatim** (sealed `thinking` +
  /// `redacted_thinking`, original order), for replay into a tool-calling
  /// conversation. [reasoningContent]/[reasoningSignature] stay the display
  /// carriers; this exists because a redacted block has no text to
  /// reconstruct from, and ④ answers an incomplete thinking history by
  /// *silently disabling thinking* (while billing it) rather than erroring.
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// The model that produced this turn's replay carriers: [rawThinkingBlocks]
  /// and [rawContentBlocks] (④), the reasoning field named by
  /// [reasoningFieldName] (① / DashScope native), and the
  /// [LLMToolCall.thoughtSignature]s of [toolCalls] (③).
  ///
  /// Replay is model-scoped (reasoning 03 §5 rule 2): another model silently
  /// ignores foreign ④ blocks and still bills them as input, official OpenAI
  /// 400s an unknown `reasoning_content`, and a relay bills it — so every
  /// payload builder drops the carrier on mismatch. ④'s raw blocks require a
  /// match; the other carriers are still echoed when this is null, which is
  /// how sessions persisted before it was recorded keep working.
  final String? rawThinkingModelId;

  /// ④'s **entire** `content` array of this assistant turn, verbatim, when
  /// the turn contained a server-side tool run (`server_tool_use` +
  /// `web_search_tool_result`). Null for every other turn.
  ///
  /// A server-tool turn cannot be rebuilt from [content] + [toolCalls]: the
  /// search blocks carry an `encrypted_content` the API decrypts to recover
  /// what the model read, and the protocol's `pause_turn` continuation is
  /// "send the assistant message back *unchanged*". So the whole array is
  /// kept and the payload builder replays it as-is — the ④ counterpart of
  /// [rawThinkingBlocks], and scoped by [rawThinkingModelId] the same way.
  final List<Map<String, dynamic>>? rawContentBlocks;

  /// ③'s `parts` array of this model turn **verbatim** — thought parts,
  /// every `thoughtSignature` (including one riding an empty text part at the
  /// end of a stream), original order — kept only for a turn that called
  /// tools. Null for every other turn.
  ///
  /// Rebuilding a ③ turn from [content] + [toolCalls] keeps only the
  /// signatures that sat on a `functionCall` part and drops the rest, and ③
  /// answers an incomplete history with `finishReason:
  /// MISSING_THOUGHT_SIGNATURE` — neither a 400 nor a silent downgrade
  /// (protocol 02 §2.2 rule 3, reasoning 03 §5). Replayed verbatim only to
  /// the model named by [rawThinkingModelId]; any other model gets the
  /// rebuild, without signatures. Dropped (with [rawContentBlocks]) wherever
  /// history rewrites a turn's tool-call arguments, because the verbatim copy
  /// would re-send what the rewrite removed.
  final List<Map<String, dynamic>>? rawModelParts;

  /// The Responses API's output **items** of this turn verbatim — `reasoning`
  /// (with its `encrypted_content`), `message` and `function_call`, in
  /// output order — kept only for a turn that called tools. Null for every
  /// other turn.
  ///
  /// Under `store: false` the next request's `input` is the history plus
  /// these items plus the `function_call_output`s (protocol 02 §7.3). A
  /// replay that rebuilds bare `function_call`s instead still answers 200
  /// and still answers correctly — the missing reasoning costs quality, never
  /// an error — so this is the one place it is kept. Replayed verbatim only
  /// to the model named by [rawThinkingModelId], and *instead of* the rebuilt
  /// calls, never beside them; any other model gets the bare calls. Dropped
  /// wherever history rewrites a turn's tool calls, like [rawModelParts].
  /// Server-tool items (`web_search_call` …) are never in it.
  final List<Map<String, dynamic>>? rawResponseItems;

  /// Tool calls carried by an assistant message (echoed back into history
  /// during an agent loop).
  final List<LLMToolCall> toolCalls;

  /// For [LLMRole.tool] messages: which call this result answers.
  final String? toolCallId;

  /// For [LLMRole.tool] messages: the tool's name (required by Google's
  /// functionResponse format).
  final String? toolName;

  /// Host bookkeeping, never put on the wire: this assistant turn ended at
  /// the model's output limit rather than where the model stopped. Stored so
  /// a restored conversation still marks the cut reply.
  final bool truncated;

  /// Host bookkeeping, never put on the wire: this assistant text is what
  /// the turn was run to produce — the answer itself, not a remark beside a
  /// tool call. Stored so a restored conversation still knows which replies
  /// to offer for copying.
  final bool deliverable;

  /// Host bookkeeping, never put on the wire: the stored model row
  /// (`llm_models.id`) that produced this assistant turn, when it ran on one.
  final int? modelDbId;

  LLMMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.reasoningContent,
    this.reasoningFieldName,
    this.reasoningSignature,
    this.rawThinkingBlocks,
    this.rawThinkingModelId,
    this.rawContentBlocks,
    this.rawModelParts,
    this.rawResponseItems,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.truncated = false,
    this.deliverable = false,
    this.modelDbId,
  });

  /// This message naming [id] as the model row it came from — a channel
  /// merge moving a reply's link onto the model it merged into.
  LLMMessage withModelDbId(int? id) => LLMMessage(
    role: role,
    content: content,
    attachments: attachments,
    reasoningContent: reasoningContent,
    reasoningFieldName: reasoningFieldName,
    reasoningSignature: reasoningSignature,
    rawThinkingBlocks: rawThinkingBlocks,
    rawThinkingModelId: rawThinkingModelId,
    rawContentBlocks: rawContentBlocks,
    rawModelParts: rawModelParts,
    rawResponseItems: rawResponseItems,
    toolCalls: toolCalls,
    toolCallId: toolCallId,
    toolName: toolName,
    truncated: truncated,
    deliverable: deliverable,
    modelDbId: id,
  );

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    // The reasoning of a tool-calling turn must survive restarts — the
    // echo-back obligation does not expire with the session.
    if (reasoningContent != null) 'reasoningContent': reasoningContent,
    if (reasoningFieldName != null) 'reasoningFieldName': reasoningFieldName,
    if (reasoningSignature != null) 'reasoningSignature': reasoningSignature,
    if (rawThinkingBlocks != null && rawThinkingBlocks!.isNotEmpty)
      'rawThinkingBlocks': rawThinkingBlocks,
    if (rawThinkingModelId != null) 'rawThinkingModelId': rawThinkingModelId,
    if (rawContentBlocks != null && rawContentBlocks!.isNotEmpty)
      'rawContentBlocks': rawContentBlocks,
    // ③'s signatures must survive restarts like ④'s blocks do.
    if (rawModelParts != null && rawModelParts!.isNotEmpty) 'rawModelParts': rawModelParts,
    // ②'s items carry the encrypted reasoning a restart must not lose.
    if (rawResponseItems != null && rawResponseItems!.isNotEmpty)
      'rawResponseItems': rawResponseItems,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((a) => a.toJson()).whereType<Map<String, dynamic>>().toList(),
    if (toolCalls.isNotEmpty) 'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (toolName != null) 'toolName': toolName,
    if (truncated) 'truncated': true,
    if (deliverable) 'deliverable': true,
    if (modelDbId != null) 'modelDbId': modelDbId,
  };

  /// Throws [FormatException] for a role this app does not know: guessing
  /// one would replay a damaged row as something the user said.
  factory LLMMessage.fromJson(Map<String, dynamic> json) => LLMMessage(
    role:
        LLMRole.values.asNameMap()[json['role']] ??
        (throw FormatException('Unknown message role', json['role'])),
    content: json['content'] as String? ?? '',
    reasoningContent: json['reasoningContent'] as String?,
    reasoningFieldName: json['reasoningFieldName'] as String?,
    reasoningSignature: json['reasoningSignature'] as String?,
    rawThinkingBlocks: json['rawThinkingBlocks'] is List
        ? [
            for (final b in json['rawThinkingBlocks'] as List)
              if (b is Map) b.cast<String, dynamic>(),
          ]
        : null,
    rawThinkingModelId: json['rawThinkingModelId'] as String?,
    rawContentBlocks: json['rawContentBlocks'] is List
        ? [
            for (final b in json['rawContentBlocks'] as List)
              if (b is Map) b.cast<String, dynamic>(),
          ]
        : null,
    rawModelParts: json['rawModelParts'] is List
        ? [
            for (final p in json['rawModelParts'] as List)
              if (p is Map) p.cast<String, dynamic>(),
          ]
        : null,
    rawResponseItems: json['rawResponseItems'] is List
        ? [
            for (final item in json['rawResponseItems'] as List)
              if (item is Map) item.cast<String, dynamic>(),
          ]
        : null,
    attachments: [
      for (final a in (json['attachments'] as List? ?? []))
        if (a is Map && LLMAttachment.fromJson(a.cast<String, dynamic>()) != null)
          LLMAttachment.fromJson(a.cast<String, dynamic>())!,
    ],
    toolCalls: [
      for (final c in (json['toolCalls'] as List? ?? []))
        if (c is Map) LLMToolCall.fromJson(c.cast<String, dynamic>()),
    ],
    toolCallId: json['toolCallId'] as String?,
    toolName: json['toolName'] as String?,
    truncated: json['truncated'] == true,
    deliverable: json['deliverable'] == true,
    modelDbId: json['modelDbId'] is int ? json['modelDbId'] as int : null,
  );
}
