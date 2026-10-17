import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_value.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

GenerationSchema schemaFor(String model) => LLMDispatcher.generationSchemaFor(
  channelType: Vendors.dashscopeNative,
  modelId: model,
  tag: 'image',
);

Map<String, dynamic> payload(String model, Map<String, dynamic> options, {bool edit = false}) {
  final caps = ModelCapabilities.forModel(model);
  return buildDashScopeImagePayload(
    modelId: model,
    shape: caps.imageRequestShape,
    prompt: 'Draw a cat',
    imageRefs: edit ? ['https://example.com/input.png'] : [],
    options: options,
    sizeSpec: caps.imageParams.firstWhere((p) => p.key == 'imageSize'),
  );
}

void main() {
  for (final model in ['qwen-image-3.0', 'qwen-image-3.0-pro']) {
    test('$model native route and enhancement parameters', () {
      final schema = schemaFor(model);
      expect(schema.protocol, WireProtocol.dashscopeImagesSync);
      expect(schema.capabilities.maxReferenceImages, 3);
      final parameters = payload(model, {
        'imageSize': '1536x1024',
        'promptExtend': 'on',
        'promptExtendMode': 'agent',
        'imageThinking': 'off',
        'watermark': 'on',
      })['parameters'];
      expect(parameters, {
        'size': '1536*1024',
        'n': 1,
        'prompt_extend': true,
        'prompt_extend_mode': 'agent',
        'enable_thinking': false,
        'watermark': true,
      });
      expect(
        payload(model, {
          'promptExtend': 'off',
          'promptExtendMode': 'agent',
          'imageThinking': 'on',
        }, edit: true)['parameters'],
        {'n': 1, 'size': '1024*1024', 'prompt_extend': false},
      );
    });
    test('$model rejects Agent edits and disables enhancement when rewriting is off', () {
      final schema = schemaFor(model);
      const media = [GenerationMedia(GenerationMediaRole.reference, 'image.png')];
      final values = schema.readLegacy({'promptExtendMode': 'agent'});
      expect(schema.validate(values, media).map((d) => d.code), contains('agentTextOnly'));
      expect(
        () => payload(model, {'promptExtendMode': 'agent'}, edit: true),
        throwsA(isA<LLMApiException>()),
      );
      final disabled = schema.readLegacy({
        'promptExtend': 'off',
        'promptExtendMode': 'agent',
        'imageThinking': 'on',
      });
      final effective = schema.effective(disabled, GenerationOperation.editImage);
      expect(effective, isNot(contains('promptExtendMode')));
      expect(effective, isNot(contains('imageThinking')));
      expect(schema.validate(effective, media), isEmpty);
    });
  }

  test('Wan Pro blocks 4K edits in schema and shared sync/async payload builder', () {
    final schema = schemaFor('wan2.7-image-pro');
    expect(schema.capabilities.maxReferenceImages, 9);
    expect(schema.capabilities.supportsAsyncImageTask, isTrue);
    const media = [GenerationMedia(GenerationMediaRole.reference, 'image.png')];
    for (final size in ['4K', '4096x2304', '3072x1536']) {
      expect(
        payload('wan2.7-image-pro', {'imageSize': size})['parameters']['size'],
        size.replaceAll('x', '*'),
      );
      expect(
        schema.validate(schema.readLegacy({'imageSize': size}), media).map((d) => d.code),
        contains('wanEditSize'),
      );
      expect(
        () => payload('wan2.7-image-pro', {'imageSize': size}, edit: true),
        throwsA(isA<LLMApiException>()),
      );
    }
    for (final size in ['1K', '2K', '4096x1024']) {
      expect(schema.validate(schema.readLegacy({'imageSize': size}), media), isEmpty);
      expect(
        payload('wan2.7-image-pro', {'imageSize': size}, edit: true)['parameters']['size'],
        size.replaceAll('x', '*'),
      );
    }
    expect(
      payload('wan2.7-image-pro', {'imageThinking': 'off', 'watermark': 'off'})['parameters'],
      {'size': '1K', 'n': 1, 'thinking_mode': false, 'watermark': false},
    );
    expect(payload('wan2.7-image-pro', {'imageThinking': 'on'}, edit: true)['parameters'], {
      'size': '1K',
      'n': 1,
    });
    expect(schema.params.map((p) => p.key), isNot(contains('promptExtend')));
  });

  test('new Qwen usage dimensions outrank requested size without billing tokens', () {
    final metadata = dashscopeImageMetadata(
      data: {
        'usage': {
          'output_width': 1536,
          'output_height': 1024,
          'output_image_count': 1,
          'input_image_count': 2,
          'output_image_type': 'qima_output_1k',
        },
      },
      imageCount: 1,
      sentSize: '2048*2048',
      inputImages: 2,
    );
    expect(metadata['output_size'], '1536x1024');
    expect(metadata['image_count'], 1);
    expect(metadata['dashscope_usage']['output_image_type'], 'qima_output_1k');
    expect(metadata, isNot(contains('output_tokens')));
  });

  for (final model in ['qwen-image-3.0', 'wan2.7-image-pro']) {
    test('$model queued snapshots accept only additive defaults', () async {
      final schema = schemaFor(model);
      final oldValues = {
        'imageSize': schema.readLegacy({})['imageSize']!,
        'promptExtend': const GenerationValue(GenerationValueKind.unset),
      };
      final request = GenerationRequest(
        prompt: 'Draw a cat',
        operation: GenerationOperation.textImage,
        values: oldValues,
        media: [],
        modelId: model,
        channelType: Vendors.dashscopeNative,
        protocolId: schema.protocol!.id,
        profileId: model == 'qwen-image-3.0' ? 'dashscopeQwenImage' : schema.profileId,
      );
      expect(
        request.matches(model: model, vendor: Vendors.dashscopeNative, schema: schema),
        isTrue,
      );
      final options = {...request.legacyOptions, GenerationRequest.taskKey: request.toJson()};
      final history = [LLMMessage(role: LLMRole.user, content: 'Draw a cat')];
      await validateGeneration(schema, history, options);
      await expectLater(
        validateGeneration(schema, history, {...options, 'watermark': 'on'}),
        throwsA(isA<LLMApiException>()),
      );
    });
  }
}
