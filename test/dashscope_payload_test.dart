import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins DashScope's native image surface: the rules that differ from every
/// other family and would otherwise only be discovered against the live,
/// billed endpoint.
void main() {
  group('dashscopeNativeBase', () {
    test('derives /api/v1 from the compatible-mode endpoint a channel stores', () {
      // The point of the derivation: one channel and one stored key serve
      // both chat (compatible-mode) and images (native).
      expect(
        dashscopeNativeBase('https://dashscope.aliyuncs.com/compatible-mode/v1'),
        'https://dashscope.aliyuncs.com/api/v1',
      );
    });

    test('is idempotent across the spellings a user can arrive with', () {
      const expected = 'https://dashscope.aliyuncs.com/api/v1';
      for (final input in [
        'https://dashscope.aliyuncs.com/compatible-mode/v1/',
        'https://dashscope.aliyuncs.com/compatible-mode',
        'https://dashscope.aliyuncs.com/api/v1',
        'https://dashscope.aliyuncs.com/api/v1/',
        'https://dashscope.aliyuncs.com',
      ]) {
        expect(dashscopeNativeBase(input), expected, reason: input);
      }
    });

    test('keys off the path, so the international host works untouched', () {
      // Why the mainland-only wizard preset costs nothing: a hand-typed intl
      // endpoint resolves the same way.
      expect(
        dashscopeNativeBase('https://dashscope-intl.aliyuncs.com/compatible-mode/v1'),
        'https://dashscope-intl.aliyuncs.com/api/v1',
      );
    });
  });

  group('dashscopeSize', () {
    test('rewrites WxH into DashScope spelling', () {
      expect(dashscopeSize({'imageSize': '1024x1024'}), '1024*1024');
      expect(dashscopeSize({'imageSize': '1536x1024'}), '1536*1024');
    });

    test('passes the wan presets through unchanged, upper-cased', () {
      expect(dashscopeSize({'imageSize': '1K'}), '1K');
      expect(dashscopeSize({'imageSize': '2k'}), '2K');
    });

    test('omits the field for defaults and for values left by another family', () {
      // Task options outlive the model they were picked for: an `auto` from a
      // previous OpenAI selection is a 400 on this endpoint.
      expect(dashscopeSize(null), isNull);
      expect(dashscopeSize({'imageSize': 'not_set'}), isNull);
      expect(dashscopeSize({'imageSize': 'auto'}), isNull);
      expect(dashscopeSize({'imageSize': '16:9'}), isNull);
    });
  });

  group('buildDashScopeImagePayload', () {
    const prompt = 'a cat';

    Map<String, dynamic> qwen({
      List<String> refs = const [],
      Map<String, dynamic>? options,
      ({int width, int height})? inputSize,
    }) =>
        buildDashScopeImagePayload(
          modelId: 'qwen-image-3.0',
          shape: ImageRequestShape.dashscopeQwen,
          prompt: prompt,
          imageRefs: refs,
          options: options,
          inputSize: inputSize,
        );

    test('qwen nests the conversation under input and leads with the images', () {
      final body = qwen(refs: ['data:image/png;base64,AAA']);
      expect(body.keys, containsAll(<String>['model', 'input']));
      expect(body.containsKey('messages'), isFalse);

      final content = ((body['input'] as Map)['messages'] as List).first['content'] as List;
      expect(content.first, {'image': 'data:image/png;base64,AAA'});
      expect(content.last, {'text': prompt});
    });

    test('wan puts messages at the top level and leads with the text', () {
      final body = buildDashScopeImagePayload(
        modelId: 'wan2.7-image',
        shape: ImageRequestShape.dashscopeWan,
        prompt: prompt,
        imageRefs: const ['https://example.com/a.png'],
      );
      expect(body.containsKey('input'), isFalse);

      final content = (body['messages'] as List).first['content'] as List;
      expect(content.first, {'text': prompt});
      expect(content.last, {'image': 'https://example.com/a.png'});
    });

    test('every knob lives in parameters, never at the top level', () {
      // Anything put at the top level is dropped silently — the endpoint
      // reads only model / input / parameters there.
      final body = qwen(options: {'imageSize': '1024x1024', 'promptExtend': 'off'});
      expect(body.keys.toSet(), {'model', 'input', 'parameters'});
      expect(body['parameters'],
          {'n': 1, 'size': '1024*1024', 'prompt_extend': false});
    });

    test('n is always sent, and always 1', () {
      // The upstream default is NOT 1 everywhere: wan2.7 defaults to four
      // images and bills each one, so a request that left `n` off bought four
      // pictures for one task. Every model in scope accepts 1.
      for (final shape in ImageRequestShape.values) {
        final body = buildDashScopeImagePayload(
          modelId: 'm',
          shape: shape,
          prompt: prompt,
          imageRefs: const [],
        );
        expect((body['parameters'] as Map)['n'], 1, reason: shape.name);
      }
    });

    test('prompt_extend is tri-state: unset leaves the upstream default on', () {
      expect((qwen()['parameters'] as Map).containsKey('prompt_extend'), isFalse);
      expect((qwen(options: {'promptExtend': 'on'})['parameters'] as Map)['prompt_extend'],
          isTrue);
      expect((qwen(options: {'promptExtend': 'off'})['parameters'] as Map)['prompt_extend'],
          isFalse);
    });

    group('size is always sent on the qwen dialect', () {
      // An unsized qwen-image request renders at 2048² and is billed at the
      // 2K tier — twice the price. "No size" therefore never goes out; the
      // author's choice or the dialect's 1K default does.
      test('text-to-image with nothing chosen is a 1K square', () {
        expect((qwen()['parameters'] as Map)['size'], '1024*1024');
        expect((qwen(options: {'imageSize': 'not_set'})['parameters'] as Map)['size'],
            '1024*1024');
      });

      test('a stale value from another family still gets the default, not nothing', () {
        expect((qwen(options: {'imageSize': 'auto'})['parameters'] as Map)['size'],
            '1024*1024');
      });

      test('an explicit choice is kept in the wire spelling', () {
        expect((qwen(options: {'imageSize': '1536x1024'})['parameters'] as Map)['size'],
            '1536*1024');
      });

      test('an edit with nothing chosen follows the input ratio at the 1K area', () {
        // Omitting size on an edit also follows the ratio — but at the 2K
        // area (768×1376 came back 1520×2736) and the 2K price.
        final body = qwen(
          refs: ['data:image/png;base64,AAA'],
          inputSize: (width: 768, height: 1376),
        );
        final size = (body['parameters'] as Map)['size'] as String;
        final m = RegExp(r'^(\d+)\*(\d+)$').firstMatch(size)!;
        final w = int.parse(m.group(1)!);
        final h = int.parse(m.group(2)!);
        expect(w % 16, 0);
        expect(h % 16, 0);
        expect(w * h, lessThanOrEqualTo(dashscopeQwenDefaultArea));
        expect(w * h, greaterThan(dashscopeQwenDefaultArea * 0.9));
        // Within one grid step of the source ratio.
        expect((w / h - 768 / 1376).abs(), lessThan(16 / h));
        expect(w, lessThan(h));
      });

      test('an edit whose input could not be measured falls back to the square', () {
        final body = qwen(refs: ['https://example.com/a.png']);
        expect((body['parameters'] as Map)['size'], '1024*1024');
      });
    });

    test('a model with no size control never receives one', () {
      // The basic qwen-image-edit has no `size` and 400s on it; that fact is
      // read off layer 3, which is why the builder takes it as a flag.
      final body = buildDashScopeImagePayload(
        modelId: 'qwen-image-edit',
        shape: ImageRequestShape.dashscopeQwen,
        prompt: prompt,
        imageRefs: const ['data:image/png;base64,AAA'],
        options: {'imageSize': '1024x1024'},
        inputSize: (width: 768, height: 1376),
        sendsSize: false,
      );
      expect((body['parameters'] as Map).containsKey('size'), isFalse);
      expect((body['parameters'] as Map)['n'], 1);
    });

    test('wan with nothing chosen sends the 1K tier, not nothing', () {
      // wan2.7's own omitted default is 2K, the same double-price trap.
      final body = buildDashScopeImagePayload(
        modelId: 'wan2.7-image',
        shape: ImageRequestShape.dashscopeWan,
        prompt: prompt,
        imageRefs: const [],
      );
      expect((body['parameters'] as Map)['size'], '1K');
    });
  });

  group('dashscopeQwenDefaultSize', () {
    test('no input is a 1K square', () {
      expect(dashscopeQwenDefaultSize(null), '1024*1024');
      expect(dashscopeQwenDefaultSize((width: 0, height: 10)), '1024*1024');
    });

    test('every ratio lands on the 16-grid just under the 1K area', () {
      for (final (w, h) in [(1, 1), (3, 2), (2, 3), (16, 9), (9, 16), (21, 9), (4, 5)]) {
        final size = dashscopeQwenDefaultSize((width: w * 100, height: h * 100));
        final m = RegExp(r'^(\d+)\*(\d+)$').firstMatch(size)!;
        final width = int.parse(m.group(1)!);
        final height = int.parse(m.group(2)!);
        expect(width % 16, 0, reason: size);
        expect(height % 16, 0, reason: size);
        expect(width * height, lessThanOrEqualTo(dashscopeQwenDefaultArea), reason: size);
        expect(width * height, greaterThan(dashscopeQwenDefaultArea * 0.9), reason: size);
      }
    });

    test('a square input is exactly the 1K square', () {
      expect(dashscopeQwenDefaultSize((width: 500, height: 500)), '1024*1024');
    });

    test('proportions past 8:1 are clamped, not refused', () {
      final strip = dashscopeQwenDefaultSize((width: 4000, height: 100));
      final m = RegExp(r'^(\d+)\*(\d+)$').firstMatch(strip)!;
      final w = int.parse(m.group(1)!);
      final h = int.parse(m.group(2)!);
      expect(w / h, lessThanOrEqualTo(8.0 + 16 / h));
      expect(h, greaterThanOrEqualTo(16));
    });
  });

  group('capabilities per DashScope image model', () {
    test('the basic qwen-image-edit declares no size control', () {
      final caps = ModelCapabilities.forModel('qwen-image-edit');
      expect(caps.imageParams.any((p) => p.key == 'imageSize'), isFalse);
      expect(caps.imageRequestShape, ImageRequestShape.dashscopeQwen);
    });

    test('its -max / -plus siblings and the generators keep it', () {
      for (final id in ['qwen-image-edit-max', 'qwen-image-edit-plus-2026-01-01', 'qwen-image-3.0-pro']) {
        expect(ModelCapabilities.forModel(id).imageParams.any((p) => p.key == 'imageSize'),
            isTrue,
            reason: id);
      }
    });
  });

  group('throwIfDashScopeError', () {
    test('a success body carries status_code 200 and must not throw', () {
      // Which is why the test is a non-empty `code`, not the presence of
      // status_code.
      expect(
        () => throwIfDashScopeError({
          'status_code': 200,
          'output': {
            'choices': [
              {
                'message': {
                  'content': [
                    {'image': 'https://example.com/a.png'}
                  ]
                }
              }
            ]
          },
        }),
        returnsNormally,
      );
    });

    test('a moderation refusal keeps its structured code', () {
      // Losing the code is what turns a refusal into prose, which the edit
      // fallback misreads as "this endpoint cannot edit" — a second, billed
      // generation.
      expect(
        () => throwIfDashScopeError({
          'status_code': 400,
          'code': 'DataInspectionFailed',
          'message': 'Input data may contain inappropriate content.',
          'request_id': 'abc-123',
        }),
        throwsA(isA<LLMApiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('DataInspectionFailed'), contains('abc-123')),
        )),
      );
    });

    test('a failed task reports through output rather than the top level', () {
      expect(
        () => throwIfDashScopeError({
          'status_code': 200,
          'output': {'task_status': 'FAILED', 'code': 'InvalidParameter', 'message': 'bad size'},
        }),
        throwsA(isA<LLMApiException>()),
      );
    });
  });

  group('dashscopeImageRefs', () {
    test('reads the chat-shaped answer of the synchronous surface', () {
      expect(
        dashscopeImageRefs({
          'output': {
            'choices': [
              {
                'message': {
                  'content': [
                    {'text': 'rewritten prompt'},
                    {'image': 'https://example.com/a.png'},
                  ]
                }
              }
            ]
          }
        }),
        ['https://example.com/a.png'],
      );
    });

    test('reads the result-list shape of the task surface', () {
      expect(
        dashscopeImageRefs({
          'output': {
            'results': [
              {'url': 'https://example.com/a.png'},
              {'url': 'https://example.com/b.png'},
            ]
          }
        }),
        ['https://example.com/a.png', 'https://example.com/b.png'],
      );
    });

    test('malformed or empty output yields nothing, never a throw', () {
      expect(dashscopeImageRefs({}), isEmpty);
      expect(dashscopeImageRefs({'output': 'nope'}), isEmpty);
      expect(dashscopeImageRefs({'output': {'choices': 'nope'}}), isEmpty);
      expect(dashscopeImageRefs({'output': {'results': [7]}}), isEmpty);
    });
  });

  group('classification', () {
    test('DashScope native image models get their own family', () {
      for (final id in ['qwen-image-3.0', 'qwen-image-edit', 'wan2.7-image', 'wan2.7-image-pro']) {
        expect(ModelFamilyClassifier.classify(id), ModelFamily.dashscopeImage, reason: id);
      }
    });

    test('the wan video ids that work today keep working', () {
      // The image rule sits *before* the video block, so this is the pin that
      // stops it from swallowing them.
      for (final id in ['wan2.5-t2v-preview', 'wan2.5-i2v-preview', 'wan2.5-t2v-plus']) {
        expect(ModelFamilyClassifier.classify(id), ModelFamily.openaiVideo, reason: id);
      }
    });

    test('a future wan2.7 video id is not claimed by the image rule', () {
      // Which is why the rule names `-image` instead of the `wan2.7` prefix.
      expect(
        ModelFamilyClassifier.classify('wan2.7-t2v'),
        isNot(ModelFamily.dashscopeImage),
      );
    });

    test('the family shows up as an image generator everywhere it matters', () {
      expect(ModelFamilyClassifier.isImageGeneration(ModelFamily.dashscopeImage), isTrue);
      expect(ModelFamilyClassifier.inferTag('qwen-image-3.0'), 'image');
    });
  });

  group('capabilities', () {
    test('reference-image ceilings are per model, not per family', () {
      expect(ModelDescriptor.of('qwen-image-edit').capabilities.maxReferenceImages, 3);
      expect(ModelDescriptor.of('wan2.7-image').capabilities.maxReferenceImages, 9);
    });

    test('each model declares the body shape its endpoint expects', () {
      expect(ModelDescriptor.of('qwen-image-3.0').capabilities.imageRequestShape,
          ImageRequestShape.dashscopeQwen);
      expect(ModelDescriptor.of('wan2.7-image-pro').capabilities.imageRequestShape,
          ImageRequestShape.dashscopeWan);
    });

    test('and declares that one request runs the whole generation', () {
      expect(ModelDescriptor.of('qwen-image-3.0').capabilities.longRunning, isTrue);
      expect(ModelDescriptor.of('gpt-image-1').capabilities.longRunning, isFalse);
    });
  });

  group('vendor + timeout', () {
    LLMModelConfig config(String modelId, String channelType) => LLMModelConfig(
          modelId: modelId,
          channelType: channelType,
          endpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          apiKey: 'k',
        );

    test('only the DashScope vendor claims the native image surface', () {
      expect(Vendors.byId(Vendors.dashscope).imageMenu,
          contains(WireProtocol.dashscopeImagesSync));
      expect(Vendors.byId(Vendors.newApiOpenAI).imageMenu, isEmpty);
    });

    test('a synchronous image request outlives a chat completion', () {
      // The generation is billed before the client gives up, so the default
      // guard would turn a paid result into a timeout message.
      expect(
        LLMDispatcher().generateTimeout(config('qwen-image-3.0', Vendors.dashscope)),
        greaterThan(
            LLMDispatcher().generateTimeout(config('qwen-max', Vendors.dashscope))),
      );
    });

    test('a chat model on the same channel stays well inside it', () {
      // Not the flat 120 s it used to be — the deadline now scales with the
      // output cap — but the longRunning exemption still has to mean
      // something, so a chat model must land under it.
      final chat =
          LLMDispatcher().generateTimeout(config('qwen-max', Vendors.dashscope));
      expect(chat, greaterThanOrEqualTo(const Duration(seconds: 120)));
      expect(chat, lessThan(const Duration(minutes: 5)));
    });

    test('Midjourney keeps its own exemption, independent of the model id', () {
      expect(
        LLMDispatcher().generateTimeout(config('anything', Vendors.midjourneyProxy)),
        const Duration(minutes: 11),
      );
    });

    test('and the image surfaces admit that their "stream" is one call', () {
      // The exemption above is worth nothing if the request goes out on the
      // streaming path instead: there the dispatcher awaits the whole
      // single-shot generate() and only then re-emits it as chunks, so the
      // first chunk cannot arrive before the task is finished. A model keeps
      // supports_stream set even when its async protocol is pinned, so this
      // is the path the app actually takes — and a first-chunk guard sized
      // for a live connection abandons a task that is billed and still
      // running.
      final dispatcher = LLMDispatcher();
      expect(
        dispatcher.streamIsSingleShot(config('qwen-image', Vendors.dashscope)),
        isTrue,
      );
      expect(
        dispatcher
            .streamIsSingleShot(config('qwen-image', Vendors.dashscopeNative)),
        isTrue,
      );
      // Chat on the same channel really does stream, and keeps the short
      // guard that says whether the connection is alive.
      expect(
        dispatcher.streamIsSingleShot(config('qwen-max', Vendors.dashscope)),
        isFalse,
      );
    });
  });
}
