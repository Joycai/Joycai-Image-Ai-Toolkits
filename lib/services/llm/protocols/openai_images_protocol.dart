import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

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

    final size = _resolveImageSize(options);
    final quality = _resolveQuality(options);
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      http.Response response;

      if (isEdit) {
        final request = http.MultipartRequest('POST', url);
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

        for (int i = 0; i < inputImages.length; i++) {
          final att = inputImages[i];
          final bytes = await readAttachmentBytes(att);
          if (bytes == null) continue;
          request.files.add(http.MultipartFile.fromBytes(
            'image[]',
            bytes,
            filename: 'image_$i.${extForMime(att.mimeType)}',
          ));
        }

        if (appState.enableApiDebug) {
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

        if (appState.enableApiDebug) {
          debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Image Generate)', {
            'url': redactUrl(url),
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

      // Status → JSON → shape → envelope, in that order (decodeJsonBody).
      // 200 does not mean success on a relay — an `{"error": …}` body used
      // to parse as zero images and report the task as finished with
      // nothing in it.
      final data = decodeJsonBody(response, apiName: 'OpenAI Images API');
      final rawItems = data['data'];
      final List<dynamic> items = rawItems is List ? rawItems : const [];
      final List<Uint8List> images = [];

      for (final item in items) {
        if (item is! Map) continue;
        final b64 = item['b64_json'];
        if (b64 is String && b64.isNotEmpty) {
          images.add(base64Decode(b64));
          continue;
        }
        final imgUrl = item['url'];
        if (imgUrl is String && imgUrl.isNotEmpty) {
          try {
            final imgResp = await client.get(Uri.parse(imgUrl));
            if (imgResp.statusCode == 200) {
              images.add(imgResp.bodyBytes);
            } else {
              logger?.call('Image URL returned ${imgResp.statusCode}: $imgUrl', level: 'WARN');
            }
          } catch (e) {
            logger?.call('Failed to fetch image URL: $e', level: 'WARN');
          }
        }
      }

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

      return LLMResponse(
        text: '',
        generatedImages: images,
        // gpt-image-1 reports `input_tokens`/`output_tokens` here, not the
        // chat spelling — see LLMService._recordUsage, which reads both.
        metadata: data['usage'] is Map
            ? (data['usage'] as Map).cast<String, dynamic>()
            : const {},
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
}
