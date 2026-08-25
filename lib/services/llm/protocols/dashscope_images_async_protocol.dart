import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
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
  static const Duration _initialPollInterval = Duration(seconds: 3);
  static const Duration _relaxedPollInterval = Duration(seconds: 6);
  static const int _densePolls = 10;

  /// Consecutive transient poll failures tolerated before giving up. The
  /// task is already billed and a poll is a cheap GET, so jitter and a 429
  /// are worth riding out — but not forever.
  static const int _maxConsecutivePollFailures = 3;

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

    bool cancelled() {
      final probe = options?[llmCancellationProbeKey];
      return probe is bool Function() && probe();
    }

    // Reference handling mirrors the synchronous protocol: cap to the
    // model's ceiling, inline as data URLs.
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

    final base = dashscopeNativeBase(config.endpoint);
    final submitUrl =
        Uri.parse('$base/services/aigc/image-generation/generation');
    final payload = buildDashScopeImagePayload(
      modelId: config.modelId,
      shape: target.model.capabilities.imageRequestShape,
      prompt: userMsg.content,
      imageRefs: imageRefs,
      options: options,
    );

    logger?.call(
        'Submitting DashScope async image task to: ${submitUrl.host}',
        level: 'DEBUG');

    final client = config.createClient();
    try {
      final appState = AppState();
      LLMDebugLog? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'DashScope (Image Async Task)',
          {
            'url': redactUrl(submitUrl),
            'headers': target.headers(),
            'body': dashscopePayloadForLog(payload, imageRefs.length),
          },
        );
      }

      final deadline = DateTime.now().add(_overallDeadline);

      final submitResponse = await client.post(
        submitUrl,
        headers: {
          ...target.headers(),
          'X-DashScope-Async': 'enable',
        },
        body: jsonEncode(payload),
      );
      final submitData = decodeJsonBody(submitResponse,
          apiName: 'DashScope image task submit');
      throwIfDashScopeError(submitData);

      final output = submitData['output'];
      final taskId =
          output is Map ? output['task_id']?.toString() : null;
      if (taskId == null || taskId.isEmpty) {
        throw LLMApiException(
            'DashScope image task submit returned no task_id: '
            '${submitResponse.body}');
      }

      // The task id goes into the logs the moment it exists — if the poll
      // loop dies, this is the only handle left to look the task up with.
      logger?.call('DashScope image task id: $taskId', level: 'INFO');
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'task_id: $taskId');
      }

      final pollUrl = Uri.parse('$base/tasks/$taskId');
      var polls = 0;
      var consecutiveFailures = 0;

      while (true) {
        if (cancelled()) {
          throw LLMApiException(
              'DashScope image task $taskId abandoned: cancelled by user.');
        }
        if (DateTime.now().isAfter(deadline)) {
          throw LLMApiException(
              'DashScope image task $taskId did not finish within '
              '${_overallDeadline.inMinutes} minutes (still polling at '
              'timeout). The task may still complete upstream.');
        }

        await _cancellableSleep(
          polls < _densePolls ? _initialPollInterval : _relaxedPollInterval,
          cancelled,
        );
        polls++;

        Map<String, dynamic> data;
        try {
          final pollResponse =
              await client.get(pollUrl, headers: target.headers());
          // checkEnvelope: false — a FAILED task arrives inside a 200 and is
          // this loop's own business to report, with the task id attached.
          data = decodeJsonBody(pollResponse,
              apiName: 'DashScope task poll', checkEnvelope: false);
          consecutiveFailures = 0;
        } on LLMApiException catch (e) {
          // Transient tolerance: the task is billed either way, and a poll
          // is cheap. Only repeated failure is a real failure.
          consecutiveFailures++;
          if (consecutiveFailures >= _maxConsecutivePollFailures) rethrow;
          logger?.call(
              'DashScope task poll failed (${e.message}); retrying '
              '($consecutiveFailures/$_maxConsecutivePollFailures).',
              level: 'WARN');
          continue;
        }

        final taskOutput = data['output'];
        final status = taskOutput is Map
            ? taskOutput['task_status']?.toString().toUpperCase() ?? ''
            : '';

        if (debugFile != null) {
          await LLMDebugLogger.appendLine(debugFile, 'poll #$polls: $status');
        }

        switch (status) {
          case 'SUCCEEDED':
            if (debugFile != null) {
              await LLMDebugLogger.appendLine(
                  debugFile, 'Body: ${jsonEncode(data)}');
            }
            return await _collectResult(data, taskId, client, logger);
          case 'FAILED':
          case 'CANCELED':
          case 'UNKNOWN':
            // UNKNOWN is also what an expired task reports — either way the
            // structured code/message live inside `output` and must survive
            // into the thrown message (DataInspectionFailed etc.).
            final code = taskOutput is Map ? taskOutput['code'] : null;
            final message = taskOutput is Map ? taskOutput['message'] : null;
            throw LLMApiException(
                'DashScope image task $taskId $status'
                '${code != null ? ' ($code)' : ''}'
                '${message != null ? ': $message' : ''}');
          default:
            // PENDING / RUNNING / anything newer — keep waiting under the
            // overall deadline.
            logger?.call('DashScope image task $taskId: $status',
                level: 'DEBUG');
        }
      }
    } finally {
      client.close();
    }
  }

  /// Extract and download the finished task's images.
  Future<LLMResponse> _collectResult(
    Map<String, dynamic> data,
    String taskId,
    http.Client client,
    LLMLogger? logger,
  ) async {
    final refs = dashscopeImageRefs(data);
    final images = <Uint8List>[];
    for (final ref in refs) {
      final bytes = await resolveDashScopeImageRef(ref, client, logger);
      if (bytes != null) images.add(bytes);
    }

    if (images.isEmpty) {
      // One deliverable — nothing to return is a failure, not an empty
      // success (the executor cannot tell those apart).
      throw LLMApiException(
          'DashScope image task $taskId succeeded but returned no image.');
    }

    logger?.call(
        'DashScope async task complete. Images: ${images.length} '
        '(downloaded inline; upstream URLs expire in 24h)',
        level: 'DEBUG');

    return LLMResponse(
      text: '',
      generatedImages: images,
      metadata: data['usage'] is Map
          ? (data['usage'] as Map).cast<String, dynamic>()
          : const {},
    );
  }

  /// Sleep [duration] in short slices so a cancellation takes effect within
  /// ~500 ms instead of a full poll interval.
  Future<void> _cancellableSleep(
      Duration duration, bool Function() cancelled) async {
    var remaining = duration;
    const slice = Duration(milliseconds: 500);
    while (remaining > Duration.zero) {
      if (cancelled()) return;
      final step = remaining < slice ? remaining : slice;
      await Future.delayed(step);
      remaining -= step;
    }
  }
}
