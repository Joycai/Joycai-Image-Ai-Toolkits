import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_discovery_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_models.dart';

class MockDiscoveryProvider implements IModelDiscoveryProvider {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    return [
      DiscoveredModel(
        modelId: 'test-1',
        displayName: 'Test Model 1',
        rawData: {'id': 'test-1'},
      ),
      DiscoveredModel(
        modelId: 'test-2',
        displayName: 'Test Model 2',
        rawData: {'id': 'test-2'},
      ),
    ];
  }
}

void main() {
  group('ModelDiscoveryService', () {
    test('should register and discover models', () async {
      final service = ModelDiscoveryService();
      service.registerProvider('mock', MockDiscoveryProvider());

      final config = LLMModelConfig(
        modelId: 'none',
        type: 'mock',
        channelType: 'mock',
        endpoint: '',
        apiKey: '',
      );

      final models = await service.discoverModels('mock', config);

      expect(models.length, 2);
      expect(models[0].modelId, 'test-1');
      expect(models[1].displayName, 'Test Model 2');
    });

    test('should throw exception for unregistered provider', () {
      final service = ModelDiscoveryService();
      final config = LLMModelConfig(
        modelId: 'none',
        type: 'unknown',
        channelType: 'unknown',
        endpoint: '',
        apiKey: '',
      );

      expect(
        () => service.discoverModels('unknown', config),
        throwsA(isA<Exception>()),
      );
    });
  });
}
