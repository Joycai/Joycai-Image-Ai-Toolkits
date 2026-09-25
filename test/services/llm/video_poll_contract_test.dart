import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_veo_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_videos_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/xai_videos_protocol.dart';

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

    test('same host on another scheme or port never receives the key', () {
      const endpoint = 'https://relay.example.com/v1';
      expect(
          videoUriNeedsAuth('http://relay.example.com/video.mp4', endpoint),
          isFalse);
      expect(
          videoUriNeedsAuth(
              'https://relay.example.com:8443/video.mp4', endpoint),
          isFalse);
      expect(
          videoUriNeedsAuth(
              'https://relay.example.com:443/video.mp4', endpoint),
          isTrue);
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
            .having(LLMService.isRetryable, 'retryable', isFalse)),
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

    test('a 2xx body without status fails immediately as malformed', () {
      expect(
        () => openaiVideoPollEnvelope({}, 'video_1', base),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('no status'))),
      );
    });
  });

  group('xaiVideoPollEnvelope', () {
    const endpoint = 'https://api.x.ai/v1';

    test('normalizes status casing and marks signed CDN output public', () {
      final env = xaiVideoPollEnvelope({
        'status': 'DONE',
        'video': {'url': 'https://cdn.x.ai/result.mp4?sig=x'},
      }, 'req_1', endpoint);
      expect(env['done'], isTrue);
      expect(videoOf(env)[videoRequiresAuthKey], isFalse);
    });

    test('cancelled and malformed responses are terminal', () {
      for (final body in [
        {'status': 'CANCELLED'},
        <String, dynamic>{},
      ]) {
        expect(
          () => xaiVideoPollEnvelope(body, 'req_1', endpoint),
          throwsA(isA<LLMApiException>()),
        );
      }
    });

    test('the done body\'s duration and cost_in_usd_ticks are published', () {
      // The terminal poll as xAI answered it on 2026-09-22 (1 s · 480p,
      // two reference images): \$0.08 for the second plus \$0.01 a frame.
      final env = xaiVideoPollEnvelope({
        'status': 'done',
        'video': {'url': 'https://cdn.x.ai/result.mp4', 'duration': 1, 'respect_moderation': true},
        'model': 'grok-imagine-video-1.5',
        'usage': {'cost_in_usd_ticks': 1000000000},
        'progress': 100,
      }, 'req_1', endpoint);
      expect(env[videoRenderedSecondsKey], 1);
      expect(reportedCostOf(env), closeTo(0.10, 1e-12));

      // A done body without either says nothing.
      final bare = xaiVideoPollEnvelope({
        'status': 'done',
        'video': {'url': 'https://cdn.x.ai/result.mp4'},
      }, 'req_1', endpoint);
      expect(bare.containsKey(videoRenderedSecondsKey), isFalse);
      expect(reportedCostOf(bare), isNull);
    });

    test('a pending body (HTTP 202) relays its progress', () {
      final env = xaiVideoPollEnvelope({'status': 'pending', 'progress': 40}, 'req_1', endpoint);
      expect(env['done'], isFalse);
      expect(env['progress'], 40);
    });
  });

  group('veoPollResult (B6)', () {
    const endpoint = 'https://generativelanguage.googleapis.com/v1beta';

    test('the reserved cost and length keys never come from the operation body', () {
      // Veo reports neither; the body goes back verbatim, so a relay could
      // otherwise plant the key the executor settles onto the usage row.
      final done = veoPollResult({
        'name': 'operations/op1',
        'done': true,
        reportedCostKey: 0.0001,
        videoRenderedSecondsKey: 99,
        'response': {
          'generateVideoResponse': {
            'generatedSamples': [
              <String, dynamic>{
                'video': <String, dynamic>{'uri': 'https://generativelanguage.googleapis.com/v1beta/files/x:download'},
              },
            ],
          },
        },
      }, 'operations/op1', endpoint);
      expect(reportedCostOf(done), isNull);
      expect(done.containsKey(videoRenderedSecondsKey), isFalse);
      expect(videoOf(done)['uri'], isNotNull);
    });

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
