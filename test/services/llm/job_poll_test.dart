import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/job_poll.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_images_async_protocol.dart';

/// Pins the shared async-job poll loop (standards 13 §4 async task flow,
/// 14 §3): consecutive-failure tolerance, the non-retryable abandon type that
/// carries the job id, cancellation, and the overall deadline.
void main() {
  Future<void> noSleep(Duration _, bool Function()? _) async {}

  group('pollJobUntilDone', () {
    test('rides out fewer than N consecutive failures', () async {
      var calls = 0;
      final result = await pollJobUntilDone<String>(
        job: 'test job',
        jobId: 'j1',
        fetch: () async {
          calls++;
          if (calls <= 2) throw LLMApiException('flaky', statusCode: 503);
          return {'status': 'done'};
        },
        interpret: (s) => s['status'] == 'done' ? 'ok' : null,
        deadline: const Duration(minutes: 1),
        interval: (_) => Duration.zero,
        sleep: noSleep,
      );
      expect(result, 'ok');
      expect(calls, 3);
    });

    test('a success resets the failure count', () async {
      var calls = 0;
      // fail, fail, running, fail, fail, done — never 3 in a row.
      final script = [false, false, true, false, false, true];
      final result = await pollJobUntilDone<String>(
        job: 'test job',
        jobId: 'j1',
        fetch: () async {
          final ok = script[calls++];
          if (!ok) throw Exception('jitter');
          return {'status': calls == script.length ? 'done' : 'running'};
        },
        interpret: (s) => s['status'] == 'done' ? 'ok' : null,
        deadline: const Duration(minutes: 1),
        interval: (_) => Duration.zero,
        sleep: noSleep,
      );
      expect(result, 'ok');
    });

    test('N consecutive failures abandon the job, naming its id, never retried',
        () async {
      final future = pollJobUntilDone<String>(
        job: 'DashScope image task',
        jobId: 'task-42',
        fetch: () async =>
            throw LLMApiException('poll request failed: 503 - down',
                statusCode: 503),
        interpret: (_) => null,
        deadline: const Duration(minutes: 1),
        interval: (_) => Duration.zero,
        sleep: noSleep,
      );
      final error = await future.then<Object?>((_) => null, onError: (e) => e);
      expect(error, isA<LLMJobAbandoned>());
      final abandoned = error as LLMJobAbandoned;
      expect(abandoned.jobId, 'task-42');
      expect(abandoned.toString(), contains('task-42'));
      expect(abandoned.cause, isA<LLMApiException>());
      // The message quotes "failed: 503" — the legacy regex alone would have
      // called it transient and re-submitted a paid task.
      expect(LLMService.isRetryable(abandoned), isFalse);
    });

    test('a terminal status from interpret is not a transient failure',
        () async {
      var calls = 0;
      await expectLater(
        pollJobUntilDone<String>(
          job: 'test job',
          jobId: 'j1',
          fetch: () async {
            calls++;
            return {'status': 'FAILED'};
          },
          interpret: (s) => throw LLMApiException('job FAILED'),
          deadline: const Duration(minutes: 1),
          interval: (_) => Duration.zero,
          sleep: noSleep,
        ),
        throwsA(isA<LLMApiException>()),
      );
      expect(calls, 1);
    });

    test('a non-transient fetch failure propagates at once', () async {
      var calls = 0;
      await expectLater(
        pollJobUntilDone<String>(
          job: 'test job',
          jobId: 'j1',
          fetch: () async {
            calls++;
            throw LLMApiException('not found', statusCode: 404);
          },
          interpret: (_) => null,
          isTransient: LLMService.isRetryable,
          deadline: const Duration(minutes: 1),
          interval: (_) => Duration.zero,
          sleep: noSleep,
        ),
        throwsA(isA<LLMApiException>()),
      );
      expect(calls, 1);
    });

    test('cancellation during the sleep stops before the next poll', () async {
      var cancelled = false;
      var calls = 0;
      await expectLater(
        pollJobUntilDone<String>(
          job: 'test job',
          jobId: 'j1',
          fetch: () async {
            calls++;
            return {'status': 'running'};
          },
          interpret: (_) => null,
          deadline: const Duration(minutes: 1),
          interval: (_) => const Duration(seconds: 5),
          isCancelled: () => cancelled,
          sleep: (d, c) async => cancelled = true,
        ),
        throwsA(isA<LLMCancelled>()),
      );
      expect(calls, 0);
    });

    test('the overall deadline abandons a job that never finishes', () async {
      var clock = DateTime(2026);
      final future = pollJobUntilDone<String>(
        job: 'slow job',
        jobId: 'j9',
        fetch: () async {
          clock = clock.add(const Duration(minutes: 4));
          return {'status': 'running'};
        },
        interpret: (_) => null,
        deadline: const Duration(minutes: 9),
        interval: (_) => Duration.zero,
        sleep: noSleep,
        now: () => clock,
      );
      await expectLater(
          future,
          throwsA(isA<LLMJobAbandoned>()
              .having((e) => e.jobId, 'jobId', 'j9')));
    });
  });

  group('dashscopeTaskFailure (B12)', () {
    test('UNKNOWN says an expired id reports it too; code/message kept', () {
      final e = dashscopeTaskFailure('DashScope image task', 't1', 'UNKNOWN',
          {'code': 'InvalidTask', 'message': 'gone'});
      expect(e.message, contains('t1'));
      expect(e.message, contains('InvalidTask'));
      expect(e.message, contains('expire after 24h'));
      expect(e.statusCode, isNull);
      expect(LLMService.isRetryable(e), isFalse);
    });

    test('FAILED carries no expiry note', () {
      final e = dashscopeTaskFailure('DashScope image task', 't1', 'FAILED',
          {'code': 'DataInspectionFailed'});
      expect(e.message, contains('DataInspectionFailed'));
      expect(e.message, isNot(contains('expire')));
    });
  });

  group('cancellableSleep', () {
    test('returns early once cancelled', () async {
      final watch = Stopwatch()..start();
      await cancellableSleep(const Duration(seconds: 10), () => true);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });
}
