import 'dart:convert';

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
    );

    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/images/generations');
    final mode = payload['layer_decomposition'] == true
        ? 'layers'
        : payload['background'] == 'transparent'
            ? 'transparent'
            : refs.isEmpty
                ? 'text-to-image'
                : '${refs.length} reference(s)';
    logger?.call('Preparing Ark image request ($mode) to: ${url.host}',
        level: 'DEBUG');

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'Ark (Image $mode)',
          {
            'url': redactUrl(url),
            'headers': target.headers(),
            'body': {
              ...payload,
              if (refs.isNotEmpty) 'image': '[${refs.length} base64 image(s)]',
            },
          },
        );
      }

      final response = await sendJsonRequest(
        client,
        url,
        headers: target.headers(),
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

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

      final images = await resolveImageRefs(
          [for (final item in result.images) item.ref], client, logger,
          source: 'Ark Images API', abortTrigger: abortTriggerOf(options));
      if (images.isEmpty) {
        throw LLMApiException(
            'Ark Images API returned ${result.images.length} image link(s), '
            'none of which could be downloaded.');
      }

      final layers = [
        for (final item in result.images)
          if (item.zIndex != null && item.zIndex! > 0) item.name ?? '?',
      ];
      if (layers.isNotEmpty) {
        logger?.call(
            'Ark layer decomposition: base + ${layers.length} layer(s) — '
            '${layers.join(', ')}',
            level: 'INFO');
      }
      logger?.call(
          'Ark parse complete. Images: ${images.length} '
          '(downloaded inline; upstream URLs expire in 24h)',
          level: 'DEBUG');

      // Ark bills Seedream per image. Its `output_tokens` (pixels / 256) is
      // informational, and publishing it under a token key would let a
      // token-priced fee group invent a cost, so the raw block is kept under
      // its own name. `image_count` keeps the metadata non-empty, which is
      // what makes LLMService record the usage row at all.
      return LLMResponse(
        text: '',
        generatedImages: images,
        metadata: {
          'image_count': images.length,
          if (result.failures.isNotEmpty)
            'failed_images': result.failures.length,
          if (result.usage.isNotEmpty) 'ark_usage': result.usage,
        },
      );
    } finally {
      client.close();
    }
  }

  static String _excerpt(String body) =>
      body.length > 500 ? '${body.substring(0, 500)}…' : body;
}
