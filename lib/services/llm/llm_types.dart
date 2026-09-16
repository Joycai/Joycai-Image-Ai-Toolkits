import 'package:flutter/foundation.dart';

import 'llm_messages.dart';

export 'llm_errors.dart';
export 'llm_messages.dart';
export 'llm_model_config.dart';

/// One subscriber to `LLMService`'s execution log — see
/// `LLMService.addLogListener`.
typedef LLMLogListener = void Function(String message,
    {String level, String? contextId});

/// Option key for the caller's cancellation probe: a `bool Function()` that
/// returns true once the surrounding task has been cancelled.
///
/// Single-request protocols never look at it — one HTTP call has no
/// checkpoint to stop at — but a protocol that hides an async task loop
/// behind the synchronous surface (DashScope's image task flow) polls for
/// minutes and must stop within seconds of the user pressing stop. Passed
/// through `options` because that is the only channel an executor already
/// has to a protocol; the value is a function, so the map carrying it must
/// never be persisted or JSON-encoded (executors build a fresh map at the
/// call site).
const String llmCancellationProbeKey = 'isCancelled';

/// Option key for the request's abort trigger: a `Future<void>` whose
/// completion aborts the HTTP request in flight (`package:http`'s
/// `Abortable.abortTrigger`).
///
/// Set by `LLMService` per attempt — completed when the caller cancels or the
/// non-streaming deadline expires — and read by the protocols' shared send
/// helper (`sendJsonRequest`). It exists because the HTTP client is pooled:
/// closing it would tear down every other request on the connection, so
/// before this a cancelled or timed-out non-streaming request kept running
/// (and billing) upstream until it finished on its own. Like the probe, the
/// value is not data: the map carrying it must never be persisted.
const String llmAbortTriggerKey = 'abortTrigger';

/// Option key for a `void Function()` the shared request builders call once
/// the request body has been handed to the connection in full.
///
/// Set by `LLMService.startLongRunning` only. A video submit may be aborted
/// while its body uploads — upstream cannot have created a job from half a
/// body — but not after: from then on the server may already have accepted
/// (and billed) the job, and aborting would throw away the only copy of its
/// id. Past this point the submit is left to finish, its ticket is persisted,
/// and the executor cancels the job upstream through the id instead.
const String llmBodySentKey = 'onRequestBodySent';

/// Key inside a video poll's done envelope (`…generatedSamples[].video`):
/// whether downloading its `uri` needs the channel's credentials.
///
/// Decided by the protocol that produced the URL, because only it knows what
/// kind of link it is: Sora-style `/videos/{id}/content` is an API endpoint
/// and wants the key, while DashScope's OSS links, MiniMax's CDN links and
/// xAI's result URLs are signed and must *not* get it — the key has no
/// meaning at that host and sending it hands a credential to a third party
/// (standard 14 §3.4). The executor used to attach the bearer to every
/// download. Absent means false. Lives here rather than in the protocol
/// layer so the executor can read it without importing a protocol.
const String videoRequiresAuthKey = 'requiresAuth';

/// Options key: a reply with nothing in it ends the turn instead of failing
/// the request.
///
/// A 200 that carries no text, reasoning, tool calls or images is normally a
/// broken relay and is thrown (pitfalls 11 §A6). An agent loop continuing
/// after a tool result is the one caller for which it is not: once a tool has
/// delivered the deliverable (`submit_prompt`), GPT-5.x ends the turn with an
/// empty `stop` — ④ already reads that off the completed message item, and
/// this key is how ① learns the same thing, since a chat-completions stream
/// has no item status to read. Set only on such continuation requests, never
/// on a turn that opens with the user's message: there an empty reply is
/// still a silent failure the user must see.
const String emptyReplyEndsTurnKey = 'emptyReplyEndsTurn';

/// The output cap the caller asked for, or null when it did not ask.
///
/// Shared so the deadline and the payload agree on what "the caller asked
/// for" means — they read the same key out of the same options map, and a
/// deadline sized against a different number than the request carries is a
/// deadline sized against nothing.
int? requestedMaxTokens(Map<String, dynamic>? options) {
  final raw = options?['maxTokens'];
  if (raw is num && raw >= 1) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

class LLMResponse {
  final String text;
  final List<Uint8List> generatedImages;
  final String? videoUri;
  final String? operationName;
  final Map<String, dynamic> metadata;

  /// Chain-of-thought the response carried, already separated from [text].
  /// See [LLMMessage.reasoningContent] for the round-trip contract.
  final String? reasoningContent;

  /// Wire field name of [reasoningContent], or null for inline/absent —
  /// see [LLMMessage.reasoningFieldName].
  final String? reasoningFieldName;

  /// ④'s seal over [reasoningContent] — see [LLMMessage.reasoningSignature].
  /// Must reach the assistant message that replays this turn, or the next
  /// request in a tool-calling conversation is rejected.
  final String? reasoningSignature;

  /// ④'s thinking-class blocks verbatim — see [LLMMessage.rawThinkingBlocks].
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// Producer of [rawThinkingBlocks] — see [LLMMessage.rawThinkingModelId].
  final String? rawThinkingModelId;

  /// ④'s whole content array for a server-tool turn — see
  /// [LLMMessage.rawContentBlocks]. Must reach the assistant message that
  /// replays this turn, or the search the host ran is lost to the next
  /// request and a paused turn cannot be continued.
  final List<Map<String, dynamic>>? rawContentBlocks;

  /// ③'s model-turn parts verbatim for a tool-calling turn — see
  /// [LLMMessage.rawModelParts]. Scoped by [rawThinkingModelId].
  final List<Map<String, dynamic>>? rawModelParts;

  /// ②'s output items verbatim for a tool-calling turn — see
  /// [LLMMessage.rawResponseItems]. Scoped by [rawThinkingModelId].
  final List<Map<String, dynamic>>? rawResponseItems;

  /// Tool calls requested by the model (empty when it answered directly).
  final List<LLMToolCall> toolCalls;

  LLMResponse({
    required this.text,
    this.generatedImages = const [],
    this.videoUri,
    this.operationName,
    this.metadata = const {},
    this.reasoningContent,
    this.reasoningFieldName,
    this.reasoningSignature,
    this.rawThinkingBlocks,
    this.rawThinkingModelId,
    this.rawContentBlocks,
    this.rawModelParts,
    this.rawResponseItems,
    this.toolCalls = const [],
  });
}

class LLMResponseChunk {
  final String? textPart;

  /// Chain-of-thought increment, kept out of [textPart] so consumers that
  /// accumulate text never glue the model's thinking into the deliverable.
  final String? reasoningPart;

  /// Wire field name of [reasoningPart] — the ①/C2 echo-back key
  /// ([LLMMessage.reasoningFieldName]), carried per chunk because the stream
  /// consumer assembles an [LLMResponse] and the replay obligation travels
  /// with the name, not just the text. Null on ④, whose obligation is the
  /// signed block ([rawThinkingBlocks]), and for inline `<think>` reasoning,
  /// which carries no obligation at all.
  final String? reasoningFieldName;

  final Uint8List? imagePart;
  final Map<String, dynamic>? metadata;

  /// One whole tool call. Emitted by the Google chunk parser, which is shared
  /// between that family's streaming and synchronous paths — the synchronous
  /// one reassembles [LLMResponse.toolCalls] from these — and by ④'s stream,
  /// which declares tools and assembles the calls itself.
  ///
  /// **Always a complete call, never a fragment.** ④ delivers tool arguments
  /// as `input_json_delta` fragments that are not valid JSON until the last
  /// one, so the accumulator lives inside the protocol and a call is emitted
  /// only at `content_block_stop`. Consumers may assume they can act on
  /// whatever arrives here.
  final LLMToolCall? toolCallPart;

  /// ④'s thinking blocks, verbatim and in order, emitted once at stream end.
  ///
  /// Not derivable from [reasoningPart]: that is display text, and the replay
  /// obligation is over the whole sealed block (including
  /// `redacted_thinking`, which has no text at all). A tool-calling turn
  /// replayed without them is an incomplete thinking history, which ④
  /// silently strips — thinking stops, billing continues — rather than
  /// rejecting. Only reachable now that the streaming surface can carry a
  /// tool call, which is the only turn whose replay needs them.
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// The seal over the last thinking block, for [LLMMessage.reasoningSignature].
  final String? reasoningSignature;

  /// ④'s whole content array, emitted once at stream end when the turn ran a
  /// server tool — see [LLMMessage.rawContentBlocks].
  final List<Map<String, dynamic>>? rawContentBlocks;

  /// ③'s model-turn parts, collected across the whole stream and emitted
  /// once at its end when the turn called a tool — see
  /// [LLMMessage.rawModelParts].
  final List<Map<String, dynamic>>? rawModelParts;

  /// ②'s output items, collected from `response.output_item.done` and
  /// emitted once at stream end when the turn called a tool — see
  /// [LLMMessage.rawResponseItems].
  final List<Map<String, dynamic>>? rawResponseItems;

  /// How many characters of tool-call arguments this response has streamed
  /// so far — a running total, not the size of this fragment.
  ///
  /// Progress only, never content: [toolCallPart] stays the one way a call
  /// reaches a consumer. It exists because a long call (a `submit_prompt` is
  /// thousands of characters) streams for minutes with nothing else on the
  /// wire, and a consumer that shows nothing for that long gets stopped by a
  /// user who reads it as hung. A total rather than a fragment length so a
  /// dialect that restates the whole call each frame is not counted twice.
  final int? toolArgumentChars;

  final bool isDone;

  LLMResponseChunk({
    this.textPart,
    this.reasoningPart,
    this.reasoningFieldName,
    this.imagePart,
    this.metadata,
    this.toolCallPart,
    this.rawThinkingBlocks,
    this.reasoningSignature,
    this.rawContentBlocks,
    this.rawModelParts,
    this.rawResponseItems,
    this.toolArgumentChars,
    this.isDone = false,
  });
}
