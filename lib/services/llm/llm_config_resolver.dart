import '../database_service.dart';
import 'llm_models.dart';

class LLMConfigResolver {
  final DatabaseService _db = DatabaseService();

  Future<LLMModelConfig> resolveConfig(dynamic modelIdentifier, {Function(String, {String level})? logger}) async {
    final models = await _db.getModels();
    
    Map<String, dynamic> modelData;
    
    if (modelIdentifier is int) {
      modelData = models.firstWhere(
        (m) => m['id'] == modelIdentifier,
        orElse: () => throw Exception("Model with PK $modelIdentifier not found"),
      );
    } else {
      // Fallback for legacy string IDs (takes the first match)
      modelData = models.firstWhere(
        (m) => m['model_id'] == modelIdentifier,
        orElse: () => throw Exception("Model $modelIdentifier not found in database"),
      );
    }

    // Fetch Fee Group
    final feeGroupId = modelData['fee_group_id'] as int?;
    double inputFee = 0.0;
    double outputFee = 0.0;
    String billingMode = 'token';
    double requestFee = 0.0;

    if (feeGroupId != null) {
      final feeGroups = await _db.getFeeGroups();
      final group = feeGroups.firstWhere((g) => g['id'] == feeGroupId, orElse: () => {});
      if (group.isNotEmpty) {
        inputFee = (group['input_price'] ?? 0.0) as double;
        outputFee = (group['output_price'] ?? 0.0) as double;
        billingMode = (group['billing_mode'] ?? 'token') as String;
        requestFee = (group['request_price'] ?? 0.0) as double;
      }
    } else {
      // Fallback to legacy columns if no group (shouldn't happen after migration)
      inputFee = (modelData['input_fee'] ?? 0.0) as double;
      outputFee = (modelData['output_fee'] ?? 0.0) as double;
      billingMode = (modelData['billing_mode'] ?? 'token') as String;
      requestFee = (modelData['request_price'] ?? 0.0) as double;
    }

    final type = modelData['type'] as String;
    final modelId = modelData['model_id'] as String;
    final channelId = modelData['channel_id'] as int?;

    if (channelId == null) {
      throw Exception("Model $modelId has no associated channel.");
    }

    final channelData = await _db.getChannel(channelId);
    if (channelData == null) {
      throw Exception("Channel for model $modelId not found.");
    }

    final endpoint = channelData['endpoint'] as String;
    final apiKey = channelData['api_key'] as String;
    final channelType = channelData['type'] as String;

    // Global Proxy Settings
    final proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    final proxyUrl = await _db.getSetting('proxy_url');
    final proxyUsername = await _db.getSetting('proxy_username');
    final proxyPassword = await _db.getSetting('proxy_password');

        return LLMModelConfig(

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

    