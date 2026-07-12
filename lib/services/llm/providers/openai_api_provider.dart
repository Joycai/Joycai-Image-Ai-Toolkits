import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/safety_settings.dart';
import '../../../state/app_state.dart';
import '../channel_dialect.dart';
import '../llm_debug_logger.dart';
import '../llm_provider_interface.dart';
import '../llm_types.dart';
import '../model_capabilities.dart';
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
    List<LLMTool>? tools,
    Function(String, {String level})? logger,
  }) async {
    final family = ModelFamilyClassifier.classify(config.modelId);

    // Native OpenAI image models use the dedicated Images API, not chat.
    if (family == ModelFamily.openaiImage) {
      return _generateOpenAIImage(config, history, options: options, logger: logger);
    }

    // Grok Imagine image models: xAI's JSON Images API on native channels;
    // OpenAI-style Images API when served through a relay.
    if (family == ModelFamily.xaiImage) {
      return ChannelDialect.isXai(config.channelType)
          ? _generateXaiImage(config, history, options: options, logger: logger)
          : _generateOpenAIImage(config, history, options: options, logger: logger);
    }

    final url = Uri.parse('${config.endpoint}/chat/completions');
    logger?.call('Preparing OpenAI request to: ${url.host}', level: 'DEBUG');
    final headers = _getHeaders(config.apiKey);
    final payload = _prepareChatPayload(config.modelId, history, options, isStreaming: false, tools: tools);
    if (payload.containsKey('safety_settings')) {
      logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');
    }

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
      final List<LLMToolCall> toolCalls = [];

      final choice = data['choices']?[0];
      final message = choice?['message'];
      if (message != null) {
        if (message['content'] != null) {
          text = message['content'];
        }

        // Native tool/function calls.
        final rawToolCalls = message['tool_calls'];
        if (rawToolCalls is List) {
          for (int i = 0; i < rawToolCalls.length; i++) {
            final tc = rawToolCalls[i];
            final fn = tc is Map ? tc['function'] : null;
            if (fn is! Map) continue;
            Map<String, dynamic> args = {};
            final rawArgs = fn['arguments'];
            if (rawArgs is String && rawArgs.isNotEmpty) {
              try {
                final decoded = jsonDecode(rawArgs);
                if (decoded is Map<String, dynamic>) args = decoded;
              } catch (e) {
                logger?.call('Failed to decode tool call arguments: $e', level: 'WARN');
              }
            } else if (rawArgs is Map<String, dynamic>) {
              args = rawArgs;
            }
            toolCalls.add(LLMToolCall(
              id: tc['id']?.toString() ?? 'call_$i',
              name: fn['name']?.toString() ?? '',
              arguments: args,
            ));
          }
          if (toolCalls.isNotEmpty) {
            logger?.call('Model requested ${toolCalls.length} tool call(s).', level: 'DEBUG');
          }
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

      final metadata = <String, dynamic>{
        ...?(data['usage'] as Map?)?.cast<String, dynamic>(),
      };
      final finishReason = choice?['finish_reason'];
      if (finishReason != null) metadata['finish_reason'] = finishReason;

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
    final family = ModelFamilyClassifier.classify(config.modelId);

    // The Images APIs do not stream — fall back to a single-shot call
    // and surface the result as chunks.
    if (family == ModelFamily.openaiImage || family == ModelFamily.xaiImage) {
      logger?.call('Image model does not support streaming; using Images API.', level: 'DEBUG');
      final response = await generate(config, history, options: options, logger: logger);
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
    if (payload.containsKey('safety_settings')) {
      logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');
    }

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

    // Cap the reference images to what the model accepts (gpt-image-1: 16).
    var inputImages = userMsg.attachments;
    final maxRef = ModelCapabilities.forModel(config.modelId).maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first $maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

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

  /// xAI Grok Imagine image generation / editing via xAI's native JSON
  /// surface (https://docs.x.ai/developers/model-capabilities/images/generation):
  ///   * No attachments → `POST /images/generations`.
  ///   * One attachment → `POST /images/edits` with `image: {url: <data URI>}`.
  ///   * 2–3 attachments → `POST /images/edits` with `images: [{url}, …]`
  ///     (mutually exclusive with `image`; reference them as `<IMAGE_0>`… in
  ///     the prompt).
  ///
  /// Reads from `options`:
  ///   * `aspectRatio` — passed as `aspect_ratio` (supports `auto`); skipped
  ///     for `not_set`.
  ///   * `imageSize` — passed as `resolution` when it is `1k` / `2k`.
  /// Requests `b64_json` so results come back inline without a second
  /// download round-trip.
  Future<LLMResponse> _generateXaiImage(
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

    // Cap the reference images to what the model accepts (3).
    var inputImages = userMsg.attachments;
    final maxRef = ModelCapabilities.forModel(config.modelId).maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first $maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

    final isEdit = inputImages.isNotEmpty;
    final baseUrl = _baseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/images/${isEdit ? 'edits' : 'generations'}');
    logger?.call('Preparing xAI Images request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}', level: 'DEBUG');

    final payload = <String, dynamic>{
      'model': config.modelId,
      'prompt': prompt,
      'n': 1,
      'response_format': 'b64_json',
    };

    final aspect = _readString(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') payload['aspect_ratio'] = aspect;

    final resolution = _readString(options, 'imageSize');
    if (resolution == '1k' || resolution == '2k') {
      payload['resolution'] = resolution;
    }

    int encodedCount = 0;
    if (isEdit) {
      final entries = <Map<String, String>>[];
      for (final att in inputImages) {
        final bytes = await _readAttachmentBytes(att);
        if (bytes != null) {
          entries.add({'url': 'data:${att.mimeType};base64,${base64Encode(bytes)}'});
        }
      }
      encodedCount = entries.length;
      if (entries.length == 1) {
        payload['image'] = entries.first;
      } else if (entries.length > 1) {
        payload['images'] = entries;
      }
    }

    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'xAI (Image ${isEdit ? 'Edit' : 'Generate'})', {
        'url': url.toString(),
        'body': {
          ...payload,
          if (payload.containsKey('image')) 'image': '[base64 data]',
          if (payload.containsKey('images')) 'images': '[$encodedCount base64 image(s)]',
        },
      });
    }

    final client = config.createClient();
    try {
      final response = await client.post(
        url,
        headers: _getHeaders(config.apiKey),
        body: jsonEncode(payload),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        logger?.call('xAI Images request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('xAI Images API failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
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

      if (images.isEmpty) {
        // e.g. respect_moderation=false leaves url/b64 empty.
        throw Exception('xAI Images API returned no image data (possibly filtered by moderation): ${response.body}');
      }

      logger?.call('xAI Images parse complete. Images: ${images.length}', level: 'DEBUG');

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
    final family = ModelFamilyClassifier.classify(config.modelId);

    // xAI native channels use their own async video surface
    // (`/videos/generations` JSON), not the Sora-style multipart `/videos`.
    if (ChannelDialect.isXai(config.channelType) &&
        family == ModelFamily.openaiVideo) {
      return _submitXaiVideo(config, history, options: options, logger: logger);
    }

    // Sora 2 / grok-imagine / Wanxiang / Kling / Vidu / Jimeng — all served
    // under NewAPI's OpenAI-compatible `/v1/videos` surface.
    if (family == ModelFamily.openaiVideo) {
      return _submitOpenAIVideo(config, history, options: options, logger: logger);
    }

    final isSimulation = options?['simulation'] == true || config.modelId.startsWith('mock-');

    if (isSimulation) {
      logger?.call('Simulating long-running operation for OpenAI-style model: ${config.modelId}', level: 'INFO');
      return 'openai_lro_sim_${DateTime.now().millisecondsSinceEpoch}';
    }

    throw UnsupportedError(
      'The model "${config.modelId}" on the OpenAI provider does not support long-running operations. '
      'Use a sora-* / grok-imagine-* / wan2.5-* / kling-* model for video generation.'
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

    // xAI native channels poll `GET /videos/{request_id}` with xAI's own
    // status vocabulary (pending / done / expired / failed).
    if (ChannelDialect.isXai(config.channelType)) {
      return _checkXaiVideo(config, operationName, logger: logger);
    }

    // Sora-style video task ids start with `video_` (NewAPI / OpenAI Sora
    // format). Also dispatch by model family for non-prefixed ids that some
    // upstreams emit (e.g. Wanxiang).
    final family = ModelFamilyClassifier.classify(config.modelId);
    if (family == ModelFamily.openaiVideo || operationName.startsWith('video_')) {
      return _checkOpenAIVideo(config, operationName, logger: logger);
    }

    throw UnsupportedError('Operation "$operationName" is not recognized by OpenAI provider.');
  }

  // ---------------------------------------------------------------------------
  // OpenAI-compatible video (`/v1/videos`) — Sora 2, grok-imagine, Wanxiang…
  // ---------------------------------------------------------------------------

  /// Submit a video generation task. The endpoint is multipart/form-data so
  /// that we can attach `input_reference` as a real file part (NewAPI also
  /// accepts a Base64 string in that field, but file upload is the spec'd
  /// shape and avoids inflating the request body unnecessarily).
  ///
  /// Reads from `options`:
  ///   * `seconds` — clip duration (string or int, e.g. "5").
  ///   * `videoQuality` — "standard" | "high".
  ///   * `aspectRatio` — passed through verbatim if the upstream accepts it.
  ///   * `resolution` — used together with aspectRatio to derive `size`.
  /// And from the user message: `firstFramePath` (LLMReferenceType.firstFrame)
  /// becomes `input_reference`; any other attachments become `images[]`.
  Future<String> _submitOpenAIVideo(
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

    final baseUrl = _baseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos');

    final size = _resolveVideoSize(options);
    final seconds = _resolveSeconds(options);
    final quality = _readString(options, 'videoQuality');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Bearer ${config.apiKey}';
    request.fields['model'] = config.modelId;
    request.fields['prompt'] = prompt;
    if (seconds != null) request.fields['seconds'] = seconds;
    if (size != null) request.fields['size'] = size;
    if (quality != null && quality != 'standard') {
      request.fields['quality'] = quality;
    }

    // First-frame attachment → input_reference. Anything beyond that goes
    // into images[] (Sora spec caps at 7; the executor already trims to the
    // capability ceiling).
    LLMAttachment? firstFrame;
    final extras = <LLMAttachment>[];
    for (final att in userMsg.attachments) {
      if (firstFrame == null && att.referenceType == LLMReferenceType.firstFrame) {
        firstFrame = att;
      } else {
        extras.add(att);
      }
    }
    firstFrame ??= userMsg.attachments.isNotEmpty ? userMsg.attachments.first : null;
    if (firstFrame != null && extras.contains(firstFrame)) {
      extras.remove(firstFrame);
    }

    if (firstFrame != null) {
      final bytes = await _readAttachmentBytes(firstFrame);
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'input_reference',
          bytes,
          filename: 'first_frame.${_extForMime(firstFrame.mimeType)}',
        ));
      }
    }
    for (int i = 0; i < extras.length; i++) {
      final att = extras[i];
      final bytes = await _readAttachmentBytes(att);
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'images[]',
          bytes,
          filename: 'reference_$i.${_extForMime(att.mimeType)}',
        ));
      }
    }

    logger?.call('Submitting OpenAI video task to: ${url.host}', level: 'DEBUG');
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Video Submit)', {
        'url': url.toString(),
        'fields': request.fields,
        'files': request.files.map((f) => f.filename).toList(),
      });
    }

    final client = config.createClient();
    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('OpenAI video submit failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) {
        throw Exception('OpenAI video submit returned no id: ${response.body}');
      }
      logger?.call('OpenAI video task id: $id', level: 'DEBUG');
      return id;
    } finally {
      client.close();
    }
  }

  /// Poll a video task and translate the upstream `{status, progress, url}`
  /// response into the Veo-shaped envelope the task executor already speaks.
  /// This keeps the executor format-agnostic and reuses the existing download
  /// path.
  Future<Map<String, dynamic>> _checkOpenAIVideo(
    LLMModelConfig config,
    String taskId, {
    Function(String, {String level})? logger,
  }) async {
    final baseUrl = _baseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$taskId');
    final headers = _getHeaders(config.apiKey);

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      if (response.statusCode != 200) {
        throw Exception('OpenAI video fetch failed: ${response.statusCode} - ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';

      if (status == 'succeeded') {
        // Prefer the explicit URL when the upstream supplies one; otherwise
        // fall back to the dedicated /content endpoint (which streams the
        // mp4 with the bearer token).
        final videoUrl = data['url']?.toString() ?? '$baseUrl/videos/$taskId/content';
        return {
          'name': taskId,
          'done': true,
          'response': {
            'generateVideoResponse': {
              'generatedSamples': [
                {
                  'video': {'uri': videoUrl},
                }
              ],
            },
          },
        };
      }

      if (status == 'failed') {
        final err = data['error'];
        final msg = err is Map ? (err['message'] ?? err.toString()) : (err?.toString() ?? 'unknown');
        throw Exception('OpenAI video task $taskId failed: $msg');
      }

      // processing / queued — relay progress without marking done.
      return {
        'name': taskId,
        'done': false,
        'progress': data['progress'] ?? 0,
        'status': status,
      };
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // xAI native video (`/videos/generations`) — grok-imagine-video…
  // ---------------------------------------------------------------------------

  /// Submit a video generation request to xAI's native async surface.
  ///
  /// JSON body (see https://docs.x.ai/developers/model-capabilities/video/generation):
  ///   * `prompt` — from the last user message.
  ///   * `duration` — seconds, 1–15 (mapped from the shared `seconds` option).
  ///   * `aspect_ratio` — e.g. "16:9" (from the shared `aspectRatio` option).
  ///   * `resolution` — "480p" | "720p" | "1080p" (mapped from `resolution`;
  ///     "4k" is clamped to "1080p").
  ///   * `image` — image-to-video first frame: an object `{url: ...}` where
  ///     `url` is a public URL or base64 data URI (per the REST schema —
  ///     a bare string is rejected with a 422).
  ///   * `reference_images` — reference-to-video guidance images, each an
  ///     object `{url: ...}` like `image`.
  ///
  /// `image` and `reference_images` are mutually exclusive upstream (400
  /// otherwise), so the first frame wins and reference images are dropped
  /// with a warning when both are supplied. Returns the `request_id`.
  Future<String> _submitXaiVideo(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );

    final payload = <String, dynamic>{
      'model': config.modelId,
      'prompt': userMsg.content,
    };

    final seconds = int.tryParse(_resolveSeconds(options) ?? '');
    if (seconds != null) payload['duration'] = seconds.clamp(1, 15);

    final aspect = _readString(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') payload['aspect_ratio'] = aspect;

    final resolution = _readString(options, 'resolution');
    if (resolution != null) {
      // xAI supports 480p / 720p / 1080p; the shared dropdown also offers 4k.
      payload['resolution'] = resolution == '4k' ? '1080p' : resolution;
    }

    // First frame → image-to-video; remaining attachments → reference images.
    LLMAttachment? firstFrame;
    final references = <LLMAttachment>[];
    for (final att in userMsg.attachments) {
      if (att.referenceType == LLMReferenceType.lastFrame) {
        logger?.call('Last frame is not supported by the xAI video API — skipped.', level: 'WARN');
        continue;
      }
      if (firstFrame == null && att.referenceType == LLMReferenceType.firstFrame) {
        firstFrame = att;
      } else {
        references.add(att);
      }
    }

    if (firstFrame != null) {
      final bytes = await _readAttachmentBytes(firstFrame);
      if (bytes != null) {
        payload['image'] = {
          'url': 'data:${firstFrame.mimeType};base64,${base64Encode(bytes)}',
        };
      }
      if (references.isNotEmpty) {
        logger?.call(
          'xAI video: image and reference_images are mutually exclusive — '
          '${references.length} reference image(s) dropped in favor of the first frame.',
          level: 'WARN',
        );
      }
    } else if (references.isNotEmpty) {
      final encoded = <Map<String, String>>[];
      for (final att in references) {
        final bytes = await _readAttachmentBytes(att);
        if (bytes != null) {
          encoded.add({'url': 'data:${att.mimeType};base64,${base64Encode(bytes)}'});
        }
      }
      if (encoded.isNotEmpty) payload['reference_images'] = encoded;
    }

    final baseUrl = _baseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/generations');
    logger?.call('Submitting xAI video task to: ${url.host}', level: 'DEBUG');

    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'xAI (Video Submit)', {
        'url': url.toString(),
        'payload': {
          ...payload,
          if (payload.containsKey('image')) 'image': '[base64 data]',
          if (payload.containsKey('reference_images'))
            'reference_images': '[${(payload['reference_images'] as List).length} base64 image(s)]',
        },
      });
    }

    final client = config.createClient();
    try {
      final response = await client.post(
        url,
        headers: _getHeaders(config.apiKey),
        body: jsonEncode(payload),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('xAI video submit failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final requestId = data['request_id']?.toString();
      if (requestId == null || requestId.isEmpty) {
        throw Exception('xAI video submit returned no request_id: ${response.body}');
      }
      logger?.call('xAI video request id: $requestId', level: 'DEBUG');
      return requestId;
    } finally {
      client.close();
    }
  }

  /// Poll an xAI video request and translate the native
  /// `{status, video: {url}}` response into the Veo-shaped envelope the task
  /// executor already speaks. Statuses: pending / done / expired / failed.
  Future<Map<String, dynamic>> _checkXaiVideo(
    LLMModelConfig config,
    String requestId, {
    Function(String, {String level})? logger,
  }) async {
    final baseUrl = _baseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$requestId');

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: _getHeaders(config.apiKey));
      // 200 = terminal result; 202 = accepted / still pending.
      if (response.statusCode != 200 && response.statusCode != 202) {
        throw Exception('xAI video fetch failed: ${response.statusCode} - ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';

      switch (status) {
        case 'done':
          final video = data['video'] as Map?;
          final videoUrl = video?['url']?.toString();
          if (videoUrl == null || videoUrl.isEmpty) {
            throw Exception('xAI video request $requestId is done but returned no URL: ${response.body}');
          }
          return {
            'name': requestId,
            'done': true,
            'response': {
              'generateVideoResponse': {
                'generatedSamples': [
                  {
                    'video': {'uri': videoUrl},
                  }
                ],
              },
            },
          };
        case 'failed':
          final err = data['error'];
          final msg = err is Map
              ? '${err['code'] ?? 'unknown'}: ${err['message'] ?? err.toString()}'
              : (err?.toString() ?? 'unknown');
          throw Exception('xAI video request $requestId failed: $msg');
        case 'expired':
          throw Exception('xAI video request $requestId expired before completing.');
        default:
          // pending — relay progress (0-100) without marking done.
          return {
            'name': requestId,
            'done': false,
            'progress': data['progress'] ?? 0,
            'status': status,
          };
      }
    } finally {
      client.close();
    }
  }

  /// Map the per-model aspectRatio + resolution options onto a Sora-compatible
  /// `WxH` size string. Falls back to the upstream default if neither is set.
  String? _resolveVideoSize(Map<String, dynamic>? options) {
    if (options == null) return null;

    // Explicit WxH wins.
    final explicit = options['size'];
    if (explicit is String && RegExp(r'^\d+x\d+$').hasMatch(explicit)) {
      return explicit;
    }

    final aspect = options['aspectRatio']?.toString();
    final resolution = options['resolution']?.toString() ?? '720p';

    final is1080 = resolution.contains('1080');
    switch (aspect) {
      case '16:9':
        return is1080 ? '1920x1080' : '1280x720';
      case '9:16':
        return is1080 ? '1080x1920' : '720x1280';
      case '1:1':
        return is1080 ? '1024x1024' : '720x720';
      case '3:2':
        return is1080 ? '1620x1080' : '1080x720';
      case '2:3':
        return is1080 ? '1080x1620' : '720x1080';
      default:
        return null;
    }
  }

  String? _resolveSeconds(Map<String, dynamic>? options) {
    final s = options?['seconds'];
    if (s == null) return null;
    return s.toString();
  }

  String? _readString(Map<String, dynamic>? options, String key) {
    final v = options?[key];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  Future<Uint8List?> _readAttachmentBytes(LLMAttachment att) async {
    if (att.path != null) return File(att.path!).readAsBytes();
    if (att.bytes != null) return att.bytes;
    return null;
  }

  String _baseUrl(String endpoint) =>
      endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;

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
    {required bool isStreaming, List<LLMTool>? tools}
  ) {
    final messages = history.map((msg) {
      // Tool result message.
      if (msg.role == LLMRole.tool) {
        return {
          "role": "tool",
          "tool_call_id": msg.toolCallId,
          "content": msg.content,
        };
      }

      // Assistant message carrying tool calls.
      if (msg.role == LLMRole.assistant && msg.toolCalls.isNotEmpty) {
        return {
          "role": "assistant",
          "content": msg.content.isEmpty ? null : msg.content,
          "tool_calls": msg.toolCalls.map((tc) => {
            "id": tc.id,
            "type": "function",
            "function": {
              "name": tc.name,
              "arguments": jsonEncode(tc.arguments),
            },
          }).toList(),
        };
      }

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

    if (tools != null && tools.isNotEmpty) {
      payload["tools"] = tools.map((t) => {
        "type": "function",
        "function": {
          "name": t.name,
          "description": t.description,
          "parameters": t.parameters,
        },
      }).toList();
      payload["tool_choice"] = "auto";
    }

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

    payload["safety_settings"] =
        SafetySettings.toApiList(options?[SafetySettings.paramKey]);

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
