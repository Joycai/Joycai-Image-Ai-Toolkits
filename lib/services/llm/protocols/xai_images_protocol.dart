import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../state/app_state.dart';
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

    // Cap the reference images to what the model accepts (3).
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
        headers: target.headers(),
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
}
