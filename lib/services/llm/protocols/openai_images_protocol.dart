import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

/// The multipart field name the source image(s) of an edit travel under.
///
/// One image goes as `image`, several as `image[]`. The plural spelling is
/// what the current endpoint documents for multi-image edits, but the older
/// surfaces (dall-e-2's edit, relays built against it) know only the
/// singular — sending `image[]` for a single picture 400s there, while
/// `image` is accepted everywhere a single picture is. So the field name
/// follows the count instead of being the plural always.
String openaiImageEditFieldName(int imageCount) => imageCount > 1 ? 'image[]' : 'image';

/// Native OpenAI image generation / editing:
/// `POST /images/generations` (JSON) and `POST /images/edits` (multipart).
///
/// With input images the request is an *edit*; otherwise a text-to-image
/// generation. The reference-image cap comes from the model descriptor
/// (gpt-image-1: 16).
class OpenAIImagesProtocol implements ImageGenProtocol {
  @override
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final req = await _prepare(target, history, options, logger, stream: false);
    final client = target.config.createClient();
    try {
      final response = await http.Response.fromStream(
        await client.send(trackBodySent(req.request, options)),
      );
      return await decodeResult(response, client, options, logger, req.sentImages, req.debugFile);
    } finally {
      await LLMDebugLogger.finish(req.debugFile);
      client.close();
    }
  }

  Future<({http.BaseRequest request, int sentImages, LLMDebugLog? debugFile})> _prepare(
    LLMTarget target,
    List<LLMMessage> history,
    Map<String, dynamic>? options,
    LLMLogger? logger, {
    required bool stream,
  }) async {
    final config = target.config;
    final userMsg = history.lastWhere((m) => m.role == LLMRole.user, orElse: () => history.last);
    final prompt = userMsg.content;

    // Cap the reference images to what the model accepts (gpt-image-1: 16).
    final inputImages = capReferenceImages(
      userMsg.attachments,
      target.model.capabilities.maxReferenceImages,
      logger,
    );

    final baseUrl = trimBaseUrl(config.endpoint);

    // With input images this is an *edit*; otherwise a text-to-image generation.
    final isEdit = inputImages.isNotEmpty;
    final url = Uri.parse('$baseUrl/images/${isEdit ? 'edits' : 'generations'}');
    logger?.call(
      'Preparing OpenAI Images request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}',
      level: 'DEBUG',
    );

    final size = resolveImageSize(optionsWithCheckedSize(target, options, logger: logger));
    final quality = _resolveQuality(options);
    final output = {
      ...outputOptions(options),
      if (stream) ...{'stream': true, 'partial_images': 3},
    };
    // Files actually attached to the edit — an unreadable attachment is not.
    var sentImages = 0;
    LLMDebugLog? debugFile;
    http.BaseRequest request;

    if (isEdit) {
      // Abortable like every non-streaming send (see sendJsonRequest).
      final multipart = http.AbortableMultipartRequest(
        'POST',
        url,
        abortTrigger: abortTriggerOf(options),
      );
      // Auth comes from the vendor profile (layer 2) like every other
      // surface — a hardcoded bearer header worked only because today's
      // OpenAI-family vendors all happen to use one, and would have failed
      // on the next one while plain generation kept working. Content-Type
      // is dropped: the multipart body sets its own with a boundary.
      multipart.headers.addAll(
        Map.of(target.headers())..removeWhere((k, _) => k.toLowerCase() == 'content-type'),
      );
      multipart.fields['model'] = config.modelId;
      multipart.fields['prompt'] = prompt;
      if (size != null) multipart.fields['size'] = size;
      if (quality != null) multipart.fields['quality'] = quality;
      multipart.fields['n'] = '1';
      multipart.fields.addAll(output.map((key, value) => MapEntry(key, value.toString())));

      final field = openaiImageEditFieldName(inputImages.length);
      for (int i = 0; i < inputImages.length; i++) {
        final att = inputImages[i];
        final bytes = await readAttachmentBytes(att);
        if (bytes == null) continue;
        // With an explicit Content-Type per part — see [imageMultipartFile]
        // for the relay that 400s on the octet-stream default.
        multipart.files.add(
          imageMultipartFile(field, bytes, declaredMime: att.mimeType, baseName: 'image_$i'),
        );
        sentImages++;
      }

      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Edit)', {
          'url': redactUrl(url),
          'fields': multipart.fields,
          'files': multipart.files.map((f) => f.filename).toList(),
        });
      }

      request = multipart;
    } else {
      final headers = target.headers();
      final payload = <String, dynamic>{
        'model': config.modelId,
        'prompt': prompt,
        'n': 1,
        'size': ?size,
        'quality': ?quality,
        ...output,
      };

      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Generate)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': payload,
        });
      }

      request = buildJsonRequest(
        'POST',
        url,
        headers: headers,
        body: jsonEncode(payload),
        options: options,
      );
    }

    return (request: request, sentImages: sentImages, debugFile: debugFile);
  }

  Future<LLMResponse> decodeResult(
    http.Response response,
    http.Client client,
    Map<String, dynamic>? options,
    LLMLogger? logger,
    int sentImages,
    LLMDebugLog? debugFile,
  ) async {
    if (debugFile != null) {
      await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
      await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
    }

    // Status → JSON → shape → envelope, in that order (decodeJsonBody).
    // 200 does not mean success on a relay — an `{"error": …}` body used
    // to parse as zero images and report the task as finished with
    // nothing in it.
    final data = decodeJsonBody(response, apiName: 'OpenAI Images API');
    final rawItems = data['data'];
    final List<dynamic> items = rawItems is List ? rawItems : const [];
    // Both spellings through the shared resolver: a `url` that is really a
    // `data:` URI (relays do this) used to be fetched as a link and fail,
    // a malformed `b64_json` threw out of the loop, and an HTML body behind
    // a link was saved as a picture. The resolver validates the bytes and
    // retries a link once.
    final refs = <String>[
      for (final item in items)
        if (item is Map)
          if (item['b64_json'] is String && (item['b64_json'] as String).isNotEmpty)
            item['b64_json'] as String
          else if (item['url'] is String && (item['url'] as String).isNotEmpty)
            item['url'] as String,
    ];
    final images = await resolveImageRefs(
      refs,
      client,
      logger,
      source: 'OpenAI Images API',
      abortTrigger: abortTriggerOf(options),
    );

    if (images.isEmpty) {
      // The Images API has exactly one deliverable. Returning an empty
      // response here reads to the task executor as a successful generation
      // that produced nothing, which is indistinguishable from a model
      // refusing — so say what actually came back instead.
      final body = response.body;
      throw LLMApiException(
        'OpenAI Images API returned no image: '
        '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
      );
    }

    logger?.call('Images parse complete. Images: ${images.length}', level: 'DEBUG');

    // dall-e-3 rewrites the prompt and says so per item; gpt-image-1 does
    // not. What was actually drawn goes in the text (standard 13 §1).
    final revised = revisedPromptFrom(items);

    return LLMResponse(
      text: revised,
      generatedImages: images,
      // gpt-image-1 reports `input_tokens`/`output_tokens` here, not the
      // chat spelling — see LLMService._recordUsage, which reads both.
      metadata: {
        if (revised.isNotEmpty) 'revised_prompt': revised,
        ...upstreamUsage(data['usage']),
        'image_token_output': true,
        // The size and quality the endpoint settled on. A request that
        // said `auto` has no spec of its own, and a spec-billed fee group
        // prices by exactly this — see `OutputSpec.from`, which prefers
        // these echoes over what was asked for. Facts only: no price here.
        if (data['size'] is String) 'output_size': data['size'],
        if (data['quality'] is String) 'output_quality': data['quality'],
        if (data['output_format'] is String) 'output_format': data['output_format'],
        if (data['background'] is String) 'output_background': data['background'],
        ...sentInputImages(sentImages),
      },
    );
  }

  /// Partial previews are a separate carrier: never a saved/billed output.
  Stream<LLMResponseChunk> generateImageStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async* {
    final req = await _prepare(target, history, options, logger, stream: true);
    final client = target.config.createClient();
    try {
      final response = await client.send(trackBodySent(req.request, options));
      await LLMDebugLogger.appendLine(
        req.debugFile,
        'Stream response: status=${response.statusCode} '
        'content-type=${response.headers['content-type'] ?? '(missing)'} '
        'content-length=${response.headers['content-length'] ?? '(missing)'} '
        'content-encoding=${response.headers['content-encoding'] ?? '(missing)'}',
      );
      if (response.statusCode != 200) {
        // Decode the provider's HTTP error from this response; never resubmit
        // an image request that may already have been accepted.
        final whole = await decodeResult(
          await http.Response.fromStream(response),
          client,
          options,
          logger,
          req.sentImages,
          req.debugFile,
        );
        for (final image in whole.generatedImages) {
          yield LLMResponseChunk(imagePart: image, metadata: whole.metadata);
        }
        yield LLMResponseChunk(textPart: whole.text, metadata: whole.metadata, isDone: true);
        return;
      }
      var completed = false;
      var eventName = '';
      final dataLines = <String>[];
      var events = 0;
      Future<LLMResponseChunk?> consume({bool deferInvalid = false}) async {
        if (dataLines.isEmpty) return null;
        final payload = dataLines.join('\n');
        if (payload == '[DONE]') {
          dataLines.clear();
          return null;
        }
        dynamic decoded;
        try {
          decoded = jsonDecode(payload);
        } on FormatException catch (error) {
          // Some relays wrap a JSON string over multiple data lines. SSE's
          // required newline join is invalid inside a string; try removing
          // only those framing newlines, without changing image characters.
          try {
            decoded = jsonDecode(dataLines.join());
          } on FormatException catch (compactError) {
            if (deferInvalid) return null;
            final offset = error.offset;
            final detail =
                'Invalid image stream JSON: ${error.message}; '
                'offset=$offset compactError=${compactError.message} compactOffset=${compactError.offset} '
                'chars=${payload.length} dataLines=${dataLines.length} '
                'event=${events + 1} name=$eventName '
                'codeUnit=${offset != null && offset < payload.length ? payload.codeUnitAt(offset) : 'EOF'}';
            await LLMDebugLogger.appendLine(req.debugFile, detail);
            throw LLMApiException(detail);
          }
          await LLMDebugLogger.appendLine(
            req.debugFile,
            'Compatibility: joined wrapped data lines',
          );
        }
        dataLines.clear();
        events++;
        if (decoded is! Map<String, dynamic>) {
          throw LLMApiException(
            'OpenAI Images stream returned an unexpected event shape: ${decoded.runtimeType}',
          );
        }
        final data = decoded;
        throwIfEnvelopeError(data);
        final type = data['type'] ?? eventName;
        if (type == 'error' || type == 'image_generation.failed' || type == 'image_edit.failed') {
          throw LLMApiException(
            'OpenAI Images stream failed: ${data['message'] ?? data['error'] ?? type}',
            isEnvelope: true,
          );
        }
        final partial =
            type == 'image_generation.partial_image' || type == 'image_edit.partial_image';
        final done = type == 'image_generation.completed' || type == 'image_edit.completed';
        if (!partial && !done) return null;
        if (completed) throw LLMApiException('OpenAI Images stream returned duplicate completion.');
        final encoded = data['b64_json'];
        if (encoded is! String || encoded.isEmpty) {
          throw LLMApiException('OpenAI Images stream returned an empty image.');
        }
        final images = await resolveImageRefs(
          [encoded],
          client,
          logger,
          source: 'OpenAI Images stream',
          abortTrigger: abortTriggerOf(options),
        );
        if (images.isEmpty) {
          throw LLMApiException('OpenAI Images stream returned an invalid image.');
        }
        await LLMDebugLogger.appendLine(
          req.debugFile,
          'Parsed event: index=$events type=$type imageBytes=${images.single.length} final=$done',
        );
        if (partial) return LLMResponseChunk(imagePreview: images.single);
        completed = true;
        return LLMResponseChunk(
          imagePart: images.single,
          metadata: {
            ...upstreamUsage(data['usage']),
            'image_token_output': true,
            ...sentInputImages(req.sentImages),
            if (data['size'] is String) 'output_size': data['size'],
            if (data['quality'] is String) 'output_quality': data['quality'],
            if (data['output_format'] is String) 'output_format': data['output_format'],
            if (data['background'] is String) 'output_background': data['background'],
          },
        );
      }

      // Relay compatibility is pinned in gpt_image_stream_test.dart: SSE with
      // JSON headers, BOM/comments/leading whitespace, missing separators,
      // multiline JSON, wrapped base64, and completion on a held-open socket.
      // Prefer standard newline joining; compact joining above is only a
      // fallback after invalid JSON, not a rewrite of valid multiline events.
      bool? isSse;
      final jsonLines = <String>[];
      await for (var line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (isSse == null) {
          line = line.replaceFirst(RegExp(r'^\uFEFF'), '');
          if (line.trim().isEmpty) continue;
          isSse = line.startsWith(':') || ['data:', 'event:', 'id:', 'retry:'].any(line.startsWith);
          await LLMDebugLogger.appendLine(
            req.debugFile,
            'Detected format: ${isSse ? 'SSE' : 'JSON'}',
          );
        }
        if (!isSse) {
          jsonLines.add(line);
          continue;
        }
        await LLMDebugLogger.appendStreamLine(req.debugFile, line);
        LLMResponseChunk? chunk;
        if (line.isEmpty || line.startsWith('event:')) {
          chunk = await consume();
          eventName = line.startsWith('event:') ? line.substring(6).trim() : '';
        } else if (line.startsWith('data:')) {
          final dataLine = line.substring(5).replaceFirst(RegExp(r'^ '), '');
          dataLines.add(dataLine);
          // A complete JSON event needs no following blank line. Relays may
          // omit separators or keep the connection open after completion.
          // Only probe plausible object endings: rejoining and decoding on
          // every wrapped base64 line makes large images quadratic to parse.
          // Event boundaries and EOF still decode unconditionally for errors.
          final tail = dataLine.trimRight();
          if (tail.endsWith('}') || tail == '[DONE]') {
            chunk = await consume(deferInvalid: true);
          }
        }
        if (chunk != null) yield chunk;
        if (completed) {
          yield LLMResponseChunk(isDone: true);
          return;
        }
      }
      if (isSse == false) {
        final whole = await decodeResult(
          http.Response(jsonLines.join('\n'), response.statusCode),
          client,
          options,
          logger,
          req.sentImages,
          req.debugFile,
        );
        for (final image in whole.generatedImages) {
          yield LLMResponseChunk(imagePart: image, metadata: whole.metadata);
        }
        yield LLMResponseChunk(textPart: whole.text, metadata: whole.metadata, isDone: true);
        return;
      }
      final tail = await consume();
      if (tail != null) yield tail;
      if (!completed) throw LLMApiException('OpenAI Images stream ended before the final image.');
      yield LLMResponseChunk(isDone: true);
    } catch (error) {
      await LLMDebugLogger.appendLine(req.debugFile, 'Stream failure: $error');
      rethrow;
    } finally {
      await LLMDebugLogger.finish(req.debugFile);
      client.close();
    }
  }

  /// Keep direct protocol callers under the same cross-field contract as the
  /// shared schema. Compression is never sent for PNG, including parked drafts.
  static Map<String, dynamic> outputOptions(Map<String, dynamic>? options) {
    final background = options?['background'];
    final format = options?['outputFormat'];
    if (background != null && !['auto', 'opaque', 'transparent'].contains(background)) {
      throw LLMApiException('Invalid image background. Nothing was sent.');
    }
    if (format != null && !['png', 'jpeg', 'webp'].contains(format)) {
      throw LLMApiException('Invalid image output format. Nothing was sent.');
    }
    if (background == 'transparent' && format == 'jpeg') {
      throw LLMApiException('Transparent backgrounds require PNG or WebP. Nothing was sent.');
    }
    final rawCompression = options?['outputCompression'];
    final compression = rawCompression == null ? null : int.tryParse(rawCompression.toString());
    if (rawCompression != null && (compression == null || compression < 0 || compression > 100)) {
      throw LLMApiException(
        'Image output compression must be an integer from 0 to 100. Nothing was sent.',
      );
    }
    return {
      'background': ?background,
      'output_format': ?format,
      if (compression != null && ['jpeg', 'webp'].contains(format))
        'output_compression': compression,
    };
  }

  /// Map the app's aspect-ratio / image-size options onto an OpenAI image size.
  static String? resolveImageSize(Map<String, dynamic>? options) {
    if (options == null) return null;

    // Explicit WxH wins if it already looks like a pixel size — in any of
    // the spellings [parseWxH] reads, sent in the `WxH` this API expects.
    final explicit = parseWxH(options['imageSize']);
    if (explicit != null) return '${explicit.width}x${explicit.height}';

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
}
