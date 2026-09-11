import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../app_breathing_dot.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_snackbar.dart';

/// The full log of a single task, in a console the user can read, select and
/// copy from (`B2 · 1b` 任务日志对话框).
///
/// The task card only shows one line, which on a failure is rarely the cause —
/// that is usually several lines up. This shows the whole thing, for finished
/// tasks as well as failed ones.
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
  /// `B2 · 1b`: the log block tops out at 200 and scrolls.
  static const double _consoleMaxHeight = 200;

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
    final media = MediaQuery.sizeOf(context);

    return AppDialog(
      maxWidth: 520,
      maxHeight: media.height * 0.8,
      // A heading of its own: the Live badge rides the title and Copy logs
      // sits in the heading's corner, neither of which the shell's icon/title
      // layout has a slot for.
      titleWidget: _buildHeader(context, logs, colorScheme, l10n),
      content: logs.isEmpty ? _buildEmpty(colorScheme, l10n) : _buildConsole(logs, colorScheme),
      actions: [
        AppButton(
          label: l10n.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<String> logs,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final task = widget.task;
    final textTheme = Theme.of(context).textTheme;
    final meta = textTheme.labelSmall!.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.article_outlined, size: 24, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.taskLogTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge,
                      ),
                    ),
                    if (_isLive) ...[
                      const SizedBox(width: 8),
                      _LiveBadge(label: l10n.taskLogLive),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Three pieces rather than one string: the id gives way first,
                // and the line count is never the part that gets cut.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.taskId(task.id.length > 8 ? task.id.substring(0, 8) : task.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                    ),
                    Text(' · ', style: meta),
                    Text(l10n.taskLogLineCount(logs.length), maxLines: 1, style: meta),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (logs.isNotEmpty) ...[
          const SizedBox(width: 8),
          AppButton(
            label: l10n.copyLogs,
            icon: Icons.content_copy,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              AppSnackBar.success(context, l10n.taskLogCopied);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildConsole(List<String> logs, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: _consoleMaxHeight),
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: logs.length,
          itemBuilder: (_, i) => _buildLine(logs[i], colorScheme),
        ),
      ),
    );
  }

  /// Tints a line by what it says. The executors log plain strings with no
  /// level attached, so this matches the wording the task card's error
  /// summary keys off — enough to make a failure findable in a long log
  /// without restructuring every `addLog` call site.
  Widget _buildLine(String line, ColorScheme colorScheme) {
    final isError = line.contains('Error') || line.contains('Failed');
    final isWarning = line.contains('Warning');
    final color = isError
        ? colorScheme.onErrorContainer
        : isWarning
            ? context.semantic.onWarningContainer
            : colorScheme.onSurface;

    return Text(
      line,
      style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
            height: AppType.looseHeight,
            color: color,
            fontWeight: isError ? FontWeight.w600 : FontWeight.w400,
          ),
    );
  }

  /// `B2 · 1d` 任务日志空: the glyph, the sentence, and why — in the block the
  /// log would have filled, so the dialog keeps its shape.
  Widget _buildEmpty(ColorScheme colorScheme, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 28, color: colorScheme.outline),
          const SizedBox(height: AppSpace.s10),
          Text(
            l10n.noTaskLog,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            // A cancellation is the usual reason a current task has no log;
            // anything else without one predates logs being kept.
            widget.task.status == TaskStatus.cancelled
                ? l10n.noTaskLogCancelledHint
                : l10n.noTaskLogHint,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: AppType.looseHeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// The running badge beside the title: the accent's 12% form, the deep ink,
/// and the breathing dot.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBreathingDot(color: scheme.primary, size: 6),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onAccentTint),
          ),
        ],
      ),
    );
  }
}
