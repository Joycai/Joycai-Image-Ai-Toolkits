import 'dart:convert';

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'dashscope_payload.dart';
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

    final media = <Map<String, String>>[];
    for (final att in userMsg.attachments) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      final String role;
      switch (att.referenceType) {
        case LLMReferenceType.firstFrame:
          role = 'first_frame';
        case LLMReferenceType.lastFrame:
          role = 'last_frame';
        default:
          role = 'reference_image';
      }
      media.add({
        'type': role,
        'url': 'data:${att.mimeType};base64,${base64Encode(bytes)}',
      });
    }

    final parameters = <String, dynamic>{
      // Billing-relevant defaults are sent explicitly rather than inherited:
      // upstream defaults audio to *on* and bills for it.
      'audio': readStringOption(options, 'videoAudio') != 'off',
    };

    final resolution = readStringOption(options, 'resolution');
    if (resolution != null) {
      // Shared spelling is lowercase (480p); DashScope wants 480P/720P/1080P.
      // The legacy Veo "4k" option has no upstream equivalent — clamp to the
      // documented maximum instead of sending a field the endpoint rejects.
      final tier = resolution.toLowerCase();
      parameters['resolution'] = tier.contains('480')
          ? '480P'
          : tier.contains('720')
              ? '720P'
              : '1080P';
    }

    final aspect = readStringOption(options, 'aspectRatio');
    if (aspect != null && aspect != 'not_set') {
      parameters['ratio'] = aspect; // `adaptive` is upstream's own default.
    }

    final seconds = int.tryParse(resolveVideoSeconds(options) ?? '');
    if (seconds != null) parameters['duration'] = seconds.clamp(2, 30);

    final promptExtend = dashscopePromptExtend(options);
    if (promptExtend != null) parameters['prompt_extend'] = promptExtend;

    final payload = <String, dynamic>{
      'model': config.modelId,
      'input': {
        'prompt': userMsg.content,
        if (media.isNotEmpty) 'media': media,
      },
      'parameters': parameters,
    };

    final base = dashscopeNativeBase(config.endpoint);
    final url = Uri.parse('$base/services/aigc/video-generation/video-synthesis');
    logger?.call('Submitting DashScope video task to: ${url.host}',
        level: 'DEBUG');

    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'DashScope (Video Submit)',
        {
          'url': redactUrl(url),
          'payload': {
            ...payload,
            if (media.isNotEmpty)
              'input': '[prompt + ${media.length} base64 media item(s)]',
          },
        },
      );
    }

    final client = config.createClient();
    try {
      final response = await client.post(
        url,
        headers: {
          ...target.headers(),
          'X-DashScope-Async': 'enable',
        },
        body: jsonEncode(payload),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data =
          decodeJsonBody(response, apiName: 'DashScope video submit');
      throwIfDashScopeError(data);

      final output = data['output'];
      final taskId = output is Map ? output['task_id']?.toString() : null;
      if (taskId == null || taskId.isEmpty) {
        throw LLMApiException(
            'DashScope video submit returned no task_id: ${response.body}');
      }
      // Into the log the moment it exists — the only handle left if polling
      // ever dies.
      logger?.call('DashScope video task id: $taskId', level: 'INFO');
      return taskId;
    } finally {
      client.close();
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
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final base = dashscopeNativeBase(config.endpoint);
    final url = Uri.parse('$base/tasks/$operationName');

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: target.headers());
      // checkEnvelope: false — a failed task arrives inside a 200 and this
      // status machine owns reporting it, with the task id in the message.
      final data = decodeJsonBody(response,
          apiName: 'DashScope video poll', checkEnvelope: false);

      final output = data['output'];
      final status = output is Map
          ? output['task_status']?.toString().toUpperCase() ?? ''
          : '';

      switch (status) {
        case 'SUCCEEDED':
          final videoUrl =
              output is Map ? output['video_url']?.toString() : null;
          if (videoUrl == null || videoUrl.isEmpty) {
            throw LLMApiException(
                'DashScope video task $operationName succeeded but returned '
                'no video_url: ${response.body}');
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
        case 'FAILED':
        case 'CANCELED':
        case 'UNKNOWN':
          final code = output is Map ? output['code'] : null;
          final message = output is Map ? output['message'] : null;
          throw LLMApiException(
              'DashScope video task $operationName $status'
              '${code != null ? ' ($code)' : ''}'
              '${message != null ? ': $message' : ''}'
              '${status == 'UNKNOWN' ? ' (task ids expire after 24h — an expired task also reports UNKNOWN)' : ''}');
        default:
          // PENDING / RUNNING / anything newer.
          return {
            'name': operationName,
            'done': false,
            'status': status,
          };
      }
    } finally {
      client.close();
    }
  }
}
