import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';

/// The full log of a single task, in a console the user can read, select and
/// copy from.
///
/// The task card only ever showed `logs.last`, which is the least useful line
/// of a failed task — the cause is usually several lines up. This shows the
/// whole thing, for finished tasks as well as failed ones.
///
/// Reads [TaskItem.logs] live off the task object rather than taking a copy, so
/// a running task's log tails as it is written.
class TaskLogDialog extends StatefulWidget {
  final TaskItem task;

  const TaskLogDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, TaskItem task) {
    return showDialog(
      context: context,
      builder: (_) => TaskLogDialog(task: task),
    );
  }

  @override
  State<TaskLogDialog> createState() => _TaskLogDialogState();
}

class _TaskLogDialogState extends State<TaskLogDialog> {
  final _scrollController = ScrollController();
  StreamSubscription<TaskEvent>? _events;
  Timer? _ticker;

  bool get _isLive =>
      widget.task.status == TaskStatus.processing || widget.task.status == TaskStatus.pending;

  @override
  void initState() {
    super.initState();
    if (_isLive) {
      final queue = Provider.of<AppState>(context, listen: false).taskQueue;
      _events = queue.subscribeToTask(widget.task.id).listen((_) => _refresh());
      // Not every `addLog` has a matching event — the executors log far more
      // than they emit — so the stream alone leaves the tail lagging. The poll
      // is the one that guarantees the view catches up; it only runs while the
      // dialog is open on an unfinished task.
      _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) => _refresh());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (!_isLive) {
      _ticker?.cancel();
      _events?.cancel();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _jumpToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _events?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final logs = widget.task.logs;
    final media = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: media.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(colorScheme, l10n),
              const SizedBox(height: 14),
              Flexible(
                child: logs.isEmpty
                    ? _buildEmpty(colorScheme, l10n)
                    : _buildConsole(logs, colorScheme),
              ),
              const SizedBox(height: 12),
              _buildActions(logs, colorScheme, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, AppLocalizations l10n) {
    final task = widget.task;
    return Row(
      children: [
        Icon(Icons.terminal, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.taskLogTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.taskId(task.id.length > 8 ? task.id.substring(0, 8) : task.id),
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (_isLive) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.taskLogLive,
            style: TextStyle(fontSize: 11, color: colorScheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _buildConsole(List<String> logs, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(isDark ? 90 : 60),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          itemCount: logs.length,
          itemBuilder: (_, i) => _buildLine(logs[i], colorScheme, isDark),
        ),
      ),
    );
  }

  /// Tints a line by what it says. The executors log plain strings with no
  /// level attached, so this matches the same wording `_errorSummary` on the
  /// task card keys off — enough to make a failure findable in a long log
  /// without restructuring every `addLog` call site.
  Widget _buildLine(String line, ColorScheme colorScheme, bool isDark) {
    final isError = line.contains('Error') || line.contains('Failed');
    final isWarning = line.contains('Warning');
    final color = isError
        ? colorScheme.error
        : isWarning
            ? (isDark ? const Color(0xFFFFD180) : const Color(0xFFB26A00))
            : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.45,
          color: color,
          fontWeight: isError ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notes_outlined, size: 26, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            l10n.noTaskLog,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.noTaskLogHint,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(170)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(List<String> logs, ColorScheme colorScheme, AppLocalizations l10n) {
    return Row(
      children: [
        Text(
          l10n.taskLogLineCount(logs.length),
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: logs.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: logs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.taskLogCopied)),
                  );
                },
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: Text(l10n.copyLogs),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
