import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/file_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/tasks/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/glass/app_glass_menu.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/tasks/smooth_progress.dart';
import '../../widgets/tasks/task_type_glyph.dart';
import '../../widgets/ui/app_breathing_dot.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_section_label.dart';
import '../../widgets/ui/app_snackbar.dart';
import '../../widgets/ui/dashed_border.dart';
import '../../widgets/ui/scroll_edge_fade.dart';
import 'task_log_dialog.dart';

part 'task_card/task_card_cells.dart';
part 'task_card/task_card_details.dart';
part 'task_card/task_card_menu.dart';

// ════════════════════════════════════════════════════════════════════════════
// Shared vocabulary — `B2` 颜色角色 / 尺寸
// ════════════════════════════════════════════════════════════════════════════

/// What a status is called on its pill. Cancelled carries its cause, because
/// the filter strip files it under 失败 and the pill is where the two part.
String taskStatusLabel(TaskStatus status, AppLocalizations l10n) => switch (status) {
  TaskStatus.processing => l10n.processingTasks,
  TaskStatus.pending => l10n.pendingTasks,
  TaskStatus.completed => l10n.completedTasks,
  TaskStatus.failed => l10n.failedTasks,
  TaskStatus.cancelled => l10n.cancelledByUser,
};

/// The status column's width: the widest of the five pills in this locale at
/// this text scale.
///
/// One width for every row, so the facts after the pill start on one line
/// down the whole list whatever each row's own status is — and a row that
/// changes status does not shift its facts sideways.
double taskStatusColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final style = Theme.of(context).textTheme.labelSmall!;
  double widest = 0;
  for (final status in TaskStatus.values) {
    final double dot = status == TaskStatus.processing
        ? TaskStatusPill.dotSize + TaskStatusPill.dotGap
        : 0;
    final width =
        measureGlassText(context, taskStatusLabel(status, l10n), style) +
        dot +
        TaskStatusPill.padX * 2;
    if (width > widest) widest = width;
  }
  return widest.ceilToDouble();
}

/// `00:42`, or `1:02:07` past the hour.
String formatTaskDuration(Duration duration) {
  String two(int v) => v.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// A wall-clock time in the detail table; `--:--` for one that has not
/// happened, so the table's rows do not appear and vanish as a task runs.
String formatTaskClock(DateTime? time) {
  if (time == null) return '--:--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Start to finish, for a task that has both.
String? taskElapsed(TaskItem task) {
  if (task.startTime == null || task.endTime == null) return null;
  return formatTaskDuration(task.endTime!.difference(task.startTime!));
}

/// The facts a collapsed row states after its pill (`B2` 事实行), each short
/// and indivisible. [position] is the task's 1-based place among the pending
/// tasks, 0 when it has none.
///
/// No retry count: [TaskItem] does not record one, and a figure the app does
/// not track is not a fact.
List<String> taskFacts(TaskItem task, int position, AppLocalizations l10n) {
  final elapsed = taskElapsed(task);
  return [
    if (task.imagePaths.length > 1) l10n.filesCount(task.imagePaths.length),
    if (task.status == TaskStatus.pending && position > 0) l10n.queuedPosition(position),
    // The image task is the ordinary case; naming the others says what the
    // plate's glyph means without a legend.
    if (task.type != TaskType.imageProcess) task.type.name,
    if (task.status == TaskStatus.processing) ...[
      if (task.progress != null) '${(task.progress! * 100).round()}%',
      if (task.startTime != null) formatTaskDuration(DateTime.now().difference(task.startTime!)),
    ],
    if ((task.status == TaskStatus.completed || task.status == TaskStatus.failed) &&
        elapsed != null)
      l10n.tookDuration(elapsed),
  ];
}

/// The line a collapsed row shows under `Latest log`: the newest line, or on a
/// failure the newest line that names an error — the tail of a failed task is
/// usually the bookkeeping after the cause, not the cause.
String taskLatestLog(TaskItem task) {
  if (task.logs.isEmpty) return '';
  final line = task.status == TaskStatus.failed
      ? task.logs.lastWhere((l) => l.contains('Error'), orElse: () => task.logs.last)
      : task.logs.last;
  return line.replaceFirst(_logStamp, '');
}

/// A leading `[HH:MM:SS]` on a log line.
final RegExp _logStamp = RegExp(r'^\s*\[[^\]]{1,12}\]\s*');

bool _isActive(TaskItem task) =>
    task.status == TaskStatus.pending || task.status == TaskStatus.processing;

bool _isTerminal(TaskItem task) =>
    task.status == TaskStatus.completed ||
    task.status == TaskStatus.failed ||
    task.status == TaskStatus.cancelled;

/// Mono 11 — facts, log lines, parameters.
TextStyle _mono11(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

/// Mono 12 — the model id, the queue number, fact-table values.
TextStyle _mono12(BuildContext context) => Theme.of(context).textTheme.bodySmall!.mono;

// ════════════════════════════════════════════════════════════════════════════
// Card
// ════════════════════════════════════════════════════════════════════════════

/// One task (`B2 · 1a` 卡 / `1c` 紧凑任务卡): a panel at r10 with a hairline,
/// a head that toggles the detail below it, and the progress edge pinned to
/// the head's bottom.
///
/// Stateless: whether it is open is [expanded], owned by the screen and keyed
/// by task id, so a card that crosses the pinned seam or is rebuilt by the
/// list builder keeps its state.
///
/// A failure tints the **head only**. Run the wash through the detail and the
/// log and parameters below read as part of the failure rather than as the
/// explanation of it.
class TaskQueueCard extends StatelessWidget {
  const TaskQueueCard({
    super.key,
    required this.task,
    required this.position,
    required this.expanded,
    required this.onToggle,
    required this.statusColumnWidth,
    this.compact = false,
  });

  final TaskItem task;

  /// 1-based place among the pending tasks; 0 when not waiting.
  final int position;
  final bool expanded;
  final VoidCallback onToggle;

  /// See [taskStatusColumnWidth]. Unused by the [compact] form.
  final double statusColumnWidth;

  /// The phone card: two lines plus optional log and output rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // A running card is the only one that has anything to say twice a second:
    // its progress edge, its percentage and its elapsed time. It subscribes
    // to [TaskQueueService.progressTick] itself, so the screen above it — the
    // filter, the sort, the queue-position pass and every other card — is out
    // of that loop entirely. The concurrency limit bounds how many cards are
    // in it at once.
    if (task.status != TaskStatus.processing) return _buildCard(context);
    return ValueListenableBuilder<int>(
      valueListenable: Provider.of<TaskQueueService>(context, listen: false).progressTick,
      builder: (context, _, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = task.status == TaskStatus.failed;

    final Widget head = compact
        ? _CompactHead(task: task, position: position)
        : _RowHead(task: task, position: position, statusColumnWidth: statusColumnWidth);

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: failed ? scheme.errorContainer : Colors.transparent,
            child: Semantics(
              expanded: expanded,
              child: InkWell(
                onTap: onToggle,
                child: Stack(
                  children: [
                    head,
                    Positioned(left: 0, right: 0, bottom: 0, child: _ProgressEdge(task: task)),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) TaskExpandedDetails(task: task),
        ],
      ),
    );
  }
}

/// The desktop / tablet head: a 56px row whose height nothing inside it can
/// change.
///
/// Columns: plate 32 · model 210 · status (list-wide width) · facts · latest
/// log (flex) · outputs 176 · ⋮ 28, 12 apart. What gives way is decided by
/// measuring against the width the row actually gets: the log is the flex and
/// shrinks first; the facts are dropped whole when they no longer fit beside
/// a sliver of log; only then does the model column narrow.
class _RowHead extends StatelessWidget {
  const _RowHead({required this.task, required this.position, required this.statusColumnWidth});

  final TaskItem task;
  final int position;
  final double statusColumnWidth;

  static const double height = 56;
  static const double _padX = 12;
  static const double _gap = 12;
  static const double _plate = 32;
  static const double _model = 210;

  /// The model column never narrows past this: below it an id is an ellipsis.
  static const double _modelMin = 96;

  /// What the log keeps before the model column starts giving width up.
  static const double _logMin = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final failed = task.status == TaskStatus.failed;
    final mono11 = _mono11(context);
    final facts = taskFacts(task, position, l10n).join(' · ');
    final log = taskLatestLog(task);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final inner = box.maxWidth - _padX * 2;
          final fixedBesideModel =
              _plate + statusColumnWidth + TaskOutputs.columnWidth + _RowIconButton.size + _gap * 5;
          final modelWidth = (inner - fixedBesideModel - _logMin)
              .clamp(_modelMin, _model)
              .toDouble();
          final flexRoom = inner - fixedBesideModel - modelWidth;
          final factsWidth = facts.isEmpty
              ? 0.0
              : measureGlassText(context, facts, mono11).ceilToDouble();
          final showFacts = factsWidth > 0 && factsWidth + (log.isEmpty ? 0 : _gap) <= flexRoom;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padX),
            child: Row(
              children: [
                TaskLeadingPlate(task: task, position: position, size: _plate),
                const SizedBox(width: _gap),
                SizedBox(
                  width: modelWidth,
                  child: _ModelAndChannel(task: task),
                ),
                const SizedBox(width: _gap),
                SizedBox(
                  width: statusColumnWidth,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TaskStatusPill(status: task.status),
                  ),
                ),
                const SizedBox(width: _gap),
                Expanded(
                  child: Row(
                    children: [
                      if (showFacts)
                        Text(
                          facts,
                          maxLines: 1,
                          softWrap: false,
                          style: mono11.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      if (showFacts && log.isNotEmpty) const SizedBox(width: _gap),
                      if (log.isNotEmpty)
                        Expanded(
                          child: Text(
                            log,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: mono11.copyWith(
                              color: failed ? scheme.onErrorContainer : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: _gap),
                SizedBox(
                  width: TaskOutputs.columnWidth,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TaskOutputs(task: task),
                  ),
                ),
                const SizedBox(width: _gap),
                TaskMenuButton(task: task),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The phone head (`B2 · 1c`, pad 10/10/12): plate 28 · model · pill · ⋮ on
/// the first line; channel and facts on the second; the latest log while a
/// task runs or after it fails; its outputs once it has some.
class _CompactHead extends StatelessWidget {
  const _CompactHead({required this.task, required this.position});

  final TaskItem task;
  final int position;

  static const double _plate = 28;
  static const double _plateGap = AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final failed = task.status == TaskStatus.failed;
    final mono11 = _mono11(context);
    final channel = task.channelTag;
    final facts = taskFacts(task, position, l10n).join(' · ');
    final log = (task.status == TaskStatus.processing || failed) ? taskLatestLog(task) : '';
    const indent = EdgeInsetsDirectional.only(start: _plate + _plateGap);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TaskLeadingPlate(task: task, position: position, size: _plate),
              const SizedBox(width: _plateGap),
              Expanded(
                child: Text(
                  task.modelId,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _mono12(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              TaskStatusPill(status: task.status),
              const SizedBox(width: AppSpace.s4),
              TaskMenuButton(task: task),
            ],
          ),
          if (channel != null || facts.isNotEmpty)
            Padding(
              padding: indent.add(const EdgeInsets.only(top: 2)),
              child: Row(
                children: [
                  if (channel != null) ...[
                    _ChannelDot(task: task),
                    const SizedBox(width: AppSpace.s6),
                  ],
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (channel != null)
                            TextSpan(
                              text: channel,
                              style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w400),
                            ),
                          if (channel != null && facts.isNotEmpty) const TextSpan(text: ' · '),
                          if (facts.isNotEmpty) TextSpan(text: facts, style: mono11),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono11.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          if (log.isNotEmpty)
            Padding(
              padding: indent.add(const EdgeInsets.only(top: AppSpace.s4)),
              child: Text(
                log,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: mono11.copyWith(
                  color: failed ? scheme.onErrorContainer : scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (task.resultPaths.isNotEmpty)
            Padding(
              padding: indent.add(const EdgeInsets.only(top: 8)),
              child: TaskOutputs(task: task),
            ),
        ],
      ),
    );
  }
}
