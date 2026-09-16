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
String openaiImageEditFieldName(int imageCount) =>
    imageCount > 1 ? 'image[]' : 'image';

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
    final config = target.config;
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );
    final prompt = userMsg.content;

    // Cap the reference images to what the model accepts (gpt-image-1: 16).
    var inputImages = userMsg.attachments;
    final maxRef = target.model.capabilities.maxReferenceImages;
    if (maxRef != null && maxRef >= 0 && inputImages.length > maxRef) {
      logger?.call(
        'Model accepts at most $maxRef reference image(s); using the first $maxRef of ${inputImages.length}.',
        level: 'WARN',
      );
      inputImages = inputImages.sublist(0, maxRef);
    }

    final baseUrl = trimBaseUrl(config.endpoint);

    // With input images this is an *edit*; otherwise a text-to-image generation.
    final isEdit = inputImages.isNotEmpty;
    final url = Uri.parse('$baseUrl/images/${isEdit ? 'edits' : 'generations'}');
    logger?.call('Preparing OpenAI Images request (${isEdit ? 'edit' : 'generate'}) to: ${url.host}', level: 'DEBUG');

    final size = resolveImageSize(options);
    final quality = _resolveQuality(options);
    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      http.Response response;

      if (isEdit) {
        // Abortable like every non-streaming send (see sendJsonRequest).
        final request = http.AbortableMultipartRequest('POST', url,
            abortTrigger: abortTriggerOf(options));
        // Auth comes from the vendor profile (layer 2) like every other
        // surface — a hardcoded bearer header worked only because today's
        // OpenAI-family vendors all happen to use one, and would have failed
        // on the next one while plain generation kept working. Content-Type
        // is dropped: the multipart body sets its own with a boundary.
        request.headers.addAll(
          Map.of(target.headers())..removeWhere((k, _) => k.toLowerCase() == 'content-type'),
        );
        request.fields['model'] = config.modelId;
        request.fields['prompt'] = prompt;
        if (size != null) request.fields['size'] = size;
        if (quality != null) request.fields['quality'] = quality;
        request.fields['n'] = '1';

        final field = openaiImageEditFieldName(inputImages.length);
        for (int i = 0; i < inputImages.length; i++) {
          final att = inputImages[i];
          final bytes = await readAttachmentBytes(att);
          if (bytes == null) continue;
          // With an explicit Content-Type per part — see [imageMultipartFile]
          // for the relay that 400s on the octet-stream default.
          request.files.add(imageMultipartFile(
            field,
            bytes,
            declaredMime: att.mimeType,
            baseName: 'image_$i',
          ));
        }

        if (LLMDebugLogger.enabled) {
          debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Edit)', {
            'url': redactUrl(url),
            'fields': request.fields,
            'files': request.files.map((f) => f.filename).toList(),
          });
        }

        final streamed = await client.send(request);
        response = await http.Response.fromStream(streamed);
      } else {
        final headers = target.headers();
        final payload = <String, dynamic>{
          'model': config.modelId,
          'prompt': prompt,
          'n': 1,
          'size': ?size,
          'quality': ?quality,
        };

        if (LLMDebugLogger.enabled) {
          debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Generate)', {
            'url': redactUrl(url),
            'headers': headers,
            'body': payload,
          });
        }

        response = await sendJsonRequest(client, url,
            headers: headers, body: jsonEncode(payload), options: options);
      }

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
            if (item['b64_json'] is String &&
                (item['b64_json'] as String).isNotEmpty)
              item['b64_json'] as String
            else if (item['url'] is String &&
                (item['url'] as String).isNotEmpty)
              item['url'] as String,
      ];
      final images = await resolveImageRefs(refs, client, logger,
          source: 'OpenAI Images API',
          abortTrigger: abortTriggerOf(options));

      if (images.isEmpty) {
        // The Images API has exactly one deliverable. Returning an empty
        // response here reads to the task executor as a successful generation
        // that produced nothing, which is indistinguishable from a model
        // refusing — so say what actually came back instead.
        final body = response.body;
        throw Exception('OpenAI Images API returned no image: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
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
          if (data['usage'] is Map)
            ...(data['usage'] as Map).cast<String, dynamic>(),
          // The size and quality the endpoint settled on. A request that
          // said `auto` has no spec of its own, and a spec-billed fee group
          // prices by exactly this — see `OutputSpec.from`, which prefers
          // these echoes over what was asked for. Facts only: no price here.
          if (data['size'] is String) 'output_size': data['size'],
          if (data['quality'] is String) 'output_quality': data['quality'],
        },
      );
    } finally {
      client.close();
    }
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
