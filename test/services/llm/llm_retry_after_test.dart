import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// Retry-After (errors 06 §3): a 429's requested wait is read generically off
/// the response headers and honoured by the retry loop, which used to sleep a
/// flat, uninterruptible two seconds and so re-sent a rate-limited request
/// straight into a second 429.
void main() {
  group('parseRetryAfter', () {
    test('delay-seconds, integer and fractional', () {
      expect(parseRetryAfter({'retry-after': '7'}), const Duration(seconds: 7));
      expect(parseRetryAfter({'retry-after': '1.5'}), const Duration(milliseconds: 1500));
    });

    test('retry-after-ms wins over retry-after', () {
      expect(
        parseRetryAfter({'retry-after-ms': '250', 'retry-after': '9'}),
        const Duration(milliseconds: 250),
      );
    });

    test('an HTTP-date becomes a delay from now; a past date means now', () {
      final now = DateTime.utc(2026, 9, 14, 12, 0, 0);
      final later = HttpDate.format(now.add(const Duration(seconds: 30)));
      expect(parseRetryAfter({'retry-after': later}, now: now), const Duration(seconds: 30));
      final earlier = HttpDate.format(now.subtract(const Duration(hours: 1)));
      expect(parseRetryAfter({'retry-after': earlier}, now: now), Duration.zero);
    });

    test('header names are case-insensitive', () {
      expect(parseRetryAfter({'Retry-After': '3'}), const Duration(seconds: 3));
    });

    test('absent, empty, negative or garbage is null', () {
      expect(parseRetryAfter(const {}), isNull);
      expect(parseRetryAfter({'retry-after': ''}), isNull);
      expect(parseRetryAfter({'retry-after': '-4'}), isNull);
      expect(parseRetryAfter({'retry-after': 'soon'}), isNull);
    });
  });

  test('decodeJsonBody carries the wait on a non-2xx failure', () {
    final response = http.Response(
      '{"error":{"message":"slow down"}}',
      429,
      headers: {'retry-after': '12'},
    );
    expect(
      () => decodeJsonBody(response, apiName: 'Test API'),
      throwsA(
        isA<LLMApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 12)),
      ),
    );
  });

  group('LLMService.retryDelayFor', () {
    LLMApiException rateLimited(Duration? wait) =>
        LLMApiException('429', statusCode: 429, retryAfter: wait);

    test('without a server wait it is the linear backoff', () {
      expect(LLMService.retryDelayFor(Exception('SocketException'), 1), const Duration(seconds: 2));
      expect(LLMService.retryDelayFor(rateLimited(null), 3), const Duration(seconds: 6));
    });

    test('a longer server wait wins over the backoff', () {
      expect(
        LLMService.retryDelayFor(rateLimited(const Duration(seconds: 20)), 1),
        const Duration(seconds: 20),
      );
    });

    test('a shorter server wait never shortens the backoff', () {
      expect(
        LLMService.retryDelayFor(rateLimited(const Duration(milliseconds: 100)), 2),
        const Duration(seconds: 4),
      );
    });

    test('exactly the cap is still waited out', () {
      expect(
        LLMService.retryDelayFor(rateLimited(LLMService.maxRetryAfter), 1),
        LLMService.maxRetryAfter,
      );
    });

    test('above the cap there is no retry at all', () {
      expect(
        LLMService.retryDelayFor(
          rateLimited(LLMService.maxRetryAfter + const Duration(seconds: 1)),
          1,
        ),
        isNull,
      );
    });

    test('the billed-route rule is untouched: a 5xx with a wait is still '
        'not retried on a billed route', () {
      final e = LLMApiException('502', statusCode: 502, retryAfter: const Duration(seconds: 1));
      expect(LLMService.shouldRetry(e, billedOnSubmit: true), isFalse);
    });
  });
}
