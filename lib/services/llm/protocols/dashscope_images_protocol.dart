import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
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
    for (final att in inputImages) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      imageRefs.add('data:${att.mimeType};base64,${base64Encode(bytes)}');
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

      final response = await client.post(
        url,
        headers: target.headers(),
        body: jsonEncode(payload),
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

      final refs = dashscopeImageRefs(data);
      final images = <Uint8List>[];
      for (final ref in refs) {
        final bytes = await resolveDashScopeImageRef(ref, client, logger);
        if (bytes != null) images.add(bytes);
      }

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

      return LLMResponse(
        text: '',
        generatedImages: images,
        metadata: data['usage'] is Map
            ? (data['usage'] as Map).cast<String, dynamic>()
            : const {},
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

/// Turn one response reference into bytes.
///
/// The endpoint answers with a signed object-storage URL that expires, so
/// the bytes are fetched here rather than handed onward as a link — a
/// gallery holding those links is empty a day later. The GET carries no
/// auth header: the signature is in the URL, and the API key has no meaning
/// at that host.
///
/// Top-level rather than a method so the async-task protocol shares the one
/// implementation.
Future<Uint8List?> resolveDashScopeImageRef(
  String ref,
  http.Client client,
  LLMLogger? logger,
) async {
  if (ref.startsWith('data:')) {
    final comma = ref.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(ref.substring(comma + 1));
    } catch (e) {
      logger?.call('Failed to decode inline image: $e', level: 'WARN');
      return null;
    }
  }

  try {
    final resp = await client.get(Uri.parse(ref));
    if (resp.statusCode == 200) return resp.bodyBytes;
    logger?.call('Image URL returned ${resp.statusCode}: $ref', level: 'WARN');
  } catch (e) {
    logger?.call('Failed to fetch image URL: $e', level: 'WARN');
  }
  return null;
}
