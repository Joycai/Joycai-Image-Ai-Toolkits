import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'minimax_payload.dart';
import 'protocol.dart';

/// MiniMax's native async video surface (`MiniMax-H3` — its *only* surface;
/// there is no synchronous form), docs/api/minimax.md §5:
///
///   `POST   {base}/v2/video_generation`              → `{task_id}`
///   `GET    {base}/v2/query/video_generation/{id}`   → `{task: {...}}`
///   `DELETE {base}/v2/video_generation/{id}`         → cancel or delete
///
/// The submit body is not chat-shaped: a `content[]` array carrying exactly
/// one `text` item plus media items tagged with a semantic `role`
/// (first_frame / last_frame / reference_image), and `resolution` / `duration`
/// as **required** top-level fields with no server-side default. Poll results
/// are translated into the Veo-shaped envelope the videoGenerate executor
/// speaks — same contract as every other family.
class MiniMaxVideoProtocol implements VideoJobProtocol, CancellableJobProtocol {
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

    final media = <MiniMaxVideoMedia>[];
    for (final att in userMsg.attachments) {
      final bytes = await readAttachmentBytes(att);
      if (bytes == null) continue;
      final MiniMaxVideoRole role;
      switch (att.referenceType) {
        case LLMReferenceType.firstFrame:
          role = MiniMaxVideoRole.firstFrame;
        case LLMReferenceType.lastFrame:
          role = MiniMaxVideoRole.lastFrame;
        default:
          role = MiniMaxVideoRole.referenceImage;
      }
      media.add(MiniMaxVideoMedia(
          role, 'data:${att.mimeType};base64,${base64Encode(bytes)}'));
    }

    // Upstream rejects a request that mixes the image-based modality with the
    // reference one, and the body shape does not prevent it — nothing but
    // the `role` tag distinguishes them.
    final (kept, dropped) = partitionMiniMaxVideoMedia(media);
    if (dropped.isNotEmpty) {
      logger?.call(
        'MiniMax video: frames and reference material are mutually exclusive '
        '— ${dropped.length} reference image(s) dropped in favor of the '
        'first/last frame.',
        level: 'WARN',
      );
    }

    final payload = buildMiniMaxVideoPayload(
      modelId: config.modelId,
      prompt: userMsg.content,
      media: kept,
      options: options,
    );

    final url = Uri.parse('${minimaxV2Base(config.endpoint)}/video_generation');
    logger?.call('Submitting MiniMax video task to: ${url.host}',
        level: 'DEBUG');

    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'MiniMax (Video Submit)',
        {
          'url': redactUrl(url),
          'payload': minimaxPayloadForLog(payload),
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

      final data = decodeJsonBody(response, apiName: 'MiniMax video submit');

      final taskId = data['task_id']?.toString();
      if (taskId == null || taskId.isEmpty) {
        throw LLMApiException(
            'MiniMax video submit returned no task_id: ${response.body}');
      }
      // Into the log the moment it exists — the only handle left if polling
      // ever dies. Records live 7 days upstream, so a lost id is recoverable
      // by hand for that long and not after.
      logger?.call('MiniMax video task id: $taskId', level: 'INFO');
      return taskId;
    } finally {
      client.close();
    }
  }

  /// Poll one task and translate MiniMax's `{task: {status, content: {url}}}`
  /// into the Veo-shaped envelope.
  ///
  /// Statuses: `queued` / `running` → not done; `succeeded` → done with
  /// `task.content.url`; `failed` / `cancelled` → error carrying
  /// `task.error.code` / `task.error.message`.
  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final client = target.config.createClient();
    try {
      final task = await _fetchTask(target, operationName, client);
      final status = task['status']?.toString().toLowerCase() ?? '';

      switch (status) {
        case 'succeeded':
          final content = task['content'];
          final videoUrl = content is Map ? content['url']?.toString() : null;
          if (videoUrl == null || videoUrl.isEmpty) {
            throw LLMApiException(
                'MiniMax video task $operationName succeeded but returned no '
                'content.url: $task');
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
        case 'cancelled':
          final error = task['error'];
          final code = error is Map ? error['code'] : null;
          final message = error is Map ? error['message'] : null;
          throw LLMApiException('MiniMax video task $operationName $status'
              '${code != null ? ' ($code)' : ''}'
              '${message != null ? ': $message' : ''}');
        default:
          // queued / running / anything newer.
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

  /// Ask upstream to stop a task the user abandoned locally.
  ///
  /// The endpoint is one `DELETE` that dispatches on the task's current
  /// status, and two of its four behaviours are wrong for a cancel:
  /// `succeeded` and `failed` **delete the record** — which for a finished
  /// video means destroying a result the user paid for, over a race they
  /// could not see (the job can finish between the last poll and this call).
  /// So the status is read first and the DELETE is sent only for `queued`,
  /// the one state where it means "cancel, and do not bill".
  ///
  /// `running` cannot be stopped at all upstream; the local task is abandoned
  /// either way, which is why this is best-effort and returns a description
  /// rather than throwing.
  @override
  Future<String?> cancel(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final client = target.config.createClient();
    try {
      final task = await _fetchTask(target, operationName, client);
      final status = task['status']?.toString().toLowerCase() ?? '';
      if (status != 'queued') {
        logger?.call(
            'MiniMax video task $operationName is "$status" — only a queued '
            'task can be cancelled upstream, so it was left alone (deleting '
            'a finished task would destroy its video).',
            level: 'INFO');
        return null;
      }

      final url = Uri.parse(
          '${minimaxV2Base(target.config.endpoint)}/video_generation/$operationName');
      final response = await client.delete(url, headers: target.headers());
      final data =
          decodeJsonBody(response, apiName: 'MiniMax video cancel');
      final action = data['action']?.toString();
      logger?.call(
          'MiniMax video task $operationName ${action ?? 'cancelled'} upstream.',
          level: 'INFO');
      return action;
    } finally {
      client.close();
    }
  }

  /// The `task` object for [operationName].
  ///
  /// `checkEnvelope: false` — a failed job arrives inside a 200 as
  /// `{task: {status: "failed", error: {...}}}`, and the status machines above
  /// own reporting that with the task id in the message; the generic envelope
  /// check would fire first and discard that context.
  Future<Map<String, dynamic>> _fetchTask(
    LLMTarget target,
    String operationName,
    http.Client client,
  ) async {
    final url = Uri.parse('${minimaxV2Base(target.config.endpoint)}'
        '/query/video_generation/$operationName');
    final response = await client.get(url, headers: target.headers());
    final data = decodeJsonBody(response,
        apiName: 'MiniMax video poll', checkEnvelope: false);

    final task = data['task'];
    if (task is! Map) {
      // Records are kept 7 days; past that the id resolves to nothing rather
      // than to a failed task, and the difference is worth saying out loud.
      throw LLMApiException(
          'MiniMax video task $operationName returned no task object — task '
          'records are kept for 7 days, after which an id resolves to nothing: '
          '${response.body}');
    }
    return task.cast<String, dynamic>();
  }
}
