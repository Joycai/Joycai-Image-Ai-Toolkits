import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';

class TaskQueueScreen extends StatelessWidget {
  const TaskQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);

    if (isNarrow) {
      return _buildMobileLayout(context, appState, l10n);
    }
    return _buildDesktopLayout(context, appState, l10n);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Mobile layout (unchanged structure, kept for all narrow screens)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context, AppState appState, AppLocalizations l10n) {
    final tasks = appState.taskQueue.queue;
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
              PopupMenuItem(value: 'clear_all', enabled: tasks.isNotEmpty, child: Text(l10n.clearAll)),
            ],
          ),
        ],
      ),
      body: tasks.isEmpty
          ? _buildEmptyState(colorScheme, l10n)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = tasks[tasks.length - 1 - index];
                return _TaskTile(task: task);
              },
            ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Desktop layout — design-aligned: inline header + flat task list
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context, AppState appState, AppLocalizations l10n) {
    final tasks = appState.taskQueue.queue;
    final colorScheme = Theme.of(context).colorScheme;

    final running = tasks.where((t) => t.status == TaskStatus.processing).length;
    final queued = tasks.where((t) => t.status == TaskStatus.pending).length;
    final done = tasks.where((t) => t.status == TaskStatus.completed).length;
    final failed = tasks.where((t) => t.status == TaskStatus.failed).length;

    final parts = <String>[];
    if (running > 0) parts.add('$running running');
    if (queued > 0) parts.add('$queued queued');
    if (done > 0) parts.add('$done done');
    if (failed > 0) parts.add('$failed failed');
    final subtitle = parts.isEmpty ? l10n.noTasksInQueue : parts.join(' · ');

    return Column(
      children: [
        // ── 60px inline header ──────────────────────────────────────────────
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.taskQueueManager,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Concurrency settings
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                tooltip: l10n.concurrencyLimit(appState.taskQueue.concurrencyLimit),
                onPressed: () => _showConcurrencyDialog(context, l10n, appState),
              ),
              const SizedBox(width: 4),
              // Pause all (cancel pending)
              OutlinedButton.icon(
                onPressed: queued == 0
                    ? null
                    : () => _handleBulkAction('cancel_pending', appState.taskQueue),
                icon: const Icon(Icons.pause, size: 18),
                label: Text(l10n.cancelAllPending),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorScheme.outlineVariant),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
                  minimumSize: const Size(0, 38),
                ),
              ),
              const SizedBox(width: 8),
              // Clear done
              OutlinedButton.icon(
                onPressed: done == 0 && failed == 0
                    ? null
                    : () => _handleBulkAction('clear_completed', appState.taskQueue),
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(l10n.clearCompleted),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: (done > 0 || failed > 0)
                        ? colorScheme.error.withAlpha(160)
                        : colorScheme.outlineVariant,
                  ),
                  foregroundColor: (done > 0 || failed > 0)
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
                  minimumSize: const Size(0, 38),
                ),
              ),
            ],
          ),
        ),

        // ── Task list ────────────────────────────────────────────────────────
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyState(colorScheme, l10n)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 11),
                  itemBuilder: (context, index) {
                    final task = tasks[tasks.length - 1 - index];
                    return _TaskTile(task: task);
                  },
                ),
        ),
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
          Text(l10n.submitTaskFromWorkbench, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Task Tile — design-aligned card
// ════════════════════════════════════════════════════════════════════════════

class _TaskTile extends StatefulWidget {
  final TaskItem task;
  const _TaskTile({required this.task});

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return _buildMobileTile(context, colorScheme, appState, l10n, task);
    }
    return _buildDesktopTile(context, colorScheme, appState, l10n, task);
  }

  // ── Desktop tile — matches design card spec ────────────────────────────────
  Widget _buildDesktopTile(
    BuildContext context,
    ColorScheme colorScheme,
    AppState appState,
    AppLocalizations l10n,
    TaskItem task,
  ) {
    final (icon, iconColor) = _taskIcon(task, colorScheme);
    final name = _taskDisplayName(task);
    final modelLabel = _shortModelId(task.modelId);
    final subText = _taskSubtitle(task, l10n);

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(
            color: _isExpanded
                ? colorScheme.primary.withAlpha(90)
                : colorScheme.outlineVariant.withAlpha(80),
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header row ────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Status / type icon
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 15),

                // Name + model chip + status pill
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (modelLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                modelLabel,
                                style: TextStyle(fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (task.channelTag != null) ...[
                            const SizedBox(width: 6),
                            _buildChannelBadge(task),
                          ],
                          const Spacer(),
                          _buildStatusPill(task, colorScheme),
                        ],
                      ),
                      const SizedBox(height: 7),
                      // Progress bar + subtitle
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: task.status == TaskStatus.processing
                                    ? (task.progress)
                                    : (task.status == TaskStatus.completed ? 1.0 : 0.0),
                                minHeight: 7,
                                backgroundColor: colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  task.status == TaskStatus.failed
                                      ? colorScheme.error
                                      : colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          SizedBox(
                            width: 100,
                            child: Text(
                              subText,
                              textAlign: TextAlign.right,
                              style: TextStyle(fontFamily: 'monospace',
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 11),

                // More / actions button
                _buildMoreButton(context, task, appState, l10n, colorScheme),
              ],
            ),

            // ── Expanded details ────────────────────────────────────────────
            if (_isExpanded) _buildExpandedDetails(context, task, colorScheme, l10n),
          ],
        ),
      ),
    );
  }

  // ── Mobile tile (simplified) ───────────────────────────────────────────────
  Widget _buildMobileTile(
    BuildContext context,
    ColorScheme colorScheme,
    AppState appState,
    AppLocalizations l10n,
    TaskItem task,
  ) {
    final (icon, iconColor) = _taskIcon(task, colorScheme);
    final name = _taskDisplayName(task);
    final modelLabel = _shortModelId(task.modelId);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22, color: iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        if (modelLabel.isNotEmpty)
                          Text(modelLabel, style: TextStyle(fontFamily: 'monospace',fontSize: 10, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  _buildStatusPill(task, colorScheme),
                  const SizedBox(width: 4),
                  _buildMoreButton(context, task, appState, l10n, colorScheme),
                ],
              ),
              if (task.status == TaskStatus.processing && task.progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
              if (_isExpanded) _buildExpandedDetails(context, task, colorScheme, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreButton(
    BuildContext context,
    TaskItem task,
    AppState appState,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final canCancel = task.status == TaskStatus.pending;
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
        _buildInfoRow(Icons.timer_outlined, l10n.started, _formatTime(task.startTime), colorScheme),
        _buildInfoRow(Icons.check_circle_outline, l10n.finished, _formatTime(task.endTime), colorScheme),
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
              style: TextStyle(fontFamily: 'monospace',fontSize: 11, color: colorScheme.onSurfaceVariant),
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

  Widget _buildChannelBadge(TaskItem task) {
    final color = Color(task.channelColor ?? 0xFF607D8B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        task.channelTag!,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusPill(TaskItem task, ColorScheme colorScheme) {
    final (color, label) = switch (task.status) {
      TaskStatus.pending => (Colors.orange, 'PENDING'),
      TaskStatus.processing => (colorScheme.primary, 'RUNNING'),
      TaskStatus.completed => (Colors.green, 'DONE'),
      TaskStatus.failed => (colorScheme.error, 'FAILED'),
      TaskStatus.cancelled => (colorScheme.onSurfaceVariant, 'CANCELLED'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  (IconData, Color) _taskIcon(TaskItem task, ColorScheme colorScheme) {
    final baseColor = switch (task.status) {
      TaskStatus.pending => Colors.orange,
      TaskStatus.processing => colorScheme.primary,
      TaskStatus.completed => Colors.green,
      TaskStatus.failed => colorScheme.error,
      TaskStatus.cancelled => colorScheme.onSurfaceVariant,
    };
    final icon = switch (task.type) {
      TaskType.imageProcess => Icons.image_outlined,
      TaskType.imageDownload => Icons.cloud_download_outlined,
      TaskType.promptRefine => Icons.auto_fix_high,
      TaskType.aiRename => Icons.drive_file_rename_outline,
      TaskType.videoGenerate => Icons.movie_outlined,
    };
    return (icon, baseColor);
  }

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

  String _taskSubtitle(TaskItem task, AppLocalizations l10n) {
    final count = task.imagePaths.length;
    final countStr = count > 0 ? '$count ${count == 1 ? "item" : "items"}' : '';
    return switch (task.status) {
      TaskStatus.pending => 'Waiting${countStr.isNotEmpty ? " · $countStr" : ""}',
      TaskStatus.processing => task.progress != null
          ? '${(task.progress! * 100).round()}%${countStr.isNotEmpty ? " · $countStr" : ""}'
          : '···',
      TaskStatus.completed => _formatTime(task.endTime),
      TaskStatus.failed => 'Failed',
      TaskStatus.cancelled => 'Cancelled',
    };
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--:--';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
