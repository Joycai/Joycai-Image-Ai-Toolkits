import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../llm_models.dart';
import '../llm_provider_interface.dart';
import '../model_discovery_service.dart';

class GoogleDiscoveryProvider implements IModelDiscoveryProvider {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    final baseUrl = config.endpoint.endsWith('/') 
        ? config.endpoint.substring(0, config.endpoint.length - 1) 
        : config.endpoint;

    // Use /models as requested, but ensure auth is sent
    final url = Uri.parse('$baseUrl/models');
    
    final headers = {"Content-Type": "application/json"};
    if (config.channelType == 'official-google-genai-api') {
      headers["x-goog-api-key"] = config.apiKey;
    } else {
      headers["Authorization"] = "Bearer ${config.apiKey}";
      headers["x-goog-api-key"] = config.apiKey;
    }

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
    final url = Uri.parse('${config.endpoint}/models/${config.modelId}:generateContent');
    logger?.call('Preparing Google GenAI request to: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey);
    final payload = _preparePayload(history, options);

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

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
    final url = Uri.parse('${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse');
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.channelType, config.apiKey);
    final payload = _preparePayload(history, options);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final response = await client.send(request);

    if (response.statusCode != 200) {
      // Try to parse error from body if possible
      final body = await response.stream.bytesToString();
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
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;

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

  Iterable<LLMResponseChunk> _parseChunks(Map<String, dynamic> chunkData, {Function(String, {String level})? logger}) sync* {
    Map<String, dynamic>? metadata = chunkData['usageMetadata'];

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

  Map<String, String> _getHeaders(String channelType, String apiKey) {
    final headers = {"Content-Type": "application/json"};
    if (channelType == 'official-google-genai-api') {
      headers["x-goog-api-key"] = apiKey;
    } else {
      headers["Authorization"] = "Bearer $apiKey";
      headers["x-goog-api-key"] = apiKey;
    }
    return headers;
  }

  Map<String, dynamic> _preparePayload(List<LLMMessage> history, Map<String, dynamic>? options) {
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
      // Only add aspectRatio if it's not "not_set"
      imageConfig['personGeneration'] = "ALLOW_ALL";
      if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
        imageConfig['aspectRatio'] = options['aspectRatio'];
      }
      if (options.containsKey('imageSize')) imageConfig['imageSize'] = options['imageSize'];
      if (imageConfig.isNotEmpty) generationConfig['imageConfig'] = imageConfig;
    }

    return {
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
