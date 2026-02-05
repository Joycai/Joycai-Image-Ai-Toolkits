import 'dart:async';
import 'dart:typed_data';

import '../database_service.dart';
import 'llm_config_resolver.dart';
import 'llm_models.dart';
import 'llm_provider_interface.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final Map<String, ILLMProvider> _providers = {};
  final Map<String, List<LLMMessage>> _sessions = {};
  final LLMConfigResolver _configResolver = LLMConfigResolver();

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
    bool useStream = true,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    final provider = _getProvider(config.type);

    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    LLMResponse response;

    if (useStream) {
      onLogAdded?.call('Connecting to ${config.type} provider (streaming)...', level: 'DEBUG', contextId: contextId);
      String accumulatedText = "";
      List<Uint8List> accumulatedImages = [];
      Map<String, dynamic>? finalMetadata;

      await for (final chunk in provider.generateStream(
        config, 
        fullHistory, 
        options: options, 
        logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
      )) {
        if (chunk.textPart != null) {
          accumulatedText += chunk.textPart!;
          onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
        }
        if (chunk.imagePart != null) {
          accumulatedImages.add(chunk.imagePart!);
        }
        if (chunk.metadata != null) finalMetadata = chunk.metadata;
      }
      
      response = LLMResponse(
        text: accumulatedText,
        generatedImages: accumulatedImages,
        metadata: finalMetadata ?? {},
      );
    } else {
      onLogAdded?.call('Connecting to ${config.type} provider (standard)...', level: 'DEBUG', contextId: contextId);
      response = await provider.generate(
        config,
        fullHistory,
        options: options,
        logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
      );
      if (response.text.isNotEmpty) {
        onLogAdded?.call('[AI]: ${response.text}', level: 'INFO', contextId: contextId);
      }
    }

    // Record usage
    if (response.metadata.isNotEmpty) {
      _recordUsage(config.modelId, config, response.metadata, modelPk: modelIdentifier is int ? modelIdentifier : null);
    }

    // Update session
    if (sessionId != null) {
      _sessions[sessionId]!.add(LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
      ));
    }

    return response;
  }

  Stream<LLMResponseChunk> requestStream({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (PK)
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
  }) async* {
    onLogAdded?.call('Preparing request for model: $modelIdentifier', level: 'DEBUG', contextId: contextId);
    final config = await _configResolver.resolveConfig(
      modelIdentifier, 
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
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
}
