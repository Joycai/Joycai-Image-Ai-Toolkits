import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_provider_interface.dart';
import '../llm_types.dart';
import '../model_discovery_service.dart';
import '../model_family.dart';
import '../../../core/safety_settings.dart';
import 'google_auth.dart';
import 'google_payload.dart';

// Re-export the auth helpers so existing importers (and tests) of this file keep
// access to buildGoogleAuthHeaders / appendGoogleKey.
export 'google_auth.dart';

class GoogleDiscoveryProvider implements IModelDiscoveryProvider {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    final baseUrl = config.endpoint.endsWith('/') 
        ? config.endpoint.substring(0, config.endpoint.length - 1) 
        : config.endpoint;

    // Use /models as requested, but ensure auth is sent
    final url = appendGoogleKey(Uri.parse('$baseUrl/models'), config.apiKey, channelType: config.channelType);
    
    final headers = buildGoogleAuthHeaders(config.channelType, config.apiKey, config.endpoint);

    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> modelsJson = data['models'] ?? [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['name']?.toString().replaceFirst('models/', '') ?? '',
      displayName: m['displayName'] ?? m['name'] ?? '',
      description: m['description'] ?? '',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }
}

class GoogleGenAIProvider implements ILLMProvider {
  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    Function(String, {String level})? logger,
  }) async {
    // Imagen uses the dedicated `:predict` surface, not `:generateContent`.
    if (ModelFamilyClassifier.classify(config.modelId) == ModelFamily.geminiImagen) {
      return _generateImagen(config, history, options: options, logger: logger);
    }

    final url = appendGoogleKey(
        Uri.parse('${config.endpoint}/models/${config.modelId}:generateContent'), config.apiKey, channelType: config.channelType);
    logger?.call('Preparing Google GenAI request to: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = prepareGooglePayload(history, options, config.endpoint, tools: tools);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Standard)', {
          'url': url.toString(),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = jsonDecode(response.body);

      // Check for System-level errors (Section 3.3)
      if (data['error'] != null) {
        final err = data['error'];
        final msg = 'Google GenAI Error: [${err['code']}] ${err['message']} (${err['status']})';
        logger?.call(msg, level: 'ERROR');
        throw Exception(msg);
      }

      if (response.statusCode != 200) {
        logger?.call('Request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('Google GenAI Request failed: ${response.statusCode} - ${response.body}');
      }

      logger?.call('Response received, parsing data...', level: 'DEBUG');
      
      String text = "";
      List<Uint8List> images = [];
      List<LLMToolCall> toolCalls = [];
      Map<String, dynamic> metadata = {};

      for (final chunk in parseGoogleChunks(data, logger: logger)) {
        if (chunk.textPart != null) text += chunk.textPart!;
        if (chunk.imagePart != null) images.add(chunk.imagePart!);
        if (chunk.toolCallPart != null) toolCalls.add(chunk.toolCallPart!);
        if (chunk.metadata != null) metadata = chunk.metadata!;
      }

      logger?.call('Parse complete. Text length: ${text.length}, Images: ${images.length}, Tool calls: ${toolCalls.length}', level: 'DEBUG');

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
        toolCalls: toolCalls,
      );
    } finally {
      client.close();
    }
  }

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async* {
    // Imagen has no streaming surface — run the single-shot predict call and
    // emit its result as chunks.
    if (ModelFamilyClassifier.classify(config.modelId) == ModelFamily.geminiImagen) {
      final response = await _generateImagen(config, history, options: options, logger: logger);
      if (response.text.isNotEmpty) {
        yield LLMResponseChunk(textPart: response.text);
      }
      for (final img in response.generatedImages) {
        yield LLMResponseChunk(imagePart: img);
      }
      yield LLMResponseChunk(metadata: response.metadata, isDone: true);
      return;
    }

    final url = appendGoogleKey(
        Uri.parse('${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse'),
        config.apiKey, channelType: config.channelType);
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = prepareGooglePayload(history, options, config.endpoint);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Stream)', {
        'url': url.toString(),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      // Try to parse error from body if possible
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
      }
      client.close();
      try {
        final data = jsonDecode(body);
        if (data['error'] != null) {
          final err = data['error'];
          final msg = 'Google GenAI Stream Error: [${err['code']}] ${err['message']}';
          logger?.call(msg, level: 'ERROR');
          throw Exception(msg);
        }
      } catch (_) {}
      
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      throw Exception('Google GenAI Stream Request failed: ${response.statusCode}');
    }

    logger?.call('Stream connection established, waiting for chunks...', level: 'DEBUG');

    try {
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
      }
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;

        if (debugFile != null) {
          await LLMDebugLogger.appendLine(debugFile, line);
        }

        String dataLine = line;
        if (line.startsWith('data: ')) {
          dataLine = line.substring(6);
        }

        try {
          final chunkData = jsonDecode(dataLine);
          
          // Check for error in chunk
          if (chunkData['error'] != null) {
            final err = chunkData['error'];
            logger?.call('Stream Chunk Error: ${err['message']}', level: 'ERROR');
            throw Exception(err['message']);
          }

          yield* Stream.fromIterable(parseGoogleChunks(chunkData, logger: logger));
        } catch (e) {
          if (e is Exception) rethrow;
          // Ignore parse errors for empty/non-json lines
        }
      }
    } finally {
      client.close();
    }

    yield LLMResponseChunk(isDone: true);
  }

  @override
  Future<String> startLongRunning(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final baseUrl = config.endpoint.endsWith('/') 
        ? config.endpoint.substring(0, config.endpoint.length - 1) 
        : config.endpoint;
    final url = appendGoogleKey(
        Uri.parse('$baseUrl/models/${config.modelId}:predictLongRunning'), config.apiKey, channelType: config.channelType);
    
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = prepareVeoPayload(history, options);

    // Veo's :predictLongRunning surface has no safetySettings field — the
    // user-configured thresholds only apply to generateContent models.
    if (options?[SafetySettings.paramKey] != null) {
      logger?.call('Safety settings not supported by Veo API — skipped.', level: 'DEBUG');
    }

    // Debug logging for the user to see what's happening
    // Never log the full URL: for Google channels it carries `?key=<API_KEY>`
    // (see appendGoogleKey), and this logger feeds the user-visible console.
    logger?.call('POST URL: ${redactUrl(url)}', level: 'DEBUG');
    logger?.call('Headers: ${headers.keys.join(', ')}', level: 'DEBUG');
    
    // Log payload structure (without large data)
    final safePayload = getSafePayload(payload);
    logger?.call('Payload Structure: ${jsonEncode(safePayload)}', level: 'DEBUG');

    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleVeo (LRO Start)', {
          'url': url.toString(),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data['error'] != null) {
        final err = data['error'];
        final msg = 'Google LRO Error: [${err['code']}] ${err['message']}';
        logger?.call(msg, level: 'ERROR');
        throw Exception(msg);
      }

      if (response.statusCode != 200) {
        throw Exception('Google LRO failed: ${response.statusCode} - ${response.body}');
      }

      final name = data['name'] as String?;
      if (name == null) {
        throw Exception('Failed to get operation name from response');
      }

      return name;
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  }) async {
    // Operation name usually starts with 'operations/'
    final url = appendGoogleKey(Uri.parse('${config.endpoint}/$operationName'), config.apiKey, channelType: config.channelType);
    logger?.call('Checking Google operation: $operationName', level: 'DEBUG');
    
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to check operation: ${response.statusCode} - ${response.body}');
      }

      return jsonDecode(response.body);
    } finally {
      client.close();
    }
  }

  /// Imagen text-to-image via the `:predict` endpoint.
  Future<LLMResponse> _generateImagen(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final baseUrl = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;
    final url = appendGoogleKey(
        Uri.parse('$baseUrl/models/${config.modelId}:predict'), config.apiKey, channelType: config.channelType);
    logger?.call('Preparing Imagen request to: ${url.host}', level: 'DEBUG');

    // Imagen is text-to-image only — surface (rather than silently drop) any
    // reference images the user attached.
    final refCount = history
        .where((m) => m.role == LLMRole.user)
        .expand((m) => m.attachments)
        .length;
    if (refCount > 0) {
      logger?.call(
        'Imagen does not support reference images; ignoring $refCount attached image(s).',
        level: 'WARN',
      );
    }

    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = prepareImagenPayload(history, options);

    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleImagen (Predict)', {
          'url': url.toString(),
          'headers': headers,
          'body': getSafePayload(payload),
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data['error'] != null) {
        final err = data['error'];
        final msg = 'Imagen Error: [${err['code']}] ${err['message']} (${err['status']})';
        logger?.call(msg, level: 'ERROR');
        throw Exception(msg);
      }

      if (response.statusCode != 200) {
        throw Exception('Imagen Request failed: ${response.statusCode} - ${response.body}');
      }

      final List<Uint8List> images = [];
      final predictions = data['predictions'] as List?;
      if (predictions != null) {
        for (final p in predictions) {
          final b64 = p['bytesBase64Encoded'] ?? p['image']?['bytesBase64Encoded'];
          if (b64 is String) {
            try {
              images.add(base64Decode(b64));
            } catch (_) {/* ignore */}
          }
        }
      }

      logger?.call('Imagen parse complete. Images: ${images.length}', level: 'DEBUG');
      return LLMResponse(text: '', generatedImages: images, metadata: {});
    } finally {
      client.close();
    }
  }

  Map<String, String> _getHeaders(String channelType, String apiKey, String endpoint) =>
      buildGoogleAuthHeaders(channelType, apiKey, endpoint);

}
