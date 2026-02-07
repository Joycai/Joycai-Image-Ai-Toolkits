import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'database_service.dart';
import 'llm/llm_models.dart';
import 'llm/llm_service.dart';
import 'web_scraper_service.dart';

enum TaskStatus { pending, processing, completed, failed, cancelled }
enum TaskType { imageProcess, imageDownload }

class TaskItem {
  final String id;
  final TaskType type;
  final List<String> imagePaths;
  final Map<String, dynamic> parameters;
  final String modelId; // Legacy string ID
  final int? modelPk;   // New internal ID
  final String? channelTag;
  final int? channelColor;
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
    this.modelPk,
    this.channelTag,
    this.channelColor,
    required this.parameters,
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
      'model_pk': modelPk,
      'channel_tag': channelTag,
      'channel_color': channelColor,
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
      modelPk: map['model_pk'] as int?,
      channelTag: map['channel_tag'] as String?,
      channelColor: map['channel_color'] as int?,
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
  
  Function(File)? onTaskCompleted;
  Function(String, {String level, String? taskId})? onLogAdded;

  List<TaskItem> get queue => _queue;
  int get concurrencyLimit => _concurrencyLimit;
  int get runningCount => _runningCount;

  TaskQueueService() {
    _loadRecentTasks();
  }

  Future<void> _loadRecentTasks() async {
    final db = DatabaseService();
    final tasks = await db.getRecentTasks(10);
    _queue.clear();
    _queue.addAll(tasks.map((t) => TaskItem.fromMap(t)).toList().reversed);
    notifyListeners();
  }

  Future<void> addTask(List<String> imagePaths, dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay, TaskType type = TaskType.imageProcess}) async {
    String modelIdStr = modelIdDisplay ?? modelIdentifier.toString();
    int? modelPk;
    String? channelTag;
    int? channelColor;

    final db = DatabaseService();

    if (modelIdentifier is int) {
      modelPk = modelIdentifier;
      // Fetch model and channel info for visual continuity in history
      final models = await db.getModels();
      final model = models.firstWhere((m) => m['id'] == modelPk, orElse: () => {});
      if (model.isNotEmpty) {
        final channelId = model['channel_id'] as int?;
        if (channelId != null) {
          final channel = await db.getChannel(channelId);
          if (channel != null) {
            channelTag = channel['tag'];
            channelColor = channel['tag_color'];
          }
        }
      }
    }

    final task = TaskItem(
      id: _uuid.v4(),
      type: type,
      imagePaths: imagePaths,
      modelId: modelIdStr,
      modelPk: modelPk,
      channelTag: channelTag,
      channelColor: channelColor,
      parameters: params,
    );
    if (type == TaskType.imageProcess) {
      task.addLog('Task created for ${imagePaths.length} images using $modelIdStr.');
    } else {
      task.addLog('Download task created for ${imagePaths.length} URLs.');
    }
    _queue.add(task);
    
    // Persist task immediately
    await db.saveTask(task.toMap());
    
    notifyListeners();
    _attemptNextExecution();
  }

  void cancelTask(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _queue[index];
      if (task.status == TaskStatus.pending) {
        task.status = TaskStatus.cancelled;
        task.addLog('Task cancelled by user.');
        DatabaseService().saveTask(task.toMap());
        notifyListeners();
      }
    }
  }

  void removeTask(String taskId) {
    _queue.removeWhere((t) => t.id == taskId && (t.status == TaskStatus.completed || t.status == TaskStatus.failed || t.status == TaskStatus.cancelled));
    DatabaseService().deleteTask(taskId);
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
    onLogAdded?.call('Processing task ${task.id.substring(0,8)}...', level: 'RUNNING', taskId: task.id);
    DatabaseService().saveTask(task.toMap());
    notifyListeners();

    try {
      if (task.type == TaskType.imageProcess) {
        await _executeImageProcessTask(task);
      } else if (task.type == TaskType.imageDownload) {
        await _executeDownloadTask(task);
      }
      
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.completed;
        task.addLog('Task completed successfully.');
        onLogAdded?.call('Task ${task.id.substring(0,8)} finished.', level: 'SUCCESS', taskId: task.id);
      }
    } catch (e) {
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.failed;
        task.addLog('Error: ${e.toString()}');
        onLogAdded?.call('Task ${task.id.substring(0,8)} failed: $e', level: 'ERROR', taskId: task.id);
      }
    } finally {
      task.endTime = DateTime.now();
      
      // Update Estimation Checkpoint
      if (task.status == TaskStatus.completed && task.modelPk != null) {
        _handleEstimationCheckpoint(task.modelPk!);
      }

      _runningCount--;
      DatabaseService().saveTask(task.toMap());
      notifyListeners();
      _attemptNextExecution();
    }
  }

  Future<void> _handleEstimationCheckpoint(int modelPk) async {
    final db = DatabaseService();
    final models = await db.getModels();
    final model = models.cast<Map<String, dynamic>?>().firstWhere((m) => m?['id'] == modelPk, orElse: () => null);
    
    if (model != null) {
      int count = (model['tasks_since_update'] as int? ?? 0) + 1;
      final mean = model['est_mean_ms'] as double? ?? 0.0;
      
      if (count >= 10 || mean == 0) {
        await _updateModelCheckpoint(modelPk);
      } else {
        await db.updateModelEstimation(modelPk, mean, model['est_sd_ms'] as double? ?? 0.0, count);
      }
    }
  }

  Future<void> _executeImageProcessTask(TaskItem task) async {
    task.addLog('Start processing with model: ${task.modelPk ?? task.modelId}');
    
    final db = DatabaseService();
    final outputDir = await db.getSetting('output_directory');
    if (outputDir == null || outputDir.isEmpty) {
      throw Exception('Output directory not set in settings!');
    }

    final attachments = task.imagePaths.map((path) => 
      LLMAttachment.fromFile(File(path), _getMimeType(path))
    ).toList();

    final stream = LLMService().requestStream(
      modelIdentifier: task.modelPk ?? task.modelId,
      messages: [
        LLMMessage(
          role: LLMRole.user,
          content: task.parameters['prompt'] ?? '',
          attachments: attachments,
        )
      ],
      contextId: task.id,
      options: task.parameters,
    );

    List<Uint8List> generatedImages = [];

    await for (final chunk in stream) {
      if (task.status == TaskStatus.cancelled) break;

      if (chunk.textPart != null) {
        task.addLog('AI: ${chunk.textPart}');
        notifyListeners();
      }

      if (chunk.imagePart != null) {
        generatedImages.add(chunk.imagePart!);
        task.addLog('Received image chunk.');
        notifyListeners();
      }
    }

    task.addLog('LLM Stream finished.');

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
      task.addLog('Saved result image to: $filePath');
      
      onTaskCompleted?.call(file);
    }
  }

  Future<void> _executeDownloadTask(TaskItem task) async {
    task.addLog('Start downloading ${task.imagePaths.length} images.');
    
    final db = DatabaseService();
    final outputDir = await db.getSetting('output_directory');
    if (outputDir == null || outputDir.isEmpty) {
      throw Exception('Output directory not set in settings!');
    }

    final cookies = task.parameters['cookies'] as String?;
    final formattedCookies = WebScraperService().parseCookies(cookies ?? '');
    final prefix = task.parameters['prefix'] ?? 'download';
    
    final client = HttpClient();
    // Configure client if needed (e.g. proxy)

    for (int i = 0; i < task.imagePaths.length; i++) {
      if (task.status == TaskStatus.cancelled) break;
      
      final url = task.imagePaths[i];
      task.addLog('Downloading: $url');
      notifyListeners();

      try {
        final request = await client.getUrl(Uri.parse(url));
        if (formattedCookies.isNotEmpty) {
          request.headers.add(HttpHeaders.cookieHeader, formattedCookies);
        }
        
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('Failed to download image: ${response.statusCode}');
        }

        final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
        
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = _getExtensionFromUrl(url);
        final fileName = '${prefix}_${timestamp}_$i$extension';
        final filePath = p.join(outputDir, fileName);
        
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        task.resultPaths.add(filePath);
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
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _updateProgress());
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _updateProgress() async {
    bool hasActive = false;
    final db = DatabaseService();
    final models = await db.getModels();

    for (var task in _queue) {
      if (task.status == TaskStatus.processing && task.startTime != null) {
        hasActive = true;
        // Find checkpoint for this model
        final model = models.cast<Map<String, dynamic>?>().firstWhere(
          (m) => m?['id'] == task.modelPk, 
          orElse: () => null
        );

        if (model != null) {
          final mean = model['est_mean_ms'] as double? ?? 0.0;
          final sd = model['est_sd_ms'] as double? ?? 0.0;
          
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

  Future<void> _updateModelCheckpoint(int modelPk) async {
    final db = DatabaseService();
    final durations = await db.getTaskDurations(modelPk, 50);
    
    if (durations.length >= 3) {
      // Calculate Mean
      final mean = durations.reduce((a, b) => a + b) / durations.length;
      // Calculate Standard Deviation
      final variance = durations.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) / durations.length;
      final sd = math.sqrt(variance);
      
      await db.updateModelEstimation(modelPk, mean, sd, 0);
    }
  }
}