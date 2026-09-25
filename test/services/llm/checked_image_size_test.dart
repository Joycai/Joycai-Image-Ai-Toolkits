import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Every image route checks the chosen size against the model's declared
/// size control before sending — DashScope always did; OpenAI Images,
/// Gemini, Imagen and Ark sent whatever was stored.
void main() {
  LLMTarget target(String modelId) => LLMTarget(
    config: LLMModelConfig(
      modelId: modelId,
      channelType: Vendors.openAIRest,
      endpoint: 'https://api.openai.com/v1',
      apiKey: 'k',
    ),
    vendor: Vendors.byId(Vendors.openAIRest),
    model: ModelDescriptor.of(modelId),
  );

  test('a size the model does not take becomes its default, logged', () {
    final logs = <String>[];
    final checked = optionsWithCheckedSize(target('gpt-image-1'), const {
      'imageSize': '4096x4096',
      'quality': 'high',
    }, logger: (m, {level = 'INFO'}) => logs.add('$level $m'));
    expect(checked!['imageSize'], 'auto');
    expect(checked['quality'], 'high');
    expect(logs.single, startsWith('WARN'));
    expect(OpenAIImagesProtocol.resolveImageSize(checked), isNull);
  });

  test('a free size is judged by the model rules', () {
    // gpt-image-2: area ≤ 8 294 400 — 3840x3840 is 14.7 MP.
    expect(
      optionsWithCheckedSize(target('gpt-image-2'), const {'imageSize': '3840x3840'})!['imageSize'],
      isNot('3840x3840'),
    );
    expect(
      optionsWithCheckedSize(target('gpt-image-2'), const {'imageSize': '2048x1152'})!['imageSize'],
      '2048x1152',
    );
  });

  test('valid, absent and undeclared sizes pass through untouched', () {
    const valid = {'imageSize': '1536x1024'};
    expect(identical(optionsWithCheckedSize(target('gpt-image-1'), valid), valid), isTrue);
    expect(optionsWithCheckedSize(target('gpt-image-1'), null), isNull);
    const chat = {'imageSize': 'whatever'};
    expect(identical(optionsWithCheckedSize(target('gpt-5'), chat), chat), isTrue);
  });
}
