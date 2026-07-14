import 'dart:async';
import 'dart:typed_data';

import '../database_service.dart';
import 'llm_config_resolver.dart';
import 'llm_provider_interface.dart';
import 'llm_types.dart';

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
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    bool useStream = true,
  }) async {
    // Tool calling is only wired through the standard (non-streaming) path.
    if (tools != null && tools.isNotEmpty) {
      useStream = false;
    }
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

    final int maxRetries = options?['retryCount'] ?? 0;
    int attempt = 0;

    while (true) {
      try {
        if (useStream) {
          onLogAdded?.call('Connecting to ${config.type} provider (streaming)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG', contextId: contextId);
          String accumulatedText = "";
          List<Uint8List> accumulatedImages = [];
          Map<String, dynamic>? finalMetadata;

          final stream = provider.generateStream(
            config, 
            fullHistory, 
            options: options, 
            logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
          );

          await for (final chunk in stream.timeout(const Duration(seconds: 120))) {
            if (chunk.textPart != null) {
              accumulatedText += chunk.textPart!;
              onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
            }
            if (chunk.imagePart != null) {
              accumulatedImages.add(chunk.imagePart!);
            }
            if (chunk.metadata != null) finalMetadata = chunk.metadata;
          }
          
          final response = LLMResponse(
            text: accumulatedText,
            generatedImages: accumulatedImages,
            metadata: finalMetadata ?? {},
          );

          // Record usage
          if (response.metadata.isNotEmpty) {
            _recordUsage(config.modelId, config, response.metadata, modelDbId: modelIdentifier is int ? modelIdentifier : null);
          }

          // Update session
          if (sessionId != null) {
            _sessions[sessionId]!.add(LLMMessage(
              role: LLMRole.assistant,
              content: response.text,
            ));
          }

          return response;
        } else {
          onLogAdded?.call('Connecting to ${config.type} provider (standard)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG', contextId: contextId);
          final response = await provider.generate(
            config,
            fullHistory,
            options: options,
            tools: tools,
            logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
          ).timeout(const Duration(seconds: 120));
          if (response.text.isNotEmpty) {
            onLogAdded?.call('[AI]: ${response.text}', level: 'INFO', contextId: contextId);
          }

          // Record usage
          if (response.metadata.isNotEmpty) {
            _recordUsage(config.modelId, config, response.metadata, modelDbId: modelIdentifier is int ? modelIdentifier : null);
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
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || !_isRetryable(e)) {
          rethrow;
        }
        onLogAdded?.call('Request failed: $e. Retrying in 2 seconds...', level: 'WARN', contextId: contextId);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  bool _isRetryable(Object e) {
    // Only retry on network errors or 5xx server errors
    // The providers throw Exception('... statusCode - body') on non-200 responses
    final errorStr = e.toString();
    
    // Check for common network exceptions
    if (e is TimeoutException || errorStr.contains('SocketException') || errorStr.contains('Connection closed')) {
      return true;
    }

    // Check for 5xx status codes in the exception message
    final statusCodeMatch = RegExp(r'(\d{3})').firstMatch(errorStr);
    if (statusCodeMatch != null) {
      final code = int.tryParse(statusCodeMatch.group(1)!);
      if (code != null && code >= 500 && code < 600) {
        return true;
      }
    }

    return false;
  }

  Stream<LLMResponseChunk> requestStream({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
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

    final int maxRetries = options?['retryCount'] ?? 0;
    int attempt = 0;

    while (true) {
      try {
        String accumulatedText = "";
        int imageCount = 0;
        Map<String, dynamic>? finalMetadata;
        
        final stream = provider.generateStream(
          config, 
          fullHistory, 
          options: options, 
          logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
        );

        await for (final chunk in stream.timeout(const Duration(seconds: 120))) {
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
          _recordUsage(config.modelId, config, finalMetadata, modelDbId: modelIdentifier is int ? modelIdentifier : null);
        }

        if (sessionId != null) {
          _sessions[sessionId]!.add(LLMMessage(
            role: LLMRole.assistant,
            content: accumulatedText,
          ));
        }
        return; // Success, exit retry loop
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || !_isRetryable(e)) {
          rethrow;
        }
        onLogAdded?.call('Stream failed: $e. Retrying in 2 seconds...', level: 'WARN', contextId: contextId);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _recordUsage(String modelId, LLMModelConfig config, Map<String, dynamic> metadata, {int? modelDbId}) async {
    final db = DatabaseService();

    // Standardize metadata keys (OpenAI vs Google)
    final promptTokens = _asTokenCount(metadata['promptTokenCount'] ?? metadata['prompt_tokens']);
    final outputTokens = _asTokenCount(metadata['candidatesTokenCount'] ?? metadata['completion_tokens']);
    final cacheTokens = _extractCacheTokens(metadata, promptTokens);

    await db.recordTokenUsage({
      'task_id': 'req_${DateTime.now().millisecondsSinceEpoch}',
      'model_id': modelId,
      'model_pk': modelDbId,
      'timestamp': DateTime.now().toIso8601String(),
      // Both providers count cached tokens inside their prompt total, so the
      // cached part is subtracted out here — input_tokens and cache_tokens are
      // stored disjoint and sum back to the full input.
      'input_tokens': promptTokens - cacheTokens,
      'cache_tokens': cacheTokens,
      'output_tokens': outputTokens,
      'input_price': config.inputFee,
      'cache_price': config.effectiveCacheInputFee,
      'output_price': config.outputFee,
      'request_count': 1,
      'request_price': config.requestFee,
      'billing_mode': config.billingMode,
    });
  }

  /// Cache-hit tokens from a usage payload: `cachedContentTokenCount` (Google)
  /// or `prompt_tokens_details.cached_tokens` (OpenAI). Clamped to [promptTokens]
  /// so a malformed payload can never drive the uncached remainder negative.
  int _extractCacheTokens(Map<String, dynamic> metadata, int promptTokens) {
    final details = metadata['prompt_tokens_details'];
    final raw = metadata['cachedContentTokenCount'] ??
        (details is Map ? details['cached_tokens'] : null);
    return _asTokenCount(raw).clamp(0, promptTokens);
  }

  /// Token counts arrive as int, double or String depending on provider and
  /// transport; anything unparseable counts as zero.
  int _asTokenCount(dynamic value) {
    final count = value is num ? value.toInt() : (value is String ? int.tryParse(value) : null);
    return (count == null || count < 0) ? 0 : count;
  }

  void clearSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  Future<String> startLongRunning({
    required dynamic modelIdentifier,
    required List<LLMMessage> messages,
    String? contextId,
    Map<String, dynamic>? options,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    final provider = _getProvider(config.type);

    return await provider.startLongRunning(
      config,
      messages,
      options: options,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
  }

  Future<Map<String, dynamic>> checkOperation({
    required dynamic modelIdentifier,
    required String operationName,
    String? contextId,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    final provider = _getProvider(config.type);

    return await provider.checkOperation(
      config,
      operationName,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
  }

  ILLMProvider _getProvider(String type) {
    final provider = _providers[type];
    if (provider == null) {
      throw Exception("LLM Provider for type '$type' not registered.");
    }
    return provider;
  }
}
