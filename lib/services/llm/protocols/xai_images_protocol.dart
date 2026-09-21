import 'dart:convert';

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

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
class XaiImagesProtocol implements ImageGenProtocol {
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
    final prompt = userMsg.content;

    // Cap the reference images to what the model accepts (5).
    var inputImages = userMsg.attachments;
    final maxRef = target.model.capabilities.maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first $maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

    final isEdit = inputImages.isNotEmpty;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/images/${isEdit ? 'edits' : 'generations'}');
    logger?.call('Preparing xAI Images request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}', level: 'DEBUG');

    final payload = <String, dynamic>{
      'model': config.modelId,
      'prompt': prompt,
      'n': 1,
      'response_format': 'b64_json',
    };

    final aspect = readStringOption(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') payload['aspect_ratio'] = aspect;

    final resolution = readStringOption(options, 'imageSize');
    if (resolution == '1k' || resolution == '2k') {
      payload['resolution'] = resolution;
    }

    int encodedCount = 0;
    if (isEdit) {
      final entries = <Map<String, String>>[];
      for (final att in inputImages) {
        final bytes = await readAttachmentBytes(att);
        if (bytes != null) {
          entries.add({'url': imageDataUrl(bytes, att.mimeType)});
        }
      }
      encodedCount = entries.length;
      if (entries.length == 1) {
        payload['image'] = entries.first;
      } else if (entries.length > 1) {
        payload['images'] = entries;
      }
    }

    LLMDebugLog? debugFile;
    if (LLMDebugLogger.enabled) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'xAI (Image ${isEdit ? 'Edit' : 'Generate'})', {
        'url': redactUrl(url),
        'body': {
          ...payload,
          if (payload.containsKey('image')) 'image': '[base64 data]',
          if (payload.containsKey('images')) 'images': '[$encodedCount base64 image(s)]',
        },
      });
    }

    final client = config.createClient();
    try {
      final response = await sendJsonRequest(
        client,
        url,
        headers: target.headers(),
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      // Status → JSON → shape → envelope, in that order (decodeJsonBody) —
      // this surface previously checked none of the body spellings, so a
      // relay's 200-with-error parsed as "no image data" and hid the cause.
      final data = decodeJsonBody(response, apiName: 'xAI Images API');
      final rawItems = data['data'];
      final List<dynamic> items = rawItems is List ? rawItems : const [];
      // Through the shared resolver: a failed link used to be swallowed
      // without a word, a `data:` URI in `url` was fetched as a link, and an
      // HTML body was accepted as an image.
      final refs = <String>[
        for (final item in items)
          if (item is Map)
            if (item['b64_json'] is String &&
                (item['b64_json'] as String).isNotEmpty)
              item['b64_json'] as String
            else if (item['url'] is String &&
                (item['url'] as String).isNotEmpty)
              item['url'] as String,
      ];
      final images = await resolveImageRefs(refs, client, logger,
          source: 'xAI Images API',
          abortTrigger: abortTriggerOf(options));

      if (images.isEmpty) {
        // e.g. respect_moderation=false leaves url/b64 empty.
        throw LLMApiException('xAI Images API returned no image data (possibly filtered by moderation): ${response.body}');
      }

      logger?.call('xAI Images parse complete. Images: ${images.length}', level: 'DEBUG');

      // Read tolerantly: xAI's current docs do not list `revised_prompt`,
      // but its Images API follows OpenAI's item shape, and a rewrite the
      // endpoint does report should reach the log (standard 13 §1).
      final revised = revisedPromptFrom(items);

      return LLMResponse(
        text: revised,
        generatedImages: images,
        metadata: {
          if (data['usage'] is Map)
            ...(data['usage'] as Map).cast<String, dynamic>(),
          if (revised.isNotEmpty) 'revised_prompt': revised,
        },
      );
    } finally {
      client.close();
    }
  }
}
