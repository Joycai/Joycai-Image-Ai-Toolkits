import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// Pins the chat-wire correctness rules of the 2026-09-14 audit round (batch
/// A): every one of them is a failure that used to arrive as a success.
void main() {
  group('content blocks fail the request (pitfalls 11 §A7, errors 06 §2.3)',
      () {
    test('① content_filter is a typed, non-retryable failure', () {
      final failure = contentBlockedFailure({
        'prompt_tokens': 10,
        'completion_tokens': 3,
        'finish_reason': 'content_filter',
      });
      expect(failure, isNotNull);
      expect(failure!.isContentBlocked, isTrue);
      expect(failure.toString(), contains('content filter'));
      expect(LLMService.isRetryable(failure), isFalse,
          reason: 'the same request meets the same filter, and bills again');
    });

    test('④ refusal reaches the same check', () {
      final metadata = anthropicUsageMetadata(
        {'input_tokens': 5, 'output_tokens': 2},
        stopReason: 'refusal',
      );
      final failure = contentBlockedFailure(metadata);
      expect(failure, isNotNull);
      expect(failure.toString(), contains('refusal'));
    });

    test('③ SAFETY after streamed text reaches the same check', () {
      final chunks = parseGoogleChunks({
        'candidates': [
          {
            'finishReason': 'SAFETY',
            'content': {
              'parts': [
                {'text': 'half an answer'}
              ]
            },
          }
        ],
      }).toList();
      expect(contentBlockedFailure(chunks.last.metadata), isNotNull);
    });

    test('ordinary endings are not blocks', () {
      for (final reason in ['stop', 'length', 'tool_calls', 'pause', null]) {
        expect(contentBlockedFailure({'finish_reason': reason}), isNull,
            reason: '$reason');
      }
      expect(contentBlockedFailure(null), isNull);
      expect(contentBlockedFailure(const {}), isNull);
    });
  });

  group('error messages name the request URL (errors 06 §2)', () {
    // The commonest third-party failure is a base URL that resolved somewhere
    // unexpected; a bare "404: <html>" gives the user nothing to compare
    // against what they pasted. The key must never ride along.
    final request = http.Request(
      'POST',
      Uri.parse('https://relay.example.com/v1beta/models/m:generateContent'
          '?key=SECRET-KEY'),
    );

    test('a non-2xx status carries the redacted URL', () {
      expect(
        () => decodeJsonBody(
          http.Response('<html>nope</html>', 404, request: request),
          apiName: 'Test API',
        ),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message',
                contains('relay.example.com/v1beta/models/m:generateContent'))
            .having((e) => e.message, 'message', isNot(contains('SECRET-KEY')))
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a non-JSON 200 carries it too', () {
      expect(
        () => decodeJsonBody(
          http.Response('<html>login</html>', 200, request: request),
          apiName: 'Test API',
        ),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('relay.example.com'))
            .having(
                (e) => e.message, 'message', isNot(contains('SECRET-KEY')))),
      );
    });

    test('a response built without a request still decodes its error', () {
      expect(
        () => decodeJsonBody(http.Response('oops', 502), apiName: 'Test API'),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', startsWith('Test API request failed: 502 - '))),
      );
    });
  });
}
