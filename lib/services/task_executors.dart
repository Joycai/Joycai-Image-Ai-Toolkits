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

  Future<void> _executePromptRefineTask(TaskItem task) async {
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

  Future<void> _executeAiRenameTask(TaskItem task) async {
    task.addLog('Start AI Batch Rename for ${task.imagePaths.length} files.');

    final instructions = task.parameters['instructions'] ?? '';
    final filesData = task.parameters['filesData'] as List<dynamic>;

    String prompt;
    if (instructions.contains('# Role') || instructions.contains('# Task')) {
      prompt = "$instructions\n\nFiles to rename (Context):\n${jsonEncode(filesData)}";
    } else {
      prompt = """
You are a professional file renaming assistant.
Instructions: $instructions

Files to rename:
${jsonEncode(filesData)}

Output ONLY a valid JSON array of objects, where each object has 'path' and 'new_name' keys.
Example: [{"path": "...", "new_name": "..."}]
Do not include any other text or markdown formatting.
""";
    }

    String jsonText = "";
    final actualUseStream = await _shouldUseStream(task);

    if (actualUseStream) {
      final stream = LLMService().requestStream(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: [LLMMessage(role: LLMRole.user, content: prompt)],
        contextId: task.id,
      );

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;
        if (chunk.textPart != null) {
          jsonText += chunk.textPart!;
        }
      }
    } else {
      final response = await LLMService().request(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: [LLMMessage(role: LLMRole.user, content: prompt)],
        options: task.parameters,
        useStream: false,
      );
      jsonText = response.text;
    }

    if (task.status == TaskStatus.cancelled) return;

    _emit(task.id, TaskEventType.textChunk, jsonText);

    // Parse and apply renames
    jsonText = jsonText.trim();
    if (jsonText.startsWith('```json')) {
      jsonText = jsonText.substring(7, jsonText.length - 3).trim();
    } else if (jsonText.startsWith('```')) {
      jsonText = jsonText.substring(3, jsonText.length - 3).trim();
    }

    final List<dynamic> suggestions = jsonDecode(jsonText);

    bool isSafeFileName(String name) {
      return !name.contains('..') && !name.contains('/') && !name.contains('\\') && !name.contains('\x00') && name.trim().isNotEmpty;
    }

    for (var s in suggestions) {
      final oldPath = s['path'] as String;
      final newName = s['new_name'] as String;

      if (!isSafeFileName(newName)) {
        task.addLog('Skipped unsafe rename suggestion: "$newName"');
        continue;
      }

      final oldFile = File(oldPath);
      final newPath = p.join(p.dirname(oldPath), newName);

      if (await oldFile.exists()) {
        await oldFile.rename(newPath);
        task.addLog('Renamed: ${p.basename(oldPath)} -> $newName');
      }
    }

    task.addLog('AI Rename complete.');
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
