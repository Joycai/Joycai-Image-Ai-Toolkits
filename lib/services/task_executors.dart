part of 'task_queue_service.dart';

/// Per-task-type execution logic for [TaskQueueService].
///
/// Implemented as a `part of` extension so it can use the service's private
/// members (`_emit`, `_queue`, callbacks) while keeping the queue-management
/// core file focused on scheduling and lifecycle.
extension TaskExecutors on TaskQueueService {
  Future<bool> _shouldUseStream(TaskItem task) async {
    if (!task.useStream) return false;
    if (task.modelDbId == null) return true; // Fallback for legacy

    final db = DatabaseService();
    final models = await db.getModels();
    final model = models.cast<LLMModel?>().firstWhere((m) => m?.id == task.modelDbId, orElse: () => null);

    if (model != null) {
      if (!model.supportsStream) {
        task.addLog('Model does not support streaming. Falling back to standard request.');
        return false;
      }
    }
    return true;
  }

  Future<void> _executeImageProcessTask(TaskItem task) async {
    task.addLog('Start processing with model: ${task.modelDbId ?? task.modelId}');

    final outputDir = await _getEffectiveOutputDir(task);

    final attachments = task.imagePaths.map((path) =>
      LLMAttachment.fromFile(File(path), _getMimeType(path))
    ).toList();

    final messages = [
      LLMMessage(
        role: LLMRole.user,
        content: task.parameters['prompt'] ?? '',
        attachments: attachments,
      )
    ];

    List<Uint8List> generatedImages = [];
    final actualUseStream = await _shouldUseStream(task);

    if (actualUseStream) {
      final stream = LLMService().requestStream(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        contextId: task.id,
        options: task.parameters,
      );

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;

        if (chunk.textPart != null) {
          _emit(task.id, TaskEventType.textChunk, chunk.textPart);
          task.addLog('AI: ${chunk.textPart}');
          refreshQueue();
        }

        if (chunk.imagePart != null) {
          generatedImages.add(chunk.imagePart!);
          task.addLog('Received image chunk.');
          refreshQueue();
        }
      }
    } else {
      final response = await LLMService().request(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        options: task.parameters,
        useStream: false,
      );

      if (response.text.isNotEmpty) {
        _emit(task.id, TaskEventType.textChunk, response.text);
        task.addLog('AI: ${response.text}');
      }

      if (response.generatedImages.isNotEmpty) {
        generatedImages.addAll(response.generatedImages);
      }
    }

    task.addLog('LLM Task finished.');

    if (task.status == TaskStatus.cancelled) return;

    for (int i = 0; i < generatedImages.length; i++) {
      final bytes = generatedImages[i];
      final prefix = task.parameters['imagePrefix'] ?? 'result';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix}_${timestamp}_$i.png';
      final filePath = p.join(outputDir, fileName);

      final file = File(filePath);
      await file.writeAsBytes(bytes);
      task.resultPaths.add(filePath);
      _emit(task.id, TaskEventType.imageResult, filePath);
      task.addLog('Saved result image to: $filePath');

      onTaskCompleted?.call(file);
    }
  }

  /// Prompt refinement.
  ///
  /// Two modes:
  ///  * `parameters['sessionId']` present — one turn of the interactive
  ///    [PromptOptimizerAgent]; the conversation lives in the in-memory
  ///    session, images are attached on demand via tool calls.
  ///  * Otherwise — legacy one-shot refinement (kept for tasks restored from
  ///    the database).
  Future<void> _executePromptRefineTask(TaskItem task) async {
    final sessionId = task.parameters['sessionId'] as String?;
    if (sessionId != null) {
      final session = PromptOptimizerAgent.sessions[sessionId];
      if (session == null) {
        throw Exception('Optimizer session is no longer available '
            '(it does not survive an app restart). Start a new conversation.');
      }

      task.addLog('Start optimizer agent turn (${task.imagePaths.length} reference images).');

      // Per-model agent setting: force viewing every reference image.
      bool forceViewAll = false;
      if (task.modelDbId != null) {
        final models = await DatabaseService().getModels();
        final model = models
            .cast<LLMModel?>()
            .firstWhere((m) => m?.id == task.modelDbId, orElse: () => null);
        forceViewAll = model?.forceViewAllImages ?? false;
      }

      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: task.modelDbId ?? task.modelId,
        systemPrompt: task.parameters['systemPrompt'],
        forceViewAllImages: forceViewAll,
        referenceImages: task.imagePaths
            .map((path) => {'path': path, 'name': p.basename(path)})
            .toList(),
        contextId: task.id,
        onLog: (msg) {
          task.addLog(msg);
          refreshQueue();
        },
        isCancelled: () => task.status == TaskStatus.cancelled,
      );

      if (session.refinedPrompt != null) {
        task.parameters['refinedPrompt'] = session.refinedPrompt;
      }
      task.addLog('Optimizer agent turn finished.');
      return;
    }

    task.addLog('Start prompt refinement.');

    final messages = <LLMMessage>[];
    if (task.parameters['systemPrompt'] != null) {
      messages.add(LLMMessage(role: LLMRole.system, content: task.parameters['systemPrompt']));
    }

    final attachments = task.imagePaths.map((path) =>
      LLMAttachment.fromFile(File(path), _getMimeType(path))
    ).toList();

    messages.add(LLMMessage(
      role: LLMRole.user,
      content: task.parameters['roughPrompt'] ?? '',
      attachments: attachments,
    ));

    String resultText = "";
    final actualUseStream = await _shouldUseStream(task);

    if (actualUseStream) {
      final stream = LLMService().requestStream(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        contextId: task.id,
      );

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;
        if (chunk.textPart != null) {
          resultText += chunk.textPart!;
          _emit(task.id, TaskEventType.textChunk, chunk.textPart);
          refreshQueue();
        }
      }
    } else {
      final response = await LLMService().request(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        options: task.parameters,
        useStream: false,
      );
      resultText = response.text;
      _emit(task.id, TaskEventType.textChunk, resultText);
    }

    if (task.status == TaskStatus.cancelled) return;

    task.parameters['refinedPrompt'] = resultText;
    task.addLog('Refinement complete.');
  }

  /// AI batch rename via a standard LLM tool-use agent loop.
  ///
  /// Two modes:
  ///  * `parameters['proposals']` present — the user already confirmed these
  ///    renames in the preview dialog; apply them directly without another
  ///    LLM round-trip.
  ///  * Otherwise — run [AiRenameAgent] (list_files / rename_file tools) to
  ///    collect proposals, then apply them.
  Future<void> _executeAiRenameTask(TaskItem task) async {
    task.addLog('Start AI Batch Rename for ${task.imagePaths.length} files.');

    List<RenameProposal> proposals;

    final preConfirmed = task.parameters['proposals'];
    if (preConfirmed is List && preConfirmed.isNotEmpty) {
      proposals = preConfirmed
          .whereType<Map>()
          .map((m) => RenameProposal(
                path: m['path']?.toString() ?? '',
                oldName: m['old_name']?.toString() ?? '',
                newName: m['new_name']?.toString() ?? '',
              ))
          .where((prop) => prop.path.isNotEmpty && prop.newName.isNotEmpty)
          .toList();
      task.addLog('Applying ${proposals.length} user-confirmed rename(s).');
    } else {
      final filesData = (task.parameters['filesData'] as List<dynamic>? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList();

      proposals = await AiRenameAgent.collectProposals(
        modelIdentifier: task.modelDbId ?? task.modelId,
        filesData: filesData,
        systemPrompt: task.parameters['system_prompt'],
        instructions: task.parameters['instructions'],
        contextId: task.id,
        onLog: (msg) {
          task.addLog(msg);
          _emit(task.id, TaskEventType.textChunk, msg);
          refreshQueue();
        },
        isCancelled: () => task.status == TaskStatus.cancelled,
      );
      task.addLog('Agent staged ${proposals.length} rename proposal(s).');
    }

    if (task.status == TaskStatus.cancelled) return;

    final renamed = await AiRenameAgent.applyProposals(
      proposals,
      onLog: task.addLog,
    );

    task.addLog('AI Rename complete. $renamed file(s) renamed.');
  }

  Future<void> _executeVideoGenerateTask(TaskItem task) async {
    task.addLog('Start video generation with model: ${task.modelDbId ?? task.modelId}');

    final outputDir = await _getEffectiveOutputDir(task);

    // 1. Prepare messages and attachments
    final attachments = <LLMAttachment>[];

    // First frame
    final firstFramePath = task.parameters['firstFramePath'] as String?;
    if (firstFramePath != null && firstFramePath.isNotEmpty) {
      attachments.add(LLMAttachment.fromFile(File(firstFramePath), _getMimeType(firstFramePath), referenceType: LLMReferenceType.firstFrame));
      task.addLog('Added first frame: ${p.basename(firstFramePath)}');
    }

    // Last frame
    final lastFramePath = task.parameters['lastFramePath'] as String?;
    if (lastFramePath != null && lastFramePath.isNotEmpty) {
      attachments.add(LLMAttachment.fromFile(File(lastFramePath), _getMimeType(lastFramePath), referenceType: LLMReferenceType.lastFrame));
      task.addLog('Added last frame: ${p.basename(lastFramePath)}');
    }

    // Reference images
    final referenceImagePaths = task.parameters['referenceImagePaths'] as List<dynamic>?;
    if (referenceImagePaths != null) {
      for (var path in referenceImagePaths) {
        final pathStr = path as String;
        attachments.add(LLMAttachment.fromFile(File(pathStr), _getMimeType(pathStr), referenceType: LLMReferenceType.asset));
        task.addLog('Added reference image: ${p.basename(pathStr)}');
      }
    }

    final messages = [
      LLMMessage(
        role: LLMRole.user,
        content: task.parameters['prompt'] ?? '',
        attachments: attachments,
      )
    ];

    // 2. Start Long Running Operation
    final operationName = await LLMService().startLongRunning(
      modelIdentifier: task.modelDbId ?? task.modelId,
      messages: messages,
      contextId: task.id,
      options: task.parameters,
    );

    task.addLog('LRO started: $operationName');
    _emit(task.id, TaskEventType.progress, 0.05);

    // 3. Polling Loop
    String? videoUri;
    final pollStartTime = DateTime.now();
    while (true) {
      if (task.status == TaskStatus.cancelled) break;

      if (DateTime.now().difference(pollStartTime) > const Duration(minutes: 30)) {
        throw Exception('Video generation task timed out after 30 minutes.');
      }

      final opStatus = await LLMService().checkOperation(
        modelIdentifier: task.modelDbId ?? task.modelId,
        operationName: operationName,
        contextId: task.id,
      );

      final isDone = opStatus['done'] == true;
      if (isDone) {
        final response = opStatus['response'] as Map?;
        if (response != null) {
          final genVideoResponse = response['generateVideoResponse'] as Map?;
          if (genVideoResponse != null) {
            final samples = genVideoResponse['generatedSamples'] as List?;
            if (samples != null && samples.isNotEmpty) {
              final firstSample = samples[0] as Map?;
              final video = firstSample?['video'] as Map?;
              videoUri = video?['uri'] as String?;
            }
          }
        }

        if (videoUri == null) {
          throw Exception('Operation finished but no video URI found. Response: ${jsonEncode(response)}');
        }
        break;
      }

      // If not done, update progress and wait
      task.addLog('Generation in progress...');
      _emit(task.id, TaskEventType.progress, 0.5); // Placeholder progress

      await Future.delayed(const Duration(seconds: 10));
    }

    if (task.status == TaskStatus.cancelled) return;

    // 4. Download Video
    task.addLog('Downloading video from: $videoUri');
    _emit(task.id, TaskEventType.progress, 0.8);

    final downloadPath = await _downloadVideo(videoUri!, task, outputDir);

    task.resultPaths.add(downloadPath);
    _emit(task.id, TaskEventType.imageResult, downloadPath); // Reusing imageResult for video path
    task.addLog('Saved video to: $downloadPath');

    onTaskCompleted?.call(File(downloadPath));
  }

  Future<String> _downloadVideo(String url, TaskItem task, String outputDir) async {
    final client = HttpClient();
    try {
      final db = DatabaseService();
      String? apiKey;
      String? providerType;
      if (task.modelDbId != null) {
        final models = await db.getModels();
        final model = models.cast<LLMModel?>().firstWhere((m) => m?.id == task.modelDbId, orElse: () => null);
        if (model != null && model.channelId != null) {
          providerType = model.type;
          final channel = await db.getChannel(model.channelId!);
          if (channel != null) {
            apiKey = channel.apiKey;
          }
        }
      }

      final request = await client.getUrl(Uri.parse(url));
      if (apiKey != null) {
        // Veo URIs sit on Google's CDN and want `x-goog-api-key`; OpenAI/Sora
        // URIs sit on the relay and want `Authorization: Bearer`. The header
        // each side doesn't recognise is silently ignored, so we add both for
        // any non-Google provider rather than try to sniff the URL host.
        if (providerType == 'google-genai') {
          request.headers.add('x-goog-api-key', apiKey);
        } else {
          request.headers.add('Authorization', 'Bearer $apiKey');
        }
      }

      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Failed to download video: ${response.statusCode}');
      }

      final prefix = task.parameters['imagePrefix'] ?? 'video';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix}_$timestamp.mp4';
      final filePath = p.join(outputDir, fileName);

      final file = File(filePath);
      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } catch (e) {
        await sink.close();
        rethrow;
      }
      return filePath;
    } finally {
      client.close();
    }
  }

  Future<void> _executeDownloadTask(TaskItem task) async {
    task.addLog('Start downloading ${task.imagePaths.length} images.');

    final outputDir = await _getEffectiveOutputDir(task);

    final cookies = task.parameters['cookies'] as String?;
    final formattedCookies = WebScraperService().parseCookies(cookies ?? '');
    final prefix = task.parameters['prefix'] ?? 'download';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    for (int i = 0; i < task.imagePaths.length; i++) {
      if (task.status == TaskStatus.cancelled) break;

      final url = task.imagePaths[i];
      task.addLog('Downloading: $url');
      refreshQueue();

      try {
        final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (formattedCookies.isNotEmpty) {
          request.headers.add(HttpHeaders.cookieHeader, formattedCookies);
        }

        final response = await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw Exception('Failed to download image: ${response.statusCode}');
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = _getExtensionFromUrl(url);
        final fileName = '${prefix}_${timestamp}_$i$extension';
        final filePath = p.join(outputDir, fileName);

        final file = File(filePath);
        final sink = file.openWrite();
        try {
          await response.timeout(const Duration(seconds: 60)).pipe(sink);
        } catch (e) {
          await sink.close();
          rethrow;
        }
        task.resultPaths.add(filePath);
        _emit(task.id, TaskEventType.imageResult, filePath);
        _emit(task.id, TaskEventType.progress, (i + 1) / task.imagePaths.length);
        task.addLog('Saved to: $filePath');

        onTaskCompleted?.call(file);
        refreshQueue();
      } catch (e) {
        task.addLog('Failed to download $url: $e');
        // We continue with other images even if one fails
      }
    }
    client.close();
  }

  String _getExtensionFromUrl(String url) {
    final path = Uri.parse(url).path;
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty || !['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext)) {
      return '.png'; // Default
    }
    return ext;
  }

  String _getMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.webp') return 'image/webp';
    return 'image/jpeg';
  }

  /// Checks if primary output is writable, returns it or falls back to Result Cache.
  Future<String> _getEffectiveOutputDir(TaskItem task) async {
    final db = DatabaseService();
    String? primary = await db.getSetting('output_directory');

    // Result Cache is always initialized in GalleryState for iOS/macOS
    String? fallback;
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final appCache = (await db.getSetting('result_cache_directory')) ?? '';
        if (appCache.isNotEmpty) fallback = appCache;
      }
    } catch (_) {}

    if (primary == null || primary.isEmpty) {
      if (fallback != null) return fallback;
      throw Exception('Output directory not set!');
    }

    try {
      final dir = Directory(primary);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      // Test writability
      final testFile = File(p.join(primary, '.write_test'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return primary;
    } catch (e) {
      task.addLog('Warning: Primary output directory is unwritable ($e). Falling back to Result Cache.');
      if (fallback != null) return fallback;
      rethrow;
    }
  }
}
