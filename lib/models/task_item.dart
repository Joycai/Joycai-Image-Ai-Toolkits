import 'dart:convert';

/// Data model and enums for the task queue.
///
/// Extracted from `task_queue_service.dart` so the queue/executor logic stays
/// separate from the serializable data it operates on. The service re-exports
/// these symbols, so existing imports of `task_queue_service.dart` keep working.

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

  /// Marks where [addLog] dropped the head of an over-long log.
  static const String logTruncationMarker = '[…] earlier lines dropped (log capped at $maxLogLines lines)';

  /// Ceiling on retained log lines. Streaming executors call [addLog] once per
  /// response chunk, so an uncapped log grows with the response and — now that
  /// logs are persisted — gets rewritten to SQLite on every status change.
  static const int maxLogLines = 500;

  void addLog(String message) {
    logs.add('[${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}] $message');
    if (logs.length <= maxLogLines) return;
    // Oldest lines go first, but the marker is kept pinned at the head and
    // trimmed around, so a truncated log never reads as a complete one.
    if (logs.first != logTruncationMarker) logs.insert(0, logTruncationMarker);
    logs.removeRange(1, logs.length - maxLogLines + 1);
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
      'logs': jsonEncode(logs),
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
    };
  }

  /// Tasks written before schema v31 have no `logs` value, and a hand-edited or
  /// half-written one shouldn't sink the whole queue reload — either way the
  /// task is still worth showing, just without its log.
  static List<String> _decodeLogs(Object? raw) {
    if (raw is! String || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
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
      logs: _decodeLogs(map['logs']),
      startTime: map['start_time'] != null ? DateTime.parse(map['start_time']) : null,
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
    );
  }
}
