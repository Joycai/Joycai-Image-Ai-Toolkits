import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/llm_model.dart';
import 'database_service.dart';
import 'llm/llm_service.dart';
import 'llm/llm_types.dart';
import 'web_scraper_service.dart';

enum TaskStatus { pending, processing, completed, failed, cancelled }
enum TaskType { imageProcess, imageDownload, promptRefine, aiRename, videoGenerate }

enum TaskEventType { textChunk, imageResult, progress, statusChanged, error }

class TaskEvent {
  final String taskId;
  final TaskType? taskType;
  final TaskEventType type;
  final dynamic data;
  final DateTime timestamp;

  TaskEvent({
    required this.taskId,
    this.taskType,
    required this.type,
    this.data,
  }) : timestamp = DateTime.now();
}

class TaskItem {
  final String id;
  final TaskType type;
  final List<String> imagePaths;
  final Map<String, dynamic> parameters;
  final String modelId; // Legacy string ID
  final int? modelDbId;   // New internal ID
  final String? channelTag;
  final int? channelColor;
  final bool useStream;
  TaskStatus status;
  List<String> logs;
  List<String> resultPaths;
  DateTime? startTime;
  DateTime? endTime;
  double? progress; // 0.0 to 1.0 (transient)

  TaskItem({
    required this.id,
    this.type = TaskType.imageProcess,
    required this.imagePaths,
    required this.modelId,
    this.modelDbId,
    this.channelTag,
    this.channelColor,
    required this.parameters,
    this.useStream = true,
    this.status = TaskStatus.pending,
    List<String>? logs,
    List<String>? resultPaths,
    this.startTime,
    this.endTime,
    this.progress,
  })  : logs = logs ?? [],
        resultPaths = resultPaths ?? [];

  void addLog(String message) {
    logs.add('[${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}] $message');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'image_path': jsonEncode(imagePaths),
      'model_id': modelId,
      'model_pk': modelDbId,
      'channel_tag': channelTag,
      'channel_color': channelColor,
      'use_stream': useStream ? 1 : 0,
      'status': status.name,
      'parameters': jsonEncode(parameters),
      'result_path': jsonEncode(resultPaths),
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
    };
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    return TaskItem(
      id: map['id'],
      type: TaskType.values.firstWhere((e) => e.name == (map['type'] ?? 'imageProcess'), orElse: () => TaskType.imageProcess),
      imagePaths: List<String>.from(jsonDecode(map['image_path'])),
      modelId: map['model_id'] ?? 'unknown',
      modelDbId: map['model_pk'] as int?,
      channelTag: map['channel_tag'] as String?,
      channelColor: map['channel_color'] as int?,
      useStream: (map['use_stream'] ?? 1) == 1,
      status: TaskStatus.values.firstWhere((e) => e.name == map['status']),
      parameters: Map<String, dynamic>.from(jsonDecode(map['parameters'])),
      resultPaths: List<String>.from(jsonDecode(map['result_path'])),
      startTime: map['start_time'] != null ? DateTime.parse(map['start_time']) : null,
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
    );
  }
}

class TaskQueueService extends ChangeNotifier {
  final List<TaskItem> _queue = [];
  int _concurrencyLimit = 2;
  int _runningCount = 0;
  final _uuid = const Uuid();
  Timer? _progressTimer;
  List<LLMModel>? _cachedModelsForProgress;
  
  // Event stream for real-time subscriptions
  final _eventController = StreamController<TaskEvent>.broadcast();
  Stream<TaskEvent> get eventStream => _eventController.stream;

  /// Returns a stream of events filtered by a specific task ID
  Stream<TaskEvent> subscribeToTask(String taskId) {
    return eventStream.where((event) => event.taskId == taskId);
  }

  void _emit(String taskId, TaskEventType type, [dynamic data]) {
    final task = _queue.cast<TaskItem?>().firstWhere((t) => t?.id == taskId, orElse: () => null);
    _eventController.add(TaskEvent(taskId: taskId, taskType: task?.type, type: type, data: data));
  }
  
  Function(File)? onTaskCompleted;
  Function(TaskItem)? onTaskFinished;
  Function(String, {String level, String? taskId})? onLogAdded;

  List<TaskItem> get queue => _queue;
  int get concurrencyLimit => _concurrencyLimit;
  int get runningCount => _runningCount;

  TaskQueueService() {
    _loadRecentTasks();
  }

  Future<void> _loadRecentTasks() async {
    final db = DatabaseService();
    await db.cleanupStuckTasks();
    final tasks = await db.getRecentTasks(10);
    _queue.clear();
    _queue.addAll(tasks.map((t) => TaskItem.fromMap(t)).toList().reversed);
    notifyListeners();
  }

  Future<void> addTask(
    List<String> imagePaths, 
    dynamic modelIdentifier, 
    Map<String, dynamic> params, {
    String? modelIdDisplay, 
    TaskType type = TaskType.imageProcess,
    bool useStream = true,
    String? id,
  }) async {
    String modelIdStr = modelIdDisplay ?? modelIdentifier.toString();
    int? modelDbId;
    String? channelTag;
    int? channelColor;

    final db = DatabaseService();

    if (modelIdentifier is int) {
      modelDbId = modelIdentifier;
      // Fetch model and channel info for visual continuity in history
      final models = await db.getModels();
      final model = models.cast<LLMModel?>().firstWhere((m) => m?.id == modelDbId, orElse: () => null);
      if (model != null) {
        final channelId = model.channelId;
        if (channelId != null) {
          final channel = await db.getChannel(channelId);
          if (channel != null) {
            channelTag = channel.tag;
            channelColor = channel.tagColor;
          }
        }
      }
    }

    final task = TaskItem(
      id: id ?? _uuid.v4(),
      type: type,
      imagePaths: imagePaths,
      modelId: modelIdStr,
      modelDbId: modelDbId,
      channelTag: channelTag,
      channelColor: channelColor,
      parameters: params,
      useStream: useStream,
    );
    if (type == TaskType.imageProcess) {
      task.addLog('Task created for ${imagePaths.length} images using $modelIdStr.');
    } else if (type == TaskType.imageDownload) {
      task.addLog('Download task created for ${imagePaths.length} URLs.');
    } else if (type == TaskType.promptRefine) {
      task.addLog('Prompt refinement task created using $modelIdStr.');
    } else if (type == TaskType.aiRename) {
      task.addLog('AI Batch Rename task created for ${imagePaths.length} files using $modelIdStr.');
    } else if (type == TaskType.videoGenerate) {
      task.addLog('Video generation task created using $modelIdStr.');
    }
    
    _queue.add(task);
    
    // Persist task immediately
    await db.saveTask(task.toMap());
    
    notifyListeners();
    _attemptNextExecution();
  }

  Future<void> cancelTask(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _queue[index];
      if (task.status == TaskStatus.pending) {
        task.status = TaskStatus.cancelled;
        task.addLog('Task cancelled by user.');
        await DatabaseService().saveTask(task.toMap());
        notifyListeners();
      }
    }
  }

  Future<void> removeTask(String taskId) async {
    _queue.removeWhere((t) => t.id == taskId && (t.status == TaskStatus.completed || t.status == TaskStatus.failed || t.status == TaskStatus.cancelled));
    await DatabaseService().deleteTask(taskId);
    notifyListeners();
  }

  void updateConcurrency(int newLimit) {
    _concurrencyLimit = newLimit;
    notifyListeners();
    _attemptNextExecution();
  }

  void refreshQueue() {
    notifyListeners();
  }

  void _attemptNextExecution() {
    if (_runningCount >= _concurrencyLimit) return;

    try {
      final nextTask = _queue.firstWhere(
        (task) => task.status == TaskStatus.pending,
      );

      _runningCount++;
      _startProgressTimer();
      _executeTask(nextTask);
      _attemptNextExecution();
    } catch (e) {
      // No pending tasks
    }
  }

  Future<void> _executeTask(TaskItem task) async {
    if (task.status == TaskStatus.cancelled) {
      _runningCount--;
      _attemptNextExecution();
      return;
    }

    task.status = TaskStatus.processing;
    task.startTime = DateTime.now();
    _emit(task.id, TaskEventType.statusChanged, task.status);
    onLogAdded?.call('Processing task ${task.id.substring(0,8)}...', level: 'RUNNING', taskId: task.id);
    DatabaseService().saveTask(task.toMap());
    notifyListeners();

    try {
      if (task.type == TaskType.imageProcess) {
        await _executeImageProcessTask(task);
      } else if (task.type == TaskType.imageDownload) {
        await _executeDownloadTask(task);
      } else if (task.type == TaskType.promptRefine) {
        await _executePromptRefineTask(task);
      } else if (task.type == TaskType.aiRename) {
        await _executeAiRenameTask(task);
      } else if (task.type == TaskType.videoGenerate) {
        await _executeVideoGenerateTask(task);
      }
      
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.completed;
        _emit(task.id, TaskEventType.statusChanged, task.status);
        task.addLog('Task completed successfully.');
        onLogAdded?.call('Task ${task.id.substring(0,8)} finished.', level: 'SUCCESS', taskId: task.id);
      }
    } catch (e) {
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.failed;
        _emit(task.id, TaskEventType.statusChanged, task.status);
        _emit(task.id, TaskEventType.error, e.toString());
        task.addLog('Error: ${e.toString()}');
        onLogAdded?.call('Task ${task.id.substring(0,8)} failed: $e', level: 'ERROR', taskId: task.id);
      }
    } finally {
      task.endTime = DateTime.now();
      
      // Update Estimation Checkpoint
      if (task.status == TaskStatus.completed && task.modelDbId != null) {
        _handleEstimationCheckpoint(task.modelDbId!);
      }

      _runningCount--;
      DatabaseService().saveTask(task.toMap());
      onTaskFinished?.call(task);
      notifyListeners();
      _attemptNextExecution();
    }
  }

  Future<void> _handleEstimationCheckpoint(int modelDbId) async {
    final db = DatabaseService();
    final models = await db.getModels();
    final model = models.cast<LLMModel?>().firstWhere((m) => m?.id == modelDbId, orElse: () => null);
    
    if (model != null) {
      int count = model.tasksSinceUpdate + 1;
      final mean = model.estMeanMs ?? 0.0;
      
      if (count >= 10 || mean == 0) {
        await _updateModelCheckpoint(modelDbId);
      } else {
        await db.updateModelEstimation(modelDbId, mean, model.estSdMs ?? 0.0, count);
      }
    }
  }

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
          notifyListeners();
        }

        if (chunk.imagePart != null) {
          generatedImages.add(chunk.imagePart!);
          task.addLog('Received image chunk.');
          notifyListeners();
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
          notifyListeners();
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
      if (task.modelDbId != null) {
        final models = await db.getModels();
        final model = models.cast<LLMModel?>().firstWhere((m) => m?.id == task.modelDbId, orElse: () => null);
        if (model != null && model.channelId != null) {
          final channel = await db.getChannel(model.channelId!);
          if (channel != null) {
            apiKey = channel.apiKey;
          }
        }
      }

      final request = await client.getUrl(Uri.parse(url));
      if (apiKey != null) {
        request.headers.add('x-goog-api-key', apiKey);
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
      notifyListeners();

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
        notifyListeners();
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

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _cachedModelsForProgress = null;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _updateProgress());
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _cachedModelsForProgress = null;
  }

  Future<void> _updateProgress() async {
    bool hasActive = false;
    final db = DatabaseService();
    _cachedModelsForProgress ??= await db.getModels();
    final models = _cachedModelsForProgress!;

    for (var task in _queue) {
      if (task.status == TaskStatus.processing && task.startTime != null) {
        hasActive = true;
        // Find checkpoint for this model
        final model = models.cast<LLMModel?>().firstWhere(
          (m) => m?.id == task.modelDbId, 
          orElse: () => null
        );

        if (model != null) {
          final mean = model.estMeanMs ?? 0.0;
          final sd = model.estSdMs ?? 0.0;
          
          if (mean > 0) {
            final targetMs = mean + (2 * sd);
            final elapsed = DateTime.now().difference(task.startTime!).inMilliseconds;
            task.progress = math.min(elapsed / targetMs, 0.99);
          }
        }
      }
    }

    if (hasActive) {
      notifyListeners();
    } else {
      _stopProgressTimer();
    }
  }

  Future<void> _updateModelCheckpoint(int modelDbId) async {
    final db = DatabaseService();
    final durations = await db.getTaskDurations(modelDbId, 50);
    
    if (durations.length >= 3) {
      // Calculate Mean
      final mean = durations.reduce((a, b) => a + b) / durations.length;
      // Calculate Standard Deviation
      final variance = durations.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) / durations.length;
      final sd = math.sqrt(variance);
      
      await db.updateModelEstimation(modelDbId, mean, sd, 0);
    }
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
