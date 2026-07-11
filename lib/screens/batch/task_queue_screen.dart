import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/panel_resizer.dart';

/// Which subset of tasks the list shows.
enum _TaskFilter { all, running, pending, done, failed }

class TaskQueueScreen extends StatefulWidget {
  const TaskQueueScreen({super.key});

  @override
  State<TaskQueueScreen> createState() => _TaskQueueScreenState();
}

class _TaskQueueScreenState extends State<TaskQueueScreen> {
  _TaskFilter _filter = _TaskFilter.all;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);

    if (isNarrow) {
      return _buildMobileLayout(context, appState, l10n);
    }

    final content = _buildDesktopContent(context, appState, l10n);

    // Embedded presentation (workbench bottom-sheet console): render
    // full-bleed on the sheet's own surface — no canvas padding, no card.
    final inBottomSheet = context.findAncestorWidgetOfExactType<BottomSheet>() != null;
    if (inBottomSheet) {
      return content;
    }

    // Standalone desktop: a rounded panel card floating on the inset canvas.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: PanelCard(child: content),
      ),
    );
  }

  // ── Shared: filtering + status-priority sorting ─────────────────────────────

  List<TaskItem> _visibleTasks(List<TaskItem> queue) {
    // Newest first within each group.
    final reversed = queue.reversed.toList();

    final filtered = switch (_filter) {
      _TaskFilter.all => reversed,
      _TaskFilter.running => reversed.where((t) => t.status == TaskStatus.processing).toList(),
      _TaskFilter.pending => reversed.where((t) => t.status == TaskStatus.pending).toList(),
      _TaskFilter.done => reversed.where((t) => t.status == TaskStatus.completed).toList(),
      _TaskFilter.failed => reversed
          .where((t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
          .toList(),
    };

    int priority(TaskItem t) => switch (t.status) {
          TaskStatus.processing => 0,
          TaskStatus.pending => 1,
          _ => 2,
        };

    // Stable sort: running pinned on top, then queued, then history.
    final sorted = List<TaskItem>.from(filtered);
    sorted.sort((a, b) => priority(a).compareTo(priority(b)));
    return sorted;
  }

  // ── Mobile layout ───────────────────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context, AppState appState, AppLocalizations l10n) {
    final queue = appState.taskQueue.queue;
    final tasks = _visibleTasks(queue);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taskQueueManager),
        actions: [
          IconButton(
            onPressed: () => appState.taskQueue.refreshQueue(),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) => _handleBulkAction(val, appState.taskQueue),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'clear_completed', child: Text(l10n.clearCompleted)),
              PopupMenuItem(value: 'cancel_pending', child: Text(l10n.cancelAllPending)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'clear_all', enabled: queue.isNotEmpty, child: Text(l10n.clearAll)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildFilterChips(context, queue, l10n, colorScheme),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState(colorScheme, l10n)
                : _buildGroupedList(context, tasks, colorScheme,
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 12), isMobile: true),
          ),
        ],
      ),
    );
  }

  // ── Desktop content (hosted in a PanelCard standalone, full-bleed in sheet) ─

  Widget _buildDesktopContent(BuildContext context, AppState appState, AppLocalizations l10n) {
    final queue = appState.taskQueue.queue;
    final tasks = _visibleTasks(queue);
    final colorScheme = Theme.of(context).colorScheme;
    final queued = queue.where((t) => t.status == TaskStatus.pending).length;
    final finished = queue
        .where((t) =>
            t.status == TaskStatus.completed ||
            t.status == TaskStatus.failed ||
            t.status == TaskStatus.cancelled)
        .length;

    return Column(
      children: [
        // Header lives inside the top of the card (its bottom border becomes
        // an internal divider on the inset-panel canvas).
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist, size: 22, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                l10n.taskQueueManager,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                tooltip: l10n.concurrencyLimit(appState.taskQueue.concurrencyLimit),
                onPressed: () => _showConcurrencyDialog(context, l10n, appState),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: queued == 0
                    ? null
                    : () => _handleBulkAction('cancel_pending', appState.taskQueue),
                icon: const Icon(Icons.pause, size: 18),
                label: Text(l10n.cancelAllPending),
                style: _headerButtonStyle(colorScheme, colorScheme.onSurfaceVariant, colorScheme.outlineVariant),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: finished == 0
                    ? null
                    : () => _handleBulkAction('clear_completed', appState.taskQueue),
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(l10n.clearCompleted),
                style: _headerButtonStyle(
                  colorScheme,
                  finished > 0 ? colorScheme.error : colorScheme.onSurfaceVariant,
                  finished > 0 ? colorScheme.error.withAlpha(160) : colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
        ),

        // ── Filter chips toolbar ────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(70))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildFilterChips(context, queue, l10n, colorScheme),
          ),
        ),

        // ── Task list (full-bleed rows inside the card) ─────────────────────
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyState(colorScheme, l10n)
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, thickness: 0.5, color: colorScheme.outlineVariant.withAlpha(70)),
                  itemBuilder: (context, index) =>
                      _TaskRow(task: tasks[index], isMobile: false),
                ),
        ),
      ],
    );
  }

  ButtonStyle _headerButtonStyle(ColorScheme colorScheme, Color fg, Color side) {
    return OutlinedButton.styleFrom(
      side: BorderSide(color: side),
      foregroundColor: fg,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
      minimumSize: const Size(0, 38),
    );
  }

  // ── Filter chips ────────────────────────────────────────────────────────────

  Widget _buildFilterChips(
    BuildContext context,
    List<TaskItem> queue,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final running = queue.where((t) => t.status == TaskStatus.processing).length;
    final pending = queue.where((t) => t.status == TaskStatus.pending).length;
    final done = queue.where((t) => t.status == TaskStatus.completed).length;
    final failed = queue
        .where((t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
        .length;

    final entries = [
      (_TaskFilter.all, l10n.filterAll, queue.length),
      (_TaskFilter.running, l10n.processingTasks, running),
      (_TaskFilter.pending, l10n.pendingTasks, pending),
      (_TaskFilter.done, l10n.completedTasks, done),
      (_TaskFilter.failed, l10n.failedTasks, failed),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (filter, label, count) in entries) ...[
          _FilterPill(
            label: '$label $count',
            selected: _filter == filter,
            onTap: () => setState(() => _filter = filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  // ── Grouped list container (bordered rows, not cards) ───────────────────────

  Widget _buildGroupedList(
    BuildContext context,
    List<TaskItem> tasks,
    ColorScheme colorScheme, {
    required EdgeInsets margin,
    required bool isMobile,
  }) {
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(90)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: tasks.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, thickness: 0.5, color: colorScheme.outlineVariant.withAlpha(70)),
        itemBuilder: (context, index) => _TaskRow(task: tasks[index], isMobile: isMobile),
      ),
    );
  }

  void _showConcurrencyDialog(BuildContext context, AppLocalizations l10n, AppState appState) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final queue = Provider.of<AppState>(dialogContext).taskQueue;
          return AlertDialog(
            title: Text(l10n.concurrencyLimit(queue.concurrencyLimit)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: queue.concurrencyLimit.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) {
                    queue.updateConcurrency(v.round());
                    setDialogState(() {});
                  },
                ),
                Text(queue.concurrencyLimit.toString()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.close),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleBulkAction(String action, TaskQueueService queue) {
    if (action == 'clear_completed') {
      final toRemove = queue.queue
          .where((t) => t.status == TaskStatus.completed || t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
          .map((t) => t.id)
          .toList();
      for (final id in toRemove) { queue.removeTask(id); }
    } else if (action == 'cancel_pending') {
      final toCancel = queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (final id in toCancel) { queue.cancelTask(id); }
    } else if (action == 'clear_all') {
      final toRemove = queue.queue.where((t) => t.status != TaskStatus.processing).map((t) => t.id).toList();
      for (final id in toRemove) { queue.removeTask(id); }
    }
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(l10n.noTasksInQueue, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.submitTaskFromWorkbench, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Filter pill
// ════════════════════════════════════════════════════════════════════════════

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Task row — shape follows status
// ════════════════════════════════════════════════════════════════════════════

class _TaskRow extends StatefulWidget {
  final TaskItem task;
  final bool isMobile;
  const _TaskRow({required this.task, required this.isMobile});

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;

    final isProcessing = task.status == TaskStatus.processing;
    final isFailed = task.status == TaskStatus.failed;

    return Material(
      color: isFailed
          ? colorScheme.error.withAlpha(14)
          : (isProcessing ? colorScheme.primary.withAlpha(10) : Colors.transparent),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.isMobile ? 12 : 16,
            vertical: isProcessing ? 12 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildLeadingTile(task, colorScheme),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTitleAndMeta(task, colorScheme, l10n)),
                  const SizedBox(width: 10),
                  ..._buildTrailing(context, task, appState, colorScheme, l10n),
                ],
              ),
              if (isProcessing) _buildProgressBar(task, colorScheme),
              if (_isExpanded) _buildExpandedDetails(context, task, colorScheme, l10n),
            ],
          ),
        ),
      ),
    );
  }

  // ── Leading 34px tile: icon + tint follow status ────────────────────────────

  Widget _buildLeadingTile(TaskItem task, ColorScheme colorScheme) {
    final (icon, fg, bg) = switch (task.status) {
      TaskStatus.processing => (
          _typeIcon(task.type),
          colorScheme.primary,
          colorScheme.primary.withAlpha(30),
        ),
      TaskStatus.pending => (
          _typeIcon(task.type),
          colorScheme.onSurfaceVariant,
          colorScheme.surfaceContainerHighest,
        ),
      TaskStatus.completed => (
          Icons.check,
          Colors.green,
          Colors.green.withAlpha(28),
        ),
      TaskStatus.failed => (
          Icons.warning_amber_rounded,
          colorScheme.error,
          colorScheme.error.withAlpha(24),
        ),
      TaskStatus.cancelled => (
          Icons.block,
          colorScheme.onSurfaceVariant,
          colorScheme.surfaceContainerHighest,
        ),
    };

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }

  // ── Title + single muted meta line ──────────────────────────────────────────

  Widget _buildTitleAndMeta(TaskItem task, ColorScheme colorScheme, AppLocalizations l10n) {
    final isFailed = task.status == TaskStatus.failed;
    final channelColor = Color(task.channelColor ?? 0xFF607D8B);

    final metaParts = <InlineSpan>[];
    void addPart(String text, {Color? color}) {
      if (text.isEmpty) return;
      if (metaParts.isNotEmpty) {
        metaParts.add(TextSpan(text: '  ·  ', style: TextStyle(color: colorScheme.outline)));
      }
      metaParts.add(TextSpan(text: text, style: color != null ? TextStyle(color: color) : null));
    }

    if (isFailed) {
      // The error summary replaces the meta line — failure info up front.
      addPart(_errorSummary(task), color: colorScheme.error);
    } else {
      addPart(_shortModelId(task.modelId));
      if (task.channelTag != null) addPart(task.channelTag!, color: channelColor);
      if (task.imagePaths.length > 1) addPart(l10n.filesCount(task.imagePaths.length));
      switch (task.status) {
        case TaskStatus.pending:
          final position = _queuePosition(task);
          if (position > 0) addPart(l10n.queuedPosition(position));
        case TaskStatus.completed:
          final duration = _elapsed(task);
          if (duration != null) addPart(l10n.tookDuration(duration));
        case TaskStatus.cancelled:
          addPart(l10n.statusCancelled);
        default:
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _taskDisplayName(task),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: task.status == TaskStatus.cancelled
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
            children: metaParts,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Trailing column: thumbnails → status/action → time → menu ──────────────

  List<Widget> _buildTrailing(
    BuildContext context,
    TaskItem task,
    AppState appState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final widgets = <Widget>[];

    if (task.status == TaskStatus.completed && task.resultPaths.isNotEmpty && !widget.isMobile) {
      widgets.add(_buildThumbnailStrip(task, colorScheme));
      widgets.add(const SizedBox(width: 10));
    }

    switch (task.status) {
      case TaskStatus.processing:
        widgets.add(Text(
          _progressLabel(task),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ));
      case TaskStatus.pending:
        widgets.add(_statusPill(l10n.pendingTasks, colorScheme.onSurfaceVariant, colorScheme));
      case TaskStatus.failed:
        widgets.add(OutlinedButton(
          onPressed: () => appState.taskQueue.retryTask(task.id),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.error.withAlpha(140)),
            foregroundColor: colorScheme.error,
            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 28),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(l10n.retryTask),
        ));
      case TaskStatus.completed:
      case TaskStatus.cancelled:
        break;
    }

    if (!widget.isMobile) {
      widgets.add(const SizedBox(width: 10));
      widgets.add(SizedBox(
        width: 42,
        child: Text(
          _formatClock(task.endTime ?? task.startTime),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ));
    }

    widgets.add(const SizedBox(width: 4));
    widgets.add(_buildMoreButton(context, task, appState, l10n, colorScheme));
    return widgets;
  }

  Widget _buildThumbnailStrip(TaskItem task, ColorScheme colorScheme) {
    const maxThumbs = 3;
    final paths = task.resultPaths.take(maxThumbs).toList();
    final overflow = task.resultPaths.length - paths.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final path in paths)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(path),
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 28,
                  height: 28,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.broken_image, size: 14, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+$overflow',
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusPill(String label, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ── 4px progress bar (processing rows only) ────────────────────────────────

  Widget _buildProgressBar(TaskItem task, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 46),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: task.progress,
          minHeight: 4,
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        ),
      ),
    );
  }

  // ── More / actions menu ─────────────────────────────────────────────────────

  Widget _buildMoreButton(
    BuildContext context,
    TaskItem task,
    AppState appState,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final canCancel = task.status == TaskStatus.pending;
    final canRetry = task.status == TaskStatus.failed || task.status == TaskStatus.cancelled;
    final canRemove = task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 19, color: colorScheme.onSurfaceVariant),
      iconSize: 34,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(34, 34)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        overlayColor: WidgetStatePropertyAll(colorScheme.onSurface.withAlpha(20)),
      ),
      onSelected: (val) {
        if (val == 'cancel') appState.taskQueue.cancelTask(task.id);
        if (val == 'retry') appState.taskQueue.retryTask(task.id);
        if (val == 'remove') appState.taskQueue.removeTask(task.id);
        if (val == 'copy_prompt') {
          final prompt = task.parameters['prompt'] ?? '';
          Clipboard.setData(ClipboardData(text: prompt));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.copiedToClipboard(prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt))),
          );
        }
      },
      itemBuilder: (context) => [
        if (canCancel)
          PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(Icons.cancel_outlined, size: 18, color: colorScheme.error),
              title: Text(l10n.cancelTask, style: TextStyle(color: colorScheme.error)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canRetry)
          PopupMenuItem(
            value: 'retry',
            child: ListTile(
              leading: const Icon(Icons.refresh, size: 18),
              title: Text(l10n.retryTask),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canRemove)
          PopupMenuItem(
            value: 'remove',
            child: ListTile(
              leading: Icon(Icons.delete_outline, size: 18, color: colorScheme.onSurface),
              title: Text(l10n.removeFromList),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (task.parameters.containsKey('prompt'))
          PopupMenuItem(
            value: 'copy_prompt',
            child: ListTile(
              leading: const Icon(Icons.copy_outlined, size: 18),
              title: const Text('Copy prompt'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  // ── Expanded details (unchanged behavior) ──────────────────────────────────

  Widget _buildExpandedDetails(
    BuildContext context,
    TaskItem task,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 22, color: colorScheme.outlineVariant.withAlpha(80)),
        _buildInfoRow(Icons.timer_outlined, l10n.started, _formatClock(task.startTime), colorScheme),
        _buildInfoRow(Icons.check_circle_outline, l10n.finished, _formatClock(task.endTime), colorScheme),
        if (task.type == TaskType.imageProcess)
          _buildInfoRow(Icons.aspect_ratio, l10n.config,
              '${task.parameters['aspectRatio'] ?? ''} ${task.parameters['imageSize'] ?? ''}'.trim(), colorScheme),
        if (task.parameters.containsKey('prompt'))
          _buildInfoRow(Icons.description_outlined, l10n.prompt, task.parameters['prompt'] ?? '', colorScheme),
        if (task.resultPaths.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: task.resultPaths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(task.resultPaths[i]),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.broken_image, size: 20, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (task.logs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              task.logs.last,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  IconData _typeIcon(TaskType type) => switch (type) {
        TaskType.imageProcess => Icons.image_outlined,
        TaskType.imageDownload => Icons.cloud_download_outlined,
        TaskType.promptRefine => Icons.auto_fix_high,
        TaskType.aiRename => Icons.drive_file_rename_outline,
        TaskType.videoGenerate => Icons.movie_outlined,
      };

  String _taskDisplayName(TaskItem task) {
    if (task.imagePaths.isNotEmpty) {
      return p.basename(task.imagePaths.first);
    }
    return switch (task.type) {
      TaskType.imageProcess => 'Image Process',
      TaskType.imageDownload => task.parameters['url'] ?? 'Download',
      TaskType.promptRefine => 'Prompt Refine',
      TaskType.aiRename => 'AI Rename',
      TaskType.videoGenerate => 'Video Generate',
    };
  }

  String _shortModelId(String modelId) {
    if (modelId.length <= 26) return modelId;
    return '${modelId.substring(0, 24)}…';
  }

  String _progressLabel(TaskItem task) {
    final percent = task.progress != null ? '${(task.progress! * 100).round()}%' : '···';
    final elapsed = task.startTime != null
        ? _formatDuration(DateTime.now().difference(task.startTime!))
        : null;
    return elapsed != null ? '$percent · $elapsed' : percent;
  }

  /// 1-based position among pending tasks in execution (FIFO) order.
  int _queuePosition(TaskItem task) {
    final queue = Provider.of<AppState>(context, listen: false).taskQueue.queue;
    int position = 0;
    for (final t in queue) {
      if (t.status == TaskStatus.pending) {
        position++;
        if (t.id == task.id) return position;
      }
    }
    return 0;
  }

  String? _elapsed(TaskItem task) {
    if (task.startTime == null || task.endTime == null) return null;
    return _formatDuration(task.endTime!.difference(task.startTime!));
  }

  String _errorSummary(TaskItem task) {
    final errorLog = task.logs.lastWhere(
      (log) => log.contains('Error'),
      orElse: () => task.logs.isNotEmpty ? task.logs.last : '',
    );
    // Strip the "[HH:mm:ss] " prefix for a cleaner inline summary.
    return errorLog.replaceFirst(RegExp(r'^\[\d{2}:\d{2}:\d{2}\]\s*'), '');
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (duration.inHours > 0) {
      return '${duration.inHours}:${minutes.remainder(60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatClock(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
