/// A failed API call, structured enough that retry policy can be decided
/// without parsing exception prose.
///
/// Protocols throw this for non-2xx responses (with [statusCode] set) and for
/// 200-with-error-envelope bodies ([isEnvelope] true, [statusCode] null).
/// `LLMService` retries only transient codes (5xx / 429). Before this existed
/// it fished the first three-digit number out of `e.toString()` with a regex,
/// which read "retry after 500ms" in an error body as a server error — and
/// missed real 5xxs whose message led with some other number.
class LLMApiException implements Exception {
  final String message;

  /// HTTP status of the failed response, or null when the failure was carried
  /// inside a 2xx body ([isEnvelope]) or never reached HTTP at all.
  final int? statusCode;

  /// True when a 2xx response body was an error envelope (`error` field or
  /// MiniMax `base_resp`). Envelope errors are never retried — the transport
  /// succeeded; the request itself was rejected.
  final bool isEnvelope;

  /// True when the response body was not JSON at all (an HTML error page, a
  /// login page, a CDN interstitial) — the classic "the base URL points at
  /// something that is not this API" signature. Structured so the channel
  /// probe can classify it without matching message prose.
  final bool isNonJsonBody;

  /// True when the provider's content filter stopped the generation — a
  /// response published with `finish_reason: content_filter` (① verbatim,
  /// ④ `stop_reason: refusal`, ③ a blocking `finishReason` or
  /// `promptFeedback.blockReason`). Never retried: the same request meets the
  /// same filter, and every attempt is billed. See [contentBlockedFailure].
  final bool isContentBlocked;

  /// How long the server asked the client to wait before trying again —
  /// `Retry-After` (seconds or an HTTP-date) or `retry-after-ms` — or null
  /// when the failed response named no wait. Read generically off the
  /// response headers (`parseRetryAfter`), never per vendor. `LLMService`
  /// sleeps at least this long before a retry, and does not retry at all
  /// when the wait exceeds its cap.
  final Duration? retryAfter;

  /// True when a video poll found the upstream job itself over without a
  /// usable result — failed, cancelled, expired, filtered, or finished with
  /// no video. Polling it again can only repeat this, so the task forgets
  /// the job id and stops offering to resume it
  /// (`TaskQueueService.canResumeVideoJob`).
  final bool isJobEnded;

  LLMApiException(this.message,
      {this.statusCode,
      this.isEnvelope = false,
      this.isNonJsonBody = false,
      this.isContentBlocked = false,
      this.retryAfter,
      this.isJobEnded = false});

  bool get isTransient =>
      statusCode != null &&
      (statusCode == 429 || (statusCode! >= 500 && statusCode! < 600));

  @override
  String toString() => message;
}

/// The `finish_reason` every chat wire publishes when the provider's content
/// filter intercepted the generation. ① sends it natively; ④ and ③ translate
/// their own vocabularies into it (`anthropicFinishReason`,
/// `geminiFinishReason`).
const String contentFilterFinishReason = 'content_filter';

/// The failure a response carrying [metadata] stands for, or null when it was
/// not content-blocked.
///
/// Interception can arrive *after* text has streamed (a Gemini `SAFETY`
/// finish on the last chunk, an Azure-style `content_filter` on ①, ④'s
/// `refusal`), and a response that ends that way is not a short answer: the
/// delivered text has to be voided (pitfalls 11 §A7, errors 06 §2.3). The
/// protocols therefore only *publish* the reason, and `LLMService` makes this
/// one check — after recording usage, since the tokens were billed either
/// way — on both the request and the stream path. Before it existed nothing
/// read `content_filter` at all and every wire returned the partial reply as a
/// success.
LLMApiException? contentBlockedFailure(Map<String, dynamic>? metadata) {
  if (metadata == null ||
      metadata['finish_reason'] != contentFilterFinishReason) {
    return null;
  }
  final raw = metadata['finish_reason_raw'] ?? metadata['stop_reason'];
  return LLMApiException(
    'Blocked by the provider\'s content filter '
    '(finish_reason: $contentFilterFinishReason'
    '${raw == null ? '' : ', reported as $raw'}). '
    'Any partial output from this request was discarded.',
    isContentBlocked: true,
  );
}

/// The caller withdrew while the request was in flight.
///
/// Its own type so it can be told apart from a failure everywhere the two
/// would otherwise look alike: [LLMService.isRetryable] must answer false (a
/// cancelled request retried is the bug this exists to prevent), and a caller
/// showing an error card must not show one for it — nobody needs to be told
/// that the button they just pressed worked.
///
/// Thrown rather than returned as an empty response because "cancelled" and
/// "the model answered with nothing" have to be distinguishable at every
/// call site, and only one of them may be written into a conversation.
class LLMCancelled implements Exception {
  const LLMCancelled();

  @override
  String toString() => 'Request cancelled by the caller.';
}

/// Local polling of an **accepted, billed** upstream job was given up — the
/// overall deadline passed, or too many consecutive polls failed.
///
/// Its own type because the one wrong reaction to it is the obvious one:
/// retrying. A retry re-submits, which buys the same generation twice while
/// the first may well still be running (and billing) upstream. Before this
/// existed, DashScope's async image loop rethrew its third transient poll
/// failure as a 5xx `LLMApiException`, and `LLMService.request` read that
/// as retryable and submitted a new paid task. `LLMService.isRetryable`
/// answers false for it explicitly.
///
/// [jobId] is carried so the user can still find the job upstream; the
/// message names it too.
class LLMJobAbandoned implements Exception {
  final String jobId;
  final String message;

  /// The last poll failure, when that is what ended polling.
  final Object? cause;

  const LLMJobAbandoned(this.jobId, this.message, {this.cause});

  @override
  String toString() => message;
}

/// A request that is clearly larger than the model's configured context
/// window, refused **before** it is sent (provider layering 01 §6, pitfalls
/// 11 §A5, errors 06 §3).
///
/// Local stacks (Ollama's default `num_ctx`, llama.cpp) do not reject an
/// oversized prompt: they silently drop its head — the system prompt first —
/// and answer 200, so the model replies to a conversation it never saw whole.
/// Checked only against an explicit window, with a permissive estimate and a
/// margin (see `ContextBudget.exceedsWindow`): a backstop for an obviously
/// oversized request, not a second budget. Never retried — nothing was sent,
/// and the same request is the same size. Carries both numbers for display.
class LLMContextSizeError implements Exception {
  final int estimatedTokens;
  final int contextWindow;

  const LLMContextSizeError(this.estimatedTokens, this.contextWindow);

  @override
  String toString() =>
      'This request is about $estimatedTokens tokens, more than the '
      '$contextWindow-token context window configured for the model, so it '
      'was not sent — a server that accepted it would silently drop the start '
      'of the conversation. Shorten the input, or raise the context window in '
      'the model settings if the model really supports more.';
}

/// The whole-request deadline on the **non-streaming** path expired.
///
/// Its own type, and deliberately not a [TimeoutException], because
/// `LLMService.isRetryable` answers the two cases oppositely and they mean
/// opposite things:
///
///  * On the streaming path the deadline is per *chunk*. It expiring means
///    no bytes at all arrived for two minutes — a dead connection, where
///    reconnecting is exactly the right move. That stays retryable.
///  * Here it means the generation did not finish in time. The input is
///    unchanged and so is the amount of output being asked for, so a retry
///    re-runs the identical request and misses the identical deadline. It is
///    worse than useless: `Future.timeout` cancels nothing, so the abandoned
///    request keeps running upstream, keeps holding the connection, and is
///    billed in full — while its replacement competes with it. The Prompt
///    Assistant used to spend three Opus generations and six minutes this
///    way and deliver nothing (docs/plans/2026-08-assistant-timeout.md).
class LLMDeadlineExceeded implements Exception {
  final Duration deadline;

  const LLMDeadlineExceeded(this.deadline);

  @override
  String toString() =>
      'No response within ${deadline.inSeconds}s. The request was not '
      'cancelled upstream — it may still complete, and it is billed either '
      'way. Nothing was retried, because an identical request would miss the '
      'same deadline.';
}
