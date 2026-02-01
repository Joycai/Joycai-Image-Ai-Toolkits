import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../llm_models.dart';
import '../llm_provider_interface.dart';

class GoogleGenAIProvider implements ILLMProvider {
  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
  }) async {
    final url = Uri.parse('${config.endpoint}/models/${config.modelId}:generateContent?key=${config.apiKey}');
    final headers = _getHeaders(config.endpoint, config.apiKey);
    final payload = _preparePayload(history, options);

    final response = await http.post(url, headers: headers, body: jsonEncode(payload));

    if (response.statusCode != 200) {
      throw Exception('Google GenAI Request failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    String text = "";
    List<Uint8List> images = [];

    for (var candidate in data['candidates'] ?? []) {
      for (var part in candidate['content']?['parts'] ?? []) {
        if (part.containsKey('text')) {
          text += part['text'];
        }
        final imgData = part['inlineData']?['data'] ?? part['inline_data']?['data'];
        if (imgData != null) {
          images.add(base64Decode(imgData));
        }
      }
    }

    return LLMResponse(
      text: text,
      generatedImages: images,
      metadata: data['usageMetadata'] ?? {},
    );
  }

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
  }) async* {
    final url = Uri.parse('${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse&key=${config.apiKey}');
    final headers = _getHeaders(config.endpoint, config.apiKey);
    final payload = _preparePayload(history, options);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Google GenAI Stream Request failed: ${response.statusCode}');
    }

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      
      String dataLine = line;
      if (line.startsWith('data: ')) {
        dataLine = line.substring(6);
      }

      try {
        final chunkData = jsonDecode(dataLine);
        for (var candidate in chunkData['candidates'] ?? []) {
          for (var part in candidate['content']?['parts'] ?? []) {
            final text = part['text'];
            final imgData = part['inlineData']?['data'] ?? part['inline_data']?['data'];
            
            yield LLMResponseChunk(
              textPart: text,
              imagePart: imgData != null ? base64Decode(imgData) : null,
            );
          }
        }
      } catch (e) {
        // Handle potential JSON parse errors for non-data lines
      }
    }
    
    yield LLMResponseChunk(isDone: true);
  }

  Map<String, String> _getHeaders(String endpoint, String apiKey) {
    final headers = {"Content-Type": "application/json"};
    if (!endpoint.contains("generativelanguage.googleapis.com")) {
      headers["Authorization"] = "Bearer $apiKey";
      headers["x-goog-api-key"] = apiKey;
    }
    return headers;
  }

  Map<String, dynamic> _preparePayload(List<LLMMessage> history, Map<String, dynamic>? options) {
    // Separate system instructions from conversation contents
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
      if (options.containsKey('aspectRatio')) imageConfig['aspectRatio'] = options['aspectRatio'];
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
