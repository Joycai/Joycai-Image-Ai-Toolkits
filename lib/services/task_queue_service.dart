import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/llm_model.dart';
import '../models/task_item.dart';
import 'ai_rename_agent.dart';
import 'database_service.dart';
import 'llm/llm_service.dart';
import 'llm/llm_types.dart';
import 'web_scraper_service.dart';

// Re-export the task data model so existing importers of this file keep working.
export '../models/task_item.dart';

part 'task_executors.dart';

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

  /// Re-queues a failed or cancelled task for another attempt.
  Future<void> retryTask(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _queue[index];
    if (task.status != TaskStatus.failed && task.status != TaskStatus.cancelled) return;

    task.status = TaskStatus.pending;
    task.progress = null;
    task.startTime = null;
    task.endTime = null;
    task.addLog('Task re-queued by user.');
    await DatabaseService().saveTask(task.toMap());
    notifyListeners();
    _attemptNextExecution();
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

}
