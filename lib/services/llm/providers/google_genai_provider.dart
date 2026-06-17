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

/// Builds the auth headers for Google's REST dialect.
///
/// Google's API key is passed in `x-goog-api-key`. The official Google host
/// (`*.googleapis.com`) treats an `Authorization: Bearer <api-key>` header as an
/// OAuth2 access token, fails to validate it, and returns 401 — so the bearer
/// token is only sent to third-party relays that emulate the dialect and may
/// expect OpenAI-style auth.
@visibleForTesting
Map<String, String> buildGoogleAuthHeaders(
  String channelType,
  String apiKey,
  String endpoint,
) {
  final headers = {
    "Content-Type": "application/json",
    "x-goog-api-key": apiKey,
  };
  final host = Uri.tryParse(endpoint)?.host ?? '';
  final isOfficialGoogle = host.endsWith('googleapis.com');
  if (channelType != 'official-google-genai-api' && !isOfficialGoogle) {
    headers["Authorization"] = "Bearer $apiKey";
  }
  return headers;
}

/// Appends the API key as a `?key=` query parameter, matching Google's
/// documented REST examples (e.g. `...:generateContent?key=$GEMINI_API_KEY`).
///
/// This is equivalent to the `x-goog-api-key` header but is the most robust
/// form: it survives any proxy/relay that strips custom request headers.
/// Existing query parameters (such as `alt=sse`) are preserved.
@visibleForTesting
Uri appendGoogleKey(Uri url, String apiKey) {
  if (apiKey.isEmpty) return url;
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'key': apiKey,
  });
}

class GoogleDiscoveryProvider implements IModelDiscoveryProvider {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    final baseUrl = config.endpoint.endsWith('/') 
        ? config.endpoint.substring(0, config.endpoint.length - 1) 
        : config.endpoint;

    // Use /models as requested, but ensure auth is sent
    final url = appendGoogleKey(Uri.parse('$baseUrl/models'), config.apiKey);
    
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
    Function(String, {String level})? logger,
  }) async {
    // Imagen uses the dedicated `:predict` surface, not `:generateContent`.
    if (ModelFamilyClassifier.classify(config.modelId) == ModelFamily.geminiImagen) {
      return _generateImagen(config, history, options: options, logger: logger);
    }

    final url = appendGoogleKey(
        Uri.parse('${config.endpoint}/models/${config.modelId}:generateContent'), config.apiKey);
    logger?.call('Preparing Google GenAI request to: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = _preparePayload(history, options, config.endpoint);

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
      Map<String, dynamic> metadata = {};

      for (final chunk in _parseChunks(data, logger: logger)) {
        if (chunk.textPart != null) text += chunk.textPart!;
        if (chunk.imagePart != null) images.add(chunk.imagePart!);
        if (chunk.metadata != null) metadata = chunk.metadata!;
      }

      logger?.call('Parse complete. Text length: ${text.length}, Images: ${images.length}', level: 'DEBUG');

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
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
        config.apiKey);
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = _preparePayload(history, options, config.endpoint);

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

          yield* Stream.fromIterable(_parseChunks(chunkData, logger: logger));
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
        Uri.parse('$baseUrl/models/${config.modelId}:predictLongRunning'), config.apiKey);
    
    final headers = _getHeaders(config.channelType, config.apiKey, config.endpoint);
    final payload = _prepareVeoPayload(history, options);

    // Debug logging for the user to see what's happening
    logger?.call('POST URL: $url', level: 'DEBUG');
    logger?.call('Headers: ${headers.keys.join(', ')}', level: 'DEBUG');
    
    // Log payload structure (without large data)
    final safePayload = _getSafePayload(payload);
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

  Map<String, dynamic> _getSafePayload(Map<String, dynamic> payload) {
    // Recursively strip 'data' fields for logging
    final Map<String, dynamic> safe = {};
    payload.forEach((key, value) {
      if ( (key == 'data' || key == 'bytesBase64Encoded') && value is String && value.length > 100) {
        safe[key] = '<BASE64_DATA (${value.length} chars)>';
      } else if (value is Map<String, dynamic>) {
        safe[key] = _getSafePayload(value);
      } else if (value is List) {
        safe[key] = value.map((e) => e is Map<String, dynamic> ? _getSafePayload(e) : e).toList();
      } else {
        safe[key] = value;
      }
    });
    return safe;
  }

  @override
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  }) async {
    // Operation name usually starts with 'operations/'
    final url = appendGoogleKey(Uri.parse('${config.endpoint}/$operationName'), config.apiKey);
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
        Uri.parse('$baseUrl/models/${config.modelId}:predict'), config.apiKey);
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
    final payload = _prepareImagenPayload(history, options);

    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleImagen (Predict)', {
          'url': url.toString(),
          'headers': headers,
          'body': _getSafePayload(payload),
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

  Map<String, dynamic> _prepareImagenPayload(List<LLMMessage> history, Map<String, dynamic>? options) {
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );

    final parameters = <String, dynamic>{
      'sampleCount': 1,
      'personGeneration': 'allow_all',
    };
    if (options != null) {
      if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
        parameters['aspectRatio'] = options['aspectRatio'];
      }
      if (options.containsKey('imageSize')) {
        parameters['sampleImageSize'] = options['imageSize'];
      }
    }

    return {
      "instances": [
        {"prompt": userMsg.content}
      ],
      "parameters": parameters,
    };
  }

  Map<String, dynamic> _prepareVeoPayload(List<LLMMessage> history, Map<String, dynamic>? options) {
    final userMsg = history.lastWhere((m) => m.role == LLMRole.user);
    
    final instance = <String, dynamic>{
      "prompt": userMsg.content,
    };

    final referenceImages = <Map<String, dynamic>>[];

    for (var attachment in userMsg.attachments) {
      String? b64Data;
      if (attachment.path != null) {
        b64Data = base64Encode(File(attachment.path!).readAsBytesSync());
      } else if (attachment.bytes != null) {
        b64Data = base64Encode(attachment.bytes!);
      }

      if (b64Data != null) {
        // // Some Google REST APIs (like Veo in Google AI Studio) expect fields directly,
        // // without the 'inline_data' or 'inlineData' wrapper.
        // // We'll use snake_case for mime_type as it's common in generativelanguage REST.
        // final mediaData = {
        //   "inlineData": {
        //     "mimeType": attachment.mimeType,
        //     "data": b64Data
        //   }
        // };

        // Google Gen API doc is wrong, this code is get from ai studio, fuck google
        final mediaDataLegacy = {
            "mimeType": attachment.mimeType,
            "bytesBase64Encoded": b64Data
        };

        switch (attachment.referenceType) {
          case LLMReferenceType.firstFrame:
            instance['image'] = mediaDataLegacy;
            break;
          case LLMReferenceType.lastFrame:
            instance['lastFrame'] = mediaDataLegacy;
            break;
          case LLMReferenceType.asset:
            referenceImages.add({
              "image": mediaDataLegacy,
              "referenceType": "asset"
            });
            break;
          default:
            referenceImages.add({
              "image": mediaDataLegacy,
              "referenceType": "asset"
            });
        }
      }
    }

    if (referenceImages.isNotEmpty) {
      instance['referenceImages'] = referenceImages;
    }

    final parameters = <String, dynamic>{};
    if (options != null) {
      // Keep parameters as camelCase for now as per LRO standard, 
      // but switch if errors persist.
      if (options.containsKey('resolution')) parameters['resolution'] = options['resolution'];
      if (options.containsKey('aspectRatio')) parameters['aspectRatio'] = options['aspectRatio'];
    }

    return {
      "instances": [instance],
      if (parameters.isNotEmpty) "parameters": parameters,
    };
  }

  Iterable<LLMResponseChunk> _parseChunks(Map<String, dynamic> chunkData, {Function(String, {String level})? logger}) sync* {
    Map<String, dynamic>? metadata = chunkData['usageMetadata'];

    // Check for prompt blocking (e.g. prohibited content)
    if (chunkData['promptFeedback'] != null) {
      final feedback = chunkData['promptFeedback'] as Map<String, dynamic>;
      final blockReason = feedback['blockReason'];
      if (blockReason != null) {
        final msg = 'Google GenAI Blocked: $blockReason';
        logger?.call(msg, level: 'ERROR');
        
        // If we have metadata, yield it before throwing so tokens can be recorded if needed
        if (metadata != null) {
          yield LLMResponseChunk(metadata: metadata);
        }
        throw Exception(msg);
      }
    }

    final candidates = chunkData['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      if (metadata != null) {
        yield LLMResponseChunk(metadata: metadata);
      }
      return;
    }

    for (var candidate in candidates) {
      final finishReason = candidate['finishReason'] as String?;
      
      // Handle Safety and other non-STOP reasons (Section 3.3)
      if (finishReason != null && finishReason != 'STOP') {
        String level = 'INFO';
        if (finishReason == 'SAFETY') level = 'WARN';
        if (finishReason == 'RECITATION') level = 'WARN';
        if (finishReason == 'OTHER') level = 'ERROR';
        
        logger?.call('Generation finished with reason: $finishReason', level: level);
        
        if (finishReason == 'SAFETY') {
          logger?.call('Content was flagged by safety filters.', level: 'WARN');
          if (candidate['safetyRatings'] != null) {
            final ratings = candidate['safetyRatings'] as List;
            for (var r in ratings) {
              if (r['probability'] != 'NEGLIGIBLE') {
                logger?.call('Safety: ${r['category']} is ${r['probability']}', level: 'DEBUG');
              }
            }
          }
        }
      }

      final parts = candidate['content']?['parts'] as List?;
      if (parts != null) {
        for (var part in parts) {
          final textPart = part['text'] as String?;
          
          // Spec prioritizes inlineData (Section 2)
          final inlineData = part['inlineData'] ?? part['inline_data'];
          final imgData = inlineData?['data'];

          yield LLMResponseChunk(
            textPart: textPart,
            imagePart: imgData != null ? base64Decode(imgData as String) : null,
            metadata: metadata,
          );
        }
      }
    }
  }

  Map<String, String> _getHeaders(String channelType, String apiKey, String endpoint) =>
      buildGoogleAuthHeaders(channelType, apiKey, endpoint);

  Map<String, dynamic> _preparePayload(List<LLMMessage> history, Map<String, dynamic>? options, String? endpoint) {
    final systemMessages = history.where((m) => m.role == LLMRole.system).toList();
    final conversationMessages = history.where((m) => m.role != LLMRole.system).toList();

    Map<String, dynamic>? systemInstruction;
    if (systemMessages.isNotEmpty) {
      systemInstruction = {
        "parts": systemMessages.map((m) => {"text": m.content}).toList()
      };
    }

    final contents = conversationMessages.map((msg) {
      final parts = <Map<String, dynamic>>[];

      if (msg.content.isNotEmpty) {
        parts.add({"text": msg.content});
      }

      for (var attachment in msg.attachments) {
        String? b64Data;
        if (attachment.path != null) {
          b64Data = base64Encode(File(attachment.path!).readAsBytesSync());
        } else if (attachment.bytes != null) {
          b64Data = base64Encode(attachment.bytes!);
        }

        if (b64Data != null) {
          parts.add({
            "inline_data": {
              "mime_type": attachment.mimeType,
              "data": b64Data
            }
          });
        }
      }

      return {
        "role": msg.role == LLMRole.user ? "user" : "model",
        "parts": parts
      };
    }).toList();

    final generationConfig = <String, dynamic>{};
    if (options != null) {
      final imageConfig = <String, dynamic>{};
      // personGeneration is Only for Imagen model
      // Only add aspectRatio if it's not "not_set"
      // if (endpoint?.contains("aabao") == false) {
      //   imageConfig['personGeneration'] = "ALLOW_ALL";
      // }
      if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
        imageConfig['aspectRatio'] = options['aspectRatio'];
      }
      if (options.containsKey('imageSize')) imageConfig['imageSize'] = options['imageSize'];
      if (imageConfig.isNotEmpty) generationConfig['imageConfig'] = imageConfig;
    }

    return {
      // ignore: use_null_aware_elements
      if (systemInstruction != null) "system_instruction": systemInstruction,
      "contents": contents,
      "generationConfig": generationConfig,
      "safetySettings": [
        {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
        {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
        {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
        {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"}
      ]
    };
  }
}
