import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_value.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: Vendors.xaiApi,
    modelId: 'grok-imagine-video',
    tag: 'video',
  );
  GenerationRequest request() => GenerationRequest(
    prompt: 'a cat',
    operation: GenerationOperation.textVideo,
    values: schema.readLegacy({'seconds': '9'}),
    media: const [],
    modelId: 'grok-imagine-video',
    channelType: Vendors.xaiApi,
    protocolId: schema.protocol?.id,
    profileId: schema.profileId,
  );

  test(
    'versioned snapshot round trips typed values, media and intent without runtime controls',
    () {
      final restored = GenerationRequest.fromJson(
        jsonDecode(jsonEncode(request().toJson())) as Map<String, dynamic>,
      );
      expect(restored.values['seconds'], const GenerationValue(GenerationValueKind.integer, 9));
      expect(restored.prompt, 'a cat');
      expect(restored.operation, GenerationOperation.textVideo);
      expect(restored.toJson(), isNot(contains('apiKey')));
      expect(restored.values.clear, throwsUnsupportedError);
      expect(restored.media.clear, throwsUnsupportedError);
    },
  );

  test('nested intent wins over stray flat keys; legacy task metadata survives unchanged', () {
    final options = generationTaskOptions({
      'generation': request().toJson(),
      'seconds': '1',
      'imagePrefix': 'keep',
    });
    expect(options['seconds'], '9');
    expect(options['imagePrefix'], 'keep');
    expect(generationTaskOptions({'prompt': 'old', 'seconds': '5', 'retryCount': 2}), {
      'prompt': 'old',
      'seconds': '5',
      'retryCount': 2,
    });
  });

  test('an unknown future codec is rejected, never treated as a legacy request', () {
    expect(
      () => GenerationRequest.fromJson({...request().toJson(), 'version': 99}),
      throwsFormatException,
    );
  });

  test('changing the queued protocol rejects before network access', () async {
    final config = LLMModelConfig(
      modelId: 'grok-imagine-video',
      channelType: Vendors.openAIRest,
      endpoint: 'http://127.0.0.1:1/v1',
      apiKey: 'unused',
      tag: 'video',
    );
    await expectLater(
      LLMDispatcher().startLongRunning(
        config,
        [LLMMessage(role: LLMRole.user, content: 'a cat')],
        options: {'generation': request().toJson()},
      ),
      throwsA(isA<LLMApiException>().having((e) => e.toString(), 'reason', contains('changed'))),
    );
  });

  test('compatible credential or endpoint updates leave the semantic contract valid', () {
    expect(
      request().matches(model: 'grok-imagine-video', vendor: Vendors.xaiApi, schema: schema),
      isTrue,
    );
    expect(request().matches(model: 'new-model', vendor: Vendors.xaiApi, schema: schema), isFalse);
  });
}
