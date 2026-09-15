import 'dart:convert';

import '../../../core/image_magic.dart';
import '../../../state/app_state.dart';
import '../image_compression.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'dashscope_payload.dart';
import 'protocol.dart';

/// Alibaba DashScope's native image generation / editing surface:
/// `POST /api/v1/services/aigc/multimodal-generation/generation`.
///
/// This is not the OpenAI-compatible images API and cannot be reached through
/// one — `qwen-image*` and `wan2.7-image*` are served only here, with a body
/// DashScope defines itself (see [buildDashScopeImagePayload]) and an error
/// envelope that no other family uses (see [throwIfDashScopeError]).
///
/// Synchronous: the response arrives once the image exists, which is why the
/// models declare `longRunning` in layer 3 and the dispatcher lifts
/// its per-request timeout for them. DashScope also serves an async task
/// variant for `wan2.7-*`; nothing here needs it, since every model in scope
/// answers synchronously.
///
/// With input images the request is an edit; otherwise text-to-image. Both go
/// to the same endpoint — the shape of `content` is the only difference.
class DashScopeImagesProtocol implements ImageGenProtocol {
  /// How long a generated image URL stays valid upstream (documented as 24 h
  /// for `qwen-image*`, unstated for `wan2.7-*`). Nothing is ever stored as a
  /// URL because of it: results are downloaded before this method returns.
  static const String _urlLifetimeNote = '24h';

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

    // Cap the reference images to what the model accepts (qwen: 3, wan2.7: 9).
    var inputImages = userMsg.attachments;
    final maxRef = target.model.capabilities.maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first $maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

    final imageRefs = <String>[];
    ({int width, int height})? inputSize;
    for (final att in inputImages) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      // The first input's proportions drive the default size of an edit —
      // see [dashscopeQwenDefaultSize] for why "no size" is not an option.
      inputSize ??= ImageCompressor.dimensionsOf(bytes);
      imageRefs.add(
          'data:${resolveImageMime(bytes, att.mimeType)};base64,${base64Encode(bytes)}');
    }

    final url = Uri.parse('${dashscopeNativeBase(config.endpoint)}'
        '/services/aigc/multimodal-generation/generation');
    final isEdit = imageRefs.isNotEmpty;
    logger?.call(
        'Preparing DashScope image request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}',
        level: 'DEBUG');

    final payload = buildDashScopeImagePayload(
      modelId: config.modelId,
      shape: target.model.capabilities.imageRequestShape,
      prompt: userMsg.content,
      imageRefs: imageRefs,
      options: options,
      inputSize: inputSize,
      sendsSize: dashscopeModelTakesSize(target),
    );

    final client = config.createClient();
    try {
      final appState = AppState();
      LLMDebugLog? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'DashScope (Image ${isEdit ? 'Edit' : 'Generate'})',
          {
            'url': redactUrl(url),
            'headers': target.headers(),
            'body': _payloadForLog(payload, imageRefs.length),
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
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      // Status → JSON → shape → envelope, then DashScope's own envelope: the
      // shared check only knows OpenAI's `{"error": …}` and MiniMax's
      // `base_resp`, and DashScope uses neither.
      final data = decodeJsonBody(response, apiName: 'DashScope Images API');
      throwIfDashScopeError(data);

      final images = await resolveImageRefs(
          dashscopeImageRefs(data), client, logger,
          source: 'DashScope Images API',
          abortTrigger: abortTriggerOf(options));

      if (images.isEmpty) {
        // One deliverable, so nothing to return is a failure, not an empty
        // success — the task executor cannot tell those apart and would
        // report a generation that produced no file as done.
        final body = response.body;
        throw Exception('DashScope Images API returned no image: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }

      logger?.call(
          'DashScope parse complete. Images: ${images.length} '
          '(downloaded inline; upstream URLs expire in $_urlLifetimeNote)',
          level: 'DEBUG');

      // The image count backstops a missing `usage` block: an empty metadata
      // map skips usage recording on the non-streaming path, which turns a
      // billed generation into one the metrics page never saw.
      return LLMResponse(
        text: '',
        generatedImages: images,
        metadata: dashscopeImageMetadata(
          data: data,
          imageCount: images.length,
          sentSize: dashscopeSentSize(payload),
        ),
      );
    } finally {
      client.close();
    }
  }

  /// The payload with reference images replaced by a count — a base64 image
  /// is megabytes of noise in a debug log that exists to be read.
  Map<String, dynamic> _payloadForLog(Map<String, dynamic> payload, int refs) =>
      dashscopePayloadForLog(payload, refs);
}

/// The `parameters.size` a DashScope image payload actually carried, or null
/// when none was sent.
String? dashscopeSentSize(Map<String, dynamic> payload) {
  final parameters = payload['parameters'];
  final size = parameters is Map ? parameters['size'] : null;
  return size is String && size.isNotEmpty ? size : null;
}

/// Response metadata for a DashScope image result, shared by the synchronous
/// and the async task surface.
///
/// Two facts a spec-billed fee group needs and neither surface published:
///  * **`output_size`** — what was rendered, which is what DashScope bills
///    (qwen-image by output area tier). Best source first: the usage echo's
///    `width`/`height`, its `size` string, then the size this request sent —
///    which the app always chooses itself (the 1K defaults), so "what was
///    asked for" is a real spec rather than "whatever upstream picked".
///    `OutputSpec.from` reads the key and normalises `*` to `x`.
///  * **`image_count`** — so the metadata is never empty: the non-streaming
///    path records usage only for a non-empty map, and the async surface
///    returned `const {}` whenever the task result had no `usage` block.
///
/// Facts only, no prices.
Map<String, dynamic> dashscopeImageMetadata({
  required Map<String, dynamic> data,
  required int imageCount,
  String? sentSize,
}) {
  final rawUsage = data['usage'];
  final usage = rawUsage is Map
      ? rawUsage.cast<String, dynamic>()
      : const <String, dynamic>{};
  final width = usage['width'];
  final height = usage['height'];
  final usageSize = usage['size'];
  final String? rendered;
  if (width is num && height is num && width > 0 && height > 0) {
    rendered = '${width.toInt()}x${height.toInt()}';
  } else if (usageSize is String && usageSize.isNotEmpty) {
    rendered = usageSize;
  } else {
    rendered = null;
  }
  final outputSize = rendered ?? sentSize;
  return {
    'image_count': imageCount,
    ...usage,
    'output_size': ?outputSize,
  };
}
