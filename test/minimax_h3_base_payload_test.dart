import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_h3_base_payload.dart';

/// Pins the wire rules of the self-hosted SGLang H3-Base video surface
/// (docs/api/minimax.md §8) against the cookbook's examples — asserted
/// verbatim, because the two ways to get this body wrong (multipart instead
/// of JSON came free with the ① protocol; a field at the wrong nesting level)
/// both fail on the server with errors that never name the actual mistake,
/// and the status vocabulary difference (`completed` vs `succeeded`) fails
/// with no error at all.
void main() {
  group('buildMiniMaxH3VideoPayload', () {
    test('t2va: no media, the cookbook body shape verbatim', () {
      final payload = buildMiniMaxH3VideoPayload(
        modelId: 'MiniMaxAI/MiniMax-H3',
        prompt: 'three cats perform with tiny brass instruments',
        media: const [],
        options: {'seconds': '5'},
      );
      expect(payload, {
        'model': 'MiniMaxAI/MiniMax-H3',
        'prompt': 'three cats perform with tiny brass instruments',
        'seconds': 5,
        'task': 't2va',
        'conditions': const <Object>[],
        'target': {
          'short_edge': 768,
          'aspect_ratio': '16:9',
          'duration_seconds': 5.0,
        },
        'num_outputs_per_prompt': 1,
        'num_inference_steps': 50,
        'flow_shift': 12.0,
        'audio_flow_shift': 3.0,
      });
    });

    test('fl2va: a first frame is a keyframe condition with frame_index 0',
        () {
      final payload = buildMiniMaxH3VideoPayload(
        modelId: 'MiniMaxAI/MiniMax-H3',
        prompt: 'continue with calm natural motion',
        media: const [
          MiniMaxH3Media(
              MiniMaxH3Role.firstFrame, 'file:///data/first-frame.png'),
        ],
      );
      expect(payload['task'], 'fl2va');
      expect(payload['conditions'], [
        {
          'type': 'image',
          'uri': 'file:///data/first-frame.png',
          'role': 'keyframe',
          'frame_index': 0,
        },
      ]);
      // With input media, the default ratio is `auto` — follow the input.
      expect((payload['target'] as Map)['aspect_ratio'], 'auto');
    });

    test('fl2va: first frame precedes last frame whatever the input order',
        () {
      final payload = buildMiniMaxH3VideoPayload(
        modelId: 'MiniMaxAI/MiniMax-H3',
        prompt: 'p',
        media: const [
          MiniMaxH3Media(MiniMaxH3Role.lastFrame, 'file:///b/last.png'),
          MiniMaxH3Media(MiniMaxH3Role.firstFrame, 'file:///a/first.png'),
        ],
      );
      final conditions = payload['conditions'] as List;
      expect(conditions, hasLength(2));
      expect((conditions[0] as Map)['frame_index'], 0);
      expect((conditions[0] as Map)['uri'], 'file:///a/first.png');
      expect((conditions[1] as Map)['frame_index'], -1);
      expect((conditions[1] as Map)['uri'], 'file:///b/last.png');
    });

    test('ref2va: references carry role reference and no frame_index key',
        () {
      final payload = buildMiniMaxH3VideoPayload(
        modelId: 'MiniMaxAI/MiniMax-H3',
        prompt: 'use the picture as the visual subject',
        media: const [
          MiniMaxH3Media(MiniMaxH3Role.reference, 'file:///r/reference.png'),
        ],
      );
      expect(payload['task'], 'ref2va');
      final condition = (payload['conditions'] as List).single as Map;
      expect(condition['role'], 'reference');
      // The key must be absent, not null: the cookbook's reference entries
      // carry no frame_index at all, and a null one is a different body.
      expect(condition.containsKey('frame_index'), isFalse);
    });

    test('aspect ratio: adaptive/auto/not_set normalize, explicit passes', () {
      Map<String, dynamic> target(String? aspect,
              {List<MiniMaxH3Media> media = const []}) =>
          buildMiniMaxH3VideoPayload(
            modelId: 'm',
            prompt: 'p',
            media: media,
            options: aspect == null ? null : {'aspectRatio': aspect},
          )['target'] as Map<String, dynamic>;

      const frame = [
        MiniMaxH3Media(MiniMaxH3Role.firstFrame, 'file:///f.png'),
      ];
      // Text-only has nothing to adapt to → 16:9, same substitution the
      // cloud builder makes for its `adaptive` spelling.
      expect(target('adaptive')['aspect_ratio'], '16:9');
      expect(target(null)['aspect_ratio'], '16:9');
      // With media, the shared `adaptive` option becomes H3-Base's `auto`.
      expect(target('adaptive', media: frame)['aspect_ratio'], 'auto');
      // An explicit ratio goes through verbatim on both shapes.
      expect(target('9:16')['aspect_ratio'], '9:16');
      expect(target('9:16', media: frame)['aspect_ratio'], '9:16');
    });

    test('duration clamps into the 4–15 s window and lands in both fields',
        () {
      Map<String, dynamic> body(String seconds) => buildMiniMaxH3VideoPayload(
            modelId: 'm',
            prompt: 'p',
            media: const [],
            options: {'seconds': seconds},
          );
      expect(body('2')['seconds'], 4);
      expect(body('30')['seconds'], 15);
      final b = body('12');
      expect(b['seconds'], 12);
      expect((b['target'] as Map)['duration_seconds'], 12.0);
    });
  });

  group('partitionMiniMaxH3Media', () {
    const first = MiniMaxH3Media(MiniMaxH3Role.firstFrame, 'file:///f.png');
    const last = MiniMaxH3Media(MiniMaxH3Role.lastFrame, 'file:///l.png');
    const ref = MiniMaxH3Media(MiniMaxH3Role.reference, 'file:///r.png');

    test('keyframes win and references are dropped', () {
      final (kept, dropped) = partitionMiniMaxH3Media(const [first, ref, last]);
      expect(kept, [first, last]);
      expect(dropped, [ref]);
    });

    test('references alone pass through untouched', () {
      final (kept, dropped) = partitionMiniMaxH3Media(const [ref]);
      expect(kept, [ref]);
      expect(dropped, isEmpty);
    });
  });

  group('minimaxH3FileUri', () {
    test('Windows paths become drive-letter file URIs', () {
      expect(minimaxH3FileUri(r'D:\refs\first frame.png', windows: true),
          'file:///D:/refs/first%20frame.png');
    });

    test('POSIX paths keep the documented file:///path shape', () {
      expect(minimaxH3FileUri('/data/minimax-h3/first-frame.png',
              windows: false),
          'file:///data/minimax-h3/first-frame.png');
    });
  });

  group('minimaxH3PollEnvelope', () {
    test('completed translates into the Veo-shaped done envelope', () {
      final envelope = minimaxH3PollEnvelope(
        {'id': 'video_abc', 'status': 'completed'},
        'video_abc',
        'http://127.0.0.1:30010/v1/videos/video_abc/content',
      );
      expect(envelope, {
        'name': 'video_abc',
        'done': true,
        'response': {
          'generateVideoResponse': {
            'generatedSamples': [
              {
                'video': {
                  'uri':
                      'http://127.0.0.1:30010/v1/videos/video_abc/content',
                },
              }
            ],
          },
        },
      });
    });

    test('succeeded is NOT this wire\'s word — it stays in-progress', () {
      // The ① surface's terminal word. If H3-Base ever said it this test
      // should fail loudly and force the vocabulary question to be re-asked,
      // rather than the two pollers quietly diverging.
      final envelope = minimaxH3PollEnvelope(
          {'status': 'succeeded'}, 'op', 'http://h/content');
      expect(envelope['done'], isFalse);
    });

    test('failed throws, carrying the operation name and the error', () {
      expect(
        () => minimaxH3PollEnvelope(
          {
            'status': 'failed',
            'error': {'message': 'out of VRAM'},
          },
          'video_abc',
          'http://h/content',
        ),
        throwsA(isA<LLMApiException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('video_abc'), contains('out of VRAM')),
        )),
      );
    });

    test('pending relays progress without marking done', () {
      final envelope = minimaxH3PollEnvelope(
          {'status': 'pending', 'progress': 40}, 'op', 'http://h/content');
      expect(envelope['done'], isFalse);
      expect(envelope['status'], 'pending');
      expect(envelope['progress'], 40);
    });
  });
}
