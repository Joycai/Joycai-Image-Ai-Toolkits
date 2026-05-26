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
    final appState = Provider.of<AppState>(context);
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
              appState.setConsoleExpanded(!appState.isConsoleExpanded);
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
                _buildStatusIndicator(appState),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.executionLogs,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                // Task Summary for Mobile
                if (isMobile) ...[
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildTaskSummary(appState, l10n, colorScheme),
                  ),
                ],

                const Spacer(),
                
                if (!isMobile && appState.logs.isNotEmpty)
                  Expanded(
                    child: Text(
                      appState.logs.last.message,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', overflow: TextOverflow.ellipsis),
                      maxLines: 1,
                    ),
                  ),
                
                Icon(
                  isMobile 
                    ? Icons.assignment_outlined
                    : (appState.isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                  size: 16,
                  color: isMobile ? colorScheme.primary : null,
                ),
              ],
            ),
          ),
        ),

        // Expanded Console (Desktop/Tablet only)
        if (!isMobile && appState.isConsoleExpanded) ...[
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

  Widget _buildStatusIndicator(AppState appState) {
    final isRunning = appState.taskQueue.runningCount > 0;
    final hasError = appState.logs.any((l) => l.level == 'ERROR');

    Color color = Colors.grey;
    if (isRunning) color = Colors.green;
    if (hasError) color = Colors.red;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isRunning ? [
          BoxShadow(color: color.withAlpha(100), blurRadius: 4, spreadRadius: 1),
        ] : null,
      ),
    );
  }

  Widget _buildTaskSummary(AppState appState, AppLocalizations l10n, ColorScheme colorScheme) {
    final pendingCount = appState.taskQueue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = appState.taskQueue.runningCount;

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
