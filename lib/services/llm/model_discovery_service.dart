import 'llm_models.dart';

class DiscoveredModel {
  final String modelId;
  final String displayName;
  final String description;
  final Map<String, dynamic> rawData;

  DiscoveredModel({
    required this.modelId,
    required this.displayName,
    this.description = '',
    required this.rawData,
  });
}

abstract class IModelDiscoveryProvider {
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config);
}

class ModelDiscoveryService {
  static final ModelDiscoveryService _instance = ModelDiscoveryService._internal();
  factory ModelDiscoveryService() => _instance;
  ModelDiscoveryService._internal();

  final Map<String, IModelDiscoveryProvider> _providers = {};

  void registerProvider(String type, IModelDiscoveryProvider provider) {
    _providers[type] = provider;
  }

  Future<List<DiscoveredModel>> discoverModels(String type, LLMModelConfig config) async {
    final provider = _providers[type];
    if (provider == null) {
      throw Exception("Discovery Provider for type '$type' not registered.");
    }
    return await provider.fetchModels(config);
  }
}
