import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the M1 error-handling fixes (docs/reviews/2026-08-ai-capability-review.md
/// B1/B2/B5): the Gemini SSE line rules, the status-first response decode, and
/// the structured retry decision.
void main() {
  group('geminiChunksFromSseLine (B1)', () {
    const chunk =
        '{"candidates":[{"content":{"parts":[{"text":"hi"}],"role":"model"}}]}';

    test('data: with a space parses', () {
      final chunks = geminiChunksFromSseLine('data: $chunk').toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.textPart, 'hi');
    });

    test('data: without a space parses — SSE makes the space optional', () {
      // The old inline parser only stripped "data: " (with space); a relay
      // emitting "data:{...}" fed the whole prefixed line to jsonDecode.
      final chunks = geminiChunksFromSseLine('data:$chunk').toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.textPart, 'hi');
    });

    test('keep-alive comments, [DONE] and event: lines are ignored, not fatal',
        () {
      // Every one of these used to kill the stream: jsonDecode threw a
      // FormatException, which implements Exception, which the old catch
      // rethrew — while its comment claimed the line would be skipped.
      expect(geminiChunksFromSseLine(': keep-alive'), isEmpty);
      expect(geminiChunksFromSseLine('data: [DONE]'), isEmpty);
      expect(geminiChunksFromSseLine('event: message'), isEmpty);
      expect(geminiChunksFromSseLine('not json at all'), isEmpty);
      expect(geminiChunksFromSseLine(''), isEmpty);
    });

    test('an in-chunk error envelope still throws', () {
      expect(
        () => geminiChunksFromSseLine(
                'data: {"error":{"code":429,"message":"quota"}}')
            .toList(),
        throwsA(isA<LLMApiException>()
            .having((e) => e.isEnvelope, 'isEnvelope', isTrue)),
      );
    });
  });

  group('decodeJsonBody (B2)', () {
    test('non-2xx throws with the status code — even for an HTML body', () {
      // The old Gemini order (jsonDecode first) turned a gateway's HTML 502
      // into "FormatException: Unexpected character"; the real status never
      // appeared and the retry policy could not see the 5xx.
      final response = http.Response('<html>502 Bad Gateway</html>', 502);
      expect(
        () => decodeJsonBody(response, apiName: 'Test'),
        throwsA(isA<LLMApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.message, 'message', contains('502'))),
      );
    });

    test('non-2xx with a JSON error body surfaces the provider message', () {
      final response = http.Response(
          '{"error":{"code":400,"message":"Invalid argument","status":"INVALID_ARGUMENT"}}',
          400);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('Invalid argument'))),
      );
    });

    test('2xx non-JSON body names the real problem instead of crashing', () {
      final response = http.Response('<html>login page</html>', 200);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('non-JSON'))),
      );
    });

    test('2xx JSON array body is a shape error, not a NoSuchMethodError', () {
      final response = http.Response('[1,2,3]', 200);
      expect(() => decodeJsonBody(response), throwsA(isA<LLMApiException>()));
    });

    test('200 with an error envelope throws (envelope, no status code)', () {
      final response = http.Response('{"error":{"message":"expired key"}}', 200);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.isEnvelope, 'isEnvelope', isTrue)
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });

    test('a clean 200 returns the decoded map', () {
      final response = http.Response('{"candidates":[]}', 200);
      expect(decodeJsonBody(response), {'candidates': []});
    });

    test('201/202 are inside the success window (submit/poll surfaces)', () {
      expect(decodeJsonBody(http.Response('{"id":"v1"}', 201)), {'id': 'v1'});
      expect(decodeJsonBody(http.Response('{"status":"pending"}', 202)),
          {'status': 'pending'});
    });

    test('checkEnvelope: false hands a failed-job body to the caller', () {
      // Poll surfaces own the {status: failed, error: {...}} case — their
      // status machine names the operation; the generic envelope check would
      // fire first and discard that context.
      final response =
          http.Response('{"status":"failed","error":{"message":"boom"}}', 200);
      expect(decodeJsonBody(response, checkEnvelope: false),
          containsPair('status', 'failed'));
      expect(() => decodeJsonBody(response), throwsA(isA<LLMApiException>()));
    });
  });

  group('VendorProfile.downloadHeaders', () {
    test('google-keyed vendors get x-goog-api-key, bearer vendors a bearer',
        () {
      expect(Vendors.byId(Vendors.officialGoogle).downloadHeaders('k'),
          {'x-goog-api-key': 'k'});
      expect(Vendors.byId(Vendors.googleRest).downloadHeaders('k'),
          {'x-goog-api-key': 'k'});
      expect(Vendors.byId(Vendors.openAIRest).downloadHeaders('k'),
          {'Authorization': 'Bearer k'});
      // newapi-gemini serves the Gemini family behind bearer auth — keying
      // off the *protocol family* (the old executor branch) would have sent
      // it x-goog-api-key, which the relay silently ignores → 403.
      expect(Vendors.byId(Vendors.newApiGemini).downloadHeaders('k'),
          {'Authorization': 'Bearer k'});
    });

    test('an empty key sends no auth header at all', () {
      expect(Vendors.byId(Vendors.openAIRest).downloadHeaders(''), isEmpty);
    });
  });

  group('ModelFamilyClassifier named predicates', () {
    test('niji / text-only / mock rules live in the rule table', () {
      expect(ModelFamilyClassifier.isNijiVariant('Niji-6'), isTrue);
      expect(ModelFamilyClassifier.isNijiVariant('mj_fast'), isFalse);
      expect(ModelFamilyClassifier.isTextOnlyChat('deepseek-chat'), isTrue);
      expect(ModelFamilyClassifier.isTextOnlyChat('gpt-4o'), isFalse);
      expect(ModelFamilyClassifier.isMockModel('mock-video'), isTrue);
      expect(ModelFamilyClassifier.isMockModel('sora-2'), isFalse);
    });
  });

  group('LLMService.isRetryable (B5)', () {
    test('structured 5xx and 429 retry; other codes do not', () {
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 502)),
          isTrue);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 429)),
          isTrue);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 400)),
          isFalse);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 401)),
          isFalse);
    });

    test('envelope errors never retry — the transport succeeded', () {
      expect(
          LLMService.isRetryable(
              LLMApiException('API error in response body: quota',
                  isEnvelope: true)),
          isFalse);
    });

    test('numbers in error prose are not status codes', () {
      // The old regex grabbed the first three-digit number anywhere, so this
      // 400-class message was retried as if it were a 5xx.
      expect(
          LLMService.isRetryable(Exception(
              'API error in response body: rate limited, retry after 500ms')),
          isFalse);
      expect(
          LLMService.isRetryable(
              Exception('model "gpt-500-turbo" does not exist')),
          isFalse);
    });

    test('legacy "... failed: <status>" prose still recognized', () {
      expect(
          LLMService.isRetryable(
              Exception('xAI Images API failed: 503 - upstream down')),
          isTrue);
      expect(
          LLMService.isRetryable(
              Exception('xAI Images API failed: 422 - bad prompt')),
          isFalse);
    });
  });
}
