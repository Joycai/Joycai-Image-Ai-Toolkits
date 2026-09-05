
import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

/// OpenAI-compatible async video (`POST /videos` → `GET /videos/{id}`) —
/// Sora 2, grok-imagine, Wanxiang, Kling, Vidu, Jimeng served under NewAPI's
/// `/v1/videos` surface.
///
/// The submit endpoint is multipart/form-data so `input_reference` can be
/// attached as a real file part (NewAPI also accepts a Base64 string in that
/// field, but file upload is the spec'd shape and avoids inflating the
/// request body unnecessarily).
///
/// Reads from `options`:
///   * `seconds` — clip duration (string or int, e.g. "5").
///   * `videoQuality` — "standard" | "high".
///   * `aspectRatio` — passed through verbatim if the upstream accepts it.
///   * `resolution` — used together with aspectRatio to derive `size`.
/// And from the user message: the [LLMReferenceType.firstFrame] attachment
/// becomes `input_reference`; any other attachments become `images[]`.
class OpenAIVideosProtocol implements VideoJobProtocol {
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
    final prompt = userMsg.content;

    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos');

    final size = resolveVideoSize(options);
    final seconds = resolveVideoSeconds(options);
    final quality = readStringOption(options, 'videoQuality');

    final request = http.MultipartRequest('POST', url);
    // Auth comes from the vendor profile (layer 2) like every other surface —
    // this was the last protocol with a hardcoded bearer header, which worked
    // only because today's OpenAI-family vendors all happen to use one.
    // Content-Type is dropped: the multipart body sets its own with a
    // boundary. Same fix openai_images_protocol.dart documents.
    request.headers.addAll(
      Map.of(target.headers())
        ..removeWhere((k, _) => k.toLowerCase() == 'content-type'),
    );
    request.fields['model'] = config.modelId;
    request.fields['prompt'] = prompt;
    if (seconds != null) request.fields['seconds'] = seconds;
    if (size != null) request.fields['size'] = size;
    if (quality != null && quality != 'standard') {
      request.fields['quality'] = quality;
    }

    // First-frame attachment → input_reference. Anything beyond that goes
    // into images[] (Sora spec caps at 7; the executor already trims to the
    // capability ceiling).
    LLMAttachment? firstFrame;
    final extras = <LLMAttachment>[];
    for (final att in userMsg.attachments) {
      if (firstFrame == null && att.referenceType == LLMReferenceType.firstFrame) {
        firstFrame = att;
      } else {
        extras.add(att);
      }
    }
    firstFrame ??= userMsg.attachments.isNotEmpty ? userMsg.attachments.first : null;
    if (firstFrame != null && extras.contains(firstFrame)) {
      extras.remove(firstFrame);
    }

    if (firstFrame != null) {
      final bytes = await readAttachmentBytes(firstFrame);
      if (bytes != null) {
        request.files.add(imageMultipartFile(
          'input_reference',
          bytes,
          declaredMime: firstFrame.mimeType,
          baseName: 'first_frame',
        ));
      }
    }
    for (int i = 0; i < extras.length; i++) {
      final att = extras[i];
      final bytes = await readAttachmentBytes(att);
      if (bytes != null) {
        request.files.add(imageMultipartFile(
          'images[]',
          bytes,
          declaredMime: att.mimeType,
          baseName: 'reference_$i',
        ));
      }
    }

    logger?.call('Submitting OpenAI video task to: ${url.host}', level: 'DEBUG');
    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Video Submit)', {
        'url': redactUrl(url),
        'fields': request.fields,
        'files': request.files.map((f) => f.filename).toList(),
      });
    }

    final client = config.createClient();
    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'OpenAI video submit');
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) {
        throw LLMApiException(
            'OpenAI video submit returned no id: ${response.body}');
      }
      logger?.call('OpenAI video task id: $id', level: 'DEBUG');
      return id;
    } finally {
      client.close();
    }
  }

  /// Poll a video task and translate the upstream `{status, progress, url}`
  /// response into the Veo-shaped envelope the task executor already speaks.
  /// This keeps the executor format-agnostic and reuses the existing download
  /// path.
  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = Uri.parse('$baseUrl/videos/$operationName');
    final headers = target.headers();

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      // checkEnvelope: false — a failed job arrives as a 200 with an `error`
      // field beside `status`; the status machine below owns that case and
      // names the operation in its message.
      final data = decodeJsonBody(response,
          apiName: 'OpenAI video fetch', checkEnvelope: false);
      final status = data['status']?.toString() ?? '';

      // Two spellings of the terminal state: NewAPI-style relays say
      // `succeeded`, OpenAI's own Sora surface — and the self-hosted MiniMax
      // H3-Base service, whose `video_…` job ids the checkOperation prefix
      // rule can route here — say `completed`. A poller that only knows one
      // word never errors on the other; it reports "processing" forever.
      if (status == 'succeeded' || status == 'completed') {
        // Prefer the explicit URL when the upstream supplies one; otherwise
        // fall back to the dedicated /content endpoint (which streams the
        // mp4 with the bearer token).
        final videoUrl = data['url']?.toString() ?? '$baseUrl/videos/$operationName/content';
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
      }

      if (status == 'failed') {
        final err = data['error'];
        final msg = err is Map ? (err['message'] ?? err.toString()) : (err?.toString() ?? 'unknown');
        throw Exception('OpenAI video task $operationName failed: $msg');
      }

      // processing / queued — relay progress without marking done.
      return {
        'name': operationName,
        'done': false,
        'progress': data['progress'] ?? 0,
        'status': status,
      };
    } finally {
      client.close();
    }
  }
}
