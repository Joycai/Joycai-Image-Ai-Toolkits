import 'dart:async';
import 'dart:convert';

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'dashscope_payload.dart';
import 'dashscope_upload.dart';
import 'dashscope_video_media.dart';
import 'protocol.dart';

/// Alibaba DashScope's native async video surface (wan3.x — its *only*
/// surface; there is no synchronous form):
///
///   `POST {base}/services/aigc/video-generation/video-synthesis`
///     + header `X-DashScope-Async: enable`      → `output.task_id`
///   `GET  {base}/tasks/{task_id}`               → task status / result
///
/// The submit body is not chat-shaped: `input.prompt` plus `input.media[]`
/// entries with a semantic `type` (first_frame / last_frame /
/// reference_image / …), and knobs under `parameters`
/// (docs/api/qianwen-bailian.md §6). Poll results are translated into the
/// Veo-shaped envelope the videoGenerate executor speaks — same contract as
/// every other family.
class DashScopeVideoProtocol implements VideoJobProtocol {
  @override
  Future<VideoSubmission> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final userMsg = history.lastWhere((m) => m.role == LLMRole.user, orElse: () => history.last);

    final attachments = [
      ...userMsg.attachments.where((a) => a.referenceType == LLMReferenceType.sourceVideo),
      ...userMsg.attachments.where((a) => a.referenceType != LLMReferenceType.sourceVideo),
    ];
    final sources = attachments
        .where((a) => a.referenceType == LLMReferenceType.sourceVideo)
        .length;
    final task = options?['videoTask'] ?? 'generate';
    if (sources > 1 ||
        ((task == 'edit' || task == 'extend') && sources != 1) ||
        (task == 'generate' && sources != 0)) {
      throw LLMApiException(
        'Exactly one source video is required for editing or extending. Nothing was sent.',
      );
    }
    var aborted = false;
    final abort = abortTriggerOf(options);
    if (abort != null) unawaited(abort.then((_) => aborted = true));
    void checkCancelled() {
      if (aborted || (cancellationProbeOf(options)?.call() ?? false)) throw const LLMCancelled();
    }

    // Cheap role/count/prompt validation precedes file access and uploads.
    buildDashScopeVideoPayload(
      modelId: config.modelId,
      prompt: userMsg.content,
      media: [
        for (final att in attachments) {'type': dashscopeVideoMediaRole(att), 'url': ''},
      ],
      options: options,
    );
    final needsUpload = attachments.any(
      (att) =>
          att.referenceType == LLMReferenceType.sourceVideo ||
          att.referenceType == LLMReferenceType.referenceVideo ||
          att.referenceType == LLMReferenceType.referenceAudio,
    );
    final media = <Map<String, String>>[];
    final client = config.createClient();
    DashScopePreparedMedia? prepared;
    try {
      if (needsUpload) {
        // Fail unsupported official regions before copying or sending files.
        dashscopeMediaUploadBase(config);
        prepared = await prepareDashScopeVideoMedia(
          attachments,
          outputSeconds: int.tryParse(resolveVideoSeconds(options) ?? '') ?? 5,
          checkCancelled: checkCancelled,
        );
        for (final entry in prepared.files) {
          final url = await uploadDashScopeMedia(
            client: client,
            target: target,
            file: entry.file,
            mime: entry.mime,
            options: options,
            checkCancelled: checkCancelled,
          );
          media.add({'type': entry.role, 'url': url});
        }
      } else {
        // Existing image-only requests keep their inline path and region support.
        for (final att in attachments) {
          checkCancelled();
          final bytes = await readAttachmentBytes(att);
          if (bytes == null) throw LLMApiException('Unreadable reference image. Nothing was sent.');
          media.add({
            'type': dashscopeVideoMediaRole(att),
            'url': imageDataUrl(bytes, att.mimeType),
          });
        }
      }
      checkCancelled();

      final payload = buildDashScopeVideoPayload(
        modelId: config.modelId,
        prompt: userMsg.content,
        media: media,
        options: options,
      );

      final base = dashscopeNativeBase(config.endpoint);
      final url = Uri.parse('$base/services/aigc/video-generation/video-synthesis');
      logger?.call('Submitting DashScope video task to: ${url.host}', level: 'DEBUG');

      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'DashScope (Video Submit)', {
          'url': redactUrl(url),
          'payload': {
            ...payload,
            if (media.isNotEmpty)
              'input': {
                'prompt': (payload['input'] as Map)['prompt'],
                'media': '${media.length} media item(s)',
              },
          },
        });
      }

      final response = await sendJsonRequest(
        client,
        url,
        headers: {
          ...target.headers(),
          'X-DashScope-Async': 'enable',
          if (media.any((item) => item['url']!.startsWith('oss://')))
            'X-DashScope-OssResourceResolve': 'enable',
        },
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'DashScope video submit');
      throwIfDashScopeError(data);

      final output = data['output'];
      final taskId = output is Map ? output['task_id']?.toString() : null;
      if (taskId == null || taskId.isEmpty) {
        throw LLMApiException('DashScope video submit returned no task_id: ${response.body}');
      }
      // Into the log the moment it exists — the only handle left if polling
      // ever dies.
      logger?.call('DashScope video task id: $taskId', level: 'INFO');
      return VideoSubmission(
        taskId,
        inputImages: media
            .where((m) => !['reference_video', 'reference_audio'].contains(m['type']))
            .length,
        inputVideoSeconds: prepared?.videoSeconds ?? 0,
      );
    } finally {
      client.close();
      try {
        await prepared?.dispose();
      } catch (_) {
        // A cleanup failure must never discard an accepted paid job's ticket.
        logger?.call('Could not remove temporary upload copies.', level: 'WARNING');
      }
    }
  }

  /// Poll one task and translate DashScope's
  /// `{output: {task_status, video_url, …}}` into the Veo-shaped envelope.
  /// Statuses: PENDING / RUNNING → not done; SUCCEEDED → done with
  /// `output.video_url` (a flat field, not a choices structure); FAILED /
  /// CANCELED / UNKNOWN → error carrying `output.code` / `output.message`
  /// (UNKNOWN is also what an expired task id reports — task records live
  /// 24 h).
  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final base = dashscopeNativeBase(config.endpoint);
    final url = Uri.parse('$base/tasks/$operationName');

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
      // checkEnvelope: false — a failed task arrives inside a 200 and this
      // status machine owns reporting it, with the task id in the message.
      final data = decodeJsonBody(response, apiName: 'DashScope video poll', checkEnvelope: false);

      final output = data['output'];
      final status = requireJobStatus(
        output is Map ? output['task_status'] : null,
        job: 'DashScope video task',
        jobId: operationName,
      ).toUpperCase();

      switch (status) {
        case 'SUCCEEDED':
          final videoUrl = output is Map ? output['video_url']?.toString() : null;
          if (videoUrl == null || videoUrl.isEmpty) {
            throw LLMApiException(
              'DashScope video task $operationName succeeded but returned '
              'no video_url: ${response.body}',
              isJobEnded: true,
            );
          }
          // A signed OSS link: the API key must not travel to it.
          final usage = data['usage'];
          return videoDoneEnvelope(
            operationName,
            videoUrl,
            requiresAuth: videoUriNeedsAuth(videoUrl, config.endpoint),
            renderedSeconds: usage is Map
                ? (usage['output_video_duration'] ?? usage['duration'])
                : null,
            inputSeconds: usage is Map ? usage['input_video_duration'] : null,
            outputSize: usage is Map && usage['SR'] is num && (usage['SR'] as num) > 0
                ? '${(usage['SR'] as num).toInt()}p'
                : null,
          );
        case 'FAILED':
        case 'CANCELED':
        case 'UNKNOWN':
          final code = output is Map ? output['code'] : null;
          final message = output is Map ? output['message'] : null;
          throw LLMApiException(
            'DashScope video task $operationName $status'
            '${code != null ? ' ($code)' : ''}'
            '${message != null ? ': $message' : ''}'
            '${status == 'UNKNOWN' ? ' (task ids expire after 24h — an expired task also reports UNKNOWN)' : ''}',
            isJobEnded: true,
          );
        default:
          // PENDING / RUNNING / anything newer.
          return {'name': operationName, 'done': false, 'status': status};
      }
    } finally {
      client.close();
    }
  }
}
