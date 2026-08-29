import 'dart:convert';
import 'dart:io';

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'minimax_h3_base_payload.dart';
import 'protocol.dart';

/// The **self-hosted** MiniMax H3 video surface — the SGLang "H3-Base API"
/// (docs/api/minimax.md §8):
///
///   `POST {base}/videos`               → `{id}`
///   `GET  {base}/videos/{id}`          → `{status}` until `completed`/`failed`
///   `GET  {base}/videos/{id}/content`  → the finished MP4
///
/// Sora-shaped paths, but neither the ① submit body (this one is JSON with a
/// `task` / `conditions[]` / `target` vocabulary, not a multipart form) nor
/// the ① status word (`completed`, not `succeeded`) — see
/// `minimax_h3_base_payload.dart` for the wire rules, which live there so the
/// payload tests can pin them.
///
/// One assumption worth restating from the payload file: reference media go
/// on the wire as `file://` URIs the *server* dereferences — the cookbook
/// documents no URL or base64 form — so attachments only work when the app
/// and the SGLang service share a filesystem. A remote server fails the
/// submit with its own file-not-found, which is the honest outcome; inventing
/// an undocumented base64 spelling would fail silently instead.
class MiniMaxH3BaseVideoProtocol implements VideoJobProtocol {
  @override
  Future<String> submit(
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

    final media = <MiniMaxH3Media>[];
    for (final att in userMsg.attachments) {
      final path = await _attachmentFilePath(att, logger);
      if (path == null) continue;
      final MiniMaxH3Role role;
      switch (att.referenceType) {
        case LLMReferenceType.firstFrame:
          role = MiniMaxH3Role.firstFrame;
        case LLMReferenceType.lastFrame:
          role = MiniMaxH3Role.lastFrame;
        default:
          role = MiniMaxH3Role.reference;
      }
      media.add(MiniMaxH3Media(
          role, minimaxH3FileUri(path, windows: Platform.isWindows)));
    }

    final (kept, dropped) = partitionMiniMaxH3Media(media);
    if (dropped.isNotEmpty) {
      logger?.call(
        'MiniMax H3 local: keyframes and reference material are mutually '
        'exclusive — ${dropped.length} reference image(s) dropped in favor '
        'of the first/last frame.',
        level: 'WARN',
      );
    }
    if (kept.isNotEmpty) {
      logger?.call(
        'MiniMax H3 local: reference media are sent as file:// paths the '
        'server reads directly — the app and the SGLang service must share '
        'a filesystem.',
        level: 'DEBUG',
      );
    }

    final payload = buildMiniMaxH3VideoPayload(
      modelId: config.modelId,
      prompt: userMsg.content,
      media: kept,
      options: options,
    );

    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/videos');
    logger?.call('Submitting MiniMax H3 local video job to: ${url.host}',
        level: 'DEBUG');

    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'MiniMax H3 Local (Video Submit)',
        {
          'url': redactUrl(url),
          'payload': payload,
        },
      );
    }

    final client = config.createClient();
    try {
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

      final data =
          decodeJsonBody(response, apiName: 'MiniMax H3 local video submit');
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) {
        throw LLMApiException(
            'MiniMax H3 local video submit returned no id: ${response.body}');
      }
      logger?.call('MiniMax H3 local video job id: $id', level: 'INFO');
      return id;
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$operationName');

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: target.headers());
      // checkEnvelope: false — a failed job arrives as a 200 with an `error`
      // beside `status`, and the status machine in the payload helper owns
      // that case and names the operation in its message.
      final data = decodeJsonBody(response,
          apiName: 'MiniMax H3 local video poll', checkEnvelope: false);
      // The poll body carries no video URL; the finished MP4 lives at the
      // job's own /content endpoint (auth headers travel with the download —
      // VendorProfile.downloadHeaders — for anyone who fronted the service
      // with an authenticated proxy).
      return minimaxH3PollEnvelope(
          data, operationName, '$baseUrl/videos/$operationName/content');
    } finally {
      client.close();
    }
  }

  /// A filesystem path for [att], materializing byte-only attachments (the
  /// workbench's oversize-compression path strips the original file) into the
  /// system temp directory — the wire carries paths, not bytes, so a path has
  /// to exist somewhere the server can read.
  Future<String?> _attachmentFilePath(
      LLMAttachment att, LLMLogger? logger) async {
    if (att.path != null) return att.path;
    final bytes = att.bytes;
    if (bytes == null) return null;
    final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}joycai_h3_ref_'
        '${DateTime.now().microsecondsSinceEpoch}.${extForMime(att.mimeType)}');
    await file.writeAsBytes(bytes);
    logger?.call(
        'MiniMax H3 local: in-memory reference image written to '
        '${file.path} so it can travel as a file:// URI.',
        level: 'INFO');
    return file.path;
  }
}
