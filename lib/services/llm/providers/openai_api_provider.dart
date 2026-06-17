import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_provider_interface.dart';
import '../llm_types.dart';
import '../model_discovery_service.dart';
import '../model_family.dart';

/// OpenAI-compatible transport.
///
/// Serves three distinct dialects, selected per-model (because a single relay
/// endpoint — e.g. New API — commonly mixes families):
///  * [ModelFamily.openaiChat] / [ModelFamily.other] — clean chat/completions,
///    no provider-specific extensions.
///  * [ModelFamily.openaiImage] — native OpenAI image generation/editing via
///    the `/images/*` endpoints.
///  * gemini families — chat/completions enriched with the Gemini-via-OpenAI
///    compatibility extensions (`modalities`, `image_config`, ...).
class OpenAIAPIProvider implements ILLMProvider, IModelDiscoveryProvider {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    final baseUrl = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;

    final url = Uri.parse('$baseUrl/models');
    final headers = _getHeaders(config.apiKey);

    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch OpenAI models: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> modelsJson = data['data'] ?? [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['id']?.toString() ?? '',
      displayName: m['id']?.toString() ?? '',
      description: 'Owned by: ${m['owned_by'] ?? 'unknown'}',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }

  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final family = ModelFamilyClassifier.classify(config.modelId);

    // Native OpenAI image models use the dedicated Images API, not chat.
    if (family == ModelFamily.openaiImage) {
      return _generateOpenAIImage(config, history, options: options, logger: logger);
    }

    final url = Uri.parse('${config.endpoint}/chat/completions');
    logger?.call('Preparing OpenAI request to: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.apiKey);
    final payload = _prepareChatPayload(config.modelId, history, options, isStreaming: false);

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Standard)', {
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

      if (response.statusCode != 200) {
        logger?.call('Request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('OpenAI API Request failed: ${response.statusCode} - ${response.body}');
      }

      logger?.call('Response received, parsing data...', level: 'DEBUG');
      final data = jsonDecode(response.body);
      String text = "";
      List<Uint8List> images = [];

      final message = data['choices']?[0]?['message'];
      if (message != null) {
        if (message['content'] != null) {
          text = message['content'];
        }

        // Some OpenAI-compat relays expose images via a structured field.
        _extractStructuredImages(message, images);

        if (text.isNotEmpty) {
          logger?.call('Extracting images from text response...', level: 'DEBUG');
          final result = await _processTextAndExtractImages(text, config);
          text = result.text;
          images.addAll(result.images);
        }
      }

      logger?.call('Parse complete. Text length: ${text.length}, Images: ${images.length}', level: 'DEBUG');

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: data['usage'] ?? {},
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
    final family = ModelFamilyClassifier.classify(config.modelId);

    // The OpenAI Images API does not stream — fall back to a single-shot call
    // and surface the result as chunks.
    if (family == ModelFamily.openaiImage) {
      logger?.call('Image model does not support streaming; using Images API.', level: 'DEBUG');
      final response = await _generateOpenAIImage(config, history, options: options, logger: logger);
      if (response.text.isNotEmpty) {
        yield LLMResponseChunk(textPart: response.text);
      }
      for (final img in response.generatedImages) {
        yield LLMResponseChunk(imagePart: img);
      }
      yield LLMResponseChunk(metadata: response.metadata, isDone: true);
      return;
    }

    final url = Uri.parse('${config.endpoint}/chat/completions');
    logger?.call('Starting OpenAI stream: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.apiKey);
    final payload = _prepareChatPayload(config.modelId, history, options, isStreaming: true);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Stream)', {
        'url': url.toString(),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      if (debugFile != null) {
        final body = await response.stream.bytesToString();
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
      }
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      client.close();
      throw Exception('OpenAI API Stream Request failed: ${response.statusCode}');
    }

    logger?.call('Stream connection established, waiting for chunks...', level: 'DEBUG');

    if (debugFile != null) {
      await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
    }

    String accumulatedText = "";
    bool isLikelyBase64Stream = false;

    try {
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendLine(debugFile, line);
        }
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
        final result = await _processTextAndExtractImages(accumulatedText, config);
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
    } finally {
      client.close();
    }

    yield LLMResponseChunk(isDone: true);
  }

  // ---------------------------------------------------------------------------
  // Native OpenAI image generation / editing (`/images/*`)
  // ---------------------------------------------------------------------------

  Future<LLMResponse> _generateOpenAIImage(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );
    final prompt = userMsg.content;
    final inputImages = userMsg.attachments;

    final baseUrl = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;

    // With input images this is an *edit*; otherwise a text-to-image generation.
    final isEdit = inputImages.isNotEmpty;
    final url = Uri.parse('$baseUrl/images/${isEdit ? 'edits' : 'generations'}');
    logger?.call('Preparing OpenAI Images request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}', level: 'DEBUG');

    final size = _resolveImageSize(options);
    final quality = _resolveQuality(options);
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      http.Response response;

      if (isEdit) {
        final request = http.MultipartRequest('POST', url);
        request.headers['Authorization'] = 'Bearer ${config.apiKey}';
        request.fields['model'] = config.modelId;
        request.fields['prompt'] = prompt;
        if (size != null) request.fields['size'] = size;
        if (quality != null) request.fields['quality'] = quality;
        request.fields['n'] = '1';

        for (int i = 0; i < inputImages.length; i++) {
          final att = inputImages[i];
          Uint8List bytes;
          if (att.path != null) {
            bytes = await File(att.path!).readAsBytes();
          } else if (att.bytes != null) {
            bytes = att.bytes!;
          } else {
            continue;
          }
          request.files.add(http.MultipartFile.fromBytes(
            'image[]',
            bytes,
            filename: 'image_$i.${_extForMime(att.mimeType)}',
          ));
        }

        if (appState.enableApiDebug) {
          debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Edit)', {
            'url': url.toString(),
            'fields': request.fields,
            'files': request.files.map((f) => f.filename).toList(),
          });
        }

        final streamed = await client.send(request);
        response = await http.Response.fromStream(streamed);
      } else {
        final headers = _getHeaders(config.apiKey);
        final payload = <String, dynamic>{
          'model': config.modelId,
          'prompt': prompt,
          'n': 1,
          'size': ?size,
          'quality': ?quality,
        };

        if (appState.enableApiDebug) {
          debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Generate)', {
            'url': url.toString(),
            'headers': headers,
            'body': payload,
          });
        }

        response = await client.post(url, headers: headers, body: jsonEncode(payload));
      }

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      if (response.statusCode != 200) {
        logger?.call('Images request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('OpenAI Images API failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body);
      final List<dynamic> items = data['data'] ?? [];
      final List<Uint8List> images = [];

      for (final item in items) {
        final b64 = item['b64_json'] as String?;
        if (b64 != null) {
          images.add(base64Decode(b64));
          continue;
        }
        final imgUrl = item['url'] as String?;
        if (imgUrl != null) {
          try {
            final imgResp = await client.get(Uri.parse(imgUrl));
            if (imgResp.statusCode == 200) images.add(imgResp.bodyBytes);
          } catch (_) {/* ignore */}
        }
      }

      logger?.call('Images parse complete. Images: ${images.length}', level: 'DEBUG');

      return LLMResponse(
        text: '',
        generatedImages: images,
        metadata: data['usage'] ?? {},
      );
    } finally {
      client.close();
    }
  }

  /// Map the app's aspect-ratio / image-size options onto an OpenAI image size.
  String? _resolveImageSize(Map<String, dynamic>? options) {
    if (options == null) return null;

    // Explicit WxH wins if it already looks like a pixel size.
    final explicit = options['imageSize'];
    if (explicit is String && RegExp(r'^\d+x\d+$').hasMatch(explicit)) {
      return explicit;
    }

    final aspect = options['aspectRatio'];
    if (aspect is! String || aspect == 'not_set') return null;

    switch (aspect) {
      case '1:1':
        return '1024x1024';
      case '16:9':
      case '3:2':
      case '4:3':
        return '1536x1024';
      case '9:16':
      case '2:3':
      case '3:4':
        return '1024x1536';
      default:
        return null;
    }
  }

  /// OpenAI image quality (`low` / `medium` / `high`); omitted for `auto`.
  String? _resolveQuality(Map<String, dynamic>? options) {
    final q = options?['quality'];
    if (q is String && q.isNotEmpty && q != 'auto') return q;
    return null;
  }

  String _extForMime(String mime) {
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    return 'jpg';
  }

  /// Pull images out of structured (non-text) response fields used by some
  /// OpenAI-compatible relays.
  void _extractStructuredImages(Map<String, dynamic> message, List<Uint8List> images) {
    final imageData = message['image_data'];
    if (imageData is String && imageData.isNotEmpty) {
      try {
        images.add(base64Decode(imageData));
      } catch (_) {/* ignore */}
    }

    // `images: [{ image_url: { url: "data:..."|"http..." } }]`
    final imageList = message['images'];
    if (imageList is List) {
      for (final entry in imageList) {
        final urlField = entry is Map ? (entry['image_url']?['url'] ?? entry['url']) : null;
        if (urlField is String && urlField.startsWith('data:image/')) {
          final comma = urlField.indexOf(',');
          if (comma != -1) {
            try {
              images.add(base64Decode(urlField.substring(comma + 1)));
            } catch (_) {/* ignore */}
          }
        }
      }
    }
  }

  bool _isBase64Heuristic(String text) {
    if (text.length < 64) return false;
    // Check if it contains data URI prefix
    if (text.contains('data:image/')) return true;
    // Check if it's a long string of base64 characters with no spaces
    return text.length > 200 && !text.contains(' ') && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text.substring(0, 100));
  }

  Future<_TextProcessResult> _processTextAndExtractImages(String text, LLMModelConfig config) async {
    final List<Uint8List> images = [];
    String cleanText = text;
    final client = config.createClient();

    try {
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
          final response = await client.get(Uri.parse(url));
          if (response.statusCode == 200) {
            images.add(response.bodyBytes);
          }
        } catch (e) { /* ignore */ }
      }
    } finally {
      client.close();
    }

    return _TextProcessResult(cleanText.trim(), images);
  }

  @override
  Future<String> startLongRunning(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    // Native OpenAI no longer exposes a supported video LRO surface here
    // (Sora is intentionally out of scope). We keep a simulation hook for
    // OpenAI-compatible providers that may add one, and for development.
    final isSimulation = options?['simulation'] == true || config.modelId.startsWith('mock-');

    if (isSimulation) {
      logger?.call('Simulating long-running operation for OpenAI-style model: ${config.modelId}', level: 'INFO');
      return 'openai_lro_sim_${DateTime.now().millisecondsSinceEpoch}';
    }

    throw UnsupportedError(
      'The model "${config.modelId}" on the OpenAI provider does not support long-running operations. '
      'Video generation via LRO is currently provided by Google Veo models.'
    );
  }

  @override
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  }) async {
    if (operationName.startsWith('openai_lro_sim_')) {
      // Simulate a completion. The TaskQueueService handles polling.
      return {
        'name': operationName,
        'done': true,
        'response': {
           'generateVideoResponse': {
             'generatedSamples': [
               {
                 'video': {
                   'uri': 'https://storage.googleapis.com/tf-js-examples/webcam-transfer-learning/video/cat.mp4'
                 }
               }
             ]
           }
        }
      };
    }

    throw UnsupportedError('Operation "$operationName" is not recognized by OpenAI provider.');
  }

  Map<String, String> _getHeaders(String apiKey) {
    return {
      "Authorization": "Bearer $apiKey",
      "Content-Type": "application/json"
    };
  }

  /// Build a chat/completions payload.
  ///
  /// The base envelope is identical for every family. Gemini-via-OpenAI-compat
  /// models additionally receive the relay extensions; native OpenAI models do
  /// not (sending Google-only fields to real OpenAI yields a 400).
  Map<String, dynamic> _prepareChatPayload(
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

    final payload = <String, dynamic>{
      "model": modelId,
      "messages": messages,
      "stream": isStreaming,
    };

    if (isStreaming) {
      payload["stream_options"] = {"include_usage": true};
    }

    // Only Gemini-served models (e.g. via New API or Google's OpenAI-compat
    // layer) understand these extensions. Native OpenAI must never receive them.
    final family = ModelFamilyClassifier.classify(modelId);
    if (ModelFamilyClassifier.isGemini(family)) {
      _applyGeminiCompatExtensions(payload, options);
    }

    return payload;
  }

  /// Gemini-via-OpenAI compatibility extensions used by relay services.
  void _applyGeminiCompatExtensions(Map<String, dynamic> payload, Map<String, dynamic>? options) {
    payload["modalities"] = ["image", "text"];

    payload["safety_settings"] = [
      {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
      {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
      {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
      {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"}
    ];

    if (options != null) {
      final imageConfig = <String, dynamic>{};
      imageConfig['person_generation'] = 'allow_all';
      if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
        imageConfig['aspect_ratio'] = options['aspectRatio'];
      }
      if (options.containsKey('imageSize')) {
        imageConfig['image_size'] = options['imageSize'];
      }
      if (imageConfig.isNotEmpty) {
        imageConfig['number_of_images'] = 1;
        payload["image_config"] = imageConfig;
      }
    }
  }
}

class _TextProcessResult {
  final String text;
  final List<Uint8List> images;
  _TextProcessResult(this.text, this.images);
}
