import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

/// The open-source `midjourney-proxy` REST wire format (also exposed by
/// NewAPI under `/mj/*`) — an independent layer-1 protocol, not a variant of
/// the OpenAI or Gemini standards.
///
/// MJ is an asynchronous task model — submit → poll → download — that doesn't
/// fit the synchronous chat-completions shape. The submit-poll loop is hidden
/// inside [generate] / [generateStream]: each progress poll surfaces as a text
/// chunk (keeping the 120s per-chunk timeout in `LLMService` reset), and the
/// final image bytes are yielded as `imagePart` — exactly what the existing
/// image-process task executor expects.
///
/// MJ-specific parameters (aspect ratio, version, stylize, chaos, quality)
/// are passed in `options` as structured values and rewritten into the
/// prompt's `--ar`, `--v`, `--s`, `--c`, `--q` flags before submission. This
/// keeps the workbench parameter UI consistent with the other protocols — the
/// user picks a value in a dropdown rather than typing flags by hand.
class MidjourneyProtocol implements ChatProtocol {
  /// Built-in catalog returned by [MidjourneyDiscoveryProtocol]. The proxy
  /// itself doesn't expose a `/models` endpoint, so we present the common MJ
  /// variants users expect to see; they remain free to add custom ids
  /// manually.
  static const List<Map<String, String>> builtinModels = [
    {'id': 'midjourney', 'name': 'Midjourney', 'desc': 'Standard Midjourney model'},
    {'id': 'mj_fast', 'name': 'Midjourney (Fast)', 'desc': 'Fast mode — quicker, higher cost'},
    {'id': 'mj_relax', 'name': 'Midjourney (Relax)', 'desc': 'Relax mode — slower, lower cost'},
    {'id': 'mj_turbo', 'name': 'Midjourney (Turbo)', 'desc': 'Turbo mode — fastest, highest cost'},
    {'id': 'niji-journey', 'name': 'Niji Journey', 'desc': 'Anime-focused MJ variant'},
  ];

  /// Polling interval for `/mj/task/{id}/fetch`. MJ generations take roughly
  /// 30–120s; 3s gives reasonable progress granularity without hammering the
  /// upstream.
  static const Duration _pollInterval = Duration(seconds: 3);

  /// Hard cap on total wait time. MJ has occasional stalls; bailing after
  /// 10 minutes avoids dangling tasks blocking the queue forever.
  static const Duration _maxWait = Duration(minutes: 10);

  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools, // Tool calling is not supported by Midjourney — ignored.
    LLMLogger? logger,
  }) async {
    final result = await _runImagine(target, history, options: options, logger: logger);
    return LLMResponse(
      text: '',
      generatedImages: result.images,
      metadata: result.metadata,
    );
  }

  /// Midjourney has no tool calling at all.
  @override
  bool get streamingDeclaresTools => false;

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    // Ignored: streamingDeclaresTools is false here, so the dispatcher never
    // routes a tool-bearing request to this surface.
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final controller = StreamController<LLMResponseChunk>();

    () async {
      try {
        final result = await _runImagine(
          target,
          history,
          options: options,
          logger: logger,
          onProgress: (msg) {
            if (!controller.isClosed) {
              controller.add(LLMResponseChunk(textPart: '$msg\n'));
            }
          },
        );

        for (final img in result.images) {
          if (controller.isClosed) return;
          controller.add(LLMResponseChunk(imagePart: img));
        }
        if (!controller.isClosed) {
          controller.add(LLMResponseChunk(metadata: result.metadata, isDone: true));
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  /// Fetch the raw `/mj/task/{id}/fetch` status for [taskId]. Exposed for the
  /// dispatcher's `checkOperation` surface.
  Future<Map<String, dynamic>> fetchTaskStatus(
    LLMTarget target,
    String taskId,
  ) async {
    final client = target.config.createClient();
    try {
      return await _fetchTask(client, target, taskId);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<_MjResult> _runImagine(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
    void Function(String message)? onProgress,
  }) async {
    final config = target.config;
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );
    final prompt = _buildPrompt(userMsg.content, options);
    final base64Images = await _encodeAttachments(userMsg.attachments);
    final isBlend = base64Images.length >= 2;

    final baseUrl = trimBaseUrl(config.endpoint);
    final mode = _readMode(options);
    final botType = target.model.isNijiVariant ? 'NIJI_JOURNEY' : 'MID_JOURNEY';

    final client = config.createClient();
    final appState = AppState();
    LLMDebugLog? debugFile;
    try {
      final endpoint = isBlend
          ? Uri.parse('$baseUrl/mj/submit/blend')
          : Uri.parse('$baseUrl/mj/submit/imagine');

      final body = <String, dynamic>{
        'botType': botType,
        if (!isBlend) 'prompt': prompt,
        if (isBlend) 'base64Array': base64Images,
        if (!isBlend && base64Images.isNotEmpty) 'base64Array': base64Images,
        'accountFilter': {
          'modes': [mode],
        },
        'state': '',
      };

      logger?.call('Submitting Midjourney ${isBlend ? "blend" : "imagine"} to: ${endpoint.host}', level: 'DEBUG');
      onProgress?.call('Submitting to Midjourney (${botType == 'NIJI_JOURNEY' ? "Niji" : "MJ"}, mode=$mode)…');

      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'Midjourney (Submit)', {
          'url': endpoint.toString(),
          'body': _safeBody(body),
        });
      }

      final submitResp = await client.post(
        endpoint,
        headers: target.headers(),
        body: jsonEncode(body),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${submitResp.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${submitResp.body}');
      }

      final submitData =
          decodeJsonBody(submitResp, apiName: 'Midjourney submit');
      final submitCode = submitData['code'];
      // code 1 = success, 22 = queued (also acceptable — task is created).
      if (submitCode != 1 && submitCode != 22) {
        throw Exception('Midjourney submit rejected: $submitData');
      }
      final taskId = submitData['result']?.toString();
      if (taskId == null || taskId.isEmpty) {
        throw Exception('Midjourney submit returned no task id: $submitData');
      }

      logger?.call('Midjourney task id: $taskId', level: 'DEBUG');
      onProgress?.call('Task queued ($taskId). Waiting for MJ…');

      // Poll until SUCCESS / FAILURE / timeout.
      final start = DateTime.now();
      int lastProgress = -1;
      String lastStatus = '';
      while (true) {
        if (DateTime.now().difference(start) > _maxWait) {
          throw Exception('Midjourney task $taskId timed out after ${_maxWait.inMinutes} minutes');
        }
        await Future.delayed(_pollInterval);

        final task = await _fetchTask(client, target, taskId);
        final status = task['status']?.toString() ?? '';
        final progress = _parseProgress(task['progress']);
        if (status != lastStatus || progress != lastProgress) {
          lastStatus = status;
          lastProgress = progress;
          final pct = progress >= 0 ? ' ($progress%)' : '';
          onProgress?.call('MJ status: $status$pct');
          logger?.call('Midjourney task $taskId status=$status progress=$progress', level: 'DEBUG');
        }

        if (status == 'SUCCESS') {
          final imageUrl = task['imageUrl']?.toString();
          if (imageUrl == null || imageUrl.isEmpty) {
            throw Exception('Midjourney task $taskId succeeded but returned no imageUrl');
          }
          onProgress?.call('Downloading image…');
          final bytes = await _downloadImage(client, imageUrl);
          return _MjResult(
            images: [bytes],
            metadata: {
              'mj_task_id': taskId,
              'mj_status': status,
              'image_url': imageUrl,
            },
          );
        }
        if (status == 'FAILURE') {
          throw Exception('Midjourney task $taskId failed: ${task['failReason'] ?? task}');
        }
      }
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _fetchTask(
    http.Client client,
    LLMTarget target,
    String taskId,
  ) async {
    final baseUrl = trimBaseUrl(target.config.endpoint);
    final url = Uri.parse('$baseUrl/mj/task/$taskId/fetch');
    final resp = await client.get(url, headers: target.headers());
    // checkEnvelope: false — the task JSON is a status record
    // (status/progress/failReason), and FAILURE is handled by the polling
    // loop with the task id in its message.
    return decodeJsonBody(resp,
        apiName: 'Midjourney fetch', checkEnvelope: false);
  }

  Future<Uint8List> _downloadImage(http.Client client, String url) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('Midjourney image download failed: ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  /// Rewrite the user's prompt to include MJ CLI flags derived from the
  /// structured `options` map. Flags already present in the prompt take
  /// precedence — we don't override what the user typed.
  String _buildPrompt(String raw, Map<String, dynamic>? options) {
    var p = raw.trim();
    if (options == null) return p;

    void appendFlag(String flag, String? value) {
      if (value == null || value.isEmpty || value == 'not_set' || value == 'auto') return;
      // Skip if the user already wrote --flag in the prompt.
      final flagPattern = RegExp('(^|\\s)$flag(\\s|\$)');
      if (flagPattern.hasMatch(p)) return;
      p = '$p $flag $value';
    }

    appendFlag('--ar', options['aspectRatio'] as String?);
    appendFlag('--v', options['mjVersion'] as String?);
    appendFlag('--q', options['mjQuality'] as String?);
    appendFlag('--s', options['mjStylize'] as String?);
    appendFlag('--c', options['mjChaos'] as String?);

    // `--v niji 6` is the canonical way to express the Niji preset; rewrite to
    // the dedicated `--niji` flag for clarity.
    p = p.replaceAll('--v niji ', '--niji ');

    return p.trim();
  }

  Future<List<String>> _encodeAttachments(List<LLMAttachment> attachments) async {
    final out = <String>[];
    for (final att in attachments) {
      final bytes = await readAttachmentBytes(att);
      if (bytes != null) {
        out.add('data:${att.mimeType};base64,${base64Encode(bytes)}');
      }
    }
    return out;
  }

  String _readMode(Map<String, dynamic>? options) {
    final mode = options?['mjMode'];
    if (mode is String && mode.isNotEmpty) {
      final upper = mode.toUpperCase();
      if (upper == 'RELAX' || upper == 'FAST' || upper == 'TURBO') return upper;
    }
    return 'FAST';
  }

  int _parseProgress(dynamic raw) {
    if (raw == null) return -1;
    final s = raw.toString().replaceAll('%', '').trim();
    return int.tryParse(s) ?? -1;
  }

  /// Copy of [body] with `base64Array` truncated for debug logs (the raw
  /// payload can be megabytes when reference images are attached).
  Map<String, dynamic> _safeBody(Map<String, dynamic> body) {
    final copy = Map<String, dynamic>.from(body);
    final arr = copy['base64Array'];
    if (arr is List && arr.isNotEmpty) {
      copy['base64Array'] = arr.map((_) => '[base64 image omitted]').toList();
    }
    return copy;
  }
}

/// Midjourney "discovery" — the proxy exposes no `/models` endpoint, so a
/// built-in catalog of the common MJ variants is returned instead.
class MidjourneyDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    return MidjourneyProtocol.builtinModels
        .map((m) => DiscoveredModel(
              modelId: m['id']!,
              displayName: m['name']!,
              description: m['desc']!,
              rawData: m,
            ))
        .toList();
  }
}

class _MjResult {
  final List<Uint8List> images;
  final Map<String, dynamic> metadata;
  _MjResult({required this.images, required this.metadata});
}
