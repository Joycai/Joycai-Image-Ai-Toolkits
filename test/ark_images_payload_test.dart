import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
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
}
