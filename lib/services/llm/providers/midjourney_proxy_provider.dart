import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_provider_interface.dart';
import '../llm_types.dart';
import '../model_discovery_service.dart';

/// Midjourney transport speaking the open-source `midjourney-proxy` REST
/// surface (also exposed by NewAPI under `/mj/*`).
///
/// MJ is an asynchronous task model — submit → poll → download — that doesn't
/// fit the synchronous chat-completions shape used by Google / OpenAI. We
/// adapt by hiding the submit-poll loop inside [generate] / [generateStream]:
/// each progress poll surfaces as a text chunk (keeping the 120s per-chunk
/// timeout in [LLMService] reset), and the final image bytes are yielded as
/// `imagePart` — exactly what the existing image-process task executor
/// expects.
///
/// MJ-specific parameters (aspect ratio, version, stylize, chaos, quality)
/// are passed in `options` as structured values and rewritten into the
/// prompt's `--ar`, `--v`, `--s`, `--c`, `--q` flags before submission. This
/// keeps the workbench parameter UI consistent with the other providers — the
/// user picks a value in a dropdown rather than typing flags by hand.
class MidjourneyProxyProvider implements ILLMProvider, IModelDiscoveryProvider {
  /// Built-in catalog returned by [fetchModels]. The proxy itself doesn't
  /// expose a `/models` endpoint, so we present the common MJ variants users
  /// expect to see; they remain free to add custom ids manually.
  static const List<Map<String, String>> _builtinModels = [
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
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    return _builtinModels
        .map((m) => DiscoveredModel(
              modelId: m['id']!,
              displayName: m['name']!,
              description: m['desc']!,
              rawData: m,
            ))
        .toList();
  }

  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final result = await _runImagine(config, history, options: options, logger: logger);
    return LLMResponse(
      text: '',
      generatedImages: result.images,
      metadata: result.metadata,
    );
  }

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async* {
    final controller = StreamController<LLMResponseChunk>();

    () async {
      try {
        final result = await _runImagine(
          config,
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

  @override
  Future<String> startLongRunning(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    throw UnsupportedError(
      'Midjourney generation runs inside generate()/generateStream(); '
      'long-running operations are not used by this provider.',
    );
  }

  @override
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  }) async {
    final client = config.createClient();
    try {
      return await _fetchTask(client, config, operationName);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<_MjResult> _runImagine(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
    void Function(String message)? onProgress,
  }) async {
    final userMsg = history.lastWhere(
      (m) => m.role == LLMRole.user,
      orElse: () => history.last,
    );
    final prompt = _buildPrompt(userMsg.content, options);
    final base64Images = await _encodeAttachments(userMsg.attachments);
    final isBlend = base64Images.length >= 2;

    final baseUrl = _normalizeBase(config.endpoint);
    final mode = _readMode(options);
    final botType = _readBotType(config.modelId);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
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
        headers: _headers(config.apiKey),
        body: jsonEncode(body),
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${submitResp.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${submitResp.body}');
      }

      if (submitResp.statusCode != 200) {
        throw Exception('Midjourney submit failed: ${submitResp.statusCode} - ${submitResp.body}');
      }

      final submitData = jsonDecode(submitResp.body) as Map<String, dynamic>;
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

        final task = await _fetchTask(client, config, taskId);
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
    LLMModelConfig config,
    String taskId,
  ) async {
    final baseUrl = _normalizeBase(config.endpoint);
    final url = Uri.parse('$baseUrl/mj/task/$taskId/fetch');
    final resp = await client.get(url, headers: _headers(config.apiKey));
    if (resp.statusCode != 200) {
      throw Exception('Midjourney fetch failed: ${resp.statusCode} - ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
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
      Uint8List? bytes;
      if (att.path != null) {
        bytes = await File(att.path!).readAsBytes();
      } else if (att.bytes != null) {
        bytes = att.bytes;
      }
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

  String _readBotType(String modelId) {
    return modelId.toLowerCase().contains('niji') ? 'NIJI_JOURNEY' : 'MID_JOURNEY';
  }

  int _parseProgress(dynamic raw) {
    if (raw == null) return -1;
    final s = raw.toString().replaceAll('%', '').trim();
    return int.tryParse(s) ?? -1;
  }

  String _normalizeBase(String endpoint) {
    var base = endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

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

class _MjResult {
  final List<Uint8List> images;
  final Map<String, dynamic> metadata;
  _MjResult({required this.images, required this.metadata});
}
