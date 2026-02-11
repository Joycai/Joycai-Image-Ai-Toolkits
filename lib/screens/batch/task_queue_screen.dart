import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    } else {
      return _buildDesktopLayout(context, appState, l10n);
    }
  }

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
              PopupMenuItem(value: 'clear_all', child: Text(l10n.clearAll), enabled: tasks.isNotEmpty),
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

  Widget _buildDesktopLayout(BuildContext context, AppState appState, AppLocalizations l10n) {
    final tasks = appState.taskQueue.queue;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskQueueManager)),
      body: Row(
        children: [
          // Left Sidebar: Summary & Controls
          Container(
            width: 300,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    l10n.taskSummary,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                _buildSummaryStat(l10n.pendingTasks, _getCount(tasks, TaskStatus.pending), Colors.orange),
                _buildSummaryStat(l10n.processingTasks, _getCount(tasks, TaskStatus.processing), Colors.blue),
                _buildSummaryStat(l10n.completedTasks, _getCount(tasks, TaskStatus.completed), Colors.green),
                _buildSummaryStat(l10n.failedTasks, _getCount(tasks, TaskStatus.failed), Colors.red),
                
                const Spacer(),
                const Divider(height: 1),
                
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.concurrencyLimit(appState.taskQueue.concurrencyLimit),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: appState.taskQueue.concurrencyLimit.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        onChanged: (v) => appState.taskQueue.updateConcurrency(v.round()),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => _handleBulkAction('clear_completed', appState.taskQueue),
                        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                        label: Text(l10n.clearCompleted),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _handleBulkAction('cancel_pending', appState.taskQueue),
                        icon: const Icon(Icons.cancel_presentation_outlined, size: 18),
                        label: Text(l10n.cancelAllPending),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: tasks.isEmpty ? null : () => _handleBulkAction('clear_all', appState.taskQueue),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(l10n.clearAll),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right Pane: Task List
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState(colorScheme, l10n)
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: tasks.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final task = tasks[tasks.length - 1 - index];
                          return _TaskTile(task: task);
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
          ),
        ],
      ),
    );
  }

  int _getCount(List<TaskItem> tasks, TaskStatus status) {
    return tasks.where((t) => t.status == status).length;
  }

  void _handleBulkAction(String action, TaskQueueService queue) {
    if (action == 'clear_completed') {
      final toRemove = queue.queue.where((t) => t.status == TaskStatus.completed).map((t) => t.id).toList();
      for (var id in toRemove) {
        queue.removeTask(id);
      }
    } else if (action == 'cancel_pending') {
      final toCancel = queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (var id in toCancel) {
        queue.cancelTask(id);
      }
    } else if (action == 'clear_all') {
      final toRemove = queue.queue.where((t) => t.status != TaskStatus.processing).map((t) => t.id).toList();
      for (var id in toRemove) {
        queue.removeTask(id);
      }
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatusBadge(task, colorScheme),
                        const Spacer(),
                        if (task.status == TaskStatus.pending)
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                            tooltip: l10n.cancelTask,
                            onPressed: () => appState.taskQueue.cancelTask(task.id),
                          ),
                        if (task.status == TaskStatus.completed || task.status == TaskStatus.failed || task.status == TaskStatus.cancelled)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: l10n.removeFromList,
                            onPressed: () => appState.taskQueue.removeTask(task.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (task.channelTag != null) ...[
                          _buildChannelBadge(task),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            l10n.taskId(task.id.substring(0, 8)),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                        Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _buildStatusBadge(task, colorScheme),
                    const SizedBox(width: 12),
                    if (task.channelTag != null) ...[
                      _buildChannelBadge(task),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        l10n.taskId(task.id.substring(0, 8)),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),
                    Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    if (task.status == TaskStatus.pending)
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        tooltip: l10n.cancelTask,
                        onPressed: () => appState.taskQueue.cancelTask(task.id),
                      ),
                    if (task.status == TaskStatus.completed || task.status == TaskStatus.failed || task.status == TaskStatus.cancelled)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.removeFromList,
                        onPressed: () => appState.taskQueue.removeTask(task.id),
                      ),
                  ],
                ),
              if (task.status == TaskStatus.processing && task.progress != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 4,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      task.type == TaskType.imageDownload ? Colors.teal : colorScheme.primary
                    ),
                  ),
                ),
              ],
              if (_isExpanded) ...[
                const Divider(height: 24),
                if (isMobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.type == TaskType.imageProcess)
                        _buildInfoRow(Icons.model_training, l10n.model, task.modelId)
                      else
                        _buildInfoRow(Icons.language, l10n.url, task.parameters['url'] ?? 'N/A'),
                      _buildInfoRow(
                        task.type == TaskType.imageProcess ? Icons.image : Icons.link,
                        task.type == TaskType.imageProcess ? l10n.images : 'URLs',
                        l10n.filesCount(task.imagePaths.length),
                      ),
                      _buildInfoRow(Icons.timer_outlined, l10n.started, _formatTime(task.startTime)),
                      _buildInfoRow(Icons.auto_awesome, l10n.processResults, l10n.filesCount(task.resultPaths.length)),
                      if (task.type == TaskType.imageProcess)
                        _buildInfoRow(Icons.aspect_ratio, l10n.config, '${task.parameters['aspectRatio']} | ${task.parameters['imageSize']}')
                      else
                        _buildInfoRow(Icons.label_outline, l10n.prefix, task.parameters['prefix'] ?? 'N/A'),
                      _buildInfoRow(Icons.check_circle_outline, l10n.finished, _formatTime(task.endTime)),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (task.type == TaskType.imageProcess)
                              _buildInfoRow(Icons.model_training, l10n.model, task.modelId)
                            else
                              _buildInfoRow(Icons.language, l10n.url, task.parameters['url'] ?? 'N/A'),
                            _buildInfoRow(
                              task.type == TaskType.imageProcess ? Icons.image : Icons.link,
                              task.type == TaskType.imageProcess ? l10n.images : 'URLs',
                              l10n.filesCount(task.imagePaths.length),
                            ),
                            _buildInfoRow(Icons.timer_outlined, l10n.started, _formatTime(task.startTime)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(Icons.auto_awesome, l10n.processResults, l10n.filesCount(task.resultPaths.length)),
                            if (task.type == TaskType.imageProcess)
                              _buildInfoRow(Icons.aspect_ratio, l10n.config, '${task.parameters['aspectRatio']} | ${task.parameters['imageSize']}')
                            else
                              _buildInfoRow(Icons.label_outline, l10n.prefix, task.parameters['prefix'] ?? 'N/A'),
                            _buildInfoRow(Icons.check_circle_outline, l10n.finished, _formatTime(task.endTime)),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                if (task.type == TaskType.imageProcess)
                  _buildInfoRow(
                    Icons.description_outlined,
                    l10n.prompt,
                    task.parameters['prompt'] ?? 'N/A',
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final prompt = task.parameters['prompt'] ?? '';
                        Clipboard.setData(ClipboardData(text: prompt));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.copiedToClipboard(
                              prompt.length > 30 ? '${prompt.substring(0, 30)}...' : prompt,
                            )),
                          ),
                        );
                      },
                      color: colorScheme.primary,
                      tooltip: 'Copy Prompt',
                    ),
                  ),
                if (task.resultPaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: task.resultPaths.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(task.resultPaths[index]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (task.logs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((255 * 0.05).round()),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.latestLog, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 12),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final log = task.logs.join('\n');
                                Clipboard.setData(ClipboardData(text: log));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard.')));
                              },
                              tooltip: 'Copy Logs',
                            ),
                          ],
                        ),
                        Text(
                          task.logs.last,
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelBadge(TaskItem task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color(task.channelColor ?? 0xFF607D8B).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Color(task.channelColor ?? 0xFF607D8B).withValues(alpha: 0.5)),
      ),
      child: Text(
        task.channelTag!,
        style: TextStyle(
          fontSize: 10, 
          color: Color(task.channelColor ?? 0xFF607D8B),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(TaskItem task, ColorScheme colorScheme) {
    Color color;
    IconData icon;
    String label = task.status.name.toUpperCase();
    final status = task.status;

    switch (status) {
      case TaskStatus.pending:
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case TaskStatus.processing:
        color = Colors.blue;
        icon = Icons.sync;
        break;
      case TaskStatus.completed:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case TaskStatus.failed:
        color = Colors.red;
        icon = Icons.error;
        break;
      case TaskStatus.cancelled:
        color = Colors.grey;
        icon = Icons.cancel;
        break;
    }

    if (task.type == TaskType.imageDownload) {
      color = (status == TaskStatus.completed) ? Colors.teal : (status == TaskStatus.processing ? Colors.cyan : color);
      if (status == TaskStatus.processing || status == TaskStatus.completed) {
        icon = (status == TaskStatus.completed) ? Icons.cloud_done : Icons.cloud_download;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.1).round()),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha((255 * 0.5).round())),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            task.type == TaskType.imageDownload ? '[DL] $label' : label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing,
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
