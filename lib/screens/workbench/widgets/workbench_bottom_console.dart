import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/task_queue_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/log_console.dart';
import '../../batch/task_queue_screen.dart';

class WorkbenchBottomConsole extends StatefulWidget {
  const WorkbenchBottomConsole({super.key});

  @override
  State<WorkbenchBottomConsole> createState() => _WorkbenchBottomConsoleState();
}

class _WorkbenchBottomConsoleState extends State<WorkbenchBottomConsole> {
  double _height = 200;

  @override
  Widget build(BuildContext context) {
    final isConsoleExpanded = context.select<AppState, bool>((s) => s.isConsoleExpanded);
    final hasErrors = context.select<AppState, bool>((s) => s.hasErrors);
    final isProcessing = context.select<AppState, bool>((s) => s.isProcessing);
    final lastLogMessage = context.select<AppState, String?>((s) => s.logs.isEmpty ? null : s.logs.last.message);
    final queue = context.watch<TaskQueueService>();
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Responsive.isMobile(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status Bar (Clickable to toggle or show sheet)
        InkWell(
          onTap: () {
            if (isMobile) {
              _showTaskQueueSheet(context);
            } else {
              context.read<AppState>().setConsoleExpanded(!isConsoleExpanded);
            }
          },
          child: Container(
            height: 36, // Slightly taller for mobile tap target
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatusIndicator(isProcessing, hasErrors),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.executionLogs,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis, maxLines: 1,
                  ),
                ),
                
                // Task Summary for Mobile
                if (isMobile) ...[
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildTaskSummary(queue, l10n, colorScheme),
                  ),
                ],

                const Spacer(),
                
                if (!isMobile && lastLogMessage != null)
                  Expanded(
                    child: Text(
                      lastLogMessage,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', overflow: TextOverflow.ellipsis),
                      maxLines: 1,
                    ),
                  ),

                Icon(
                  isMobile
                    ? Icons.assignment_outlined
                    : (isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                  size: 16,
                  color: isMobile ? colorScheme.primary : null,
                ),
              ],
            ),
          ),
        ),

        // Expanded Console (Desktop/Tablet only)
        if (!isMobile && isConsoleExpanded) ...[
          GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _height = (_height - details.delta.dy).clamp(100.0, 600.0);     
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Container(
                height: 4,
                width: double.infinity,
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
          ),
          SizedBox(
            height: _height,
            child: const LogConsoleWidget(),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusIndicator(bool isProcessing, bool hasErrors) {
    Color color = Colors.grey;
    if (isProcessing) color = Colors.green;
    if (hasErrors) color = Colors.red;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isProcessing ? [
          BoxShadow(color: color.withAlpha(100), blurRadius: 4, spreadRadius: 1),
        ] : null,
      ),
    );
  }

  Widget _buildTaskSummary(TaskQueueService queue, AppLocalizations l10n, ColorScheme colorScheme) {
    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = queue.runningCount;

    if (pendingCount == 0 && runningCount == 0) {
      return Text(
        l10n.noTasks,
        style: TextStyle(fontSize: 11, color: colorScheme.outline),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (runningCount > 0) ...[
          Icon(Icons.sync, size: 14, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            "$runningCount",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
        ],
        if (pendingCount > 0) ...[
          Icon(Icons.schedule, size: 14, color: colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            "$pendingCount",
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ],
      ],
    );
  }

  void _showTaskQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return const TaskQueueScreen();
        },
      ),
    );
  }
}
