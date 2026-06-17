import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/providers/google_genai_provider.dart';

void main() {
  group('buildGoogleAuthHeaders', () {
    const key = 'AIza-test-key';

    test('always sends the API key in x-goog-api-key', () {
      final headers = buildGoogleAuthHeaders(
        'google-genai-rest',
        key,
        'https://generativelanguage.googleapis.com/v1beta',
      );
      expect(headers['x-goog-api-key'], key);
      expect(headers['Content-Type'], 'application/json');
    });

    test('official Google host never receives Authorization: Bearer (the 401 cause)', () {
      // Regression: google-genai-rest pointed at the official endpoint used to
      // also send `Authorization: Bearer <key>`, which Google rejects with 401.
      final headers = buildGoogleAuthHeaders(
        'google-genai-rest',
        key,
        'https://generativelanguage.googleapis.com/v1beta',
      );
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers['x-goog-api-key'], key);
    });

    test('official-google-genai-api type never sends Authorization', () {
      final headers = buildGoogleAuthHeaders(
        'official-google-genai-api',
        key,
        'https://generativelanguage.googleapis.com/v1beta',
      );
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers['x-goog-api-key'], key);
    });

    test('third-party relay still receives bearer token for compatibility', () {
      final headers = buildGoogleAuthHeaders(
        'google-genai-rest',
        key,
        'https://api.yyds168.net/v1beta',
      );
      expect(headers['Authorization'], 'Bearer $key');
      expect(headers['x-goog-api-key'], key);
    });

    test('any *.googleapis.com host is treated as official', () {
      final headers = buildGoogleAuthHeaders(
        'google-genai-rest',
        key,
        'https://us-central1-aiplatform.googleapis.com/v1',
      );
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('appendGoogleKey', () {
    const key = 'AIza-test-key';

    test('adds key query parameter matching Google docs', () {
      final url = appendGoogleKey(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'),
        key,
      );
      expect(url.queryParameters['key'], key);
      expect(url.path, endsWith(':generateContent'));
    });

    test('preserves existing query parameters (e.g. alt=sse for streaming)', () {
      final url = appendGoogleKey(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/m:streamGenerateContent?alt=sse'),
        key,
      );
      expect(url.queryParameters['alt'], 'sse');
      expect(url.queryParameters['key'], key);
    });

    test('leaves the URL untouched when the key is empty', () {
      final original = Uri.parse('https://example.com/v1beta/models');
      expect(appendGoogleKey(original, ''), original);
    });
  });
}
