import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/app_theme.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../services/task_queue_service.dart';
import '../state/app_state.dart';
import 'app_button.dart';

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
    final queue = context.watch<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    final screenSize = MediaQuery.sizeOf(context);

    _initPosition(screenSize, isMobile);

    // Calculate task stats
    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = queue.runningCount;
    final activeTasks = queue.queue.where((t) => t.status == TaskStatus.processing).toList();
    
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
            duration: AppMotion.durationOf(context, AppMotion.reveal),
            curve: AppMotion.move,
            width: capsuleWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              // `12g` floats this at 92% of a near-white, not 70% of a mid
              // grey. It sits over whatever screen is behind it — a gallery, a
              // task list — so it has to read as something laid on top; a grey
              // at 70% reads as a smudge on the content instead.
              color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
              // dialog, not the 24 this shipped with: 24 is on no rung of
              // AppRadius, and the capsule is a floating overlay — the one
              // class of shape allowed to be rounder than a card.
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              border: Border.all(color: colorScheme.surfaceContainerHigh),
              boxShadow: colorScheme.shadowOverlay,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              // No backdrop blur here: the 92%-opaque fill above hides what a
              // blur would show, while the blur still cost a full backdrop
              // readback every frame the capsule was on screen.
              child: AnimatedSize(
                duration: AppMotion.durationOf(context, AppMotion.reveal),
                curve: AppMotion.move,
                alignment: Alignment.topCenter,
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
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                ),
                              ),
                              if (pendingCount > 0 && runningCount > 0)
                                Text(
                                  l10n.plannedCount(pendingCount),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                            ],
                          ),
                        ),
                        // Percentage
                        if (runningCount > 0)
                          Text(
                            "${(avgProgress * 100).toInt()}%",
                            // Mono: this number ticks while the user watches
                            // it, and a proportional face shifts the chevron
                            // beside it every time a digit changes width.
                            style: Theme.of(context).textTheme.titleSmall?.mono.copyWith(
                              color: colorScheme.onAccentTint,
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
                                style: Theme.of(context).textTheme.labelMedium,
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
                      AppButton(
                        label: l10n.viewAll,
                        variant: AppButtonVariant.text,
                        size: AppButtonSize.compact,
                        onPressed: () {
                          context.read<AppState>().navigateToScreen(2);
                          setState(() => _isExpanded = false);
                        },
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
