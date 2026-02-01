import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../llm_models.dart';
import '../llm_provider_interface.dart';

class OpenAIAPIProvider implements ILLMProvider {
  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
  }) async {
    final url = Uri.parse('${config.endpoint}/chat/completions');
    final headers = _getHeaders(config.apiKey);
    final payload = _preparePayload(config.modelId, history, options, isStreaming: false);

    final response = await http.post(url, headers: headers, body: jsonEncode(payload));

    if (response.statusCode != 200) {
      throw Exception('OpenAI API Request failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    String text = "";
    List<Uint8List> images = [];

    final message = data['choices']?[0]?['message'];
    if (message != null) {
      if (message['content'] != null) {
        text = message['content'];
      }
      
      if (message['image_data'] != null) {
        images.add(base64Decode(message['image_data']));
      }

      if (text.isNotEmpty) {
        final result = await _processTextAndExtractImages(text);
        text = result.text;
        images.addAll(result.images);
      }
    }

    return LLMResponse(
      text: text,
      generatedImages: images,
      metadata: data['usage'] ?? {},
    );
  }

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
  }) async* {
    final url = Uri.parse('${config.endpoint}/chat/completions');
    final headers = _getHeaders(config.apiKey);
    final payload = _preparePayload(config.modelId, history, options, isStreaming: true);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('OpenAI API Stream Request failed: ${response.statusCode}');
    }

    String accumulatedText = "";
    bool isLikelyBase64Stream = false;

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty || line == 'data: [DONE]') continue;
      
      String dataLine = line;
      if (line.startsWith('data: ')) {
        dataLine = line.substring(6);
      }

      try {
        final chunkData = jsonDecode(dataLine);
        final choice = chunkData['choices']?[0];
        if (choice == null) {
          if (chunkData['usage'] != null) {
            yield LLMResponseChunk(metadata: chunkData['usage']);
          }
          continue;
        }

        final delta = choice['delta'];
        final text = delta?['content'];
        final reasoning = delta?['reasoning_content'];
        final imageData = delta?['image_data'];
        
        if (reasoning != null && reasoning.isNotEmpty) {
          yield LLMResponseChunk(textPart: reasoning);
        }

        if (text != null && text.isNotEmpty) {
          accumulatedText += text;
          
          // Check if we are currently receiving a massive base64 string
          if (!isLikelyBase64Stream && accumulatedText.length > 500 && _isBase64Heuristic(accumulatedText)) {
            isLikelyBase64Stream = true;
          }

          // Only yield text to console if it doesn't look like raw image data
          if (!isLikelyBase64Stream && !_isBase64Heuristic(text)) {
            yield LLMResponseChunk(textPart: text);
          }
        }

        if (imageData != null) {
          yield LLMResponseChunk(
            imagePart: base64Decode(imageData),
            metadata: chunkData['usage'],
          );
        }
      } catch (e) {
        // Ignore parse errors
      }
    }

    if (accumulatedText.isNotEmpty) {
      final result = await _processTextAndExtractImages(accumulatedText);
      // If the text was mostly images, don't yield the messy leftover text
      if (result.text.length < accumulatedText.length * 0.1 || _isBase64Heuristic(result.text)) {
        // Skip yielding textPart
      } else if (isLikelyBase64Stream) {
        // If we suppressed it during streaming but it turned out to have valid text, yield it now
        yield LLMResponseChunk(textPart: result.text);
      }

      for (var img in result.images) {
        yield LLMResponseChunk(imagePart: img);
      }
    }
    
    yield LLMResponseChunk(isDone: true);
  }

  bool _isBase64Heuristic(String text) {
    if (text.length < 64) return false;
    // Check if it contains data URI prefix
    if (text.contains('data:image/')) return true;
    // Check if it's a long string of base64 characters with no spaces
    return text.length > 200 && !text.contains(' ') && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text.substring(0, 100));
  }

  Future<_TextProcessResult> _processTextAndExtractImages(String text) async {
    final List<Uint8List> images = [];
    String cleanText = text;

    // 1. Extract and remove Inline Base64
    final base64Regex = RegExp(r'data:image/[^;]+;base64,([a-zA-Z0-9+/=]+)');
    final b64Matches = base64Regex.allMatches(text);
    for (var match in b64Matches) {
      try {
        images.add(base64Decode(match.group(1)!));
        cleanText = cleanText.replaceFirst(match.group(0)!, '[Image Data]');
      } catch (e) { /* ignore */ }
    }

    // 2. Extract Cloud URLs
    final urlRegex = RegExp(r'(https?://storage\.googleapis\.com/[^\s"\]\)]+)');
    final urlMatches = urlRegex.allMatches(text);
    for (var match in urlMatches) {
      try {
        final url = match.group(1)!;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          images.add(response.bodyBytes);
        }
      } catch (e) { /* ignore */ }
    }

    return _TextProcessResult(cleanText.trim(), images);
  }

  Map<String, String> _getHeaders(String apiKey) {
    return {
      "Authorization": "Bearer $apiKey",
      "Content-Type": "application/json"
    };
  }

  Map<String, dynamic> _preparePayload(
    String modelId, 
    List<LLMMessage> history, 
    Map<String, dynamic>? options, 
    {required bool isStreaming}
  ) {
    final messages = history.map((msg) {
      dynamic content;
      
      if (msg.attachments.isEmpty) {
        content = msg.content;
      } else {
        final parts = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          parts.add({"type": "text", "text": msg.content});
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
              "type": "image_url",
              "image_url": {
                "url": "data:${attachment.mimeType};base64,$b64Data"
              }
            });
          }
        }
        content = parts;
      }

      return {
        "role": msg.role.name,
        "content": content
      };
    }).toList();

    final payload = {
      "model": modelId,
      "messages": messages,
      "stream": isStreaming,
    };

    if (isStreaming) {
      payload["stream_options"] = {"include_usage": true};
    }

    if (modelId.contains('gemini-3') || modelId.contains('image')) {
      final extraBody = {
        "response_modalities": ["text", "image"],
        "google": {
          "generation_config": {
            "imageConfig": {}
          }
        }
      };

      if (options != null) {
        final imageConfig = <String, dynamic>{};
        if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
          imageConfig['aspect_ratio'] = options['aspectRatio'];
        }
        if (options.containsKey('imageSize')) imageConfig['image_size'] = options['imageSize'];
        if (imageConfig.isNotEmpty) {
          (extraBody["google"] as Map)["generation_config"]["imageConfig"] = imageConfig;
        }
      }
      payload["extra_body"] = extraBody;
    }

    return payload;
  }
}

class _TextProcessResult {
  final String text;
  final List<Uint8List> images;
  _TextProcessResult(this.text, this.images);
}
