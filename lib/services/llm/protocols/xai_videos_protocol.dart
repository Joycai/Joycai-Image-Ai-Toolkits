import 'dart:convert';
import 'dart:io';

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

/// xAI native async video (`POST /videos/generations` →
/// `GET /videos/{request_id}`) — grok-imagine-video on native xAI channels.
///
/// JSON body (see https://docs.x.ai/developers/model-capabilities/video/generation):
///   * `prompt` — from the last user message.
///   * `duration` — seconds, 1–15 (mapped from the shared `seconds` option).
///   * `aspect_ratio` — e.g. "16:9" (from the shared `aspectRatio` option).
///   * `resolution` — "480p" | "720p" | "1080p" (mapped from `resolution`;
///     "4k" is clamped to "1080p").
///   * `image` — image-to-video first frame: an object `{url: ...}` where
///     `url` is a public URL or base64 data URI (per the REST schema —
///     a bare string is rejected with a 422).
///   * `reference_images` — reference-to-video guidance images, each an
///     object `{url: ...}` like `image`.
///
/// `image` and `reference_images` are mutually exclusive upstream (400
/// otherwise), so the first frame wins and reference images are dropped
/// with a warning when both are supplied. [submit] returns the `request_id`.
class XaiVideosProtocol implements VideoJobProtocol {
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

    final payload = <String, dynamic>{
      'model': config.modelId,
      'prompt': userMsg.content,
    };

    final seconds = int.tryParse(resolveVideoSeconds(options) ?? '');
    if (seconds != null) payload['duration'] = seconds.clamp(1, 15);

    final aspect = readStringOption(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') payload['aspect_ratio'] = aspect;

    final resolution = readStringOption(options, 'resolution');
    if (resolution != null) {
      // xAI supports 480p / 720p / 1080p; the shared dropdown also offers 4k.
      payload['resolution'] = resolution == '4k' ? '1080p' : resolution;
    }

    // First frame → image-to-video; remaining attachments → reference images.
    LLMAttachment? firstFrame;
    final references = <LLMAttachment>[];
    for (final att in userMsg.attachments) {
      if (att.referenceType == LLMReferenceType.lastFrame) {
        logger?.call('Last frame is not supported by the xAI video API — skipped.', level: 'WARN');
        continue;
      }
      if (firstFrame == null && att.referenceType == LLMReferenceType.firstFrame) {
        firstFrame = att;
      } else {
        references.add(att);
      }
    }

    if (firstFrame != null) {
      final bytes = await readAttachmentBytes(firstFrame);
      if (bytes != null) {
        payload['image'] = {
          'url': 'data:${firstFrame.mimeType};base64,${base64Encode(bytes)}',
        };
      }
      if (references.isNotEmpty) {
        logger?.call(
          'xAI video: image and reference_images are mutually exclusive — '
          '${references.length} reference image(s) dropped in favor of the first frame.',
          level: 'WARN',
        );
      }
    } else if (references.isNotEmpty) {
      final encoded = <Map<String, String>>[];
      for (final att in references) {
        final bytes = await readAttachmentBytes(att);
        if (bytes != null) {
          encoded.add({'url': 'data:${att.mimeType};base64,${base64Encode(bytes)}'});
        }
      }
      if (encoded.isNotEmpty) payload['reference_images'] = encoded;
    }

    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/generations');
    logger?.call('Submitting xAI video task to: ${url.host}', level: 'DEBUG');

    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'xAI (Video Submit)', {
        'url': url.toString(),
        'payload': {
          ...payload,
          if (payload.containsKey('image')) 'image': '[base64 data]',
          if (payload.containsKey('reference_images'))
            'reference_images': '[${(payload['reference_images'] as List).length} base64 image(s)]',
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
        throw Exception('xAI video submit failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final requestId = data['request_id']?.toString();
      if (requestId == null || requestId.isEmpty) {
        throw Exception('xAI video submit returned no request_id: ${response.body}');
      }
      logger?.call('xAI video request id: $requestId', level: 'DEBUG');
      return requestId;
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
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$operationName');

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: target.headers());
      // 200 = terminal result; 202 = accepted / still pending.
      if (response.statusCode != 200 && response.statusCode != 202) {
        throw Exception('xAI video fetch failed: ${response.statusCode} - ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';

      switch (status) {
        case 'done':
          final video = data['video'] as Map?;
          final videoUrl = video?['url']?.toString();
          if (videoUrl == null || videoUrl.isEmpty) {
            throw Exception('xAI video request $operationName is done but returned no URL: ${response.body}');
          }
          return {
            'name': operationName,
            'done': true,
            'response': {
              'generateVideoResponse': {
                'generatedSamples': [
                  {
                    'video': {'uri': videoUrl},
                  }
                ],
              },
            },
          };
        case 'failed':
          final err = data['error'];
          final msg = err is Map
              ? '${err['code'] ?? 'unknown'}: ${err['message'] ?? err.toString()}'
              : (err?.toString() ?? 'unknown');
          throw Exception('xAI video request $operationName failed: $msg');
        case 'expired':
          throw Exception('xAI video request $operationName expired before completing.');
        default:
          // pending — relay progress (0-100) without marking done.
          return {
            'name': operationName,
            'done': false,
            'progress': data['progress'] ?? 0,
            'status': status,
          };
      }
    } finally {
      client.close();
    }
  }
}
