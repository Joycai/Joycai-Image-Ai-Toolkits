import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_debug_logger.dart';

/// Every retry, continuation leg and tool round used to open an unrelated
/// debug log. LLMService now runs each attempt under a correlation that
/// `startLog` reads from the zone — these pin that the zone value actually
/// reaches a protocol's body on both the Future and the stream path — and
/// every log ends with one normalised summary line (errors 06 §4).
void main() {
  LLMLogCorrelation correlation({int leg = 0, int attempt = 0}) =>
      LLMLogCorrelation(
          contextId: 'task-7', request: 12, leg: leg, attempt: attempt);

  test('the header names context, request, leg and attempt', () {
    expect(correlation(leg: 1, attempt: 2).header,
        'Correlation: context=task-7 request=#12 leg=1 attempt=2');
    expect(
        LLMLogCorrelation(contextId: null, request: 1, leg: 0, attempt: 0)
            .header,
        'Correlation: context=- request=#1 leg=0 attempt=0');
  });

  test('outside an attempt there is no correlation', () {
    expect(LLMDebugLogger.currentCorrelation, isNull);
  });

  test('runCorrelated reaches past awaits inside a protocol call', () async {
    final c = correlation(attempt: 1);
    Future<LLMLogCorrelation?> protocolGenerate() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await Future<void>.value();
      return LLMDebugLogger.currentCorrelation;
    }

    final seen = await LLMDebugLogger.runCorrelated(c, protocolGenerate);
    expect(seen, same(c));
    expect(LLMDebugLogger.currentCorrelation, isNull,
        reason: 'it does not leak out of the attempt');
  });

  test('correlatedStream reaches an async* protocol body listened to from '
      'an async* caller', () async {
    final c = correlation(leg: 2);
    Stream<LLMLogCorrelation?> protocolStream() async* {
      yield LLMDebugLogger.currentCorrelation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      yield LLMDebugLogger.currentCorrelation;
    }

    Stream<LLMLogCorrelation?> serviceStream() async* {
      await for (final value
          in LLMDebugLogger.correlatedStream(c, protocolStream)) {
        yield value;
      }
    }

    final seen = await serviceStream().toList();
    expect(seen, [same(c), same(c)]);
  });

  test('cancelling the correlated stream cancels the protocol stream',
      () async {
    var cancelled = false;
    final source = StreamController<int>(onCancel: () => cancelled = true);
    final sub = LLMDebugLogger.correlatedStream(correlation(), () => source.stream)
        .listen((_) {});
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(cancelled, isTrue);
  });

  group('responseSummary', () {
    test('finish reason, usage and wire rewrites on one line', () {
      final line = LLMDebugLogger.responseSummary({
        'finish_reason': 'length',
        'prompt_tokens': 120,
        'completion_tokens': 4096,
        'stream_incomplete': true,
        'wire_rewrites': [
          {'field': 'reasoning.effort', 'sent': 'max', 'echoed': 'none'}
        ],
      });
      expect(line, startsWith('Summary: finish_reason=length'));
      expect(line, contains('usage{prompt_tokens=120 completion_tokens=4096}'));
      expect(line, contains('stream_incomplete'));
      expect(line, contains('wire_rewrites=[{"field":"reasoning.effort"'));
    });

    test('absent usage says so instead of printing zeros', () {
      expect(LLMDebugLogger.responseSummary({'finish_reason': 'stop'}),
          'Summary: finish_reason=stop usage=none');
      expect(LLMDebugLogger.responseSummary(null),
          'Summary: finish_reason=- usage=none');
    });

    test('a failure names its type and a bounded message', () {
      final line = LLMDebugLogger.responseSummary(null,
          error: StateError('boom\n${'x' * 1000}'));
      expect(line, startsWith('Summary: error=StateError Bad state: boom '));
      expect(line.length, lessThan(400));
      expect(line.contains('\n'), isFalse);
    });
  });

  test('appendSummaries is a no-op when nothing was opened', () async {
    await expectLater(
        LLMDebugLogger.appendSummaries(correlation(), {'finish_reason': 'stop'}),
        completes);
  });
}
