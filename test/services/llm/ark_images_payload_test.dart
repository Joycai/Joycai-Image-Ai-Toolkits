import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/ark_payload.dart';

/// The Ark image body and response rules (docs/api/volcengine-ark.md). Every
/// case here is one that, written wrong, still gets an answer from upstream:
/// a watermark nobody asked for, a group that silently shrinks, a ratio that
/// is ignored.
void main() {
  final pro = ModelCapabilities.forModel('doubao-seedream-5-0-pro-260628');
  final lite = ModelCapabilities.forModel('doubao-seedream-5.0-lite');
  const ref = 'data:image/png;base64,AAAA';

  Map<String, dynamic> build({
    List<String> refs = const [],
    Map<String, dynamic>? options,
    ModelCapabilities? caps,
    List<String>? warnings,
    String prompt = 'a red apple',
  }) =>
      buildArkImagePayload(
        modelId: 'doubao-seedream-5.0-lite',
        prompt: prompt,
        imageRefs: refs,
        tierPixelSizes: (caps ?? lite).tierPixelSizes,
        options: options,
        warn: warnings?.add,
      );

  group('request body', () {
    test('text-to-image with no options: tier-free, watermark off, url', () {
      expect(build(), {
        'model': 'doubao-seedream-5.0-lite',
        'prompt': 'a red apple',
        'watermark': false,
        'response_format': 'url',
      });
    });

    test('watermark is sent true only when asked', () {
      expect(build(options: {'watermark': 'on'})['watermark'], isTrue);
      expect(build(options: {'watermark': 'off'})['watermark'], isFalse);
    });

    test('one reference is a string, several are an array in order', () {
      expect(build(refs: [ref])['image'], ref);
      expect(build(refs: ['a', 'b', 'c'])['image'], ['a', 'b', 'c']);
      expect(build().containsKey('image'), isFalse);
    });

    test('tier alone when the ratio is automatic', () {
      final body = build(options: {'imageSize': '3K', 'aspectRatio': 'not_set'});
      expect(body['size'], '3K');
    });

    test('tier × ratio sends the version\'s own documented pixels', () {
      expect(build(options: {'imageSize': '2K', 'aspectRatio': '16:9'})['size'],
          '2848x1600');
      // 5.0 pro's 2K 16:9 differs from lite's.
      expect(
          build(caps: pro, options: {'imageSize': '2K', 'aspectRatio': '16:9'})[
              'size'],
          '2816x1584');
      expect(
          build(caps: pro, options: {'imageSize': '1.5K', 'aspectRatio': '1:1'})[
              'size'],
          '1536x1536');
    });

    test('a ratio with no tier uses the first mapped tier', () {
      final v30 = ModelCapabilities.forModel('doubao-seedream-3-0-t2i-250415');
      expect(build(caps: v30, options: {'aspectRatio': '16:9'})['size'],
          '1280x720');
    });

    test('an unmapped ratio falls back to the tier and says so', () {
      final warnings = <String>[];
      final body = build(
          warnings: warnings,
          options: {'imageSize': '2K', 'aspectRatio': '5:4'});
      expect(body['size'], '2K');
      expect(warnings, hasLength(1));
    });

    test('group generation: 1 sends nothing, more turns it on', () {
      expect(build(options: {'maxImages': '1'})
          .containsKey('sequential_image_generation'), isFalse);
      final body = build(options: {'maxImages': '4'});
      expect(body['sequential_image_generation'], 'auto');
      expect(body['sequential_image_generation_options'], {'max_images': 4});
    });

    test('references + group ceiling stay within 15, with a warning', () {
      final warnings = <String>[];
      final body = build(
          refs: List.filled(12, ref),
          warnings: warnings,
          options: {'maxImages': '6'});
      expect(body['sequential_image_generation_options'], {'max_images': 3});
      expect(warnings, hasLength(1));

      // 14 references leave room for one image: no group at all.
      final full = build(refs: List.filled(14, ref), options: {'maxImages': '6'});
      expect(full.containsKey('sequential_image_generation'), isFalse);
    });

    test('format, prompt optimization and web search map one to one', () {
      final body = build(options: {
        'outputFormat': 'png',
        'optimizeMode': 'fast',
        'webSearch': 'on',
      });
      expect(body['output_format'], 'png');
      expect(body['optimize_prompt_options'], {'mode': 'fast'});
      expect(body['tools'], [
        {'type': 'web_search'},
      ]);
      expect(build(options: {'webSearch': 'off'}).containsKey('tools'), isFalse);
    });
  });

  group('5.0 pro task modes', () {
    test('layers: exactly one reference, tier only, prompt optional', () {
      final body = build(
          caps: pro,
          prompt: '  ',
          refs: [ref],
          options: {
            'imageTask': 'layers',
            'imageSize': '2K',
            'aspectRatio': '16:9',
            'maxImages': '4',
          });
      expect(body['layer_decomposition'], isTrue);
      expect(body['size'], '2K', reason: 'the ratio has nothing to act on');
      expect(body.containsKey('prompt'), isFalse);
      expect(body.containsKey('sequential_image_generation'), isFalse);
    });

    test('layers with the tier unset send no size: upstream keeps the source',
        () {
      // `auto` is layer decomposition's default (§6) — the source's own size
      // inside [1280x720, 2K×1.1025]. Any tier sent forces a resample, and a
      // forced 2K (4.19 MP) is billed 0.6 元 where the source might have
      // stayed at 0.3.
      for (final unset in ['not_set', 'auto']) {
        final body = build(
            caps: pro,
            refs: [ref],
            options: {
              'imageTask': 'layers',
              'imageSize': unset,
              'aspectRatio': '16:9',
            });
        expect(body['layer_decomposition'], isTrue);
        expect(body.containsKey('size'), isFalse, reason: unset);
      }
    });

    test('generation with the tier unset is upstream\'s 2K, ratio included',
        () {
      expect(
          build(caps: pro, options: {'imageSize': 'not_set'})
              .containsKey('size'),
          isFalse);
      // A ratio with no tier takes upstream's default tier's pixels — 2K —
      // not the smallest tier the table lists.
      expect(
          build(caps: pro, options: {
            'imageSize': 'not_set',
            'aspectRatio': '16:9',
          })['size'],
          '2816x1584');
    });

    test('transparent: background set, PNG forced over a JPEG choice', () {
      final warnings = <String>[];
      final body = build(
          caps: pro,
          refs: [ref],
          warnings: warnings,
          options: {'imageTask': 'transparent', 'outputFormat': 'jpeg'});
      expect(body['background'], 'transparent');
      expect(body['output_format'], 'png');
      expect(warnings, hasLength(1));
    });

    test('both modes refuse anything but one reference, before sending', () {
      for (final task in ['layers', 'transparent']) {
        for (final refs in [<String>[], [ref, ref]]) {
          expect(
              () => build(caps: pro, refs: refs, options: {'imageTask': task}),
              throwsA(isA<LLMApiException>()
                  .having((e) => e.statusCode, 'statusCode', isNull)),
              reason: '$task with ${refs.length}');
        }
      }
    });
  });

  group('response', () {
    test('successes in order; per-image errors collected, not fatal', () {
      final r = parseArkImageResponse({
        'data': [
          {'url': 'https://x/1.jpeg', 'size': '2048x2048'},
          {
            'error': {
              'code': 'OutputImageSensitiveContentDetected',
              'message': 'blocked',
            },
          },
          {'b64_json': 'QUJD'},
          {'size': '1x1'},
        ],
        'usage': {'generated_images': 2, 'output_tokens': 32768},
      });
      expect([for (final i in r.images) i.ref], ['https://x/1.jpeg', 'QUJD']);
      expect(r.failures.single.code, 'OutputImageSensitiveContentDetected');
      expect(r.usage['generated_images'], 2);
    });

    test('a layer decomposition is delivered base first, bottom to top', () {
      final r = parseArkImageResponse({
        'data': [
          {'url': 'l2', 'z_index': 2, 'name': 'tagline'},
          {'url': 'base', 'z_index': 0},
          {'url': 'l1', 'z_index': 1, 'name': 'title'},
        ],
      });
      expect([for (final i in r.images) i.ref], ['base', 'l1', 'l2']);
      expect(r.images[1].name, 'title');
    });

    test('the live layer response carries names, descriptions and boxes', () {
      // Captured 2026-09-18 (plan endpoint, 5.0 pro, 1K, no prompt), links
      // shortened.
      final r = parseArkImageResponse({
        'data': [
          {'url': 'base', 'size': '912x1168', 'z_index': 0, 'output_format': 'jpeg'},
          {
            'url': 'layer',
            'size': '861x1137',
            'z_index': 1,
            'output_format': 'png',
            'name': '魔法少女立绘主体',
            'description': '一名穿着华丽服饰的魔法少女',
            'bounding_box': {
              'absolute': [27, 0, 888, 1137],
              'normalized': [30, 0, 973, 973],
            },
          },
        ],
      });
      final base = r.images.first.layer!;
      expect(base.zIndex, 0);
      expect(base.box, isNull);
      final layer = r.images.last.layer!;
      expect(layer.zIndex, 1);
      expect(layer.name, '魔法少女立绘主体');
      expect(layer.description, '一名穿着华丽服饰的魔法少女');
      expect(layer.box, const LayerBox(27, 0, 888, 1137));
      expect(layer.box!.width, 861);
    });

    test('an ordinary image has no layer; a malformed box is dropped', () {
      final r = parseArkImageResponse({
        'data': [
          {'url': 'plain'},
          {'url': 'odd', 'z_index': 1, 'bounding_box': {'absolute': [5, 5, 5, 9]}},
          {'url': 'short', 'z_index': 2, 'bounding_box': {'absolute': [1, 2]}},
        ],
      });
      expect(r.images.map((i) => i.ref), ['odd', 'short', 'plain']);
      expect(r.images.last.layer, isNull);
      expect(r.images[0].layer!.box, isNull);
      expect(r.images[1].layer!.box, isNull);
    });

    test('the live 5.0 pro response shape parses', () {
      // Captured 2026-09-18 (plan endpoint, 1K, png), link shortened.
      final r = parseArkImageResponse({
        'model': 'doubao-seedream-5-0-pro',
        'created': 1789701354,
        'data': [
          {
            'url': 'https://ark-acg-cn-beijing.tos-cn-beijing.volces.com/x.png',
            'size': '1248x832',
            'output_format': 'png',
          },
        ],
        'usage': {
          'input_images': 0,
          'generated_images': 1,
          'output_tokens': 4056,
          'total_tokens': 4056,
        },
      });
      expect(r.images, hasLength(1));
      expect(r.failures, isEmpty);
    });
  });

  group('result metadata', () {
    test('Ark\'s charged count is published beside what was delivered', () {
      // Two drawn and billed, one link undownloadable: the row must still
      // charge two (docs/api/volcengine-ark.md §4 — billed by
      // `generated_images`).
      final meta = arkResultMetadata(
        delivered: 1,
        failed: 0,
        usage: const {'generated_images': 2, 'output_tokens': 32448},
        refCount: 0,
      );
      expect(meta['image_count'], 1);
      expect(meta[billedImageCountKey], 2);
      expect(meta['ark_usage'], {'generated_images': 2, 'output_tokens': 32448});
      expect(meta.containsKey(inputImageCountKey), isFalse);
    });

    test('no usable charged count publishes none', () {
      for (final usage in [
        const <String, dynamic>{},
        const {'generated_images': 0},
        const {'generated_images': 'two'},
        const {'generated_images': double.nan},
      ]) {
        final meta = arkResultMetadata(
            delivered: 2, failed: 0, usage: usage, refCount: 0);
        expect(meta.containsKey(billedImageCountKey), isFalse,
            reason: '$usage');
        expect(meta['image_count'], 2);
      }
    });

    test('the echoed pixels are published only when no tier was chosen', () {
      // 「自动」 on 5.0 pro draws upstream's 2K — 0.6 元, where 1K / 1.5K are
      // 0.3 — and the request names no tier to match it by.
      Map<String, dynamic> meta(List<String?> sizes, {required bool left}) =>
          arkResultMetadata(
            delivered: sizes.length,
            failed: 0,
            usage: const {},
            refCount: 0,
            renderedSizes: sizes,
            tierLeftToUpstream: left,
          );
      expect(meta(['2816x1584', '2816x1584'], left: true)['output_size'],
          '2816x1584');
      // A chosen tier is what Ark prices; pixels matched to the nearest
      // tier a two-row table lists would put 1.5K on its 2K row.
      expect(meta(['2048x1152'], left: false).containsKey('output_size'),
          isFalse);
      // A decomposition's base and layers differ; the row has one size.
      for (final sizes in [
        ['912x1168', '861x1137'],
        ['912x1168', null],
        <String?>[null],
        ['big'],
        <String?>[],
      ]) {
        expect(meta(sizes, left: true).containsKey('output_size'), isFalse,
            reason: '$sizes');
      }
    });

    test('a tier is left to upstream by its absence or a sentinel', () {
      expect(arkTierLeftToUpstream(null), isTrue);
      expect(arkTierLeftToUpstream(const {}), isTrue);
      expect(arkTierLeftToUpstream(const {'imageSize': 'not_set'}), isTrue);
      expect(arkTierLeftToUpstream(const {'imageSize': 'auto'}), isTrue);
      expect(arkTierLeftToUpstream(const {'imageSize': '1.5K'}), isFalse);
    });

    test('the item carries Ark\'s echoed size', () {
      final r = parseArkImageResponse({
        'data': [
          {'url': 'https://x/a.jpeg', 'size': '2048x2048'},
          {'url': 'https://x/b.jpeg'},
        ],
      });
      expect(r.images.map((i) => i.size), ['2048x2048', null]);
      final streamed = parseArkStreamEvent({
        'type': 'image_generation.partial_succeeded',
        'url': 'https://x/c.jpeg',
        'size': '2848x1600',
      }) as ArkStreamImage;
      expect(streamed.item.size, '2848x1600');
    });

    test('failures and 5.0 pro\'s reported inputs ride along', () {
      final meta = arkResultMetadata(
        delivered: 1,
        failed: 1,
        usage: const {'input_images': 2, 'generated_images': 1},
        refCount: 3,
      );
      expect(meta['failed_images'], 1);
      expect(meta[billedImageCountKey], 1);
      expect(meta[inputImageCountKey], 2, reason: 'Ark\'s count outranks ours');
      expect(
          arkResultMetadata(delivered: 1, failed: 0, usage: const {}, refCount: 3)[
              inputImageCountKey],
          3);
    });
  });

  group('streaming', () {
    test('which versions declare it: lite, 4.5, 4.0 — not pro, 3.0, generic',
        () {
      for (final id in [
        'doubao-seedream-5.0-lite',
        'doubao-seedream-5-0-lite-260128',
        'doubao-seedream-4-5-251128',
        'doubao-seedream-4-0-250828',
      ]) {
        expect(ModelCapabilities.forModel(id).streamsImages, isTrue,
            reason: id);
      }
      for (final id in [
        'doubao-seedream-5-0-pro-260628',
        'doubao-seedream-3-0-t2i-250415',
        'doubao-seedream-latest', // version unreadable → generic table
      ]) {
        final caps = ModelCapabilities.forModel(id);
        expect(caps.isImageGenerator, isTrue, reason: id);
        expect(caps.streamsImages, isFalse, reason: id);
      }
    });

    test('`stream` is sent only when asked for', () {
      expect(build().containsKey('stream'), isFalse);
      final body = buildArkImagePayload(
          modelId: 'm', prompt: 'p', imageRefs: const [], stream: true);
      expect(body['stream'], isTrue);
    });

    test('events, as captured on the plan (§5)', () {
      final image = parseArkStreamEvent({
        'type': 'image_generation.partial_succeeded',
        'model': 'doubao-seedream-5.0-lite',
        'created': 1,
        'image_index': 1,
        'url': 'https://x/1.jpeg',
        'size': '2496x1664',
      });
      expect(image, isA<ArkStreamImage>());
      image as ArkStreamImage;
      expect(image.item.ref, 'https://x/1.jpeg');
      expect(image.index, 1);

      final done = parseArkStreamEvent({
        'type': 'image_generation.completed',
        'usage': {'generated_images': 2, 'output_tokens': 32448},
      });
      expect(done, isA<ArkStreamCompleted>());
      expect((done as ArkStreamCompleted).usage['generated_images'], 2);
    });

    test('a failed image, under `error` or at the top level', () {
      final nested = parseArkStreamEvent({
        'type': 'image_generation.partial_failed',
        'image_index': 0,
        'error': {'code': 'OutputImageSensitiveContentDetected', 'message': 'x'},
      });
      expect((nested as ArkStreamFailure).failure.code,
          'OutputImageSensitiveContentDetected');
      final flat = parseArkStreamEvent({
        'type': 'image_generation.partial_failed',
        'code': 'C',
        'message': 'm',
      });
      expect((flat as ArkStreamFailure).failure.toString(), 'C: m');
    });

    test('unknown or empty events are skipped, not fatal', () {
      expect(parseArkStreamEvent({'type': 'image_generation.progress'}), isNull);
      expect(parseArkStreamEvent({}), isNull);
      expect(
          parseArkStreamEvent(
              {'type': 'image_generation.partial_succeeded', 'url': ''}),
          isNull);
      final b64 = parseArkStreamEvent(
          {'type': 'image_generation.partial_succeeded', 'b64_json': 'AAAA'});
      expect((b64 as ArkStreamImage).item.ref, 'AAAA');
      expect(b64.index, isNull);
    });
  });
}
