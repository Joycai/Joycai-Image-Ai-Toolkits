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
import '../../core/task_type_glyph.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/app_breathing_dot.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_section_label.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/dialogs/task_log_dialog.dart';
import '../../widgets/glass/app_glass_menu.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/scroll_edge_fade.dart';
import '../../widgets/smooth_progress.dart';

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
    final width = measureGlassText(context, taskStatusLabel(status, l10n), style) +
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
    if ((task.status == TaskStatus.completed || task.status == TaskStatus.failed) && elapsed != null)
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
// Status pill
// ════════════════════════════════════════════════════════════════════════════

/// `B2` 状态胶囊: r4, 2/8, 11/500, each status on its own container pair.
/// Running is the accent's 12% form with the breathing dot — the one loop the
/// system allows, and it stops under reduce-motion and reduce-visual-effects.
class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill({super.key, required this.status});

  final TaskStatus status;

  static const double padX = 8;
  static const double dotSize = 6;
  static const double dotGap = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    final (Color background, Color ink) = switch (status) {
      TaskStatus.processing => (scheme.accentTint, scheme.onAccentTint),
      TaskStatus.pending => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      TaskStatus.completed => (semantic.successContainer, semantic.onSuccessContainer),
      TaskStatus.failed => (scheme.errorContainer, scheme.onErrorContainer),
      TaskStatus.cancelled => (semantic.warningContainer, semantic.onWarningContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: padX, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == TaskStatus.processing) ...[
            AppBreathingDot(color: scheme.primary, size: dotSize),
            const SizedBox(width: dotGap),
          ],
          Text(
            taskStatusLabel(status, l10n),
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Leading plate
// ════════════════════════════════════════════════════════════════════════════

/// The type glyph on its identity plate — or, while the task waits, its place
/// in the queue on the track colour (`B2`: 等待中用排队序号替掉图标).
///
/// The number replaces the glyph rather than joining it: the glyph only
/// restates the kind of task, and the place in the queue is the one thing
/// about waiting that moves.
class TaskLeadingPlate extends StatelessWidget {
  const TaskLeadingPlate({
    super.key,
    required this.task,
    required this.position,
    this.size = 32,
  });

  final TaskItem task;
  final int position;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final radius = BorderRadius.circular(AppRadius.sm);

    if (task.status == TaskStatus.pending && position > 0) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: radius),
        // A three-digit queue still fits the plate rather than overflowing it.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '#$position',
            style: _mono12(context).copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Identity colours: which kind of work a row is does not change with the
    // outcome, so the plate stays put while the pill beside it moves.
    final (Color background, Color ink) = switch (task.type) {
      TaskType.imageProcess => (semantic.infoContainer, semantic.onInfoContainer),
      TaskType.videoGenerate => (scheme.errorContainer, scheme.onErrorContainer),
      TaskType.promptRefine => (scheme.accentTint, scheme.onAccentTint),
      TaskType.aiRename => (semantic.warningContainer, semantic.onWarningContainer),
      TaskType.imageDownload => (semantic.successContainer, semantic.onSuccessContainer),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: Icon(
        task.type.glyph,
        size: size >= 32 ? AppSize.iconMd : AppSize.iconSm,
        color: ink,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Model + channel
// ════════════════════════════════════════════════════════════════════════════

class _ChannelDot extends StatelessWidget {
  const _ChannelDot({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // The channel's own tag colour — identity, never the accent.
          color: Color(task.channelColor ?? AppConstants.defaultTagColor),
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(dimension: 6),
      );
}

/// Mono 12/600 model id over a 6px channel dot and the channel's name.
class _ModelAndChannel extends StatelessWidget {
  const _ModelAndChannel({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final channel = task.channelTag;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.modelId,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: _mono12(context).copyWith(
            fontWeight: FontWeight.w600,
            color: task.status == TaskStatus.cancelled ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        if (channel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              _ChannelDot(task: task),
              const SizedBox(width: AppSpace.s6),
              Flexible(
                child: Text(
                  channel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Outputs
// ════════════════════════════════════════════════════════════════════════════

/// What the task produced (`B2` 产物列): up to three 40px thumbnails and a
/// `+N` pill; a failure's grey plate with a cross where a result should have
/// been; a dashed slot where nothing is due yet.
///
/// Deliberately only *outputs* — a source image in the slot a result
/// normally fills is the one picture on this screen that must not be
/// ambiguous about which it is.
class TaskOutputs extends StatelessWidget {
  const TaskOutputs({super.key, required this.task});

  final TaskItem task;

  /// The fixed desktop column the outputs are right-aligned in, so every
  /// row's menu sits on one vertical line whatever the row produced.
  static const double columnWidth = 176;
  static const double tileSize = 40;
  static const double _gap = AppSpace.s4;
  static const int _maxThumbs = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.sm);

    if (task.resultPaths.isNotEmpty) {
      final shown = task.resultPaths.take(_maxThumbs).toList();
      final more = task.resultPaths.length - shown.length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            ClipRRect(borderRadius: radius, child: _Thumbnail(path: shown[i])),
          ],
          if (more > 0) ...[
            const SizedBox(width: _gap),
            Container(
              height: tileSize,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '+$more',
                  style: _mono11(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    if (task.status == TaskStatus.failed) {
      return Container(
        width: tileSize,
        height: tileSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
        child: Icon(Icons.close, size: AppSize.iconMd, color: scheme.outline),
      );
    }

    return SizedBox.square(
      dimension: tileSize,
      child: DashedBorder(color: scheme.outlineVariant, radius: AppRadius.sm),
    );
  }
}

/// One 40px square of [path], decoded at the size it is drawn.
///
/// `cacheWidth` matters: without it a 40px chip held a full 2K generation in
/// the image cache, and a handful of finished tasks pushed every visible
/// thumbnail back onto the decoder while scrolling.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const double size = TaskOutputs.tileSize;
    return Image.file(
      File(path),
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Progress edge
// ════════════════════════════════════════════════════════════════════════════

/// The 3px edge along the bottom of a row head (`B2`: 进度 = 贴行底 3px 细边，
/// 绝对定位不占行高).
///
/// Positioned by the card rather than laid out in the row: a task that starts
/// running must not make its row taller, which on a working queue is every
/// row below it jumping down and back up. A failed task that stopped part way
/// keeps its residue in the error colour.
class _ProgressEdge extends StatelessWidget {
  const _ProgressEdge({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = task.status == TaskStatus.processing;
    final residue = task.status == TaskStatus.failed && (task.progress ?? 0) > 0;
    if (!running && !residue) return const SizedBox.shrink();

    return SmoothProgress(
      value: task.progress,
      builder: (context, value) => LinearProgressIndicator(
        value: running ? value : task.progress,
        minHeight: 3,
        borderRadius: BorderRadius.zero,
        backgroundColor: scheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(running ? scheme.primary : scheme.error),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Row menu
// ════════════════════════════════════════════════════════════════════════════

/// A 28px glyph button inside a row, r6 — the row is the container here, so
/// this is a control inside one, not a boxed one on the canvas.
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  static const double size = AppSize.compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: AppSize.iconMd),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(size),
          minimumSize: const Size.square(size),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: selected ? scheme.onAccentTint : scheme.onSurfaceVariant,
          backgroundColor: selected ? scheme.accentTint : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
    );
  }
}

/// A task's ⋮ (`B2 · 1b`): view log · retry · copy prompt, a hairline, then
/// remove and cancel. Each entry appears only where it can act.
class TaskMenuButton extends StatefulWidget {
  const TaskMenuButton({super.key, required this.task});

  final TaskItem task;

  @override
  State<TaskMenuButton> createState() => _TaskMenuButtonState();
}

/// `B2 · 1b` 任务 ⋮ 菜单: G2 glass, 210 wide, dropping from the button.
class _TaskMenuButtonState extends State<TaskMenuButton> {
  /// Open, so the button keeps its lens while the menu is up.
  bool _open = false;

  static const double _menuWidth = 210;

  Future<void> _openMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;

    final canCancel = _isActive(task);
    final canRetry = task.status == TaskStatus.failed || task.status == TaskStatus.cancelled;
    final canRemove = _isTerminal(task);
    final hasPrompt = task.parameters.containsKey('prompt');

    setState(() => _open = true);
    await showAppGlassMenu(
      context,
      position: appGlassMenuPositionBelow(context, width: _menuWidth),
      width: _menuWidth,
      entries: [
        // First and unconditional: every status has a use for it, and a
        // running task's log tails live in the dialog.
        AppGlassMenuItem(
          icon: Icons.article_outlined,
          label: l10n.viewTaskLog,
          onSelected: () {
            if (mounted) TaskLogDialog.show(context, task);
          },
        ),
        if (canRetry)
          AppGlassMenuItem(
            icon: Icons.refresh,
            label: l10n.retryTask,
            onSelected: () => queue.retryTask(task.id),
          ),
        if (hasPrompt)
          AppGlassMenuItem(
            icon: Icons.content_copy,
            label: l10n.copyPrompt,
            onSelected: () {
              final prompt = '${task.parameters['prompt'] ?? ''}';
              Clipboard.setData(ClipboardData(text: prompt));
              if (!mounted) return;
              AppSnackBar.info(
                context,
                l10n.copiedToClipboard(prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt),
              );
            },
          ),
        if (canRemove || canCancel) const AppGlassMenuDivider(),
        if (canRemove)
          AppGlassMenuItem(
            icon: Icons.playlist_remove,
            label: l10n.removeFromList,
            onSelected: () => queue.removeTask(task.id),
          ),
        if (canCancel)
          AppGlassMenuItem(
            icon: Icons.cancel_outlined,
            label: l10n.cancelTask,
            danger: true,
            onSelected: () => queue.cancelTask(task.id),
          ),
      ],
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _RowIconButton(
      icon: Icons.more_vert,
      tooltip: l10n.more,
      selected: _open,
      onPressed: _openMenu,
    );
  }
}

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
  const _RowHead({
    required this.task,
    required this.position,
    required this.statusColumnWidth,
  });

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
          final fixedBesideModel = _plate +
              statusColumnWidth +
              TaskOutputs.columnWidth +
              _RowIconButton.size +
              _gap * 5;
          final modelWidth = (inner - fixedBesideModel - _logMin).clamp(_modelMin, _model).toDouble();
          final flexRoom = inner - fixedBesideModel - modelWidth;
          final factsWidth = facts.isEmpty ? 0.0 : measureGlassText(context, facts, mono11).ceilToDouble();
          final showFacts = factsWidth > 0 && factsWidth + (log.isEmpty ? 0 : _gap) <= flexRoom;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padX),
            child: Row(
              children: [
                TaskLeadingPlate(task: task, position: position, size: _plate),
                const SizedBox(width: _gap),
                SizedBox(width: modelWidth, child: _ModelAndChannel(task: task)),
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

// ════════════════════════════════════════════════════════════════════════════
// Expanded detail — `B2 · 1a` 展开区
// ════════════════════════════════════════════════════════════════════════════

/// What a card opens onto: the fact table and the things to do about the task
/// on the left (340), and the request, its outputs and its log on the right —
/// each an inset card on the column colour. Stacked where the two will not
/// both fit.
class TaskExpandedDetails extends StatelessWidget {
  const TaskExpandedDetails({super.key, required this.task});

  final TaskItem task;

  static const double _factsWidth = 340;
  static const double _gap = 14;

  /// The narrowest the right-hand cards read as cards rather than as a
  /// column of wrapped words.
  static const double _paneMin = 280;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, box) {
            final left = _FactsAndActions(task: task);
            final right = _DetailPanes(task: task);
            if (box.maxWidth >= _factsWidth + _gap + _paneMin) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: _factsWidth, child: left),
                  const SizedBox(width: _gap),
                  Expanded(child: right),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: _gap), right],
            );
          },
        ),
      ),
    );
  }
}

class _FactsAndActions extends StatelessWidget {
  const _FactsAndActions({required this.task});

  final TaskItem task;

  /// Lines a prompt may take in the table before it is ellipsized; the whole
  /// text is one menu entry away (copy prompt).
  static const int _promptLines = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;
    final failed = task.status == TaskStatus.failed;

    final prompt = '${task.parameters['prompt'] ?? ''}';
    final config = task.type == TaskType.imageProcess
        ? '${task.parameters['aspectRatio'] ?? ''} ${task.parameters['imageSize'] ?? ''}'.trim()
        : '';
    final source = switch (task.imagePaths.length) {
      0 => '',
      1 => p.basename(task.imagePaths.first),
      final n => '${p.basename(task.imagePaths.first)} +${n - 1}',
    };

    final rows = <(String, String, int)>[
      (l10n.model, task.modelId, 1),
      (l10n.createdAt, formatTaskClock(task.createdAt), 1),
      (l10n.started, formatTaskClock(task.startTime), 1),
      (l10n.finished, formatTaskClock(task.endTime), 1),
      (l10n.durationLabel, taskElapsed(task) ?? '', 1),
      (l10n.config, config, 1),
      (l10n.sourceFiles, source, 1),
      (l10n.prompt, prompt, _promptLines),
    ].where((row) => row.$2.isNotEmpty);

    final actions = <Widget>[
      if (failed || task.status == TaskStatus.cancelled)
        AppButton(
          label: l10n.retryTask,
          icon: Icons.refresh,
          size: AppButtonSize.compact,
          // A failure's retry is the solid error fill (`B2`); a cancellation
          // is not a fault, so its retry is the neutral outline.
          variant: failed ? AppButtonVariant.destructive : AppButtonVariant.secondary,
          onPressed: () => queue.retryTask(task.id),
        ),
      if (failed && task.logs.isNotEmpty)
        AppButton(
          label: l10n.copyError,
          icon: Icons.content_copy,
          size: AppButtonSize.compact,
          variant: AppButtonVariant.secondary,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
            AppSnackBar.success(context, l10n.copiedAll);
          },
        ),
      if (_isTerminal(task))
        AppButton(
          label: l10n.removeFromList,
          icon: Icons.playlist_remove,
          size: AppButtonSize.compact,
          variant: AppButtonVariant.text,
          onPressed: () => queue.removeTask(task.id),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (key, value, lines) in rows) _FactRow(label: key, value: value, maxLines: lines),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          Wrap(spacing: AppSpace.s6, runSpacing: AppSpace.s6, children: actions),
        ],
      ],
    );
  }
}

/// An 88px grey key beside a mono value that ellipsizes.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value, this.maxLines = 1});

  final String label;
  final String value;
  final int maxLines;

  static const double keyWidth = 88;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: keyWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: _mono12(context).copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanes extends StatelessWidget {
  const _DetailPanes({required this.task});

  final TaskItem task;

  /// The log card's ceiling. A failed generation can log a hundred lines, and
  /// an open card that runs past the window takes the rest of the queue with
  /// it.
  static const double _logMaxHeight = 168;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono = _mono11(context).copyWith(height: AppType.looseHeight, color: scheme.onSurface);
    final dash = Text('—', style: mono.copyWith(color: scheme.outline));

    // The prompt is already in the fact table beside this card.
    final params = [
      for (final entry in task.parameters.entries)
        if (entry.key != 'prompt' && '${entry.value ?? ''}'.isNotEmpty) '${entry.key}: ${entry.value}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PaneCard(
          caption: l10n.requestParameters,
          child: params.isEmpty
              ? dash
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in params)
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.s10),
        _PaneCard(
          caption: l10n.outputPaths,
          trailing: task.resultPaths.isEmpty
              ? null
              : AppButton(
                  label: l10n.openInFolder,
                  icon: Icons.folder_open,
                  size: AppButtonSize.compact,
                  variant: AppButtonVariant.text,
                  onPressed: () => FileUtils.openFolder(task.resultPaths.first),
                ),
          child: task.resultPaths.isEmpty
              ? (task.status == TaskStatus.failed
                  ? Text(l10n.taskNoOutputsFailed, style: mono.copyWith(color: scheme.onSurfaceVariant))
                  : dash)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final path in task.resultPaths)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        onTap: () => FileUtils.openPath(path),
                        child: Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.s10),
        _PaneCard(
          caption: l10n.executionLogs,
          trailing: task.logs.isEmpty
              ? null
              : AppButton(
                  label: l10n.copyAll,
                  size: AppButtonSize.compact,
                  variant: AppButtonVariant.text,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
                    AppSnackBar.success(context, l10n.copiedAll);
                  },
                ),
          child: task.logs.isEmpty
              ? Text(l10n.noLogsYet, style: textTheme.bodySmall?.copyWith(color: scheme.outline))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _logMaxHeight),
                  child: ScrollEdgeFade(
                    child: SingleChildScrollView(
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [for (final line in task.logs) _LogLine(line: line)],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A card inside the open card: the column colour at r10 with a hairline, a
/// tracked caption, and whatever it holds. The caption row is always a compact
/// control tall, so a card with an action beside its caption lines up with one
/// without.
class _PaneCard extends StatelessWidget {
  const _PaneCard({required this.caption, required this.child, this.trailing});

  final String caption;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: AppSize.compact,
            child: AppSectionLabel(caption, padding: EdgeInsets.zero, trailing: trailing),
          ),
          const SizedBox(height: AppSpace.s4),
          child,
        ],
      ),
    );
  }
}

/// One log line, its `[HH:MM:SS]` set apart in the quiet tone so the message
/// is what the eye lands on; error lines in the error ink.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final String line;

  static final RegExp _stamp = RegExp(r'^\s*(\[[^\]]{1,12}\])\s*');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final match = _stamp.firstMatch(line);
    final stamp = match?.group(1);
    final message = match == null ? line : line.substring(match.end);
    final upper = message.toUpperCase();
    final isError = upper.contains('ERROR') || upper.contains('FAILED');
    final base = _mono11(context).copyWith(height: AppType.looseHeight);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stamp != null) ...[
          Text(stamp, style: base.copyWith(color: scheme.outline)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            message,
            style: base.copyWith(
              color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
