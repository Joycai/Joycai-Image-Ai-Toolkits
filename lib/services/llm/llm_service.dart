import 'dart:async';
import 'dart:typed_data';

import '../database_service.dart';
import 'llm_models.dart';
import 'llm_provider_interface.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final Map<String, ILLMProvider> _providers = {};
  final Map<String, List<LLMMessage>> _sessions = {};

  Function(String, {String level, String? contextId})? onLogAdded;

  void registerProvider(String type, ILLMProvider provider) {
    _providers[type] = provider;
  }

  Future<LLMResponse> request({
    required dynamic modelIdentifier,
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
  }) async {
    String accumulatedText = "";
    List<Uint8List> accumulatedImages = [];
    Map<String, dynamic> metadata = {};

    await for (final chunk in requestStream(
      modelIdentifier: modelIdentifier,
      messages: messages,
      sessionId: sessionId,
      contextId: contextId,
      options: options,
    )) {
      if (chunk.textPart != null) accumulatedText += chunk.textPart!;
      if (chunk.imagePart != null) accumulatedImages.add(chunk.imagePart!);
      if (chunk.metadata != null) metadata = chunk.metadata!;
    }

    return LLMResponse(
      text: accumulatedText,
      generatedImages: accumulatedImages,
      metadata: metadata,
    );
  }

  Stream<LLMResponseChunk> requestStream({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (PK)
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
  }) async* {
    onLogAdded?.call('Preparing request for model: $modelIdentifier', level: 'DEBUG', contextId: contextId);
    final config = await _getModelConfig(modelIdentifier, contextId: contextId);
    final provider = _getProvider(config.type);

    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    onLogAdded?.call('Connecting to ${config.type} provider...', level: 'DEBUG', contextId: contextId);

    String accumulatedText = "";
    int imageCount = 0;
    Map<String, dynamic>? finalMetadata;
    
    await for (final chunk in provider.generateStream(config, fullHistory, options: options, logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId))) {
      if (chunk.textPart != null) {
        accumulatedText += chunk.textPart!;
        onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
      }
      if (chunk.imagePart != null) {
        imageCount++;
        onLogAdded?.call('Received image part ($imageCount)', level: 'DEBUG', contextId: contextId);
      }
      if (chunk.metadata != null) finalMetadata = chunk.metadata;
      yield chunk;
    }

    onLogAdded?.call('Stream completed. Total images: $imageCount', level: 'DEBUG', contextId: contextId);

    // Unified Token Usage Recording
    if (finalMetadata != null) {
      onLogAdded?.call('Recording token usage...', level: 'DEBUG', contextId: contextId);
      _recordUsage(config.modelId, config, finalMetadata, modelPk: modelIdentifier is int ? modelIdentifier : null);
    }

    if (sessionId != null) {
      _sessions[sessionId]!.add(LLMMessage(
        role: LLMRole.assistant,
        content: accumulatedText,
      ));
    }
  }

  Future<void> _recordUsage(String modelId, LLMModelConfig config, Map<String, dynamic> metadata, {int? modelPk}) async {
    final db = DatabaseService();
    
    // Standardize metadata keys (OpenAI vs Google)
    final inputTokens = metadata['promptTokenCount'] ?? metadata['prompt_tokens'] ?? 0;
    final outputTokens = metadata['candidatesTokenCount'] ?? metadata['completion_tokens'] ?? 0;

    await db.recordTokenUsage({
      'task_id': 'req_${DateTime.now().millisecondsSinceEpoch}',
      'model_id': modelId,
      'model_pk': modelPk,
      'timestamp': DateTime.now().toIso8601String(),
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'input_price': config.inputFee,
      'output_price': config.outputFee,
      'request_count': 1,
      'request_price': config.requestFee,
      'billing_mode': config.billingMode,
    });
  }

  void clearSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  ILLMProvider _getProvider(String type) {
    final provider = _providers[type];
    if (provider == null) {
      throw Exception("LLM Provider for type '$type' not registered.");
    }
    return provider;
  }

  Future<LLMModelConfig> _getModelConfig(dynamic modelIdentifier, {String? contextId}) async {
    final db = DatabaseService();
    final models = await db.getModels();
    
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
      final feeGroups = await db.getFeeGroups();
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
      requestFee = (modelData['request_fee'] ?? 0.0) as double;
    }

    final type = modelData['type'] as String;
    final isPaid = modelData['is_paid'] == 1;
    final modelId = modelData['model_id'] as String;

    // Determine the Channel for configuration selection
    String channel;
    if (type == 'google-genai') {
      channel = isPaid ? 'google_paid' : 'google_free';
    } else {
      channel = 'openai'; // Standard OpenAI API channel
    }

    onLogAdded?.call('Using channel: $channel', level: 'DEBUG', contextId: contextId);

    final endpoint = await db.getSetting('${channel}_endpoint') ?? "";
    final apiKey = await db.getSetting('${channel}_apikey') ?? "";

    return LLMModelConfig(
      modelId: modelId,
      type: type,
      endpoint: endpoint,
      apiKey: apiKey,
      inputFee: inputFee,
      outputFee: outputFee,
      billingMode: billingMode,
      requestFee: requestFee,
    );
  }
}
