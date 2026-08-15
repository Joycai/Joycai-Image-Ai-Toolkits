import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database_service.dart';
import 'llm_config_resolver.dart';
import 'llm_dispatcher.dart';
import 'llm_types.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final Map<String, List<LLMMessage>> _sessions = {};
  final LLMConfigResolver _configResolver = LLMConfigResolver();
  final LLMDispatcher _dispatcher = LLMDispatcher();

  Function(String, {String level, String? contextId})? onLogAdded;

  Future<LLMResponse> request({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    bool useStream = true,
  }) async {
    // Tool calling is only wired through the standard (non-streaming) path —
    // see [ChatProtocol.generateStream]. Silently downgrading beats honouring
    // useStream: a caller that passed tools needs them, and a stream that
    // never declares them just answers as if there were none.
    if (tools != null && tools.isNotEmpty) {
      useStream = false;
    }
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
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
          onLogAdded?.call('Connecting to ${config.channelType} (streaming)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG', contextId: contextId);
          String accumulatedText = "";
          List<Uint8List> accumulatedImages = [];
          List<LLMToolCall> accumulatedToolCalls = [];
          Map<String, dynamic>? finalMetadata;

          final stream = _dispatcher.generateStream(
            config, 
            fullHistory, 
            options: options, 
            logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
          );

          await for (final chunk in stream.timeout(const Duration(seconds: 120))) {
            if (chunk.reasoningPart != null) {
              // Thinking is surfaced to the console but never accumulated —
              // the deliverable must not contain the chain of thought.
              onLogAdded?.call('[AI thinking]: ${chunk.reasoningPart}', level: 'DEBUG', contextId: contextId);
            }
            if (chunk.textPart != null) {
              accumulatedText += chunk.textPart!;
              onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
            }
            if (chunk.imagePart != null) {
              accumulatedImages.add(chunk.imagePart!);
            }
            // Collected rather than ignored: a dropped tool call reads to the
            // caller as "the model chose to answer directly", which is the one
            // failure mode an agent loop cannot detect. Not reachable while
            // the guard above forces tools onto the standard path, but the
            // guard is the reason, not an excuse for losing them here.
            if (chunk.toolCallPart != null) {
              accumulatedToolCalls.add(chunk.toolCallPart!);
            }
            if (chunk.metadata != null) finalMetadata = chunk.metadata;
          }

          final response = LLMResponse(
            text: accumulatedText,
            generatedImages: accumulatedImages,
            metadata: finalMetadata ?? {},
            toolCalls: accumulatedToolCalls,
          );

          // Record usage
          if (response.metadata.isNotEmpty) {
            _recordUsage(config.modelId, config, response.metadata, modelDbId: modelIdentifier is int ? modelIdentifier : null, taskTag: options?['usageTag']?.toString());
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
          onLogAdded?.call('Connecting to ${config.channelType} (standard)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG', contextId: contextId);
          final response = await _dispatcher.generate(
            config,
            fullHistory,
            options: options,
            tools: tools,
            logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
          ).timeout(_dispatcher.generateTimeout(config));
          if (response.text.isNotEmpty) {
            onLogAdded?.call('[AI]: ${response.text}', level: 'INFO', contextId: contextId);
          }

          // Record usage
          if (response.metadata.isNotEmpty) {
            _recordUsage(config.modelId, config, response.metadata, modelDbId: modelIdentifier is int ? modelIdentifier : null, taskTag: options?['usageTag']?.toString());
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
        if (attempt > maxRetries || !isRetryable(e)) {
          rethrow;
        }
        onLogAdded?.call('Request failed: $e. Retrying in 2 seconds...', level: 'WARN', contextId: contextId);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Whether a failed attempt is worth retrying: network-level failures and
  /// transient HTTP codes (5xx / 429), nothing else.
  ///
  /// Structured errors ([LLMApiException]) answer directly. The regex is a
  /// legacy fallback for protocols still throwing plain Exceptions with
  /// `... failed: <status> - <body>` prose — anchored to that shape because
  /// the old version grabbed the *first* three-digit number anywhere in the
  /// message, which read "retry after 500ms" in an error body as a server
  /// error and re-sent a request that was going to fail (and bill) again.
  @visibleForTesting
  static bool isRetryable(Object e) {
    if (e is TimeoutException) return true;
    if (e is LLMApiException) return e.isTransient;

    final errorStr = e.toString();
    if (errorStr.contains('SocketException') ||
        errorStr.contains('Connection closed')) {
      return true;
    }

    final statusCodeMatch =
        RegExp(r'failed:?\s+(\d{3})\b').firstMatch(errorStr);
    if (statusCodeMatch != null) {
      final code = int.tryParse(statusCodeMatch.group(1)!);
      if (code != null &&
          (code == 429 || (code >= 500 && code < 600))) {
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
    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    onLogAdded?.call('Connecting to ${config.channelType}...', level: 'DEBUG', contextId: contextId);

    final int maxRetries = options?['retryCount'] ?? 0;
    int attempt = 0;
    // Chunks already yielded to the consumer cannot be retracted, and there
    // is no reset signal in the chunk protocol — a retry after the first
    // yield would replay the stream from the start and duplicate everything
    // downstream (doubled text, duplicate images written to disk). So retry
    // only covers failures that happen before any chunk was delivered.
    var deliveredAnyChunk = false;

    while (true) {
      try {
        String accumulatedText = "";
        int imageCount = 0;
        Map<String, dynamic>? finalMetadata;
        
        final stream = _dispatcher.generateStream(
          config, 
          fullHistory, 
          options: options, 
          logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
        );

        await for (final chunk in stream.timeout(const Duration(seconds: 120))) {
          if (chunk.reasoningPart != null) {
            onLogAdded?.call('[AI thinking]: ${chunk.reasoningPart}', level: 'DEBUG', contextId: contextId);
          }
          if (chunk.textPart != null) {
            accumulatedText += chunk.textPart!;
            onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
          }
          if (chunk.imagePart != null) {
            imageCount++;
            onLogAdded?.call('Received image part ($imageCount)', level: 'DEBUG', contextId: contextId);
          }
          if (chunk.metadata != null) finalMetadata = chunk.metadata;
          deliveredAnyChunk = true;
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
        if (deliveredAnyChunk || attempt > maxRetries || !isRetryable(e)) {
          rethrow;
        }
        onLogAdded?.call('Stream failed: $e. Retrying in 2 seconds...', level: 'WARN', contextId: contextId);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _recordUsage(String modelId, LLMModelConfig config, Map<String, dynamic> metadata, {int? modelDbId, String? taskTag}) async {
    final db = DatabaseService();

    // Standardize metadata keys. Three spellings are in play: Google
    // (`promptTokenCount`), OpenAI chat (`prompt_tokens`) and the OpenAI
    // *Images* API (`input_tokens`) — gpt-image-1 reports only the third, so
    // reading the first two alone recorded every image generation as zero
    // tokens and only request-billed channels came out right.
    final promptTokens = _asTokenCount(metadata['promptTokenCount'] ??
        metadata['prompt_tokens'] ??
        metadata['input_tokens']);
    final outputTokens = _asTokenCount(metadata['candidatesTokenCount'] ??
        metadata['completion_tokens'] ??
        metadata['output_tokens']);
    final cacheTokens = _extractCacheTokens(metadata, promptTokens);

    await db.recordTokenUsage({
      // The tag makes delegated work distinguishable in the usage table
      // (e.g. `task_id LIKE 'subagent:%'`) — a sub-agent's spend should be
      // attributable to delegation, not blended into ordinary requests.
      'task_id': '${taskTag ?? 'req'}_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Cache-hit tokens from a usage payload: `cachedContentTokenCount` (Google),
  /// `prompt_tokens_details.cached_tokens` (OpenAI) or `cache_read_input_tokens`
  /// (Anthropic). Clamped to [promptTokens] so a malformed payload can never
  /// drive the uncached remainder negative.
  ///
  /// Anthropic's bucket is only comparable to the other two because its
  /// protocol already republished the *inclusive* prompt total as
  /// `prompt_tokens` — its own `input_tokens` excludes the cached part, so
  /// subtracting one from the other would count the cache twice.
  int _extractCacheTokens(Map<String, dynamic> metadata, int promptTokens) {
    final details = metadata['prompt_tokens_details'];
    final raw = metadata['cachedContentTokenCount'] ??
        metadata['cache_read_input_tokens'] ??
        (details is Map ? details['cached_tokens'] : null);
    return _asTokenCount(raw).clamp(0, promptTokens);
  }

  /// Token counts arrive as int, double or String depending on provider and
  /// transport; anything unparseable counts as zero.
  int _asTokenCount(dynamic value) {
    final count = value is num ? value.toInt() : (value is String ? int.tryParse(value) : null);
    return (count == null || count < 0) ? 0 : count;
  }

  /// Prompt tokens a response reported, or null when the provider did not
  /// report any.
  ///
  /// Absent must stay distinguishable from zero: `usage` is optional in the
  /// OpenAI-compatible response and llama.cpp, LM Studio and various proxies
  /// omit it. A caller that read "not reported" as "zero tokens" would
  /// conclude the context is empty on exactly the small local models that
  /// overflow first, so this returns null and lets them fall back.
  static int? promptTokensOf(Map<String, dynamic> metadata) {
    final raw = metadata['promptTokenCount'] ??
        metadata['prompt_tokens'] ??
        metadata['input_tokens'];
    if (raw == null) return null;
    final count = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    return (count == null || count <= 0) ? null : count;
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
    final operationName = await _dispatcher.startLongRunning(
      config,
      messages,
      options: options,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    // Video jobs never flow back through request()/requestStream(), so the
    // accepted submission is the only moment they can be billed at all —
    // without this every Veo/Sora/xAI generation was invisible to the metrics
    // page and to request-billed channels. Providers report no token usage at
    // submit time; the row records the request itself (tokens 0).
    _recordUsage(config.modelId, config, const {'operation': 'submit'},
        modelDbId: modelIdentifier is int ? modelIdentifier : null);
    return operationName;
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
    return await _dispatcher.checkOperation(
      config,
      operationName,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
  }
}
