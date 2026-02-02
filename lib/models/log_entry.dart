class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? taskId;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.taskId,
  });
}
