import 'dart:convert';

import '../generation/generation_schema.dart';
import '../generation/generation_validator.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import '../output_spec.dart' show reportedCostFromTicks, reportedCostOf;
import '../vendors/vendor_profile.dart';
import 'protocol.dart';

/// xAI native async video (`POST /videos/generations` →
/// `GET /videos/{request_id}`) — grok-imagine-video on native xAI channels.
///
/// JSON body (see https://docs.x.ai/developers/model-capabilities/video/generation):
///   * `prompt` — from the last user message.
///   * `duration` — seconds, 1–15 (mapped from the shared `seconds` option).
///   * `aspect_ratio` — e.g. "16:9" (from the shared `aspectRatio` option).
///   * `resolution` — validated against the version and input mode.
///   * `last_frame` — 1.5 pinned last frame, an object `{url: ...}`.
///   * `image` — image-to-video first frame: an object `{url: ...}` where
///     `url` is a public URL or base64 data URI (per the REST schema —
///     a bare string is rejected with a 422).
///   * `reference_images` — reference-to-video guidance images, each an
///     object `{url: ...}` like `image`.
///
/// Version-specific validation runs before encoding. 1.5 supports pinned
/// first/last frames together with references; classic keeps them exclusive.
/// [submit] returns the request ID and the count of all images actually sent.
class XaiVideosProtocol implements VideoJobProtocol {
  @override
  Future<VideoSubmission> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    options = await validateGeneration(
      GenerationSchema(
        protocol: WireProtocol.xaiVideos,
        capabilities: target.model.capabilities,
        profileId: target.model.capabilities.profileId,
      ),
      history,
      options,
    );
    final config = target.config;
    final userMsg = history.lastWhere((m) => m.role == LLMRole.user, orElse: () => history.last);

    final payload = <String, dynamic>{'model': config.modelId, 'prompt': userMsg.content};

    final seconds = int.tryParse(resolveVideoSeconds(options) ?? '');
    if (seconds != null) payload['duration'] = seconds;

    final aspect = readStringOption(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') payload['aspect_ratio'] = aspect;

    final resolution = readStringOption(options, 'resolution');
    if (resolution != null) payload['resolution'] = resolution;

    final references = <Map<String, String>>[];
    var sentImages = 0;
    for (final att in userMsg.attachments) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null || bytes.isEmpty) {
        throw LLMApiException('Unreadable xAI video input. Nothing was sent.');
      }
      final image = {'url': imageDataUrl(bytes, att.mimeType)};
      switch (att.referenceType) {
        case LLMReferenceType.firstFrame:
          payload['image'] = image;
        case LLMReferenceType.lastFrame:
          payload['last_frame'] = image;
        default:
          references.add(image);
      }
      sentImages++;
    }
    if (references.isNotEmpty) payload['reference_images'] = references;

    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/generations');
    logger?.call('Submitting xAI video task to: ${url.host}', level: 'DEBUG');

    LLMDebugLog? debugFile;
    if (LLMDebugLogger.enabled) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'xAI (Video Submit)', {
        'url': redactUrl(url),
        'payload': {
          ...payload,
          if (payload.containsKey('image')) 'image': '[base64 data]',
          if (payload.containsKey('last_frame')) 'last_frame': '[base64 data]',
          if (payload.containsKey('reference_images'))
            'reference_images': '[${(payload['reference_images'] as List).length} base64 image(s)]',
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

      final data = decodeJsonBody(response, apiName: 'xAI video submit');
      final requestId = data['request_id']?.toString();
      if (requestId == null || requestId.isEmpty) {
        throw LLMApiException('xAI video submit returned no request_id: ${response.body}');
      }
      logger?.call('xAI video request id: $requestId', level: 'DEBUG');
      return VideoSubmission(requestId, inputImages: sentImages);
    } finally {
      client.close();
    }
  }

  /// Poll an xAI video request and translate the native
  /// `{status, video: {url}}` response into the Veo-shaped envelope the task
  /// executor already speaks. Statuses: pending / done / expired / failed.
  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$operationName');

    final client = config.createClient();
    try {
      final response = await sendJsonRequest(
        client,
        url,
        headers: target.headers(),
        body: '',
        options: options,
        method: 'GET',
      );
      // 200 = terminal result; 202 = accepted / still pending — both inside
      // decodeJsonBody's 2xx window. checkEnvelope: false because a failed
      // job carries an `error` field beside `status`, owned by the status
      // machine below (which names the request in its message).
      final data = decodeJsonBody(response, apiName: 'xAI video fetch', checkEnvelope: false);
      return xaiVideoPollEnvelope(data, operationName, config.endpoint);
    } finally {
      client.close();
    }
  }
}

/// One xAI status response translated into the common video-job envelope.
///
/// The done body (【实测 2026-09-22】, `grok-imagine-video-1.5`) is
/// `{status: 'done', video: {url, duration, respect_moderation}, model,
/// usage: {cost_in_usd_ticks}, progress: 100}` — the seconds actually
/// rendered and the charge, both only here: a pending poll is HTTP 202
/// `{status, progress}` and the submit reply is `{request_id}` alone. The
/// charge counts the frames the submit sent (\$0.01 each beside the
/// per-second rate), so it outranks the submit row's own estimate the way an
/// images reply's does (`D2d`).
Map<String, dynamic> xaiVideoPollEnvelope(
  Map<String, dynamic> data,
  String operationName,
  String endpoint,
) {
  final status = requireJobStatus(
    data['status'],
    job: 'xAI video request',
    jobId: operationName,
  ).toLowerCase();

  switch (status) {
    case 'done':
      final video = data['video'] as Map?;
      final videoUrl = video?['url']?.toString();
      if (videoUrl == null || videoUrl.isEmpty) {
        throw LLMApiException(
          'xAI video request $operationName is done but returned no URL: $data',
          isJobEnded: true,
        );
      }
      final usage = data['usage'];
      return videoDoneEnvelope(
        operationName,
        videoUrl,
        requiresAuth: videoUriNeedsAuth(videoUrl, endpoint),
        renderedSeconds: video?['duration'],
        reportedCost: reportedCostOf(
          reportedCostFromTicks(usage is Map ? usage['cost_in_usd_ticks'] : null),
        ),
      );
    case 'failed':
      final err = data['error'];
      final msg = err is Map
          ? '${err['code'] ?? 'unknown'}: ${err['message'] ?? err.toString()}'
          : (err?.toString() ?? 'unknown');
      throw LLMApiException('xAI video request $operationName failed: $msg', isJobEnded: true);
    case 'expired':
      throw LLMApiException(
        'xAI video request $operationName expired before completing.',
        isJobEnded: true,
      );
    case 'cancelled':
    case 'canceled':
      throw LLMApiException(
        'xAI video request $operationName was cancelled upstream.',
        isJobEnded: true,
      );
    default:
      return {
        'name': operationName,
        'done': false,
        'progress': data['progress'] ?? 0,
        'status': status,
      };
  }
}
