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
    }) =>
        buildDashScopeImagePayload(
          modelId: 'qwen-image-3.0',
          shape: ImageRequestShape.dashscopeQwen,
          prompt: prompt,
          imageRefs: refs,
          options: options,
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
      expect(body['parameters'], {'size': '1024*1024', 'prompt_extend': false});
    });

    test('sends no parameters block when nothing was chosen', () {
      expect(qwen().containsKey('parameters'), isFalse);
    });

    test('never sends n — the ceiling differs within one family', () {
      // qwen-image-edit takes n=1 where its siblings take 6, and 1 is the
      // upstream default, so the field can only cost a 400.
      final body = qwen(options: {'imageSize': '1024x1024'});
      expect(body.containsKey('n'), isFalse);
      expect((body['parameters'] as Map).containsKey('n'), isFalse);
    });

    test('prompt_extend is tri-state: unset leaves the upstream default on', () {
      expect(qwen().containsKey('parameters'), isFalse);
      expect(qwen(options: {'promptExtend': 'on'})['parameters'], {'prompt_extend': true});
      expect(qwen(options: {'promptExtend': 'off'})['parameters'], {'prompt_extend': false});
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
      expect(Vendors.byId(Vendors.dashscope).usesDashScopeNativeImages, isTrue);
      expect(Vendors.byId(Vendors.newApiOpenAI).usesDashScopeNativeImages, isFalse);
    });

    test('a synchronous image request outlives the 120 s chat guard', () {
      // The generation is billed before the client gives up, so the default
      // guard would turn a paid result into a timeout message.
      final timeout = LLMDispatcher().generateTimeout(config('qwen-image-3.0', Vendors.dashscope));
      expect(timeout, greaterThan(const Duration(seconds: 120)));
    });

    test('chat models on the same channel keep the short guard', () {
      expect(
        LLMDispatcher().generateTimeout(config('qwen-max', Vendors.dashscope)),
        const Duration(seconds: 120),
      );
    });

    test('Midjourney keeps its own exemption, independent of the model id', () {
      expect(
        LLMDispatcher().generateTimeout(config('anything', Vendors.midjourneyProxy)),
        const Duration(minutes: 11),
      );
    });
  });
}
