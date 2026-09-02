import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/task_type_glyph.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../services/task_list_ordering.dart';
import '../../state/app_state.dart';
import '../../state/task_list_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/scroll_edge_fade.dart';
import '../../widgets/smooth_progress.dart';
import '../../widgets/app_section_label.dart';
import '../../core/file_utils.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dialogs/task_log_dialog.dart';

/// The colour a status is spoken in, shared by a task's accent stripe, its
/// leading tile and its count in the header — so one glance down the stripes
/// answers the same question the header summary does.
Color _statusColor(TaskStatus status, ColorScheme colorScheme, AppSemanticColors semantic) =>
    switch (status) {
      TaskStatus.processing => colorScheme.primary,
      TaskStatus.pending => colorScheme.onSurfaceVariant,
      TaskStatus.completed => semantic.success,
      TaskStatus.failed => colorScheme.error,
      TaskStatus.cancelled => colorScheme.outline,
    };

/// The same five states, as *text* rather than as a fill.
///
/// Only the running one differs, and `10h` draws it that way: `primary` is the
/// colour tuned for filling a stripe or a plate, and at 13px semibold on a
/// plain surface it reads thin. `onAccentTint` is the app's answer to exactly
/// that pairing — see [AppAccent.onAccentTint] and `design-tokens.md` §4's row
/// on 分组小标题, which is the same trade in a different place.
Color _statusInk(TaskStatus status, ColorScheme colorScheme, AppSemanticColors semantic) =>
    status == TaskStatus.processing
        ? colorScheme.onAccentTint
        : _statusColor(status, colorScheme, semantic);

class TaskQueueScreen extends StatefulWidget {
  const TaskQueueScreen({super.key});

  @override
  State<TaskQueueScreen> createState() => _TaskQueueScreenState();
}

class _TaskQueueScreenState extends State<TaskQueueScreen> {
  /// Whether the phone layout's more-menu is up, so the button that opened it
  /// can wear the selected skin while it is (`C1 11c` note 03).
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    // The queue is what this screen renders, so it subscribes to the queue.
    // AppState no longer re-broadcasts queue changes — it used to, which meant
    // the 500ms progress tick rebuilt every screen in the app, not just this
    // one. `appState` stays on as the handle the helpers below reach through.
    context.watch<TaskQueueService>();
    // Filter, sort and pinning live in [TaskListState], not in this State —
    // the screen is rebuilt from scratch on every visit, and a filter kept
    // here was back on 「全部」 each time.
    final listState = context.watch<TaskListState>();
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    // Embedded presentation (workbench bottom-sheet console): the sheet already
    // paints the canvas and its own run console, so nesting another one here
    // would show a console inside the console it was opened from.
    final inBottomSheet = context.findAncestorWidgetOfExactType<BottomSheet>() != null;

    if (Responsive.isNarrow(context)) {
      return _buildMobileLayout(context, appState, listState, l10n, inBottomSheet: inBottomSheet);
    }

    final content = _buildDesktopContent(context, appState, listState, l10n);
    if (inBottomSheet) return content;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      bottomNavigationBar: const AppRunConsole(),
      body: content,
    );
  }

  // ── Mobile layout ───────────────────────────────────────────────────────────

  Widget _buildMobileLayout(
    BuildContext context,
    AppState appState,
    TaskListState listState,
    AppLocalizations l10n, {
    required bool inBottomSheet,
  }) {
    final queue = appState.taskQueue.queue;
    final tasks = listState.arrange(queue);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      bottomNavigationBar: inBottomSheet ? null : const AppRunConsole(),
      appBar: AppBar(
        // `10k` keeps the five counts on a narrow screen — set smaller and
        // abbreviated, but kept. They are the reason to open this screen, and
        // dropping them left the phone layout showing a title over a filter
        // strip that answered the same question one tap at a time.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.taskQueueManager),
            const SizedBox(height: 2),
            _buildHeaderSummary(queue, l10n, colorScheme, compact: true),
          ],
        ),
        // One button. `11c` folds the bulk actions into its menu beside the
        // sort and pin settings, and drops the refresh: the queue notifies
        // this screen itself, so that button only ever redrew what was
        // already current.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildMobileMoreButton(context, appState, listState, queue, l10n),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            // A fade at the right edge instead of `10k`'s 「›」 (`11c` note
            // 02): with the sort tools out of this strip the five pills all
            // but fit, and what is cut off says "continues" better softened
            // than pointed at.
            child: ScrollEdgeFade(
              axis: Axis.horizontal,
              extent: 36,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildFilterPills(context, queue, listState, l10n),
              ),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyOrFiltered(context, listState, queue, l10n)
                : _buildTaskList(
                    tasks,
                    const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    l10n,
                    isMobile: true,
                  ),
          ),
        ],
      ),
    );
  }

  /// The phone's more button.
  ///
  /// `showMenu` from an [AppIconButton] rather than a [PopupMenuButton]: the
  /// menu has to be told apart from the row kebabs under it, which `11c`
  /// does by giving its button the pills' selected skin while it is open —
  /// and a [PopupMenuButton] never says whether it is.
  Widget _buildMobileMoreButton(
    BuildContext context,
    AppState appState,
    TaskListState listState,
    List<TaskItem> queue,
    AppLocalizations l10n,
  ) {
    return Builder(
      builder: (buttonContext) => AppIconButton(
        icon: Icons.more_vert,
        tooltip: l10n.more,
        selected: _menuOpen,
        onPressed: () => _openMobileMenu(buttonContext, appState, listState, queue, l10n),
      ),
    );
  }

  /// `11c` note 01: a sort section of two single-choice rows, the pin switch,
  /// a hairline, then the two bulk actions the desktop header carries.
  Future<void> _openMobileMenu(
    BuildContext buttonContext,
    AppState appState,
    TaskListState listState,
    List<TaskItem> queue,
    AppLocalizations l10n,
  ) async {
    final colorScheme = Theme.of(buttonContext).colorScheme;
    final textTheme = Theme.of(buttonContext).textTheme;

    final button = buttonContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final queued = queue.where((t) => t.status == TaskStatus.pending).length;
    final finished = queue.where((t) => !isActiveTask(t)).length;

    // The chosen order wears the pills' selected fill and a check; the other
    // is plain. Radios would say the same at twice the weight, in a menu
    // whose other rows carry none.
    PopupMenuItem<String> choice({
      required String value,
      required IconData icon,
      required String label,
      required bool selected,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? colorScheme.accentTint : null,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: AppSize.iconMd,
                color: selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check, size: AppSize.iconSm, color: colorScheme.onAccentTint),
            ],
          ),
        ),
      );
    }

    PopupMenuItem<String> action({
      required String value,
      required IconData icon,
      required String label,
      required bool enabled,
      Color? color,
    }) {
      final ink = !enabled
          ? colorScheme.onSurface.withValues(alpha: AppAlpha.disabled)
          : color ?? colorScheme.onSurfaceVariant;
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: AppSize.iconMd, color: ink),
            const SizedBox(width: 10),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: ink),
            ),
          ],
        ),
      );
    }

    setState(() => _menuOpen = true);
    final selected = await showMenu<String>(
      context: buttonContext,
      position: position,
      constraints: const BoxConstraints(minWidth: 262),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            l10n.sortSection.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: AppType.trackedLabelSpacing,
              color: colorScheme.outline,
            ),
          ),
        ),
        choice(
          value: 'sort_newest',
          icon: Icons.arrow_downward_rounded,
          label: l10n.sortNewestFirst,
          selected: listState.sortOrder == TaskSortOrder.newestFirst,
        ),
        choice(
          value: 'sort_oldest',
          icon: Icons.arrow_upward_rounded,
          label: l10n.sortOldestFirst,
          selected: listState.sortOrder == TaskSortOrder.oldestFirst,
        ),
        PopupMenuItem<String>(
          value: 'toggle_pin',
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.pinActiveTasks,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // The switch is a picture of the state; the row is the control.
              IgnorePointer(
                child: AppSwitch(value: listState.pinActive, onChanged: (_) {}),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        action(
          value: 'cancel_pending',
          icon: Icons.pause,
          label: l10n.cancelAllPending,
          enabled: queued > 0,
        ),
        action(
          value: 'clear_completed',
          icon: Icons.delete_outline,
          label: l10n.clearCompleted,
          enabled: finished > 0,
          color: colorScheme.error,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);

    switch (selected) {
      case 'sort_newest':
        listState.setSortOrder(TaskSortOrder.newestFirst);
      case 'sort_oldest':
        listState.setSortOrder(TaskSortOrder.oldestFirst);
      case 'toggle_pin':
        listState.setPinActive(!listState.pinActive);
      case 'cancel_pending':
      case 'clear_completed':
        _handleBulkAction(selected!, appState.taskQueue);
      default:
        break;
    }
  }

  // ── Desktop content: header, filters and task cards on the canvas ───────────

  Widget _buildDesktopContent(
    BuildContext context,
    AppState appState,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    final queue = appState.taskQueue.queue;
    final tasks = listState.arrange(queue);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _buildHeader(context, appState, queue, l10n, colorScheme),
        ),
        // Filters on the left, the sort and pin tools on the right, one row.
        // `11a` puts them together because they answer one question — what
        // am I looking at, in what order — and keeps them out of the header
        // because the header's buttons *do* things to the queue, where these
        // only change how it is read.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: ScrollEdgeFade(
                  axis: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildFilterPills(context, queue, listState, l10n),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildSortControls(context, listState, l10n, colorScheme),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyOrFiltered(context, listState, queue, l10n)
              : _buildTaskList(
                  tasks,
                  const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  l10n,
                  isMobile: false,
                ),
        ),
      ],
    );
  }

  /// Sort direction and the pin switch — `11a` notes 02 and 03.
  ///
  /// A size down from the pills beside them and the raised style rather than
  /// the tinted: these are tools for *reading* the list, not categories of
  /// it, and at the pills' height in the pills' accent they read as three
  /// more filters. The switch is only offered under 「全部」 — every other
  /// filter shows a single status, so there is nothing for it to lift above
  /// what.
  Widget _buildSortControls(
    BuildContext context,
    TaskListState listState,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmentedControl<TaskSortOrder>(
          compact: true,
          style: AppSegmentStyle.raised,
          segments: [
            AppSegment(
              value: TaskSortOrder.newestFirst,
              icon: Icons.arrow_downward_rounded,
              label: l10n.sortNewestFirst,
            ),
            AppSegment(
              value: TaskSortOrder.oldestFirst,
              icon: Icons.arrow_upward_rounded,
              label: l10n.sortOldestFirst,
            ),
          ],
          value: listState.sortOrder,
          onChanged: listState.setSortOrder,
        ),
        if (listState.filter == TaskFilter.all) ...[
          const SizedBox(width: 16),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: () => listState.setPinActive(!listState.pinActive),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.pinActiveTasks,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 9),
                  AppSwitch(value: listState.pinActive, onChanged: listState.setPinActive),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The empty canvas: the queue's own when there is nothing at all, and the
  /// filter's when there is plenty but none of it is what was asked for.
  Widget _buildEmptyOrFiltered(
    BuildContext context,
    TaskListState listState,
    List<TaskItem> queue,
    AppLocalizations l10n,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (queue.isEmpty) return _buildEmptyState(colorScheme, l10n);
    return _buildFilteredEmptyState(context, listState, queue.length, l10n);
  }

  Widget _buildTaskList(
    ArrangedTasks tasks,
    EdgeInsets padding,
    AppLocalizations l10n, {
    required bool isMobile,
  }) {
    // Keyed by id: a task crosses the seam the moment it finishes, and the
    // key is what carries its open/closed state across with it instead of
    // handing it to whichever row now sits at its old index.
    Widget card(TaskItem task) =>
        _TaskCard(key: ValueKey(task.id), task: task, isMobile: isMobile);

    final pinned = tasks.pinned.length;
    final dividers = tasks.hasDivider ? 1 : 0;
    return ListView.builder(
      padding: padding,
      itemCount: tasks.length + dividers,
      itemBuilder: (context, index) {
        if (index < pinned) return card(tasks.pinned[index]);
        final below = index - pinned;
        if (dividers == 1 && below == 0) {
          return _GroupDivider(label: l10n.restByCreatedTime);
        }
        return card(tasks.rest[below - dividers]);
      },
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  /// Title block plus the queue-wide actions, on the canvas rather than in a
  /// card header: the actions and the filters below them govern every card on
  /// the page, so inside one card's header they would read as that card's.
  Widget _buildHeader(
    BuildContext context,
    AppState appState,
    List<TaskItem> queue,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final queued = queue.where((t) => t.status == TaskStatus.pending).length;
    final finished = queue
        .where((t) =>
            t.status == TaskStatus.completed ||
            t.status == TaskStatus.failed ||
            t.status == TaskStatus.cancelled)
        .length;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.checklist_rounded, size: 22, color: colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.taskQueueManager,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 3),
              _buildHeaderSummary(queue, l10n, colorScheme),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // No queue-settings button here any more (`11a` note 05). The
        // concurrency slider lives with the rest of the queue settings in the
        // workbench's dialog, and beside the sort tools a third slider glyph
        // on this screen read as one of them.
        OutlinedButton.icon(
          onPressed:
              queued == 0 ? null : () => _handleBulkAction('cancel_pending', appState.taskQueue),
          icon: const Icon(Icons.pause, size: 18),
          label: Text(l10n.cancelAllPending),
          style: _headerButtonStyle(colorScheme, colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed:
              finished == 0 ? null : () => _handleBulkAction('clear_completed', appState.taskQueue),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l10n.clearCompleted),
          // Filled in its own colour, unlike its neighbour: it is the one action
          // here that destroys something.
          style: _headerButtonStyle(colorScheme, colorScheme.error, filled: finished > 0),
        ),
      ],
    );
  }

  /// The queue in one line: the total, then each status that has anything in
  /// it, in that status's colour. Statuses at zero are left out — an empty
  /// count is not news, and the filter pills below already list them all.
  /// The five counts. [compact] abbreviates every label and tightens the
  /// separators, which is what `10k` does to fit them on a phone — the counts
  /// are the reason to open this screen, so the narrow layout shortens them
  /// rather than dropping them.
  Widget _buildHeaderSummary(
    List<TaskItem> queue,
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    final counts = <(String, TaskStatus)>[
      (compact ? l10n.statusShortRunning : l10n.processingTasks, TaskStatus.processing),
      (compact ? l10n.statusShortPending : l10n.pendingTasks, TaskStatus.pending),
      (compact ? l10n.statusShortDone : l10n.completedTasks, TaskStatus.completed),
      (compact ? l10n.statusShortFailed : l10n.failedTasks, TaskStatus.failed),
    ];

    final spans = <InlineSpan>[
      TextSpan(
        text: compact
            ? l10n.taskTotalShort(queue.length)
            : l10n.taskTotalCount(queue.length),
        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
      ),
    ];

    for (final (label, status) in counts) {
      final count = queue.where((t) => t.status == status).length;
      if (count == 0) continue;
      spans.add(TextSpan(
        text: compact ? ' · ' : '  ·  ',
        style: TextStyle(color: colorScheme.outline),
      ));
      spans.add(TextSpan(
        text: '$label $count',
        style: TextStyle(color: _statusInk(status, colorScheme, context.semantic), fontWeight: FontWeight.w600),
      ));
    }

    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  ButtonStyle _headerButtonStyle(ColorScheme colorScheme, Color accent, {bool filled = false}) {
    return OutlinedButton.styleFrom(
      backgroundColor: filled ? accent.withValues(alpha: 0.12) : null,
      side: BorderSide(
        color: filled ? accent.withValues(alpha: 0.5) : colorScheme.outline.withValues(alpha: 0.45),
      ),
      foregroundColor: accent,
      textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(0, appButtonMinHeight),
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
    );
  }

  // ── Filter pills ────────────────────────────────────────────────────────────

  Widget _buildFilterPills(
    BuildContext context,
    List<TaskItem> queue,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    int countOf(TaskFilter filter) => queue.where(filter.matches).length;

    final entries = <(TaskFilter, String)>[
      (TaskFilter.all, l10n.filterAll),
      (TaskFilter.running, l10n.processingTasks),
      (TaskFilter.pending, l10n.pendingTasks),
      (TaskFilter.done, l10n.completedTasks),
      (TaskFilter.failed, l10n.failedTasks),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (filter, label) in entries) ...[
          _FilterPill(
            label: label,
            count: countOf(filter),
            selected: listState.filter == filter,
            onTap: () => listState.setFilter(filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  void _handleBulkAction(String action, TaskQueueService queue) {
    if (action == 'clear_completed') {
      final toRemove = queue.queue
          .where((t) => t.status == TaskStatus.completed || t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
          .map((t) => t.id)
          .toList();
      for (final id in toRemove) { queue.removeTask(id); }
    } else if (action == 'cancel_pending') {
      final toCancel = queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (final id in toCancel) { queue.cancelTask(id); }
    } else if (action == 'clear_all') {
      final toRemove = queue.queue.where((t) => t.status != TaskStatus.processing).map((t) => t.id).toList();
      for (final id in toRemove) { queue.removeTask(id); }
    }
  }

  /// `10j`. A bare grey glyph over two lines of grey text was the one screen
  /// in the app whose empty state offered nothing to do about being empty —
  /// and this is the screen a user lands on precisely when they are waiting
  /// for something, so the way out belongs here.
  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A tinted plate rather than a floating glyph, which is how every
            // other framed icon in the app is drawn.
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.accentTint,
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                border: Border.all(color: colorScheme.accentRing),
              ),
              child: Icon(Icons.assignment_outlined,
                  size: AppSize.iconLg, color: colorScheme.onAccentTint),
            ),
            const SizedBox(height: 18),
            Text(l10n.noTasksInQueue, style: textTheme.titleMedium),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                l10n.submitTaskFromWorkbench,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: l10n.goToWorkbench,
              icon: Icons.dashboard_outlined,
              onPressed: () =>
                  Provider.of<AppState>(context, listen: false).navigateToScreen(0),
            ),
          ],
        ),
      ),
    );
  }

  /// `11d`. Empty because of the filter, not because of the queue — and the
  /// three things that say so: the header counts and the other pills keep
  /// their figures, only the chosen pill reads 0; the block is a size down
  /// from `10j`, on a grey plate rather than the accent one, since nothing
  /// is wrong; and its one action puts the filter back rather than sending
  /// the user to the workbench, which would be a way out of a screen that is
  /// not empty.
  Widget _buildFilteredEmptyState(
    BuildContext context,
    TaskListState listState,
    int total,
    AppLocalizations l10n,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = switch (listState.filter) {
      TaskFilter.running => l10n.noRunningTasks,
      TaskFilter.pending => l10n.noPendingTasks,
      TaskFilter.done => l10n.noCompletedTasks,
      TaskFilter.failed => l10n.noFailedTasks,
      TaskFilter.all => l10n.noTasksInQueue,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.filter_list_off_rounded,
                size: AppSize.iconLg,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: textTheme.titleSmall),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                l10n.filteredEmptyHint(total),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: l10n.viewAllTasks,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.compact,
              onPressed: () => listState.setFilter(TaskFilter.all),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seam between the pinned tasks and the rest — `11a` note 03.
///
/// A hairline and four grey words, and deliberately no more: the rows on
/// either side already say what they are through their stripes and glyphs,
/// and a heading over each group would be a third place stating the status.
/// Drawn only while the pin switch is on; off, the list is one run of
/// creation times and there is nothing for a seam to separate.
class _GroupDivider extends StatelessWidget {
  final String label;

  const _GroupDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget hairline() => Expanded(
          child: Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          hairline(),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(width: 12),
          hairline(),
        ],
      ),
    );
  }
}

/// The 44px dashed square standing in for an output a task has not produced.
class _EmptyOutputSlot extends StatelessWidget {
  const _EmptyOutputSlot();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: DashedBorder(
          color: Theme.of(context).colorScheme.outlineVariant,
          radius: AppRadius.md,
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Filter pill
// ════════════════════════════════════════════════════════════════════════════

/// One filter, with its count in a badge of its own rather than trailing the
/// label as text — the counts move as the queue drains, and a number that
/// changes inside a run of words drags the whole label around with it.
class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // An outline on the surface when unselected, not a grey slab. `10h` draws
    // these the way the app draws every other secondary control — the rule
    // [AppButtonVariant.secondary] states outright — and it matters more here
    // than usual: five filled grey pills in a row above a list of white cards
    // read as a second toolbar rather than as a filter that is currently off.
    //
    // Selected takes the accent ladder, label included. `primary` at 13px on a
    // 12% wash of itself is the exact case [AppAccent.onAccentTint] exists for.
    // The label dims with the count, which `10j` spells out by drawing every
    // pill of an empty queue in the quieter tone: four of the five are usually
    // zero, and at one weight the strip reads as five equal buckets rather
    // than as "everything is in 已完成".
    final Color label = selected
        ? colorScheme.onAccentTint
        : count == 0
            ? colorScheme.outline
            : colorScheme.onSurfaceVariant;

    return Material(
      color: selected ? colorScheme.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(appButtonRadius),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(appButtonRadius),
        child: Container(
          height: appButtonMinHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appButtonRadius),
            border: Border.all(
              color: selected ? colorScheme.accentRing : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                this.label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: label,
                ),
              ),
              const SizedBox(width: 9),
              _CountChip(count: count, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The number on a filter pill.
///
/// A zero is drawn quieter than a figure, which `10h` spells out with its own
/// pair of colours: four of the five pills are usually zero, and at one weight
/// the strip reads as five equal buckets rather than as "everything is in
/// 已完成". Nothing here is a state the user has to act on, so the distinction
/// is tone, not hue.
class _CountChip extends StatelessWidget {
  final int count;
  final bool selected;

  const _CountChip({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool empty = count == 0;

    final (Color fill, Color ink) = selected
        ? (colorScheme.primary.withValues(alpha: AppAlpha.ring), colorScheme.onAccentTint)
        : empty
            ? (colorScheme.surfaceContainerHigh, colorScheme.outline)
            : (colorScheme.surfaceContainerHighest, colorScheme.onSurface);

    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 20,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
              fontWeight: FontWeight.w600,
              color: ink,
            ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
/// One labelled line of a task's expanded detail.
///
/// Its own widget so the layout can be pinned without standing up the screen's
/// AppState and database — both properties below shipped wrong and neither is
/// visible from reading the call site.
class TaskInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Lines a value may occupy before it is ellipsized. A prompt is the only
  /// value long enough to reach this; the whole text stays available from the
  /// card's menu (copy prompt).
  static const int maxValueLines = 4;

  const TaskInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        // A value can run to several lines, and centering parks the icon and
        // label halfway down it — which reads as if the lines above the label
        // belonged to the row before. That is what made a prompt look like it
        // was part of the config row.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sits on the first line of text rather than the row's top edge.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodySmall,
              // maxLines is what makes the ellipsis do anything: unbounded, the
              // overflow setting is inert and the text just keeps wrapping.
              maxLines: maxValueLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Task card — an accent stripe carries the status down the list
// ════════════════════════════════════════════════════════════════════════════

class _TaskCard extends StatefulWidget {
  final TaskItem task;
  final bool isMobile;
  const _TaskCard({super.key, required this.task, required this.isMobile});

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  /// The status stripe down the row's leading edge.
  static const double _stripeWidth = 4;

  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;

    final isProcessing = task.status == TaskStatus.processing;
    final isFailed = task.status == TaskStatus.failed;
    final accent = _statusColor(task.status, colorScheme, context.semantic);

    // A card of its own rather than a PanelCard: the stripe has to reach both
    // edges, and a failed card carries a wash of its status through the surface.
    //
    // `surfaceContainerLowest` since the restyle. `C1` draws these white with a
    // hairline, and the tone matters more than it used to: the rows are the
    // only thing on this screen, so they are what has to lift off the ground
    // rather than sit level with it.
    final base = colorScheme.surfaceContainerLowest;
    // The status wash sits on the *header row*, not on the whole card. `10i`
    // draws it that way and the reason shows the moment a row is opened: run
    // it through the card and the detail panel — a log box, a column of
    // parameters — reads as part of the failure rather than as an explanation
    // of it.
    //
    // `10h` goes further and draws even the collapsed rows plain white, the
    // stripe carrying the status alone. Kept here, because that frame's list
    // has its failed row second from the top: in a queue of forty, the wash is
    // what makes one findable without reading every stripe.
    final headerWash = isFailed
        ? Color.alphaBlend(colorScheme.error.withValues(alpha: 0.06), base)
        : isProcessing
            ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.05), base)
            : base;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: base,
        // An edge as well as a fill: at white on a near-white ground the fill
        // alone stops separating them, which is the same reason every other
        // card in the app gained one.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colorScheme.surfaceContainerHigh),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Stack(
            children: [
              // The detail panel is a sibling of the header rather than a
              // child of its padding: `10i` runs its divider and its action
              // bar to the card's edges, which a panel inset by the header's
              // own gutters cannot do.
              Padding(
                padding: const EdgeInsets.only(left: _stripeWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: headerWash,
                      // One extra pixel at the bottom, for the progress sliver
                      // to sit on without touching the last line.
                      padding: EdgeInsets.fromLTRB(widget.isMobile ? 10 : 14, 14, 8, 15),
                      child: Row(
                        children: [
                          _buildLeadingTile(task, colorScheme, accent),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTitleAndMeta(task, colorScheme, l10n)),
                          const SizedBox(width: 10),
                          ..._buildTrailing(context, task, appState, colorScheme, l10n),
                        ],
                      ),
                    ),
                    if (_isExpanded)
                      _buildExpandedDetails(context, task, colorScheme, l10n),
                  ],
                ),
              ),
              // Positioned, not a Row child under an [IntrinsicHeight]. That
              // arrangement cannot measure through the [LayoutBuilder] the
              // expanded panel now uses — the same "intrinsic dimensions
              // through a layout callback" wall the workbench's config panel
              // hit. Positioned stretches to whatever the content turns out to
              // be and asks nothing of it.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _stripeWidth,
                child: ColoredBox(color: accent),
              ),
              // `10h` runs the progress along the row's bottom edge rather than
              // giving it a line of its own, and says why: a task that starts
              // running must not make its row taller. It did — every row in the
              // list below it jumped down 16px the moment one began, and back
              // up when it finished, which on a working queue is a list that
              // will not hold still.
              if (isProcessing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildProgressBar(task, colorScheme),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Leading tile: icon + tint follow status ────────────────────────────────

  Widget _buildLeadingTile(TaskItem task, ColorScheme colorScheme, Color accent) {
    // A waiting task's plate carries its place in the queue rather than a
    // glyph, per `10h`. The icon on a pending row said only "this is an image
    // task", which the row's own name already says; the number is the one
    // thing about waiting that the user actually wants to know, and it moves.
    // Zero means "not found", which a plate cannot draw — fall back to the
    // glyph rather than printing a place in the queue that is not one.
    final int position =
        task.status == TaskStatus.pending ? _queuePosition(task) : 0;

    final icon = switch (task.status) {
      TaskStatus.completed => Icons.check,
      TaskStatus.failed => Icons.warning_amber_rounded,
      // A stop square, per `11a` note 04 — cancelled is "stopped", not
      // "forbidden", and the row is grey rather than red for the same reason.
      TaskStatus.cancelled => Icons.stop_rounded,
      _ => _typeIcon(task.type),
    };

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: position == 0
          ? Icon(icon, size: 20, color: accent)
          : Text(
              '$position',
              style: Theme.of(context).textTheme.bodyMedium?.mono.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
            ),
    );
  }

  // ── Title + meta line ──────────────────────────────────────────────────────

  Widget _buildTitleAndMeta(TaskItem task, ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _taskDisplayName(task),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: task.status == TaskStatus.cancelled
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        _buildMeta(task, colorScheme, l10n),
      ],
    );
  }

  Widget _buildMeta(TaskItem task, ColorScheme colorScheme, AppLocalizations l10n) {
    // Failure info replaces the meta line — what went wrong outranks what ran.
    // Unless there is none: tasks reloaded from the database come back without
    // their logs, and a blank line says less about a failure than the model
    // that produced it does.
    final textTheme = Theme.of(context).textTheme;
    final error = task.status == TaskStatus.failed ? _errorSummary(task) : '';
    if (error.isNotEmpty) {
      return Text(
        error,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
      );
    }

    final muted = textTheme.bodySmall!.copyWith(color: colorScheme.onSurfaceVariant);
    final (marker, modelId) = _splitModelMarker(task.modelId);
    // One entry per fact, each indivisible: the marker rides with the model id
    // it qualifies, the clock with the duration it measures. What the line is
    // allowed to break between is decided here.
    final facts = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (marker != null) ...[
            _MetaBadge(label: marker, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              _shortModelId(modelId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted.mono,
            ),
          ),
        ],
      ),
    ];

    if (task.channelTag != null) {
      facts.add(_MetaBadge(
        label: task.channelTag!,
        color: Color(task.channelColor ?? AppConstants.defaultTagColor),
      ));
    }

    if (task.imagePaths.length > 1) {
      facts.add(Text(l10n.filesCount(task.imagePaths.length), style: muted));
    }

    switch (task.status) {
      case TaskStatus.pending:
        final position = _queuePosition(task);
        if (position > 0) {
          facts.add(Text(l10n.queuedPosition(position), style: muted));
        }
      // No 「用时 0:45」 on a finished row any more (`11a` note 01): the
      // row's clock is now its creation time, and a duration beside it
      // invited arithmetic between two figures that do not add up. Started,
      // finished and elapsed all live in the expanded panel.
      case TaskStatus.cancelled:
        facts.add(Text(l10n.cancelledByUser, style: muted));
      default:
        break;
    }

    // A Wrap, not a Row: on a phone the title column is ~230px and four facts
    // plus their separators do not fit on one line. A Row could only get there
    // by truncating, and every one of these is short enough that a second line
    // costs less than an ellipsis does. Wide layouts never reach the wrap point
    // and read exactly as before.
    //
    // Each dot travels with the fact in front of it, so a line that wraps opens
    // on the next fact instead of on a stray separator.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: [
        for (int i = 0; i < facts.length; i++)
          if (i == facts.length - 1)
            facts[i]
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: facts[i]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Text(
                    '·',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                ),
              ],
            ),
      ],
    );
  }

  // ── Trailing: status/action → time → thumbnail → menu ──────────────────────

  List<Widget> _buildTrailing(
    BuildContext context,
    TaskItem task,
    AppState appState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final widgets = <Widget>[];

    final Widget? progress = task.status == TaskStatus.processing
        ? Text(
            _progressLabel(task),
            style: textTheme.bodySmall?.mono.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onAccentTint,
            ),
          )
        : null;

    switch (task.status) {
      case TaskStatus.processing:
        // On a phone the figure stacks over the clock instead (`11c` note 04).
        if (!widget.isMobile) {
          widgets.add(progress!);
          widgets.add(const SizedBox(width: 10));
        }
      case TaskStatus.pending:
        widgets.add(_statusPill(l10n.pendingTasks, colorScheme.onSurfaceVariant, colorScheme));
        widgets.add(const SizedBox(width: 10));
      case TaskStatus.failed:
        widgets.add(OutlinedButton(
          onPressed: () => appState.taskQueue.retryTask(task.id),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            backgroundColor: colorScheme.error.withValues(alpha: 0.12),
            foregroundColor: colorScheme.error,
            textStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(l10n.retryTask),
        ));
        widgets.add(const SizedBox(width: 10));
      case TaskStatus.completed:
      case TaskStatus.cancelled:
        break;
    }

    // `10k` keeps both on a narrow screen: the outputs collapse from a strip
    // of thumbnails to a count, and the clock stays. A phone row that showed
    // neither could not tell a finished task from a cancelled one without
    // reading its status glyph.
    //
    // The clock is the creation time on every row (`11a` note 01). It used to
    // be "finished, else started", which left a pending row reading `--:--`
    // and put two different clocks in one column.
    if (widget.isMobile) {
      if (task.resultPaths.isNotEmpty) {
        widgets.add(Container(
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 13, color: colorScheme.outline),
              const SizedBox(width: 5),
              Text(
                '${task.resultPaths.length}',
                style: textTheme.labelSmall?.mono.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ));
        widgets.add(const SizedBox(width: 8));
      }
      final clock = Text(
        _formatClock(task.createdAt),
        style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
      );
      widgets.add(progress == null
          ? clock
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [progress, const SizedBox(height: 3), clock],
            ));
      widgets.add(const SizedBox(width: 4));
    } else {
      widgets.add(Text(
        _formatClock(task.createdAt),
        style: textTheme.bodySmall?.mono.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ));
      widgets.add(const SizedBox(width: 12));

      // Always, and always the same width. `10h` gives the outputs a fixed
      // 176px column so the rows line up down the list instead of each ending
      // wherever its own contents happen to stop — and so a row with nothing
      // to show still reserves the space rather than sliding its kebab left.
      widgets.add(_buildOutputs(task, colorScheme));
      widgets.add(const SizedBox(width: 6));
    }

    widgets.add(_buildMoreButton(context, task, appState, l10n, colorScheme));
    return widgets;
  }

  /// What the task produced, in a column of its own.
  ///
  /// Deliberately *only* outputs. Showing the source image here instead when
  /// there is no result would put an input where every other row shows a
  /// result — the one place a picture must not be ambiguous about which it is.
  /// A row with nothing to show says so with an empty outline.
  Widget _buildOutputs(TaskItem task, ColorScheme colorScheme) {
    final Widget content;
    if (task.resultPaths.isNotEmpty) {
      content = _buildThumbnailStrip(task, colorScheme);
    } else if (task.status == TaskStatus.failed) {
      // A filled plate with a mark, not a dashed one: this task *should* have
      // produced something, and the difference from "not yet" is worth a
      // pixel of weight.
      content = Container(
        width: _outputTileSize,
        height: _outputTileSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Icon(Icons.image_not_supported_outlined,
            size: AppSize.iconSm, color: colorScheme.outline),
      );
    } else {
      // Dashed, per `10h`. A solid hairline here is the same edge a real tile
      // draws, so an empty slot read as a picture that had failed to load;
      // dashes are what say "nothing yet" rather than "something is missing".
      content = const _EmptyOutputSlot();
    }

    return SizedBox(
      width: _outputColumnWidth,
      child: Align(alignment: Alignment.centerRight, child: content),
    );
  }

  /// One output tile, and the column they are right-aligned in.
  static const double _outputTileSize = 44;
  static const double _outputColumnWidth = 176;

  Widget _buildThumbnailStrip(TaskItem task, ColorScheme colorScheme) {
    const maxThumbs = 3;
    const size = 44.0;
    final paths = task.resultPaths.take(maxThumbs).toList();
    final overflow = task.resultPaths.length - paths.length;
    Widget frame({required Widget child}) => Padding(
          padding: const EdgeInsets.only(left: 5),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final path in paths) frame(child: _thumbnailImage(path, colorScheme)),
        if (overflow > 0)
          // Sized to its text rather than to a tile: `10h` draws this as a
          // pill, and a square is a promise of a picture.
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              height: size,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                '+$overflow',
                style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  /// One 44px square of [path], decoded at the size it is drawn.
  ///
  /// `width` constrains the layout, not the decode: without `cacheWidth` a
  /// 44px chip held a full 2K generation in the image cache — a handful of
  /// finished tasks was enough to blow past the cache ceiling and put every
  /// visible thumbnail back on the decoder, over and over, while scrolling the
  /// queue.
  Widget _thumbnailImage(String path, ColorScheme colorScheme) {
    const double size = 44;
    return Image.file(
      File(path),
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, size: 16, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _statusPill(String label, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ── 3px progress sliver along the row's bottom edge ────────────────────────

  /// Square, not rounded: it is an edge of the card rather than a bar laid on
  /// it, and the card's own corner radius is what shapes its ends.
  Widget _buildProgressBar(TaskItem task, ColorScheme colorScheme) {
    return SmoothProgress(
      value: task.progress,
      builder: (context, v) => LinearProgressIndicator(
        value: v,
        minHeight: 3,
        borderRadius: BorderRadius.zero,
        backgroundColor: colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
      ),
    );
  }

  // ── More / actions menu ─────────────────────────────────────────────────────

  Widget _buildMoreButton(
    BuildContext context,
    TaskItem task,
    AppState appState,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final canCancel = task.status == TaskStatus.pending ||
        task.status == TaskStatus.processing;
    final canRetry = task.status == TaskStatus.failed || task.status == TaskStatus.cancelled;
    final canRemove = task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 19, color: colorScheme.onSurfaceVariant),
      iconSize: 34,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(34, 34)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        overlayColor: WidgetStatePropertyAll(colorScheme.onSurface.withAlpha(20)),
      ),
      onSelected: (val) {
        if (val == 'cancel') appState.taskQueue.cancelTask(task.id);
        if (val == 'retry') appState.taskQueue.retryTask(task.id);
        if (val == 'remove') appState.taskQueue.removeTask(task.id);
        if (val == 'view_log') TaskLogDialog.show(context, task);
        if (val == 'copy_prompt') {
          final prompt = task.parameters['prompt'] ?? '';
          Clipboard.setData(ClipboardData(text: prompt));
          AppSnackBar.info(
            context,
            l10n.copiedToClipboard(prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt),
          );
        }
      },
      itemBuilder: (context) => [
        // First and unconditional: it is the one action every status has a use
        // for, and the only way to see why a failed task failed.
        PopupMenuItem(
          value: 'view_log',
          child: ListTile(
            leading: const Icon(Icons.terminal, size: 18),
            title: Text(l10n.viewTaskLog),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canCancel)
          PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(Icons.cancel_outlined, size: 18, color: colorScheme.error),
              title: Text(l10n.cancelTask, style: TextStyle(color: colorScheme.error)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canRetry)
          PopupMenuItem(
            value: 'retry',
            child: ListTile(
              leading: const Icon(Icons.refresh, size: 18),
              title: Text(l10n.retryTask),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canRemove)
          PopupMenuItem(
            value: 'remove',
            child: ListTile(
              leading: Icon(Icons.delete_outline, size: 18, color: colorScheme.onSurface),
              title: Text(l10n.removeFromList),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (task.parameters.containsKey('prompt'))
          PopupMenuItem(
            value: 'copy_prompt',
            child: ListTile(
              leading: const Icon(Icons.copy_outlined, size: 18),
              title: Text(l10n.copyPrompt),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  // ── Expanded details — `C1 10i` ────────────────────────────────────────────

  /// What a row opens onto: the log on the left, what was asked for and what
  /// came of it on the right, and the things you would want to do about it
  /// along the bottom.
  ///
  /// It used to be a stack of labelled lines with the log reduced to its
  /// *last* one behind a "open the dialog" affordance — which on a failure is
  /// almost never the interesting line, and which meant the one screen whose
  /// job is explaining what happened sent you to a dialog to find out. The log
  /// is the reason to open a row, so it gets the wider half and shows itself.
  ///
  /// Full-bleed: it sits outside the header's padding so its divider and its
  /// action bar reach the card's edges, the way `10i` draws them.
  Widget _buildExpandedDetails(
    BuildContext context,
    TaskItem task,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        LayoutBuilder(
          builder: (context, box) {
            final log = _buildLogPane(context, task, colorScheme, l10n);
            final facts = _buildFactsPane(context, task, colorScheme, l10n);

            // Side by side where there is room for two readable columns, and
            // stacked below that. The log is the wider of the two because its
            // lines are the long ones — a parameter is a word and a path, a
            // log line is a sentence with a stack trace in it.
            if (box.maxWidth < _twoColumnFloor) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  log,
                  Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
                  facts,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: log),
                  VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant),
                  Expanded(flex: 5, child: facts),
                ],
              ),
            );
          },
        ),
        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        _buildExpandedActions(context, task, colorScheme, l10n),
      ],
    );
  }

  /// Below this the two panes stop being two readable columns.
  static const double _twoColumnFloor = 620;

  Widget _buildLogPane(
    BuildContext context,
    TaskItem task,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSectionLabel(
            l10n.executionLogs,
            padding: EdgeInsets.zero,
            trailing: task.logs.isEmpty
                ? null
                : AppButton(
                    label: l10n.copyAll,
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
                      AppSnackBar.success(context, l10n.copiedAll);
                    },
                  ),
          ),
          const SizedBox(height: 8),
          if (task.logs.isEmpty)
            Text(
              l10n.noLogsYet,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.outline),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: _logMaxHeight),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: ScrollEdgeFade(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final line in task.logs) _buildLogLine(line, colorScheme, textTheme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The log box's ceiling. A failed generation can log a hundred lines, and
  /// an expanded row that runs past the window takes the rest of the queue
  /// with it.
  static const double _logMaxHeight = 168;

  /// One line, with its leading `[HH:MM:SS]` set apart.
  ///
  /// The timestamp is the same width on every line and carries no information
  /// once you have found the line you want, so it recedes; what remains is the
  /// message, coloured only when it is an error.
  Widget _buildLogLine(String line, ColorScheme colorScheme, TextTheme textTheme) {
    final match = RegExp(r'^\s*(\[[^\]]{1,12}\])\s*').firstMatch(line);
    final stamp = match?.group(1);
    final message = match == null ? line : line.substring(match.end);
    final bool isError = message.toUpperCase().contains('ERROR') ||
        message.toUpperCase().contains('FAILED');

    final base = textTheme.labelSmall?.mono.copyWith(height: AppType.proseHeight);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stamp != null) ...[
            Text(stamp, style: base?.copyWith(color: colorScheme.outline)),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Text(
              message,
              style: base?.copyWith(
                color: isError ? colorScheme.error : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactsPane(
    BuildContext context,
    TaskItem task,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final textTheme = Theme.of(context).textTheme;

    final params = <(String, String)>[
      (l10n.model, task.modelId),
      (l10n.createdAt, _formatClock(task.createdAt)),
      (l10n.started, _formatClock(task.startTime)),
      (l10n.finished, _formatClock(task.endTime)),
      (l10n.durationLabel, _elapsed(task) ?? ''),
      if (task.type == TaskType.imageProcess)
        (
          l10n.config,
          '${task.parameters['aspectRatio'] ?? ''} ${task.parameters['imageSize'] ?? ''}'.trim(),
        ),
      if (task.imagePaths.isNotEmpty) (l10n.sourceFiles, '${task.imagePaths.length}'),
      if ((task.parameters['prompt'] ?? '').isNotEmpty)
        (l10n.prompt, task.parameters['prompt']!),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSectionLabel(l10n.requestParameters, padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          for (final (key, value) in params)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      key,
                      style: textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          if (task.resultPaths.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppSectionLabel(l10n.outputPaths, padding: EdgeInsets.zero),
            const SizedBox(height: 8),
            for (final path in task.resultPaths)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => FileUtils.openPath(path),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.image_outlined, size: 14, color: colorScheme.outline),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            p.basename(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.mono
                                .copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// `10i`'s action bar. Every one of these was already reachable from the
  /// kebab; the point of repeating them here is that a row is opened *because*
  /// something went wrong, and hunting through a menu for the retry is the
  /// wrong last step of reading why.
  ///
  /// 换渠道重试 is not among them: the queue can re-run a task but not re-point
  /// it at a different channel, and a button that silently retried on the same
  /// one would be worse than its absence.
  Widget _buildExpandedActions(
    BuildContext context,
    TaskItem task,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final appState = Provider.of<AppState>(context, listen: false);
    final bool canRetry =
        task.status == TaskStatus.failed || task.status == TaskStatus.cancelled;
    final String? error = task.logs.isEmpty ? null : task.logs.last;

    return Container(
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (canRetry)
            AppButton(
              label: l10n.retryTask,
              icon: Icons.refresh,
              size: AppButtonSize.compact,
              onPressed: () => appState.taskQueue.retryTask(task.id),
            ),
          if (task.status == TaskStatus.failed && error != null)
            AppButton(
              label: l10n.copyError,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
                AppSnackBar.success(context, l10n.copiedAll);
              },
            ),
          if (task.resultPaths.isNotEmpty)
            AppButton(
              label: l10n.openInFolder,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.compact,
              onPressed: () => FileUtils.openPath(task.resultPaths.first),
            ),
          AppButton(
            label: l10n.removeFromList,
            variant: AppButtonVariant.destructiveOutline,
            size: AppButtonSize.compact,
            onPressed: () => appState.taskQueue.removeTask(task.id),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  IconData _typeIcon(TaskType type) => type.glyph;

  String _taskDisplayName(TaskItem task) {
    if (task.imagePaths.isNotEmpty) {
      return p.basename(task.imagePaths.first);
    }
    return switch (task.type) {
      TaskType.imageProcess => 'Image Process',
      TaskType.imageDownload => task.parameters['url'] ?? 'Download',
      TaskType.promptRefine => 'Prompt Refine',
      TaskType.aiRename => 'AI Rename',
      TaskType.videoGenerate => 'Video Generate',
    };
  }

  /// Lifts a leading `[MARKER]` off a model id so it can be drawn as a badge.
  ///
  /// Users prefix ids to mark a variant of a model they run more than one way.
  /// Left inline the bracket reads as part of the id, and the id is exactly
  /// what the eye skips to; as a badge the marker is the thing that differs
  /// between two otherwise identical rows.
  (String?, String) _splitModelMarker(String modelId) {
    final match = RegExp(r'^\[([^\[\]]{1,8})\]\s*').firstMatch(modelId);
    if (match == null) return (null, modelId);
    return (match.group(1), modelId.substring(match.end));
  }

  String _shortModelId(String modelId) {
    if (modelId.length <= 26) return modelId;
    return '${modelId.substring(0, 24)}…';
  }

  String _progressLabel(TaskItem task) {
    final percent = task.progress != null ? '${(task.progress! * 100).round()}%' : '···';
    final elapsed = task.startTime != null
        ? _formatDuration(DateTime.now().difference(task.startTime!))
        : null;
    return elapsed != null ? '$percent · $elapsed' : percent;
  }

  /// 1-based position among pending tasks in execution (FIFO) order.
  int _queuePosition(TaskItem task) {
    final queue = Provider.of<AppState>(context, listen: false).taskQueue.queue;
    int position = 0;
    for (final t in queue) {
      if (t.status == TaskStatus.pending) {
        position++;
        if (t.id == task.id) return position;
      }
    }
    return 0;
  }

  String? _elapsed(TaskItem task) {
    if (task.startTime == null || task.endTime == null) return null;
    return _formatDuration(task.endTime!.difference(task.startTime!));
  }

  String _errorSummary(TaskItem task) {
    final errorLog = task.logs.lastWhere(
      (log) => log.contains('Error'),
      orElse: () => task.logs.isNotEmpty ? task.logs.last : '',
    );
    // Strip the "[HH:mm:ss] " prefix for a cleaner inline summary.
    return errorLog.replaceFirst(RegExp(r'^\[\d{2}:\d{2}:\d{2}\]\s*'), '');
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (duration.inHours > 0) {
      return '${duration.inHours}:${minutes.remainder(60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatClock(DateTime? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Meta badge
// ════════════════════════════════════════════════════════════════════════════

/// A short tag in the meta line — a channel, or a model-id marker. Boxed in its
/// own colour so it separates from the ids and durations it sits among, which
/// are all one muted grey.
class _MetaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
