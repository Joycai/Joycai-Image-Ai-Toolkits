import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/image_magic.dart';
import '../image_compression.dart';
import '../image_job.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'dashscope_images_protocol.dart';
import 'dashscope_payload.dart';
import 'protocol.dart';

/// Alibaba DashScope's *asynchronous* image task surface, the per-model
/// alternate to [DashScopeImagesProtocol]:
///
///   `POST {base}/services/aigc/image-generation/generation`
///     + header `X-DashScope-Async: enable`         → `output.task_id`
///   `GET  {base}/tasks/{task_id}`                  → task status / result
///
/// Note the submit path differs from the synchronous surface
/// (`multimodal-generation/generation`) — it is a different endpoint, not a
/// header toggle (docs/api/qianwen-bailian.md §5). The request body is the
/// same wan shape, so the payload builder is shared.
///
/// The poll loop is hidden inside [generateImage] (the Midjourney precedent:
/// an async wire behind the synchronous surface), because the imageProcess
/// executor consumes [LLMResponse], not the video executor's LRO envelope.
class DashScopeImagesAsyncProtocol implements ImageGenProtocol {
  /// One deadline over the whole job — submit, every poll, downloads.
  /// Generation runs on minute timescales, so a per-request guard is the
  /// wrong semantics here; the dispatcher's generateTimeout is lifted above
  /// this so it never fires first.
  static const Duration _overallDeadline = Duration(minutes: 9);

  /// Poll pacing: dense at first, relaxed once the task is clearly queued.
  static const Duration _initialPollInterval = Duration(seconds: 5);
  static const Duration _relaxedPollInterval = Duration(seconds: 6);
  static const int _densePolls = 10;

  @override
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final userMsg = history.lastWhere((m) => m.role == LLMRole.user, orElse: () => history.last);

    // Reference handling mirrors the synchronous protocol: cap to the
    // model's ceiling, inline as data URLs.
    final inputImages = capReferenceImages(
      userMsg.attachments,
      target.model.capabilities.maxReferenceImages,
      logger,
    );
    final imageRefs = <String>[];
    ({int width, int height})? inputSize;
    for (final att in inputImages) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      inputSize ??= ImageCompressor.dimensionsOf(bytes);
      imageRefs.add('data:${resolveImageMime(bytes, att.mimeType)};base64,${base64Encode(bytes)}');
    }

    final base = dashscopeNativeBase(config.endpoint);
    final submitUrl = Uri.parse('$base/services/aigc/image-generation/generation');
    final payload = buildDashScopeImagePayload(
      modelId: config.modelId,
      shape: target.model.capabilities.imageRequestShape,
      prompt: userMsg.content,
      imageRefs: imageRefs,
      options: options,
      inputSize: inputSize,
      sizeSpec: dashscopeSizeSpec(target),
    );

    logger?.call('Submitting DashScope async image task to: ${submitUrl.host}', level: 'DEBUG');

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'DashScope (Image Async Task)', {
          'url': redactUrl(submitUrl),
          'headers': target.headers(),
          'body': dashscopePayloadForLog(payload, imageRefs.length),
        });
      }

      final started = DateTime.now();

      final submitResponse = await sendJsonRequest(
        client,
        submitUrl,
        headers: {...target.headers(), 'X-DashScope-Async': 'enable'},
        body: jsonEncode(payload),
        options: options,
      );
      final submitData = decodeJsonBody(submitResponse, apiName: 'DashScope image task submit');
      throwIfDashScopeError(submitData);

      final output = submitData['output'];
      final taskId = output is Map ? output['task_id']?.toString() : null;
      if (taskId == null || taskId.isEmpty) {
        throw LLMApiException(
          'DashScope image task submit returned no task_id: '
          '${submitResponse.body}',
        );
      }

      final job = ImageJob(
        id: taskId,
        base: base,
        model: config.modelId,
        inputImages: imageRefs.length,
        sentSize: dashscopeSentSize(payload),
      );
      final callback = options?[ImageJob.callbackKey];
      if (callback is Future<void> Function(ImageJob)) {
        try {
          await callback(job);
        } catch (error) {
          throw LLMJobAbandoned(
            taskId,
            'Could not save accepted image task $taskId.',
            cause: error,
          );
        }
      }
      // Recovery information is durable before logging or polling can fail.
      logger?.call('DashScope image task id: $taskId', level: 'INFO');
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'task_id: $taskId');
      }

      return await _poll(
        target,
        job,
        client,
        options: options,
        logger: logger,
        debugFile: debugFile,
        deadline: _overallDeadline - DateTime.now().difference(started),
      );
    } finally {
      client.close();
    }
  }

  /// Recovery deliberately skips original inputs and POST submission.
  Future<LLMResponse> resume(
    LLMTarget target,
    ImageJob job, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    if (dashscopeNativeBase(target.config.endpoint) != job.base ||
        target.config.modelId != job.model) {
      throw LLMJobAbandoned(
        job.id,
        'The image task endpoint or model changed. Restore its original configuration to resume.',
      );
    }
    final client = target.config.createClient();
    try {
      return await _poll(target, job, client, options: options, logger: logger);
    } finally {
      client.close();
    }
  }

  Future<LLMResponse> _poll(
    LLMTarget target,
    ImageJob job,
    http.Client client, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
    LLMDebugLog? debugFile,
    Duration deadline = _overallDeadline,
  }) async {
    final pollUrl = Uri.parse('${job.base}/tasks/${job.id}');
    var polls = 0;

    // The shared loop owns cancellation, the sliced sleep, transient
    // tolerance and the deadline. Its exhausted-failure exit is
    // LLMJobAbandoned, never a 5xx: the old rethrow of the third failed
    // poll made LLMService.request submit a second paid task.
    try {
      return await pollJobUntilDone<LLMResponse>(
        job: 'DashScope image task ${job.id}',
        jobId: job.id,
        // One deadline over the whole job, submit included.
        deadline: deadline,
        interval: (n) => n < _densePolls ? _initialPollInterval : _relaxedPollInterval,
        isCancelled: cancellationProbeOf(options),
        logger: logger,
        fetch: () async {
          final pollResponse = await sendJsonRequest(
            client,
            pollUrl,
            headers: target.headers(),
            body: '',
            options: options,
            method: 'GET',
          );
          // checkEnvelope: false — a FAILED task arrives inside a 200 and is
          // this loop's own business to report, with the task id attached.
          return decodeJsonBody(pollResponse, apiName: 'DashScope task poll', checkEnvelope: false);
        },
        interpret: (data) async {
          polls++;
          final taskOutput = data['output'];
          final status = requireJobStatus(
            taskOutput is Map ? taskOutput['task_status'] : null,
            job: 'DashScope image task',
            jobId: job.id,
          ).toUpperCase();

          if (debugFile != null) {
            await LLMDebugLogger.appendLine(debugFile, 'poll #$polls: $status');
          }

          switch (status) {
            case 'SUCCEEDED':
              if (debugFile != null) {
                await LLMDebugLogger.appendLine(debugFile, 'Body: ${jsonEncode(data)}');
              }
              return _collectResult(
                data,
                job.id,
                client,
                logger,
                sentSize: job.sentSize,
                inputImages: job.inputImages,
                abortTrigger: abortTriggerOf(options),
              );
            case 'FAILED':
            case 'CANCELED':
            case 'UNKNOWN':
              throw LLMApiException(
                dashscopeTaskFailure('DashScope image task', job.id, status, taskOutput).toString(),
                isJobEnded: true,
              );
            default:
              // PENDING / RUNNING / anything newer — keep waiting under the
              // overall deadline.
              logger?.call('DashScope image task ${job.id}: $status', level: 'DEBUG');
              return null;
          }
        },
      );
    } catch (error) {
      if (error is LLMJobAbandoned || (error is LLMApiException && error.isJobEnded)) rethrow;
      throw LLMJobAbandoned(job.id, 'Image task ${job.id} can be resumed.', cause: error);
    }
  }

  /// Extract and download the finished task's images.
  Future<LLMResponse> _collectResult(
    Map<String, dynamic> data,
    String taskId,
    http.Client client,
    LLMLogger? logger, {
    String? sentSize,
    int inputImages = 0,
    Future<void>? abortTrigger,
  }) async {
    final images = await resolveImageRefs(
      dashscopeImageRefs(data),
      client,
      logger,
      source: 'DashScope image task $taskId',
      abortTrigger: abortTrigger,
    );

    if (images.isEmpty) {
      // One deliverable — nothing to return is a failure, not an empty
      // success (the executor cannot tell those apart).
      throw LLMApiException('DashScope image task $taskId succeeded but returned no image.');
    }

    logger?.call(
      'DashScope async task complete. Images: ${images.length} '
      '(downloaded inline; upstream URLs expire in 24h)',
      level: 'DEBUG',
    );

    // With `prompt_extend` on, the task result carries the rewritten prompt
    // as `output.results[].actual_prompt` (documented for async calls only —
    // the synchronous surface returns none). Standard 13 §1.
    final output = data['output'];
    final revised = revisedPromptFrom(
      output is Map ? output['results'] : null,
      key: 'actual_prompt',
    );

    return LLMResponse(
      text: revised,
      generatedImages: images,
      // Same facts as the synchronous surface: the rendered size for spec
      // billing, and an image count so a result without `usage` is still
      // recorded.
      metadata: {
        'dashscopeTaskId': taskId,
        ...dashscopeImageMetadata(
          data: data,
          imageCount: images.length,
          sentSize: sentSize,
          inputImages: inputImages,
        ),
        if (revised.isNotEmpty) 'revised_prompt': revised,
      },
    );
  }
}

/// The error a terminal DashScope task status (FAILED / CANCELED / UNKNOWN)
/// throws, shared by the image and video task surfaces.
///
/// The structured `output.code` / `output.message` survive into the message
/// (`DataInspectionFailed` is a moderation refusal and must not degrade into
/// prose). UNKNOWN gets the expiry note on both surfaces: task records live
/// 24 h, and an expired id reports UNKNOWN rather than "not found" — a
/// different failure from a task that ran and failed (standard 14 §3.3).
LLMApiException dashscopeTaskFailure(String surface, String taskId, String status, Object? output) {
  final code = output is Map ? output['code'] : null;
  final message = output is Map ? output['message'] : null;
  return LLMApiException(
    '$surface $taskId $status'
    '${code != null ? ' ($code)' : ''}'
    '${message != null ? ': $message' : ''}'
    '${status == 'UNKNOWN' ? ' (task ids expire after 24h — an expired task also reports UNKNOWN)' : ''}',
  );
}
