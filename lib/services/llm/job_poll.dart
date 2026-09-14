import 'dart:async';

import 'llm_types.dart';

/// The poll loop every async job this app waits on shares: DashScope's image
/// task behind the synchronous image surface, Midjourney's submit → fetch
/// cycle, and the video executor's LRO loop (standards 13 §4 "异步任务流",
/// 14 §3).
///
/// Written once because each copy had lost a different piece of it: the
/// Midjourney loop logged its task id at DEBUG only, slept uninterruptibly
/// and died on the first failed fetch of an already-billed task; the video
/// executor slept a flat 10 s and gave up on one poll error; DashScope's
/// loop had all of it but threw its exhausted failure as a retryable 5xx,
/// which made `LLMService.request` submit a second paid task.
///
/// Pure and dependency-free (no HTTP, no clock of its own) so every rule is
/// pinned by `test/job_poll_test.dart` without a socket.

/// Consecutive transient poll failures tolerated before a job is abandoned.
/// The job is already billed and a poll is a cheap GET, so jitter and a 429
/// are worth riding out — but three in a row is a real failure.
const int defaultMaxConsecutivePollFailures = 3;

/// The caller's cancellation probe out of request [options]
/// ([llmCancellationProbeKey]), or null when none was passed.
bool Function()? cancellationProbeOf(Map<String, dynamic>? options) {
  final probe = options?[llmCancellationProbeKey];
  return probe is bool Function() ? probe : null;
}

/// Sleeps [duration] in [slice]-sized steps, returning early once [cancelled]
/// answers true — so a stop takes effect within half a second instead of a
/// whole poll interval.
Future<void> cancellableSleep(
  Duration duration,
  bool Function()? cancelled, {
  Duration slice = const Duration(milliseconds: 500),
}) async {
  var remaining = duration;
  while (remaining > Duration.zero) {
    if (cancelled?.call() ?? false) return;
    final step = remaining < slice ? remaining : slice;
    await Future<void>.delayed(step);
    remaining -= step;
  }
}

bool _anyFailureIsTransient(Object _) => true;

String _describe(Duration d) =>
    d.inMinutes >= 1 ? '${d.inMinutes} minutes' : '${d.inSeconds} seconds';

/// Polls one upstream job until [interpret] returns a result.
///
/// * [fetch] performs one status request. A failure it throws counts toward
///   [maxConsecutiveFailures] when [isTransient] says so (default: every
///   failure — a status GET has no side effects); anything else propagates
///   at once. A successful fetch resets the count.
/// * [interpret] reads one status body: a non-null result ends the loop,
///   null means "still running", and a throw is a terminal job failure —
///   never counted as a transient poll failure.
/// * The loop is bounded by [deadline] from the first call, checks
///   [isCancelled] before and after every sleep, and sleeps [interval] of
///   the polls made so far.
///
/// Exits:
/// * cancelled → logs the job id at INFO and throws [LLMCancelled];
/// * past [deadline] or out of tolerated failures → [LLMJobAbandoned],
///   which names the job id and is never retried — the job may still be
///   running, and billed, upstream.
Future<T> pollJobUntilDone<T>({
  required String job,
  required String jobId,
  required Future<Map<String, dynamic>> Function() fetch,
  required FutureOr<T?> Function(Map<String, dynamic> status) interpret,
  required Duration deadline,
  required Duration Function(int pollsSoFar) interval,
  bool Function()? isCancelled,
  bool Function(Object error) isTransient = _anyFailureIsTransient,
  int maxConsecutiveFailures = defaultMaxConsecutivePollFailures,
  bool sleepBeforeFirstPoll = true,
  Function(String, {String level})? logger,
  Future<void> Function(Duration, bool Function()?)? sleep,
  DateTime Function() now = DateTime.now,
}) async {
  final doSleep = sleep ?? (d, c) => cancellableSleep(d, c);
  final start = now();
  var polls = 0;
  var failures = 0;

  void checkCancelled() {
    if (isCancelled?.call() ?? false) {
      logger?.call(
          '$job abandoned locally: cancelled by user (upstream job id: $jobId).',
          level: 'INFO');
      throw const LLMCancelled();
    }
  }

  while (true) {
    checkCancelled();
    if (now().difference(start) > deadline) {
      throw LLMJobAbandoned(
        jobId,
        '$job did not finish within ${_describe(deadline)}; polling stopped. '
        'The job may still complete, and bill, upstream — look it up by its '
        'id: $jobId.',
      );
    }
    if (polls > 0 || sleepBeforeFirstPoll) {
      await doSleep(interval(polls), isCancelled);
      checkCancelled();
    }
    polls++;

    final Map<String, dynamic> status;
    try {
      status = await fetch();
      failures = 0;
    } on LLMCancelled {
      rethrow;
    } catch (e) {
      if (!isTransient(e)) rethrow;
      failures++;
      if (failures >= maxConsecutiveFailures) {
        throw LLMJobAbandoned(
          jobId,
          '$job: $failures consecutive poll failures (last: $e). Polling '
          'stopped; the job may still complete, and bill, upstream — look it '
          'up by its id: $jobId.',
          cause: e,
        );
      }
      logger?.call(
          '$job poll failed ($e); retrying ($failures/$maxConsecutiveFailures).',
          level: 'WARN');
      continue;
    }

    final result = await interpret(status);
    if (result != null) return result;
  }
}
