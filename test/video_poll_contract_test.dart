import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_veo_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_videos_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// The video poll contract (standard 14 §1, §3): failure is thrown, never
/// returned (B6, B12), and each done envelope says whether its URL may carry
/// the channel key (B4, 14 §3.4).
void main() {
  Map<String, dynamic> videoOf(Map<String, dynamic> envelope) =>
      ((envelope['response'] as Map)['generateVideoResponse']
              as Map)['generatedSamples'][0]['video']
          as Map<String, dynamic>;

  group('videoUriNeedsAuth', () {
    test('only a URL back on the API host gets the key', () {
      expect(
          videoUriNeedsAuth('https://relay.example.com/v1/videos/v1/content',
              'https://relay.example.com/v1'),
          isTrue);
      expect(
          videoUriNeedsAuth(
              'https://dashscope-result.oss-cn-beijing.aliyuncs.com/x.mp4?Signature=abc',
              'https://dashscope.aliyuncs.com/api/v1'),
          isFalse);
      expect(videoUriNeedsAuth('not a url', 'https://h/v1'), isFalse);
    });
  });

  group('openaiVideoPollEnvelope', () {
    const base = 'https://relay.example.com/v1';

    test('completed without a url falls back to /content, which needs auth',
        () {
      final env = openaiVideoPollEnvelope(
          {'status': 'completed'}, 'video_1', base);
      expect(env['done'], isTrue);
      expect(videoOf(env)['uri'], '$base/videos/video_1/content');
      expect(videoOf(env)[videoRequiresAuthKey], isTrue);
    });

    test('a signed CDN url does not get the key', () {
      final env = openaiVideoPollEnvelope(
          {'status': 'succeeded', 'url': 'https://cdn.other.net/v.mp4?sig=1'},
          'video_1',
          base);
      expect(videoOf(env)[videoRequiresAuthKey], isFalse);
    });

    test('failed throws with the upstream code and message, not retryable',
        () {
      expect(
        () => openaiVideoPollEnvelope({
          'status': 'failed',
          'error': {'code': 'moderation_blocked', 'message': 'nope'},
        }, 'video_1', base),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('moderation_blocked'))
            .having((e) => e.message, 'message', contains('video_1'))
            .having((e) => LLMService.isRetryable(e), 'retryable', isFalse)),
      );
    });

    test('cancelled and expired are terminal, not "still processing"', () {
      for (final s in ['cancelled', 'canceled', 'expired']) {
        expect(
            () => openaiVideoPollEnvelope({'status': s}, 'video_1', base),
            throwsA(isA<LLMApiException>()),
            reason: s);
      }
    });

    test('in_progress is not done and relays progress', () {
      final env = openaiVideoPollEnvelope(
          {'status': 'in_progress', 'progress': 40}, 'video_1', base);
      expect(env['done'], isFalse);
      expect(env['progress'], 40);
    });
  });

  group('veoPollResult (B6)', () {
    const endpoint = 'https://generativelanguage.googleapis.com/v1beta';

    test('a failed operation throws its code and message', () {
      // Used to be returned verbatim; the executor read only `response` and
      // reported "no video URI found. Response: null".
      expect(
        () => veoPollResult({
          'name': 'operations/op1',
          'done': true,
          'error': {'code': 3, 'message': 'prompt rejected'},
        }, 'operations/op1', endpoint),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('prompt rejected'))
            .having((e) => e.message, 'message', contains('code 3'))),
      );
    });

    test('a safety-filtered result says so', () {
      expect(
        () => veoPollResult({
          'done': true,
          'response': {
            'generateVideoResponse': {
              'raiMediaFilteredCount': 1,
              'raiMediaFilteredReasons': ['celebrity'],
            },
          },
        }, 'operations/op1', endpoint),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('celebrity'))),
      );
    });

    test('a Google files URI on the API host is marked as needing the key', () {
      final data = veoPollResult({
        'done': true,
        'response': {
          'generateVideoResponse': {
            'generatedSamples': [
              {
                // Typed as jsonDecode produces it: the poll adds a bool.
                'video': <String, dynamic>{
                  'uri':
                      'https://generativelanguage.googleapis.com/v1beta/files/abc:download?alt=media',
                },
              },
            ],
          },
        },
      }, 'operations/op1', endpoint);
      expect(videoOf(data)[videoRequiresAuthKey], isTrue);
    });

    test('a relay storage link is not', () {
      final data = veoPollResult({
        'done': true,
        'response': {
          'generateVideoResponse': {
            'generatedSamples': [
              {
                'video': <String, dynamic>{
                  'uri': 'https://files.relay-cdn.net/v.mp4',
                },
              },
            ],
          },
        },
      }, 'operations/op1', 'https://relay.example.com/v1beta');
      expect(videoOf(data)[videoRequiresAuthKey], isFalse);
    });

    test('an unfinished operation passes through', () {
      final data = veoPollResult(
          {'name': 'operations/op1', 'done': false}, 'operations/op1', endpoint);
      expect(data['done'], isFalse);
    });
  });
}
