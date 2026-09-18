import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'ark_payload.dart';
import 'protocol.dart';

/// Volcengine Ark's image surface: `POST {base}/images/generations`
/// (docs/api/volcengine-ark.md) — Seedream.
///
/// The path is the OpenAI Images API's generation path, but the body is
/// Ark's: references ride the same JSON request as `image` (a string, or an
/// array for several) instead of an `/images/edits` multipart; `size` is a
/// resolution tier or exact pixels; group generation, the watermark switch,
/// prompt optimization, web search and 5.0 pro's layer decomposition /
/// transparent background have no OpenAI counterpart. The body rules live in
/// `ark_payload.dart`; this class is the transport.
///
/// Synchronous: the response arrives once every image exists (43 s for one
/// 1K 5.0 pro image, measured; minutes for a group), which is why every
/// Seedream table declares `longRunning` and the dispatcher lifts the
/// per-request timeout — further for a larger group ceiling.
///
/// [generateImageStream] is the SSE twin (docs/api/volcengine-ark.md §5):
/// each image is pushed the moment it is drawn — 21 s apart in a measured
/// two-image group — so a long group shows its first result early and a
/// failure late in the group no longer takes the finished ones with it.
///
/// A group can succeed in part: `data[]` then carries an `error` in place of
/// each image that failed (typically moderation) while the rest arrive. Those
/// are delivered with a warning; only a request with no image at all fails.
class ArkImagesProtocol implements ImageGenProtocol {
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
      final debugFile = await _startDebugLog(target, req);
      final response = await sendJsonRequest(
        client,
        req.url,
        headers: target.headers(),
        body: jsonEncode(req.payload),
        options: options,
      );
      await _logWholeBody(debugFile, response);
      return await _fromWholeBody(response, client, options, logger);
    } finally {
      client.close();
    }
  }

  /// The streamed form of [generateImage]: one [LLMResponseChunk.imagePart]
  /// per `image_generation.partial_succeeded`, downloaded as it arrives, then
  /// a closing metadata chunk shaped like [generateImage]'s.
  ///
  /// Only for a model whose table declares `streamsImages` on Ark's own
  /// route — the dispatcher decides. A request upstream answers with plain
  /// JSON instead of SSE (every parameter error does: a 400 envelope, never
  /// an event) goes through the synchronous reader, so both forms fail and
  /// succeed alike.
  Stream<LLMResponseChunk> generateImageStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async* {
    final req = await _prepare(target, history, options, logger, stream: true);
    final client = target.config.createClient();
    LLMDebugLog? debugFile;
    try {
      debugFile = await _startDebugLog(target, req);
      final request = buildJsonRequest('POST', req.url,
          headers: target.headers(),
          body: jsonEncode(req.payload),
          options: options);
      final response = await client.send(trackBodySent(request, options));

      if (response.statusCode != 200) {
        yield* _wholeBodyAsChunks(
            await http.Response.fromStream(response), client, options, logger,
            debugFile);
        return;
      }

      var delivered = 0;
      var undownloadable = 0;
      final failures = <ArkImageFailure>[];
      var usage = const <String, dynamic>{};
      // SSE or one JSON body, told apart by the body rather than by
      // `Content-Type`: the header on a streamed answer was never captured,
      // and misreading SSE as JSON would throw away a group that is already
      // drawn and billed. Null until the first non-empty line decides.
      bool? isSse;
      final jsonLines = <String>[];
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (isSse == null && line.trim().isNotEmpty) {
          final head = line.trimLeft();
          isSse = head.startsWith('data:') ||
              head.startsWith('event:') ||
              head.startsWith(':');
          if (isSse) {
            await LLMDebugLogger.appendLine(debugFile, 'Status: 200 (stream)');
          }
        }
        if (isSse != true) {
          jsonLines.add(line);
          continue;
        }
        if (line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        final data = sseDataPayload(line);
        if (data == null) continue;
        Map<String, dynamic>? event;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) event = decoded;
        } catch (_) {
          continue; // `event:` lines and other non-JSON SSE noise.
        }
        if (event == null) continue;
        final parsed = parseArkStreamEvent(event);
        // An error envelope mid-stream ends the request as a failure; the
        // images already yielded stay delivered. Asked only of what is not a
        // known event: `partial_failed` carries an `error` object too, and
        // it fails one image, not the request.
        if (parsed == null) throwIfEnvelopeError(event);

        switch (parsed) {
          case ArkStreamImage(:final item, :final index):
            final bytes = await resolveImageRef(item.ref, client, logger,
                abortTrigger: abortTriggerOf(options));
            if (bytes == null) {
              undownloadable++;
              logger?.call(
                  'Ark: image ${index ?? delivered + undownloadable} arrived '
                  'but could not be downloaded.',
                  level: 'WARN');
              continue;
            }
            delivered++;
            logger?.call('Ark stream: image $delivered received.',
                level: 'DEBUG');
            yield LLMResponseChunk(imagePart: bytes, imageLayer: item.layer);
          case ArkStreamFailure(:final failure):
            failures.add(failure);
            logger?.call('Ark: one image of the group failed — $failure',
                level: 'WARN');
          case ArkStreamCompleted(usage: final u):
            usage = u;
          case null:
            break;
        }
      }

      if (isSse != true) {
        yield* _wholeBodyAsChunks(
            http.Response(jsonLines.join('\n'), 200,
                headers: response.headers),
            client, options, logger, debugFile);
        return;
      }

      if (delivered == 0) {
        throw LLMApiException(undownloadable > 0
            ? 'Ark Images API streamed $undownloadable image link(s), none '
                'of which could be downloaded.'
            : 'Ark Images API returned no image: '
                '${failures.isNotEmpty ? failures.first : 'the stream ended without one'}');
      }
      logger?.call(
          'Ark stream complete. Images: $delivered '
          '(downloaded inline; upstream URLs expire in 24h)',
          level: 'DEBUG');
      yield LLMResponseChunk(
        metadata: _metadata(delivered, failures.length, usage),
        isDone: true,
      );
    } finally {
      client.close();
      await LLMDebugLogger.finish(debugFile);
    }
  }

  /// A whole (non-SSE) answer to a stream request, as the same chunks the
  /// stream would have produced.
  Stream<LLMResponseChunk> _wholeBodyAsChunks(
    http.Response whole,
    http.Client client,
    Map<String, dynamic>? options,
    LLMLogger? logger,
    LLMDebugLog? debugFile,
  ) async* {
    await _logWholeBody(debugFile, whole);
    final result = await _fromWholeBody(whole, client, options, logger);
    for (final (i, image) in result.generatedImages.indexed) {
      yield LLMResponseChunk(
          imagePart: image,
          imageLayer: i < result.imageLayers.length
              ? result.imageLayers[i]
              : null);
    }
    yield LLMResponseChunk(metadata: result.metadata, isDone: true);
  }

  /// Everything before the send: references encoded, body built, URL and a
  /// mode label for the log.
  Future<_ArkRequest> _prepare(
    LLMTarget target,
    List<LLMMessage> history,
    Map<String, dynamic>? options,
    LLMLogger? logger, {
    required bool stream,
  }) async {
    final config = target.config;
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );

    var inputImages = userMsg.attachments;
    final maxRef = target.model.capabilities.maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first '
        '$maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

    // `data:image/<fmt>;base64,…` with the format read off the bytes — Ark
    // requires the format in lower case, which `resolveImageMime` yields.
    final refs = <String>[];
    for (final att in inputImages) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      refs.add(imageDataUrl(bytes, att.mimeType));
    }

    final payload = buildArkImagePayload(
      modelId: config.modelId,
      prompt: userMsg.content,
      imageRefs: refs,
      tierPixelSizes: target.model.capabilities.tierPixelSizes,
      options: options,
      warn: (m) => logger?.call(m, level: 'WARN'),
      stream: stream,
    );

    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/images/generations');
    final mode = payload['layer_decomposition'] == true
        ? 'layers'
        : payload['background'] == 'transparent'
            ? 'transparent'
            : refs.isEmpty
                ? 'text-to-image'
                : '${refs.length} reference(s)';
    logger?.call(
        'Preparing Ark image request ($mode${stream ? ', streamed' : ''}) '
        'to: ${url.host}',
        level: 'DEBUG');
    return _ArkRequest(url, payload, refs.length, mode);
  }

  Future<LLMDebugLog?> _startDebugLog(LLMTarget target, _ArkRequest req) async {
    if (!LLMDebugLogger.enabled) return null;
    return LLMDebugLogger.startLog(
      target.config.modelId,
      'Ark (Image ${req.mode})',
      {
        'url': redactUrl(req.url),
        'headers': target.headers(),
        'body': {
          ...req.payload,
          if (req.refCount > 0) 'image': '[${req.refCount} base64 image(s)]',
        },
      },
    );
  }

  static Future<void> _logWholeBody(
      LLMDebugLog? debugFile, http.Response response) async {
    if (debugFile == null) return;
    await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
    await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
  }

  /// A whole (non-SSE) response body → the delivered result.
  Future<LLMResponse> _fromWholeBody(
    http.Response response,
    http.Client client,
    Map<String, dynamic>? options,
    LLMLogger? logger,
  ) async {
    // Status → JSON → shape → envelope. Ark's errors are OpenAI-shaped
    // (`{error: {code, message, param, type}}`), both on a 4xx and — when
    // not a single image was produced — inside a 200.
    final data = decodeJsonBody(response, apiName: 'Ark Images API');
    final result = parseArkImageResponse(data);

    for (final failure in result.failures) {
      logger?.call('Ark: one image of the group failed — $failure',
          level: 'WARN');
    }
    if (result.images.isEmpty) {
      final why = result.failures.isNotEmpty
          ? result.failures.first.toString()
          : _excerpt(response.body);
      throw LLMApiException('Ark Images API returned no image: $why');
    }

    // One by one rather than through resolveImageRefs, which drops a link
    // that fails to download and so would slide every later image off its
    // layer record: the pairing below is by position.
    final images = <Uint8List>[];
    final layers = <GeneratedImageLayer?>[];
    for (final item in result.images) {
      final bytes = await resolveImageRef(item.ref, client, logger,
          abortTrigger: abortTriggerOf(options));
      if (bytes == null) continue;
      images.add(bytes);
      layers.add(item.layer);
    }
    if (images.isNotEmpty && images.length < result.images.length) {
      logger?.call(
          'Ark Images API: only ${images.length} of ${result.images.length} '
          'generated image(s) could be retrieved; the rest were billed but '
          'are not saved.',
          level: 'WARN');
    }
    if (images.isEmpty) {
      throw LLMApiException(
          'Ark Images API returned ${result.images.length} image link(s), '
          'none of which could be downloaded.');
    }

    final named = [
      for (final layer in layers)
        if (layer != null && layer.zIndex > 0) layer.name ?? '?',
    ];
    if (named.isNotEmpty) {
      logger?.call(
          'Ark layer decomposition: base + ${named.length} layer(s) — '
          '${named.join(', ')}',
          level: 'INFO');
    }
    logger?.call(
        'Ark parse complete. Images: ${images.length} '
        '(downloaded inline; upstream URLs expire in 24h)',
        level: 'DEBUG');

    return LLMResponse(
      text: '',
      generatedImages: images,
      imageLayers: layers.any((l) => l != null) ? layers : const [],
      metadata: _metadata(images.length, result.failures.length, result.usage),
    );
  }

  /// Ark bills Seedream per image. Its `output_tokens` (pixels / 256) is
  /// informational, and publishing it under a token key would let a
  /// token-priced fee group invent a cost, so the raw block is kept under
  /// its own name. `image_count` keeps the metadata non-empty, which is
  /// what makes LLMService record the usage row at all.
  static Map<String, dynamic> _metadata(
          int images, int failed, Map<String, dynamic> usage) =>
      {
        'image_count': images,
        if (failed > 0) 'failed_images': failed,
        if (usage.isNotEmpty) 'ark_usage': usage,
      };

  static String _excerpt(String body) =>
      body.length > 500 ? '${body.substring(0, 500)}…' : body;
}

/// One prepared request: where it goes, what it carries, and how the log
/// names it.
class _ArkRequest {
  final Uri url;
  final Map<String, dynamic> payload;
  final int refCount;
  final String mode;
  const _ArkRequest(this.url, this.payload, this.refCount, this.mode);
}
