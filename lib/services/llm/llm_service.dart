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

  Function(String, {String level})? onLogAdded;

  void registerProvider(String type, ILLMProvider provider) {
    _providers[type] = provider;
  }

  Future<LLMResponse> request({
    required String modelId,
    required List<LLMMessage> messages,
    String? sessionId,
    Map<String, dynamic>? options,
  }) async {
    String accumulatedText = "";
    List<Uint8List> accumulatedImages = [];
    Map<String, dynamic> metadata = {};

    await for (final chunk in requestStream(
      modelId: modelId,
      messages: messages,
      sessionId: sessionId,
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
    required String modelId,
    required List<LLMMessage> messages,
    String? sessionId,
    Map<String, dynamic>? options,
  }) async* {
    onLogAdded?.call('Preparing request for model: $modelId', level: 'DEBUG');
    final config = await _getModelConfig(modelId);
    final provider = _getProvider(config.type);

    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    onLogAdded?.call('Connecting to ${config.type} provider...', level: 'DEBUG');

    String accumulatedText = "";
    int imageCount = 0;
    Map<String, dynamic>? finalMetadata;
    
    await for (final chunk in provider.generateStream(config, fullHistory, options: options, logger: onLogAdded)) {
      if (chunk.textPart != null) {
        accumulatedText += chunk.textPart!;
        onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO');
      }
      if (chunk.imagePart != null) {
        imageCount++;
        onLogAdded?.call('Received image part ($imageCount)', level: 'DEBUG');
      }
      if (chunk.metadata != null) finalMetadata = chunk.metadata;
      yield chunk;
    }

    onLogAdded?.call('Stream completed. Total images: $imageCount', level: 'DEBUG');

    // Unified Token Usage Recording
    if (finalMetadata != null) {
      onLogAdded?.call('Recording token usage...', level: 'DEBUG');
      _recordUsage(modelId, config, finalMetadata);
    }

    if (sessionId != null) {
      _sessions[sessionId]!.add(LLMMessage(
        role: LLMRole.assistant,
        content: accumulatedText,
      ));
    }
  }

  Future<void> _recordUsage(String modelId, LLMModelConfig config, Map<String, dynamic> metadata) async {
    final db = DatabaseService();
    
    // Standardize metadata keys (OpenAI vs Google)
    final inputTokens = metadata['promptTokenCount'] ?? metadata['prompt_tokens'] ?? 0;
    final outputTokens = metadata['candidatesTokenCount'] ?? metadata['completion_tokens'] ?? 0;

    if (inputTokens > 0 || outputTokens > 0) {
      await db.recordTokenUsage({
        'task_id': 'req_${DateTime.now().millisecondsSinceEpoch}',
        'model_id': modelId,
        'timestamp': DateTime.now().toIso8601String(),
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'input_price': config.inputFee,
        'output_price': config.outputFee,
      });
    }
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

  Future<LLMModelConfig> _getModelConfig(String modelId) async {
    final db = DatabaseService();
    final models = await db.getModels();
    final modelData = models.firstWhere(
      (m) => m['model_id'] == modelId,
      orElse: () => throw Exception("Model $modelId not found in database"),
    );

    final type = modelData['type'] as String;
    final isPaid = modelData['is_paid'] == 1;
    final inputFee = (modelData['input_fee'] ?? 0.0) as double;
    final outputFee = (modelData['output_fee'] ?? 0.0) as double;

    String prefix = type == 'google-genai' 
        ? (isPaid ? 'google_paid' : 'google_free') 
        : 'openai';

    final endpoint = await db.getSetting('${prefix}_endpoint') ?? "";
    final apiKey = await db.getSetting('${prefix}_apikey') ?? "";

    return LLMModelConfig(
      modelId: modelId,
      type: type,
      endpoint: endpoint,
      apiKey: apiKey,
      inputFee: inputFee,
      outputFee: outputFee,
    );
  }
}
