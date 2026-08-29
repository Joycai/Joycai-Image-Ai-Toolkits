import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'minimax_payload.dart';
import 'protocol.dart';

/// MiniMax's native image surface: `POST /v1/image_generation`
/// (docs/api/minimax.md §4).
///
/// One endpoint serves both modes — text-to-image, and the "reference" mode
/// that adds `subject_reference`. This is *not* the OpenAI Images API and
/// cannot be reached through one: the body is MiniMax's own, and so is the
/// result envelope (`data.image_urls` beside a `base_resp` that reports
/// failure inside a 200).
///
/// Synchronous: the response arrives once the image exists, which is why
/// `image-01*` declares `longRunning` in layer 3 and the dispatcher lifts its
/// per-request timeout accordingly.
///
/// The one thing worth knowing before using it: MiniMax's reference mode is
/// **subject reference**, not editing — see [minimaxSubjectReferenceNote].
class MiniMaxImagesProtocol implements ImageGenProtocol {
  /// How long a generated image URL stays valid upstream. Nothing is ever
  /// stored as a URL because of it: results are downloaded before this method
  /// returns.
  static const String _urlLifetime = '24h';

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

    final subjectRefs = <String>[];
    for (final att in inputImages) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      subjectRefs.add('data:${att.mimeType};base64,${base64Encode(bytes)}');
    }
    if (subjectRefs.isNotEmpty) {
      logger?.call(minimaxSubjectReferenceNote, level: 'WARN');
    }

    final payload = buildMiniMaxImagePayload(
      modelId: config.modelId,
      prompt: userMsg.content,
      subjectRefs: subjectRefs,
      options: options,
    );

    final url =
        Uri.parse('${minimaxOpenAIBase(config.endpoint)}/image_generation');
    final isReference = subjectRefs.isNotEmpty;
    logger?.call(
        'Preparing MiniMax image request '
        '(${isReference ? 'subject reference' : 'text-to-image'}) to: ${url.host}',
        level: 'DEBUG');

    final client = config.createClient();
    try {
      final appState = AppState();
      LLMDebugLog? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'MiniMax (Image ${isReference ? 'Reference' : 'Generate'})',
          {
            'url': redactUrl(url),
            'headers': target.headers(),
            'body': _payloadForLog(payload, subjectRefs.length),
          },
        );
      }

      final response = await client.post(
        url,
        headers: target.headers(),
        body: jsonEncode(payload),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      // Status → JSON → shape → envelope, in that order. The envelope check
      // is the one that matters here: this surface reports an expired key,
      // an empty balance and a moderation block all as HTTP 200 with a
      // non-zero `base_resp.status_code`, which the shared check already
      // understands (it was written against MiniMax).
      final data = decodeJsonBody(response, apiName: 'MiniMax Images API');
      // Per-image failure lives one level down and survives `status_code: 0`.
      throwIfMiniMaxImagesFailed(data);

      final images = <Uint8List>[];
      for (final ref in minimaxImageRefs(data)) {
        final bytes = await _resolveImageRef(ref, client, logger);
        if (bytes != null) images.add(bytes);
      }

      if (images.isEmpty) {
        // One deliverable, so nothing to return is a failure, not an empty
        // success — the task executor cannot tell those apart and would
        // report a generation that produced no file as done.
        final body = response.body;
        throw LLMApiException('MiniMax Images API returned no image: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }

      logger?.call(
          'MiniMax parse complete. Images: ${images.length} '
          '(downloaded inline; upstream URLs expire in $_urlLifetime)',
          level: 'DEBUG');

      return LLMResponse(
        text: '',
        generatedImages: images,
        // No usage block on this surface — MiniMax bills images per call, and
        // `metadata` carries success/failure counts rather than tokens.
        metadata: const {},
      );
    } finally {
      client.close();
    }
  }

  /// The payload with reference images replaced by a count.
  Map<String, dynamic> _payloadForLog(Map<String, dynamic> payload, int refs) {
    if (refs == 0) return payload;
    return {
      ...payload,
      'subject_reference': '[$refs base64 reference image(s)]',
    };
  }

  /// Turn one response reference into bytes.
  ///
  /// The endpoint answers with a signed object-storage URL that expires in
  /// [_urlLifetime], so the bytes are fetched here rather than handed onward
  /// as a link — a gallery holding those links is empty a day later. The GET
  /// carries no auth header: the signature is in the URL, and the API key has
  /// no meaning at that host.
  ///
  /// A bare base64 string (what `response_format: base64` returns) is decoded
  /// directly; `data:` URIs are handled too, since nothing guarantees which
  /// spelling a relay fronting this surface uses.
  Future<Uint8List?> _resolveImageRef(
    String ref,
    http.Client client,
    LLMLogger? logger,
  ) async {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      try {
        final resp = await client.get(Uri.parse(ref));
        if (resp.statusCode == 200) return resp.bodyBytes;
        logger?.call('Image URL returned ${resp.statusCode}: $ref',
            level: 'WARN');
      } catch (e) {
        logger?.call('Failed to fetch image URL: $e', level: 'WARN');
      }
      return null;
    }

    final payload =
        ref.startsWith('data:') ? ref.substring(ref.indexOf(',') + 1) : ref;
    try {
      return base64Decode(payload);
    } catch (e) {
      logger?.call('Failed to decode inline image: $e', level: 'WARN');
      return null;
    }
  }
}
