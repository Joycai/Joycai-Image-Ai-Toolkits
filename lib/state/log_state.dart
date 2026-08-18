import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';

/// The execution log, and the only thing that rebuilds when a line lands.
///
/// Split out of [AppState] rather than living on it. Every streaming chunk from
/// every model goes through here (`LLMService.onLogAdded` fires once per
/// `chunk.textPart`), and while it sat on the app-wide notifier each of those
/// chunks rebuilt the navigation rail, the gallery grid and both config panels
/// — a response streaming at a few dozen chunks a second rebuilt the entire
/// tree that many times. Nothing outside the console and the run bar reads a
/// log line, so nothing else should pay for one.
///
/// Deliberately *not* wired into [AppState] as a forwarded listener. The point
/// of the split is that log traffic stops at the console; re-broadcasting it
/// would put it straight back where it was.
class LogState extends ChangeNotifier {
  /// How many lines are kept. Older ones are dropped from the front.
  static const int _maxEntries = 1000;

  /// Longest a listener waits to hear about a line.
  ///
  /// Notifications are coalesced to roughly this interval, with the first line
  /// after a quiet stretch going out immediately — an isolated message (a task
  /// starting, an error) still appears at once, while a stream that produces
  /// fifty chunks a second costs eight rebuilds instead of fifty.
  static const Duration _coalesceWindow = Duration(milliseconds: 120);

  /// Mutated in place, against the project's usual "new list before notify"
  /// rule. That rule exists so `Selector`s can tell the value changed; the two
  /// widgets that read this are full listeners which rebuild either way, and
  /// copying a thousand entries per streamed chunk is the exact cost this class
  /// was written to remove.
  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => _logs;

  bool _hasErrors = false;

  /// Whether an error has been logged since the last successful task or clear.
  /// Drives the run console's status dot.
  bool get hasErrors => _hasErrors;

  Timer? _coalesceTimer;
  bool _pending = false;

  void add(String message, {String level = 'INFO', String? taskId}) {
    if (level == 'ERROR') _hasErrors = true;

    // Streamed assistant text arrives one fragment at a time; appending it to
    // the entry already on screen keeps a reply as one paragraph instead of a
    // hundred one-word lines.
    if (message.startsWith('[AI]: ') &&
        _logs.isNotEmpty &&
        _logs.last.message.startsWith('[AI]: ')) {
      final lastLog = _logs.last;
      if (lastLog.taskId == taskId) {
        _logs[_logs.length - 1] = LogEntry(
          timestamp: lastLog.timestamp,
          level: lastLog.level,
          message: lastLog.message + message.substring(6),
          taskId: taskId,
        );
        _scheduleNotify();
        return;
      }
    }

    _logs.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      taskId: taskId,
    ));

    if (_logs.length > _maxEntries) {
      _logs.removeRange(0, _logs.length - _maxEntries);
    }

    _scheduleNotify();
  }

  void clear() {
    _logs.clear();
    _hasErrors = false;
    _flushNow();
  }

  /// Drops the stale error indicator without touching the lines themselves —
  /// a task completing successfully means the red dot no longer describes the
  /// current state, but the errors that led here are still worth reading.
  void clearErrorFlag() {
    if (!_hasErrors) return;
    _hasErrors = false;
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_coalesceTimer != null) {
      _pending = true;
      return;
    }
    notifyListeners();
    _coalesceTimer = Timer(_coalesceWindow, () {
      _coalesceTimer = null;
      if (_pending) {
        _pending = false;
        _scheduleNotify();
      }
    });
  }

  void _flushNow() {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _coalesceTimer?.cancel();
    super.dispose();
  }
}
