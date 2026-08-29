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

    test('a response carrying both spellings is not counted twice', () {
      // A relay that mirrors the same images into both fields would otherwise
      // yield two refs per image, and the image task would write duplicate
      // files for one generation.
      expect(
        minimaxImageRefs(const {
          'data': {
            'image_urls': ['https://a'],
            'image_base64': ['AAA'],
          }
        }),
        ['https://a'],
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
      //
      // The counts are **strings** here because that is what the endpoint
      // actually sends (`"success_count": "3"`), despite the field being
      // documented as an integer. An int-only guard type-checks, passes an
      // int-fed test, and never fires in production.
      expect(
        () => throwIfMiniMaxImagesFailed(const {
          'base_resp': {'status_code': 0},
          'metadata': {'success_count': '0', 'failed_count': '1'},
        }),
        throwsA(isA<LLMApiException>()),
      );
      // A relay that re-serializes the body may hand back real integers.
      expect(
        () => throwIfMiniMaxImagesFailed(const {
          'metadata': {'success_count': 0, 'failed_count': 1},
        }),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('a partial success is not an error', () {
      for (final metadata in const [
        {'success_count': '1', 'failed_count': '2'},
        {'success_count': 1, 'failed_count': 2},
        // All succeeded, the ordinary case.
        {'success_count': '3', 'failed_count': '0'},
        // Unparseable counts must not be read as zero successes.
        {'success_count': 'n/a', 'failed_count': '1'},
      ]) {
        expect(() => throwIfMiniMaxImagesFailed({'metadata': metadata}),
            returnsNormally,
            reason: '$metadata');
      }
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

    test('the media URL is nested under its type, and role is a sibling', () {
      // Verbatim against the documented request sample. The two halves are
      // easy to conflate and only one of them is flat: `role` really does sit
      // beside `type`, but the URL lives inside a per-type object. Sending a
      // flat `url` is not rejected loudly — the request generates as though
      // nothing was attached, and it is billed.
      final body = buildMiniMaxVideoPayload(
        modelId: 'MiniMax-H3',
        prompt: 'p',
        media: const [
          MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'u1'),
          MiniMaxVideoMedia(MiniMaxVideoRole.lastFrame, 'u2'),
        ],
      );
      expect(content(body).sublist(1), [
        {
          'type': 'image_url',
          'image_url': {'url': 'u1'},
          'role': 'first_frame',
        },
        {
          'type': 'image_url',
          'image_url': {'url': 'u2'},
          'role': 'last_frame',
        },
      ]);
      // The URL must not also appear flat — a body carrying both spellings
      // would pass a nesting-only assertion while still being wrong.
      expect(content(body)[1].containsKey('url'), isFalse);
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

    test('only the two frame roles count as frames', () {
      // Spelled positively in the enum so a future reference_video /
      // reference_audio defaults to the reference side. An exclusion test
      // ("not a reference image") would call them frames and invert the rule.
      expect(MiniMaxVideoRole.firstFrame.isFrame, isTrue);
      expect(MiniMaxVideoRole.lastFrame.isFrame, isTrue);
      expect(MiniMaxVideoRole.referenceImage.isFrame, isFalse);
      expect(MiniMaxVideoRole.values.where((r) => r.isFrame), hasLength(2));
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
      // The redaction has to follow `type` to the nested media object; a
      // predicate reading a flat `url` finds nothing and silently passes the
      // whole base64 through into the log.
      expect(items[1]['image_url'], {'url': '[base64 image_url]'});
      expect(items[2]['image_url'], {'url': 'https://example/img.png'});
      // Roles and types survive redaction — the log is for reading.
      expect(items[1]['role'], 'first_frame');
      expect(items[2]['role'], 'reference_image');
      // Redaction must not disturb anything else in the body.
      expect(logged['duration'], body['duration']);
      expect(logged['resolution'], body['resolution']);
      // Nothing base64 anywhere in the rendered log.
      expect(logged.toString(), isNot(contains('AAAA')));
    });
  });
}
