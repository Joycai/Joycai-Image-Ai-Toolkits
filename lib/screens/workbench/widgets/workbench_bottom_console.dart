import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/log_console.dart';

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status Bar (Clickable to toggle)
        InkWell(
          onTap: () => appState.setConsoleExpanded(!appState.isConsoleExpanded),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatusIndicator(appState),
                const SizedBox(width: 8),
                Text(
                  l10n.executionLogs,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (appState.logs.isNotEmpty)
                  Expanded(
                    child: Text(
                      appState.logs.last.message,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', overflow: TextOverflow.ellipsis),
                      maxLines: 1,
                    ),
                  ),
                Icon(
                  appState.isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 16,
                ),
              ],
            ),
          ),
        ),

        // Expanded Console
        if (appState.isConsoleExpanded) ...[
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
}
