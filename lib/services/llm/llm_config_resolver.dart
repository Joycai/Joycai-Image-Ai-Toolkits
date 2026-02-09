import '../../models/fee_group.dart';
import '../../models/llm_model.dart';
import '../database_service.dart';
import 'llm_models.dart';

class LLMConfigResolver {
  final DatabaseService _db = DatabaseService();

  Future<LLMModelConfig> resolveConfig(dynamic modelIdentifier, {Function(String, {String level})? logger}) async {
    final models = await _db.getModels();
    
    LLMModel modelData;
    
    if (modelIdentifier is int) {
      modelData = models.firstWhere(
        (m) => m.id == modelIdentifier,
        orElse: () => throw Exception("Model with PK $modelIdentifier not found"),
      );
    } else {
      // Fallback for legacy string IDs (takes the first match)
      modelData = models.firstWhere(
        (m) => m.modelId == modelIdentifier,
        orElse: () => throw Exception("Model $modelIdentifier not found in database"),
      );
    }

    // Fetch Fee Group
    final feeGroupId = modelData.feeGroupId;
    double inputFee = 0.0;
    double outputFee = 0.0;
    String billingMode = 'token';
    double requestFee = 0.0;

    if (feeGroupId != null) {
      final feeGroups = await _db.getFeeGroups();
      final group = feeGroups.cast<FeeGroup?>().firstWhere((g) => g?.id == feeGroupId, orElse: () => null);
      if (group != null) {
        inputFee = group.inputPrice;
        outputFee = group.outputPrice;
        billingMode = group.billingMode;
        requestFee = group.requestPrice;
      }
    }

    final type = modelData.type;
    final modelId = modelData.modelId;
    final channelId = modelData.channelId;

    if (channelId == null) {
      throw Exception("Model $modelId has no associated channel.");
    }

    final channelData = await _db.getChannel(channelId);
    if (channelData == null) {
      throw Exception("Channel for model $modelId not found.");
    }

    final endpoint = channelData.endpoint;
    final apiKey = channelData.apiKey;
    final channelType = channelData.type;

    // Global Proxy Settings
    final proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    final proxyUrl = await _db.getSetting('proxy_url');
    final proxyUsername = await _db.getSetting('proxy_username');
    final proxyPassword = await _db.getSetting('proxy_password');

    return LLMModelConfig(
      pk: modelData.id,
      modelId: modelId,
      type: type,
      channelType: channelType,
      endpoint: endpoint,
      apiKey: apiKey,
      inputFee: inputFee,
      outputFee: outputFee,
      billingMode: billingMode,
      requestFee: requestFee,
      proxyEnabled: proxyEnabled,
      proxyUrl: proxyUrl,
      proxyUsername: proxyUsername,
      proxyPassword: proxyPassword,
    );
  }
}