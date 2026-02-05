import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'database_service.dart';
import 'llm/llm_models.dart';
import 'llm/llm_service.dart';

enum TaskStatus { pending, processing, completed, failed, cancelled }

class TaskItem {
  final String id;
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

  TaskItem({
    required this.id,
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
  })  : logs = logs ?? [],
        resultPaths = resultPaths ?? [];

  void addLog(String message) {
    logs.add('[${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}] $message');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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

  Future<void> addTask(List<String> imagePaths, dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay}) async {
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
      imagePaths: imagePaths,
      modelId: modelIdStr,
      modelPk: modelPk,
      channelTag: channelTag,
      channelColor: channelColor,
      parameters: params,
    );
    task.addLog('Task created for ${imagePaths.length} images using $modelIdStr.');
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
    task.addLog('Start processing with model: ${task.modelPk ?? task.modelId}');
    onLogAdded?.call('Processing task ${task.id.substring(0,8)}...', level: 'RUNNING', taskId: task.id);
    DatabaseService().saveTask(task.toMap());
    notifyListeners();

    try {
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

      task.status = TaskStatus.completed;
      task.addLog('Task completed successfully.');
      onLogAdded?.call('Task ${task.id.substring(0,8)} finished.', level: 'SUCCESS', taskId: task.id);
      
    } catch (e) {
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.failed;
        task.addLog('Error: ${e.toString()}');
        onLogAdded?.call('Task ${task.id.substring(0,8)} failed: $e', level: 'ERROR', taskId: task.id);
      }
    } finally {
      task.endTime = DateTime.now();
      _runningCount--;
      DatabaseService().saveTask(task.toMap());
      notifyListeners();
      _attemptNextExecution();
    }
  }

  String _getMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.webp') return 'image/webp';
    return 'image/jpeg';
  }
}
