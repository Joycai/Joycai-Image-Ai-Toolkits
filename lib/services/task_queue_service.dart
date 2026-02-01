import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'llm/llm_service.dart';
import 'llm/llm_models.dart';
import 'database_service.dart';
import 'package:path/path.dart' as p;

enum TaskStatus { pending, processing, completed, failed, cancelled }

class TaskItem {
  final String id;
  final List<String> imagePaths;
  final Map<String, dynamic> parameters;
  final String modelId;
  TaskStatus status;
  List<String> logs;
  List<String> resultPaths;
  DateTime? startTime;
  DateTime? endTime;

  TaskItem({
    required this.id,
    required this.imagePaths,
    required this.modelId,
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
}

class TaskQueueService extends ChangeNotifier {
  final List<TaskItem> _queue = [];
  int _concurrencyLimit = 2;
  int _runningCount = 0;
  final _uuid = const Uuid();
  
  Function(File)? onTaskCompleted;
  Function(String, {String level})? onLogAdded;

  List<TaskItem> get queue => _queue;
  int get concurrencyLimit => _concurrencyLimit;
  int get runningCount => _runningCount;

  void addTask(List<String> imagePaths, String modelId, Map<String, dynamic> params) {
    final task = TaskItem(
      id: _uuid.v4(),
      imagePaths: imagePaths,
      modelId: modelId,
      parameters: params,
    );
    task.addLog('Task created for ${imagePaths.length} images using $modelId.');
    _queue.add(task);
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
        notifyListeners();
      }
    }
  }

  void removeTask(String taskId) {
    _queue.removeWhere((t) => t.id == taskId && (t.status == TaskStatus.completed || t.status == TaskStatus.failed || t.status == TaskStatus.cancelled));
    notifyListeners();
  }

  void updateConcurrency(int newLimit) {
    _concurrencyLimit = newLimit;
    notifyListeners();
    _attemptNextExecution();
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
    task.addLog('Start processing with model: ${task.modelId}');
    onLogAdded?.call('Processing task ${task.id.substring(0,8)}...', level: 'RUNNING');
    notifyListeners();

    try {
      final db = DatabaseService();
      final outputDir = await db.getSetting('output_directory');
      if (outputDir == null || outputDir.isEmpty) {
        throw Exception('Output directory not set in settings!');
      }

      final models = await db.getModels();
      final modelInfo = models.firstWhere((m) => m['model_id'] == task.modelId, orElse: () => {});
      final inputPrice = modelInfo['input_fee'] ?? 0.0;
      final outputPrice = modelInfo['output_fee'] ?? 0.0;

      final attachments = task.imagePaths.map((path) => 
        LLMAttachment.fromFile(File(path), _getMimeType(path))
      ).toList();

      final stream = LLMService().requestStream(
        modelId: task.modelId,
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content: task.parameters['prompt'] ?? '',
            attachments: attachments,
          )
        ],
        options: task.parameters,
      );

      String accumulatedText = "";
      List<Uint8List> generatedImages = [];
      Map<String, dynamic>? finalMetadata;

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;

        if (chunk.textPart != null) {
          accumulatedText += chunk.textPart!;
          task.addLog('AI: ${chunk.textPart}');
          onLogAdded?.call('[${task.modelId}] ${chunk.textPart}', level: 'INFO');
          notifyListeners();
        }

        if (chunk.imagePart != null) {
          generatedImages.add(chunk.imagePart!);
          task.addLog('Received image chunk.');
          notifyListeners();
        }

        if (chunk.metadata != null) {
          finalMetadata = chunk.metadata;
        }
      }

      task.addLog('LLM Stream finished.');

      // Record Token Usage using metadata from stream
      if (finalMetadata != null) {
        final inputTokens = finalMetadata['promptTokenCount'] ?? finalMetadata['prompt_tokens'] ?? 0;
        final outputTokens = finalMetadata['candidatesTokenCount'] ?? finalMetadata['completion_tokens'] ?? 0;
        
        await db.recordTokenUsage({
          'task_id': task.id,
          'model_id': task.modelId,
          'timestamp': DateTime.now().toIso8601String(),
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          'input_price': inputPrice,
          'output_price': outputPrice,
        });
        task.addLog('Token usage recorded: In=$inputTokens, Out=$outputTokens');
      }

      if (task.status == TaskStatus.cancelled) return;

      for (int i = 0; i < generatedImages.length; i++) {
        final bytes = generatedImages[i];
        final fileName = 'result_${task.id.substring(0, 8)}_$i.png';
        final filePath = p.join(outputDir, fileName);
        
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        task.resultPaths.add(filePath);
        task.addLog('Saved result image to: $filePath');
        
        onTaskCompleted?.call(file);
      }

      task.status = TaskStatus.completed;
      task.addLog('Task completed successfully.');
      onLogAdded?.call('Task ${task.id.substring(0,8)} finished.', level: 'SUCCESS');
      
    } catch (e) {
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.failed;
        task.addLog('Error: ${e.toString()}');
        onLogAdded?.call('Task ${task.id.substring(0,8)} failed: $e', level: 'ERROR');
      }
    } finally {
      task.endTime = DateTime.now();
      _runningCount--;
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
