import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';

class TaskQueueScreen extends StatelessWidget {
  const TaskQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tasks = appState.taskQueue.queue;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taskQueueManager),
        actions: [
          TextButton.icon(
            onPressed: () => appState.taskQueue.notifyListeners(), // Refresh
            icon: const Icon(Icons.refresh),
            label: Text(l10n.refresh),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: tasks.isEmpty
          ? _buildEmptyState(colorScheme, l10n)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = tasks[tasks.length - 1 - index]; // Show newest first
                return _TaskTile(task: task);
              },
            ),
    );
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
              Row(
                children: [
                  _buildStatusBadge(task.status, colorScheme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.taskId(task.id.substring(0, 8)),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ),
                  Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
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
              if (_isExpanded) ...[
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(Icons.model_training, l10n.model, task.modelId),
                          _buildInfoRow(Icons.image, l10n.images, l10n.filesCount(task.imagePaths.length)),
                          _buildInfoRow(Icons.timer_outlined, l10n.started, _formatTime(task.startTime)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(Icons.auto_awesome, l10n.processResults, l10n.filesCount(task.resultPaths.length)),
                          _buildInfoRow(Icons.aspect_ratio, l10n.config, '${task.parameters['aspectRatio']} | ${task.parameters['imageSize']}'),
                          _buildInfoRow(Icons.check_circle_outline, l10n.finished, _formatTime(task.endTime)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                        Text(l10n.latestLog, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
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

  Widget _buildStatusBadge(TaskStatus status, ColorScheme colorScheme) {
    Color color;
    IconData icon;
    String label = status.name.toUpperCase();

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
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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
