import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/task_queue_service.dart';

class BatchScreen extends StatelessWidget {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tasks = appState.taskQueue.queue;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Queue Manager'),
        actions: [
          TextButton.icon(
            onPressed: () => appState.taskQueue.notifyListeners(), // Refresh
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: tasks.isEmpty
          ? _buildEmptyState(colorScheme)
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

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          const Text('No tasks in queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Submit a task from the Workbench to see it here.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final TaskItem task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context, listen: false);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
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
                    'Task ID: ${task.id.substring(0, 8)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ),
                if (task.status == TaskStatus.pending)
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    tooltip: 'Cancel Task',
                    onPressed: () => appState.taskQueue.cancelTask(task.id),
                  ),
                if (task.status == TaskStatus.completed || task.status == TaskStatus.failed || task.status == TaskStatus.cancelled)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove from list',
                    onPressed: () => appState.taskQueue.removeTask(task.id),
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(Icons.model_training, 'Model', task.modelId),
                      _buildInfoRow(Icons.image, 'Images', '${task.imagePaths.length} files'),
                      _buildInfoRow(Icons.timer_outlined, 'Started', _formatTime(task.startTime)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(Icons.description_outlined, 'Prompt', task.parameters['prompt'] ?? 'N/A'),
                      _buildInfoRow(Icons.aspect_ratio, 'Config', '${task.parameters['aspectRatio']} | ${task.parameters['imageSize']}'),
                      _buildInfoRow(Icons.check_circle_outline, 'Finished', _formatTime(task.endTime)),
                    ],
                  ),
                ),
              ],
            ),
            if (task.logs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Latest Log:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
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

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
