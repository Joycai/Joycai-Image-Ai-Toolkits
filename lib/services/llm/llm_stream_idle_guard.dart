part of 'llm_service.dart';

/// How long the *first* chunk may take.
///
/// Longer than [_idleGap] because a silent stream means different things
/// before and after the first byte. Afterwards, two minutes of nothing is a
/// dead connection. Beforehand it is ambiguous — a large prompt still
/// prefilling behind a queue at a busy relay looks exactly the same — and
/// treating that as a dead connection re-sends the entire request, which is
/// the waste this whole change set exists to remove
/// (docs/plans/2026-08-assistant-timeout.md).
const Duration _firstChunkGap = Duration(seconds: 180);

/// How long any subsequent chunk may take.
const Duration _idleGap = Duration(seconds: 120);

/// [stream] with an idle guard that is generous about the first chunk.
///
/// Written over a [StreamIterator] rather than with `Stream.timeout`, which
/// takes one fixed duration for every element. The rewrite pays for itself
/// twice: cancelling the iterator in the `finally` actually tears down the
/// subscription, where the non-streaming `Future.timeout` leaves its request
/// running upstream and billing.
///
/// [firstIsDeadline] is for a route [LLMDispatcher.streamIsSingleShot]
/// calls out: there the first gap *is* the generation's deadline, so it
/// expiring throws [LLMDeadlineExceeded] — never retried — instead of the
/// plain [TimeoutException] that [LLMService.isRetryable] reads as a dead connection.
/// The old spelling let a slow single-shot image generation time out and
/// be re-sent while upstream was still drawing (and billing) the first.
Stream<LLMResponseChunk> _idleGuarded(
  Stream<LLMResponseChunk> stream, {
  Duration? first,
  bool firstIsDeadline = false,
}) => _guard(stream,
    first: first ?? _firstChunkGap,
    subsequent: _idleGap,
    firstIsDeadline: firstIsDeadline);

Stream<T> _guard<T>(
  Stream<T> stream, {
  required Duration first,
  required Duration subsequent,
  bool firstIsDeadline = false,
}) async* {
  final iterator = StreamIterator(stream);
  var gap = first;
  var awaitingFirst = true;
  try {
    while (await iterator.moveNext().timeout(gap, onTimeout: () {
      if (awaitingFirst && firstIsDeadline) {
        throw LLMDeadlineExceeded(first);
      }
      throw TimeoutException('No stream chunk within $gap', gap);
    })) {
      awaitingFirst = false;
      gap = subsequent;
      yield iterator.current;
    }
  } finally {
    await iterator.cancel();
  }
}
