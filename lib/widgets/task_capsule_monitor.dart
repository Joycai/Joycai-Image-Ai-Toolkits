import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../services/task_queue_service.dart';

class TaskCapsuleMonitor extends StatefulWidget {
  const TaskCapsuleMonitor({super.key});

  @override
  State<TaskCapsuleMonitor> createState() => _TaskCapsuleMonitorState();
}

class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor> {
  bool _isExpanded = false;
  Offset? _offset;

  void _initPosition(Size screenSize, bool isMobile) {
    if (_offset != null) return;
    if (isMobile) {
      // Bottom Center for Mobile
      _offset = Offset(16, screenSize.height - 160);
    } else {
      // Bottom Right for Desktop
      _offset = Offset(screenSize.width - 320, screenSize.height - 100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    final screenSize = MediaQuery.of(context).size;

    _initPosition(screenSize, isMobile);

    // Calculate task stats
    final pendingCount = appState.taskQueue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = appState.taskQueue.runningCount;
    final activeTasks = appState.taskQueue.queue.where((t) => t.status == TaskStatus.processing).toList();
    
    if (pendingCount == 0 && runningCount == 0) return const SizedBox.shrink();

    double avgProgress = 0;
    if (activeTasks.isNotEmpty) {
      double total = 0;
      int count = 0;
      for (var t in activeTasks) {
        if (t.progress != null) {
          total += t.progress!;
          count++;
        }
      }
      if (count > 0) avgProgress = total / count;
    }

    final capsuleWidth = isMobile ? (screenSize.width - 32) : (_isExpanded ? 300.0 : 180.0);

    return Positioned(
      left: _offset!.dx,
      top: _offset!.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset = Offset(
              (_offset!.dx + details.delta.dx).clamp(0, screenSize.width - capsuleWidth),
              (_offset!.dy + details.delta.dy).clamp(0, screenSize.height - 80),
            );
          });
        },
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Material( // Fixes yellow underline
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: capsuleWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(180),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Animated Spinner / Icon
                        _buildStatusIcon(runningCount, avgProgress, colorScheme),
                        const SizedBox(width: 12),
                        // Text Label
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                runningCount > 0 
                                  ? l10n.runningCount(runningCount)
                                  : l10n.plannedCount(pendingCount),
                                style: TextStyle(
                                  fontSize: 13, 
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurfaceVariant
                                ),
                              ),
                              if (pendingCount > 0 && runningCount > 0)
                                Text(
                                  l10n.plannedCount(pendingCount),
                                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                ),
                            ],
                          ),
                        ),
                        // Percentage
                        if (runningCount > 0)
                          Text(
                            "${(avgProgress * 100).toInt()}%",
                            style: TextStyle(
                              fontSize: 13, 
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                    // Progress Bar (Linear)
                    if (runningCount > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: avgProgress,
                          minHeight: 3,
                          backgroundColor: colorScheme.surfaceContainer,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        ),
                      ),
                    ],
                    // Expanded Details
                    if (_isExpanded) ...[
                      const Divider(height: 20),
                      ...activeTasks.take(3).map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.image_outlined, size: 14, color: colorScheme.outline),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t.modelId,
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (t.status == TaskStatus.processing)
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                          ],
                        ),
                      )),
                      TextButton(
                        onPressed: () {
                          appState.navigateToScreen(2); // Tasks screen index
                          setState(() => _isExpanded = false);
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(l10n.viewAll, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(int runningCount, double progress, ColorScheme colorScheme) {
    if (runningCount > 0) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              backgroundColor: colorScheme.surfaceContainer,
            ),
            Icon(Icons.auto_awesome, size: 12, color: colorScheme.primary),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.layers_outlined, size: 16, color: colorScheme.outline),
    );
  }
}
