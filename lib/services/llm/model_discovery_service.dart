import 'llm_dispatcher.dart';
import 'llm_types.dart';
import 'protocols/protocol.dart' show DiscoveredModel;

export 'protocols/protocol.dart' show DiscoveredModel;

/// Model listing facade. The discovery protocol is picked by the dispatcher
/// from the channel's vendor (layer 2), exactly like generation requests.
class ModelDiscoveryService {
  static final ModelDiscoveryService _instance = ModelDiscoveryService._internal();
  factory ModelDiscoveryService() => _instance;
  ModelDiscoveryService._internal();

  final LLMDispatcher _dispatcher = LLMDispatcher();

  Future<List<DiscoveredModel>> discoverModels(LLMModelConfig config) =>
      _dispatcher.discoverModels(config);
}
