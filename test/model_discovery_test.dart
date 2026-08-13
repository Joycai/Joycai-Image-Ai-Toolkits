import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/midjourney_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  group('Model discovery', () {
    test('midjourney vendor lists the built-in catalog without any network', () async {
      final config = LLMModelConfig(
        modelId: 'discovery',
        channelType: Vendors.midjourneyProxy,
        endpoint: 'https://example.com',
        apiKey: 'k',
      );
      final target = LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );

      final models = await MidjourneyDiscoveryProtocol().fetchModels(target);

      expect(models, isNotEmpty);
      expect(models.map((m) => m.modelId), contains('midjourney'));
      expect(models.map((m) => m.modelId), contains('niji-journey'));
    });

    test('unknown channel types resolve to the generic OpenAI vendor', () {
      final vendor = Vendors.byId('some-unknown-type');
      expect(vendor.id, Vendors.openAIRest);
      expect(vendor.family, ProtocolFamily.openai);
    });
  });
}
