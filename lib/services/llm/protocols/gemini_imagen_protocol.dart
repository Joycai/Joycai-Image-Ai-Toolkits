import 'dart:convert';

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'gemini_payload.dart';
import 'protocol.dart';

/// Extracts inline images from an Imagen `predictions` value.
/// Malformed relay entries are skipped; bytes are validated later by
/// [resolveImageRefs] before a generation can be reported as successful.
List<String> imagenImageRefs(Object? predictions) {
  if (predictions is! List) return const [];
  final refs = <String>[];
  for (final prediction in predictions) {
    if (prediction is! Map) continue;
    final nested = prediction['image'];
    final raw =
        prediction['bytesBase64Encoded'] ?? (nested is Map ? nested['bytesBase64Encoded'] : null);
    if (raw is String && raw.trim().isNotEmpty) refs.add(raw);
  }
  return refs;
}

/// Imagen text-to-image via the dedicated Gemini `:predict` surface
/// (not `:generateContent`). Text-to-image only — reference images are
/// surfaced (rather than silently dropped) via a warning.
class GeminiImagenProtocol implements ImageGenProtocol {
  @override
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = target.decorateUrl(Uri.parse('$baseUrl/models/${config.modelId}:predict'));
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

    final headers = target.headers();
    final payload = prepareImagenPayload(
      history,
      optionsWithCheckedSize(target, options, logger: logger),
    );

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleImagen (Predict)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': getSafePayload(payload),
        });
      }

      final response = await sendJsonRequest(
        client,
        url,
        headers: headers,
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'Imagen');

      final images = await resolveImageRefs(
        imagenImageRefs(data['predictions']),
        client,
        logger,
        source: 'Imagen',
        abortTrigger: abortTriggerOf(options),
      );

      if (images.isEmpty) {
        // Mirrors the OpenAI/xAI images surfaces: a 200 that carries no
        // decodable image (missing predictions, filtered prompt) is a
        // failure, not an empty success the caller reads as "nothing to do".
        final body = response.body;
        throw LLMApiException(
          'Imagen returned no image data: '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
        );
      }

      logger?.call('Imagen parse complete. Images: ${images.length}', level: 'DEBUG');
      // Imagen's :predict reports no token usage; a non-empty metadata still
      // matters — LLMService only records usage (request-count billing
      // included) when there is some, so `{}` made every Imagen call
      // invisible to the metrics page.
      return LLMResponse(
        text: '',
        generatedImages: images,
        metadata: {'prediction_count': images.length},
      );
    } finally {
      client.close();
    }
  }
}
