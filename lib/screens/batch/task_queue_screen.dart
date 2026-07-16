import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/dialogs/task_log_dialog.dart';

/// Which subset of tasks the list shows.
enum _TaskFilter { all, running, pending, done, failed }

/// The colour a status is spoken in, shared by a task's accent stripe, its
/// leading tile and its count in the header — so one glance down the stripes
/// answers the same question the header summary does.
Color _statusColor(TaskStatus status, ColorScheme colorScheme) => switch (status) {
      TaskStatus.processing => colorScheme.primary,
      TaskStatus.pending => colorScheme.onSurfaceVariant,
      TaskStatus.completed => Colors.green,
      TaskStatus.failed => colorScheme.error,
      TaskStatus.cancelled => colorScheme.outline,
    };

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

    if (Responsive.isNarrow(context)) {
      return _buildMobileLayout(context, appState, l10n);
    }

    final content = _buildDesktopContent(context, appState, l10n);

    // Embedded presentation (workbench bottom-sheet console): the sheet already
    // paints the canvas, so the content drops straight onto it.
    final inBottomSheet = context.findAncestorWidgetOfExactType<BottomSheet>() != null;
    if (inBottomSheet) return content;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: content,
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
      backgroundColor: colorScheme.surfaceContainer,
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
            height: 58,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _buildFilterPills(context, queue, l10n),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState(colorScheme, l10n)
                : _buildTaskList(tasks, const EdgeInsets.fromLTRB(12, 2, 12, 12), isMobile: true),
          ),
        ],
      ),
    );
  }

  // ── Desktop content: header, filters and task cards on the canvas ───────────

  Widget _buildDesktopContent(BuildContext context, AppState appState, AppLocalizations l10n) {
    final queue = appState.taskQueue.queue;
    final tasks = _visibleTasks(queue);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _buildHeader(context, appState, queue, l10n, colorScheme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildFilterPills(context, queue, l10n),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyState(colorScheme, l10n)
              : _buildTaskList(tasks, const EdgeInsets.fromLTRB(16, 14, 16, 12), isMobile: false),
        ),
      ],
    );
  }

  Widget _buildTaskList(List<TaskItem> tasks, EdgeInsets padding, {required bool isMobile}) {
    return ListView.builder(
      padding: padding,
      itemCount: tasks.length,
      itemBuilder: (context, index) => _TaskCard(task: tasks[index], isMobile: isMobile),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  /// Title block plus the queue-wide actions, on the canvas rather than in a
  /// card header: the actions and the filters below them govern every card on
  /// the page, so inside one card's header they would read as that card's.
  Widget _buildHeader(
    BuildContext context,
    AppState appState,
    List<TaskItem> queue,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final queued = queue.where((t) => t.status == TaskStatus.pending).length;
    final finished = queue
        .where((t) =>
            t.status == TaskStatus.completed ||
            t.status == TaskStatus.failed ||
            t.status == TaskStatus.cancelled)
        .length;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.checklist_rounded, size: 22, color: colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.taskQueueManager,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(height: 3),
              _buildHeaderSummary(queue, l10n, colorScheme),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppIconButton(
          icon: Icons.tune,
          tooltip: l10n.concurrencyLimit(appState.taskQueue.concurrencyLimit),
          onPressed: () => _showConcurrencyDialog(context, l10n, appState),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed:
              queued == 0 ? null : () => _handleBulkAction('cancel_pending', appState.taskQueue),
          icon: const Icon(Icons.pause, size: 18),
          label: Text(l10n.cancelAllPending),
          style: _headerButtonStyle(colorScheme, colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed:
              finished == 0 ? null : () => _handleBulkAction('clear_completed', appState.taskQueue),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l10n.clearCompleted),
          // Filled in its own colour, unlike its neighbour: it is the one action
          // here that destroys something.
          style: _headerButtonStyle(colorScheme, colorScheme.error, filled: finished > 0),
        ),
      ],
    );
  }

  /// The queue in one line: the total, then each status that has anything in
  /// it, in that status's colour. Statuses at zero are left out — an empty
  /// count is not news, and the filter pills below already list them all.
  Widget _buildHeaderSummary(
    List<TaskItem> queue,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final counts = <(String, TaskStatus)>[
      (l10n.processingTasks, TaskStatus.processing),
      (l10n.pendingTasks, TaskStatus.pending),
      (l10n.completedTasks, TaskStatus.completed),
      (l10n.failedTasks, TaskStatus.failed),
    ];

    final spans = <InlineSpan>[
      TextSpan(
        text: l10n.taskTotalCount(queue.length),
        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
      ),
    ];

    for (final (label, status) in counts) {
      final count = queue.where((t) => t.status == status).length;
      if (count == 0) continue;
      spans.add(TextSpan(text: '  ·  ', style: TextStyle(color: colorScheme.outline)));
      spans.add(TextSpan(
        text: '$label $count',
        style: TextStyle(color: _statusColor(status, colorScheme), fontWeight: FontWeight.w600),
      ));
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  ButtonStyle _headerButtonStyle(ColorScheme colorScheme, Color accent, {bool filled = false}) {
    return OutlinedButton.styleFrom(
      backgroundColor: filled ? accent.withValues(alpha: 0.12) : null,
      side: BorderSide(
        color: filled ? accent.withValues(alpha: 0.5) : colorScheme.outline.withValues(alpha: 0.45),
      ),
      foregroundColor: accent,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(0, appButtonMinHeight),
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
    );
  }

  // ── Filter pills ────────────────────────────────────────────────────────────

  Widget _buildFilterPills(BuildContext context, List<TaskItem> queue, AppLocalizations l10n) {
    int countOf(bool Function(TaskItem) test) => queue.where(test).length;

    final entries = <(_TaskFilter, String, int)>[
      (_TaskFilter.all, l10n.filterAll, queue.length),
      (_TaskFilter.running, l10n.processingTasks, countOf((t) => t.status == TaskStatus.processing)),
      (_TaskFilter.pending, l10n.pendingTasks, countOf((t) => t.status == TaskStatus.pending)),
      (_TaskFilter.done, l10n.completedTasks, countOf((t) => t.status == TaskStatus.completed)),
      (
        _TaskFilter.failed,
        l10n.failedTasks,
        countOf((t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled),
      ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (filter, label, count) in entries) ...[
          _FilterPill(
            label: label,
            count: count,
            selected: _filter == filter,
            onTap: () => setState(() => _filter = filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
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
          Text(l10n.submitTaskFromWorkbench, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Filter pill
// ════════════════════════════════════════════════════════════════════════════

/// One filter, with its count in a badge of its own rather than trailing the
/// label as text — the counts move as the queue drains, and a number that
/// changes inside a run of words drags the whole label around with it.
class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.15)
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(appButtonRadius),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(appButtonRadius),
        child: Container(
          height: appButtonMinHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appButtonRadius),
            border: Border.all(
              color: selected ? colorScheme.primary.withValues(alpha: 0.6) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary.withValues(alpha: 0.22)
                      : colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Task card — an accent stripe carries the status down the list
// ════════════════════════════════════════════════════════════════════════════

class _TaskCard extends StatefulWidget {
  final TaskItem task;
  final bool isMobile;
  const _TaskCard({required this.task, required this.isMobile});

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;

    final isProcessing = task.status == TaskStatus.processing;
    final isFailed = task.status == TaskStatus.failed;
    final accent = _statusColor(task.status, colorScheme);

    // A card of its own rather than a PanelCard: the stripe has to reach both
    // edges, and a failed card carries a wash of its status through the surface.
    final surface = isFailed
        ? Color.alphaBlend(colorScheme.error.withValues(alpha: 0.06), colorScheme.surface)
        : isProcessing
            ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.05), colorScheme.surface)
            : colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(widget.isMobile ? 10 : 14, 14, 8, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildLeadingTile(task, colorScheme, accent),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Leading tile: icon + tint follow status ────────────────────────────────

  Widget _buildLeadingTile(TaskItem task, ColorScheme colorScheme, Color accent) {
    final icon = switch (task.status) {
      TaskStatus.completed => Icons.check,
      TaskStatus.failed => Icons.warning_amber_rounded,
      TaskStatus.cancelled => Icons.block,
      _ => _typeIcon(task.type),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: accent),
    );
  }

  // ── Title + meta line ──────────────────────────────────────────────────────

  Widget _buildTitleAndMeta(TaskItem task, ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _taskDisplayName(task),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: task.status == TaskStatus.cancelled
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        _buildMeta(task, colorScheme, l10n),
      ],
    );
  }

  Widget _buildMeta(TaskItem task, ColorScheme colorScheme, AppLocalizations l10n) {
    // Failure info replaces the meta line — what went wrong outranks what ran.
    // Unless there is none: tasks reloaded from the database come back without
    // their logs, and a blank line says less about a failure than the model
    // that produced it does.
    final error = task.status == TaskStatus.failed ? _errorSummary(task) : '';
    if (error.isNotEmpty) {
      return Text(
        error,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colorScheme.error),
      );
    }

    final muted = TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant);
    final (marker, modelId) = _splitModelMarker(task.modelId);
    final children = <Widget>[];

    void addSeparator() {
      if (children.isEmpty) return;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text('·', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
      ));
    }

    if (marker != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _MetaBadge(label: marker, color: colorScheme.onSurfaceVariant),
      ));
    }
    children.add(Flexible(
      child: Text(
        _shortModelId(modelId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted.copyWith(fontFamily: 'monospace'),
      ),
    ));

    if (task.channelTag != null) {
      addSeparator();
      children.add(_MetaBadge(
        label: task.channelTag!,
        color: Color(task.channelColor ?? 0xFF607D8B),
      ));
    }

    if (task.imagePaths.length > 1) {
      addSeparator();
      children.add(Text(l10n.filesCount(task.imagePaths.length), style: muted));
    }

    switch (task.status) {
      case TaskStatus.pending:
        final position = _queuePosition(task);
        if (position > 0) {
          addSeparator();
          children.add(Text(l10n.queuedPosition(position), style: muted));
        }
      case TaskStatus.completed:
        final duration = _elapsed(task);
        if (duration != null) {
          addSeparator();
          children.add(Icon(Icons.schedule, size: 12, color: colorScheme.onSurfaceVariant));
          children.add(const SizedBox(width: 5));
          children.add(Text(l10n.tookDuration(duration), style: muted));
        }
      case TaskStatus.cancelled:
        addSeparator();
        children.add(Text(l10n.statusCancelled, style: muted));
      default:
        break;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  // ── Trailing: status/action → time → thumbnail → menu ──────────────────────

  List<Widget> _buildTrailing(
    BuildContext context,
    TaskItem task,
    AppState appState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final widgets = <Widget>[];

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
        widgets.add(const SizedBox(width: 10));
      case TaskStatus.pending:
        widgets.add(_statusPill(l10n.pendingTasks, colorScheme.onSurfaceVariant, colorScheme));
        widgets.add(const SizedBox(width: 10));
      case TaskStatus.failed:
        widgets.add(OutlinedButton(
          onPressed: () => appState.taskQueue.retryTask(task.id),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            backgroundColor: colorScheme.error.withValues(alpha: 0.12),
            foregroundColor: colorScheme.error,
            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(l10n.retryTask),
        ));
        widgets.add(const SizedBox(width: 10));
      case TaskStatus.completed:
      case TaskStatus.cancelled:
        break;
    }

    if (!widget.isMobile) {
      widgets.add(Text(
        _formatClock(task.endTime ?? task.startTime),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ));
      widgets.add(const SizedBox(width: 12));

      if (task.status == TaskStatus.completed && task.resultPaths.isNotEmpty) {
        widgets.add(_buildThumbnailStrip(task, colorScheme));
        widgets.add(const SizedBox(width: 6));
      }
    }

    widgets.add(_buildMoreButton(context, task, appState, l10n, colorScheme));
    return widgets;
  }

  Widget _buildThumbnailStrip(TaskItem task, ColorScheme colorScheme) {
    const maxThumbs = 3;
    const size = 44.0;
    final paths = task.resultPaths.take(maxThumbs).toList();
    final overflow = task.resultPaths.length - paths.length;

    Widget frame({required Widget child}) => Padding(
          padding: const EdgeInsets.only(left: 5),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final path in paths)
          frame(
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: colorScheme.surfaceContainerHighest,
                child: Icon(Icons.broken_image, size: 16, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        if (overflow > 0)
          frame(
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: colorScheme.surfaceContainerHighest,
              child: Text(
                '+$overflow',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusPill(String label, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ── 4px progress bar (processing cards only) ───────────────────────────────

  Widget _buildProgressBar(TaskItem task, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 56),
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
        if (val == 'view_log') TaskLogDialog.show(context, task);
        if (val == 'copy_prompt') {
          final prompt = task.parameters['prompt'] ?? '';
          Clipboard.setData(ClipboardData(text: prompt));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.copiedToClipboard(prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt))),
          );
        }
      },
      itemBuilder: (context) => [
        // First and unconditional: it is the one action every status has a use
        // for, and the only way to see why a failed task failed.
        PopupMenuItem(
          value: 'view_log',
          child: ListTile(
            leading: const Icon(Icons.terminal, size: 18),
            title: Text(l10n.viewTaskLog),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
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
              title: Text(l10n.copyPrompt),
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
        Divider(height: 24, color: colorScheme.outlineVariant.withAlpha(80)),
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
          // The peek is the last line only, which for a failure is rarely the
          // interesting one — so it doubles as the way in to the full log.
          Material(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => TaskLogDialog.show(context, task),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.logs.last,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.unfold_more, size: 14, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                  ],
                ),
              ),
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

  /// Lifts a leading `[MARKER]` off a model id so it can be drawn as a badge.
  ///
  /// Users prefix ids to mark a variant of a model they run more than one way.
  /// Left inline the bracket reads as part of the id, and the id is exactly
  /// what the eye skips to; as a badge the marker is the thing that differs
  /// between two otherwise identical rows.
  (String?, String) _splitModelMarker(String modelId) {
    final match = RegExp(r'^\[([^\[\]]{1,8})\]\s*').firstMatch(modelId);
    if (match == null) return (null, modelId);
    return (match.group(1), modelId.substring(match.end));
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

// ════════════════════════════════════════════════════════════════════════════
// Meta badge
// ════════════════════════════════════════════════════════════════════════════

/// A short tag in the meta line — a channel, or a model-id marker. Boxed in its
/// own colour so it separates from the ids and durations it sits among, which
/// are all one muted grey.
class _MetaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          color: color,
        ),
      ),
    );
  }
}
