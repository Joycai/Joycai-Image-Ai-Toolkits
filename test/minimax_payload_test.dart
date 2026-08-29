import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_payload.dart';

/// Pins MiniMax's two native wire formats — the image body, the video body and
/// the base-URL derivation that lets one channel reach both from either chat
/// face. Everything here is the IO-free half of the protocols, which is the
/// only half a test can reach without an HTTP mock.
void main() {
  group('base derivation', () {
    test('every face of the host derives every other face', () {
      const faces = [
        'https://api.minimaxi.com',
        'https://api.minimaxi.com/',
        'https://api.minimaxi.com/v1',
        'https://api.minimaxi.com/v1/',
        'https://api.minimaxi.com/v2',
        'https://api.minimaxi.com/anthropic',
        'https://api.minimaxi.com/anthropic/v1',
        'https://api.minimaxi.com/anthropic/v1/',
      ];
      for (final endpoint in faces) {
        expect(minimaxOpenAIBase(endpoint), 'https://api.minimaxi.com/v1',
            reason: endpoint);
        expect(minimaxAnthropicBase(endpoint),
            'https://api.minimaxi.com/anthropic/v1',
            reason: endpoint);
        expect(minimaxV2Base(endpoint), 'https://api.minimaxi.com/v2',
            reason: endpoint);
      }
    });

    test('/anthropic/v1 is stripped whole, never as a bare /v1', () {
      // The failure this guards is silent: strip `/v1` off
      // `…/anthropic/v1` and the image surface resolves to
      // `…/anthropic/v1/image_generation`, which 404s with nothing in the
      // message about which half of the URL was wrong.
      expect(minimaxOpenAIBase('https://api.minimaxi.com/anthropic/v1'),
          'https://api.minimaxi.com/v1');
    });

    test('derivation is idempotent and keys off the path only', () {
      final once = minimaxV2Base('https://api.minimaxi.com/v1');
      expect(minimaxV2Base(once), once);
      // A corporate gateway or a regional host works unchanged.
      expect(minimaxOpenAIBase('https://gateway.internal/minimax/v1'),
          'https://gateway.internal/minimax/v1');
      expect(minimaxV2Base('https://gateway.internal/minimax/v1'),
          'https://gateway.internal/minimax/v2');
    });
  });

  group('image payload', () {
    test('text-to-image sends no subject_reference', () {
      final body = buildMiniMaxImagePayload(
        modelId: 'image-01',
        prompt: 'a lighthouse',
        subjectRefs: const [],
      );
      expect(body['model'], 'image-01');
      expect(body['prompt'], 'a lighthouse');
      expect(body['response_format'], 'url');
      expect(body.containsKey('subject_reference'), isFalse);
      // Absent, not defaulted: the field is only sent when asked for.
      expect(body.containsKey('aspect_ratio'), isFalse);
      expect(body.containsKey('prompt_optimizer'), isFalse);
    });

    test('a reference becomes a character subject, not an edit source', () {
      final body = buildMiniMaxImagePayload(
        modelId: 'image-01',
        prompt: 'her, on a beach',
        subjectRefs: const ['data:image/png;base64,AAA'],
      );
      expect(body['subject_reference'], [
        {'type': 'character', 'image_file': 'data:image/png;base64,AAA'},
      ]);
    });

    test('not_set leaves the ratio off; a real ratio is passed through', () {
      expect(
        buildMiniMaxImagePayload(
          modelId: 'image-01',
          prompt: 'p',
          subjectRefs: const [],
          options: const {'aspectRatio': 'not_set'},
        ).containsKey('aspect_ratio'),
        isFalse,
      );
      expect(
        buildMiniMaxImagePayload(
          modelId: 'image-01',
          prompt: 'p',
          subjectRefs: const [],
          options: const {'aspectRatio': '21:9'},
        )['aspect_ratio'],
        '21:9',
      );
    });

    test('prompt_optimizer is tri-state, not a boolean with a default', () {
      Object? optimizer(String? value) => buildMiniMaxImagePayload(
            modelId: 'image-01',
            prompt: 'p',
            subjectRefs: const [],
            options: value == null ? null : {'promptExtend': value},
          )['prompt_optimizer'];
      expect(optimizer('on'), isTrue);
      expect(optimizer('off'), isFalse);
      // `not_set` must send nothing at all — sending `false` would pin a
      // default the vendor is free to change.
      expect(optimizer('not_set'), isNull);
      expect(optimizer(null), isNull);
    });
  });

  group('image response', () {
    test('reads both result spellings, in declaration order', () {
      expect(
        minimaxImageRefs(const {
          'data': {
            'image_urls': ['https://a', 'https://b'],
          }
        }),
        ['https://a', 'https://b'],
      );
      // A relay may answer in the other spelling even though the request
      // pinned `url`; reading only the requested one turns that into "no
      // image returned" with the bytes sitting in the body.
      expect(
        minimaxImageRefs(const {
          'data': {
            'image_base64': ['AAA'],
          }
        }),
        ['AAA'],
      );
    });

    test('a missing or malformed data block yields nothing, never throws', () {
      expect(minimaxImageRefs(const {}), isEmpty);
      expect(minimaxImageRefs(const {'data': 'oops'}), isEmpty);
      expect(minimaxImageRefs(const {'data': {'image_urls': 'oops'}}), isEmpty);
      expect(
          minimaxImageRefs(const {
            'data': {
              'image_urls': ['', null],
            }
          }),
          isEmpty);
    });

    test('all-images-failed is an error even inside a 200 with status 0', () {
      // base_resp says the *request* succeeded; metadata says nothing was
      // generated. Without this the only symptom is an empty result list.
      expect(
        () => throwIfMiniMaxImagesFailed(const {
          'base_resp': {'status_code': 0},
          'metadata': {'success_count': 0, 'failed_count': 1},
        }),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('a partial success is not an error', () {
      expect(
        () => throwIfMiniMaxImagesFailed(const {
          'metadata': {'success_count': 1, 'failed_count': 2},
        }),
        returnsNormally,
      );
      expect(() => throwIfMiniMaxImagesFailed(const {}), returnsNormally);
    });
  });

  group('video payload', () {
    List<Map<String, dynamic>> content(Map<String, dynamic> body) =>
        (body['content'] as List).cast<Map<String, dynamic>>();

    test('the text item is always present and always first', () {
      final body = buildMiniMaxVideoPayload(
        modelId: 'MiniMax-H3',
        prompt: '',
        media: const [
          MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'data:image/png;base64,A'),
        ],
      );
      // Exactly one text item is mandatory upstream even for a pure
      // image-to-video request, so an empty prompt is still a text item.
      expect(content(body).first, {'type': 'text', 'text': ''});
      expect(content(body).where((c) => c['type'] == 'text'), hasLength(1));
    });

    test('roles are tags on content items, not separate fields', () {
      final body = buildMiniMaxVideoPayload(
        modelId: 'MiniMax-H3',
        prompt: 'p',
        media: const [
          MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'u1'),
          MiniMaxVideoMedia(MiniMaxVideoRole.lastFrame, 'u2'),
        ],
      );
      expect(content(body).sublist(1), [
        {'type': 'image_url', 'role': 'first_frame', 'url': 'u1'},
        {'type': 'image_url', 'role': 'last_frame', 'url': 'u2'},
      ]);
    });

    test('resolution and duration are always sent, with real defaults', () {
      // Both are required upstream with no server-side default, so "leave it
      // unset" is not available the way it is for an optional knob.
      final bare = buildMiniMaxVideoPayload(
          modelId: 'MiniMax-H3', prompt: 'p', media: const []);
      expect(bare['resolution'], '768P');
      expect(bare['duration'], 5);

      // The capability table carries MiniMax's own spelling; the builder
      // still accepts either case, because the value round-trips through
      // saved task parameters and a stored lowercase one must keep working.
      expect(minimaxVideoResolution(const {'resolution': '2K'}), '2K');
      expect(minimaxVideoResolution(const {'resolution': '768P'}), '768P');
      expect(minimaxVideoResolution(const {'resolution': '2k'}), '2K');
      expect(minimaxVideoResolution(const {'resolution': '768p'}), '768P');
      // An unrecognized tier (a shared 1080p dropdown, say) falls to the
      // cheaper of the two rather than 400ing.
      expect(minimaxVideoResolution(const {'resolution': '1080p'}), '768P');
      expect(minimaxVideoResolution(null), '768P');
    });

    test('duration is clamped into the documented 4-15s window', () {
      expect(minimaxVideoDuration(const {'seconds': '1'}), 4);
      expect(minimaxVideoDuration(const {'seconds': '30'}), 15);
      expect(minimaxVideoDuration(const {'seconds': '9'}), 9);
      expect(minimaxVideoDuration(const {'seconds': 'nonsense'}), 5);
    });

    test('a text-only request never asks for adaptive', () {
      // `adaptive` means "take the ratio from the input media"; with no media
      // there is nothing to adapt to and upstream demands an explicit value.
      final textOnly = buildMiniMaxVideoPayload(
        modelId: 'MiniMax-H3',
        prompt: 'p',
        media: const [],
        options: const {'aspectRatio': 'adaptive'},
      );
      expect(textOnly['ratio'], '16:9');

      expect(
        buildMiniMaxVideoPayload(
          modelId: 'MiniMax-H3',
          prompt: 'p',
          media: const [MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'u')],
          options: const {'aspectRatio': 'adaptive'},
        )['ratio'],
        'adaptive',
      );
      // An explicit ratio always wins, media or not.
      expect(
        buildMiniMaxVideoPayload(
          modelId: 'MiniMax-H3',
          prompt: 'p',
          media: const [],
          options: const {'aspectRatio': '9:16'},
        )['ratio'],
        '9:16',
      );
    });
  });

  group('video media exclusion', () {
    test('frames win over reference material when both are supplied', () {
      const media = [
        MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'r1'),
        MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'f'),
        MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'r2'),
      ];
      final (kept, dropped) = partitionMiniMaxVideoMedia(media);
      expect(kept.map((m) => m.url), ['f']);
      expect(dropped.map((m) => m.url), ['r1', 'r2']);
    });

    test('a pure reference request keeps everything', () {
      const media = [
        MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'r1'),
        MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'r2'),
      ];
      final (kept, dropped) = partitionMiniMaxVideoMedia(media);
      expect(kept, hasLength(2));
      expect(dropped, isEmpty);
    });

    test('a last frame counts as a frame, not as reference material', () {
      const media = [
        MiniMaxVideoMedia(MiniMaxVideoRole.lastFrame, 'l'),
        MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'r'),
      ];
      final (kept, dropped) = partitionMiniMaxVideoMedia(media);
      expect(kept.map((m) => m.url), ['l']);
      expect(dropped.map((m) => m.url), ['r']);
    });

    test('nothing in, nothing out', () {
      final (kept, dropped) = partitionMiniMaxVideoMedia(const []);
      expect(kept, isEmpty);
      expect(dropped, isEmpty);
    });
  });

  group('debug log redaction', () {
    test('base64 media is replaced by its type, public URLs are kept', () {
      final body = buildMiniMaxVideoPayload(
        modelId: 'MiniMax-H3',
        prompt: 'p',
        media: const [
          MiniMaxVideoMedia(
              MiniMaxVideoRole.firstFrame, 'data:image/png;base64,AAAA'),
          MiniMaxVideoMedia(
              MiniMaxVideoRole.referenceImage, 'https://example/img.png'),
        ],
      );
      final logged = minimaxPayloadForLog(body);
      final items = (logged['content'] as List).cast<Map>();
      expect(items[1]['url'], '[base64 image_url]');
      expect(items[2]['url'], 'https://example/img.png');
      // Redaction must not disturb anything else in the body.
      expect(logged['duration'], body['duration']);
      expect(logged['resolution'], body['resolution']);
    });
  });
}
