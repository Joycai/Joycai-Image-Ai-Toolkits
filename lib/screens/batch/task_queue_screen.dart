import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_list_ordering.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/task_list_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/scroll_edge_fade.dart';
import '../../widgets/shell/app_destinations.dart';
import 'task_queue_card.dart';

/// The batch task queue (`B2`).
///
/// ≥600: a 72px header (title, the five counts, the queue-wide actions) and a
/// 44px filter row on the column colour, over a list of task cards on the
/// aurora, with the run console at the foot. <600: a G1 top bar with one ⋮, an
/// abbreviated counts row, a 58px chip strip and compact cards.
///
/// The floating task capsule stays off this screen — the queue's own header
/// already reports what the capsule would. The shell decides that
/// (`task_capsule_monitor.dart`), not this file.
class TaskQueueScreen extends StatefulWidget {
  const TaskQueueScreen({super.key});

  @override
  State<TaskQueueScreen> createState() => _TaskQueueScreenState();
}

/// The queue in five figures.
class _Counts {
  _Counts(List<TaskItem> queue) : total = queue.length {
    for (final task in queue) {
      switch (task.status) {
        case TaskStatus.processing:
          running++;
        case TaskStatus.pending:
          pending++;
        case TaskStatus.completed:
          done++;
        case TaskStatus.failed:
          failed++;
        case TaskStatus.cancelled:
          cancelled++;
      }
    }
  }

  final int total;
  int running = 0;
  int pending = 0;
  int done = 0;
  int failed = 0;
  int cancelled = 0;

  /// What 清除已完成 removes: every settled task.
  int get settled => done + failed + cancelled;

  /// What 清除全部 is offered for: anything not running.
  int get clearable => total - running;
}

/// How much of the header's action group fits beside the title block.
enum _HeaderFit { labelled, icons, folded }

class _TaskQueueScreenState extends State<TaskQueueScreen> {
  /// Which cards are open, by task id.
  ///
  /// Here rather than in each card: a task crosses the pinned seam the moment
  /// it finishes and moves when the sort flips, and a list builder that
  /// rebuilds or recycles its card must not lose — or hand to a neighbour —
  /// whether it was open.
  final Set<String> _expanded = <String>{};

  void _toggle(String id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  @override
  Widget build(BuildContext context) {
    // The queue is what this screen renders, so it subscribes to the queue
    // itself; AppState no longer re-broadcasts queue ticks.
    context.watch<TaskQueueService>();
    // Filter, sort and pinning live in TaskListState: the shell rebuilds this
    // screen on every visit, and a filter kept here reset each time.
    final listState = context.watch<TaskListState>();
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final queue = appState.taskQueue.queue;

    // Forget cards whose task has left the queue.
    final ids = {for (final task in queue) task.id};
    _expanded.retainWhere(ids.contains);

    // Embedded in the phone console's bottom sheet: the sheet is the console,
    // so a console inside it would be the console twice.
    final inBottomSheet = context.findAncestorWidgetOfExactType<BottomSheet>() != null;

    final counts = _Counts(queue);
    final tasks = listState.arrange(queue);
    final positions = _queuePositions(queue);

    if (Responsive.isMobile(context)) {
      return _buildPhone(context, queue, counts, tasks, positions, listState, l10n,
          inBottomSheet: inBottomSheet);
    }

    final content = _buildWide(context, queue, counts, tasks, positions, listState, l10n);
    if (inBottomSheet) return content;
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const AppRunConsole(),
      body: content,
    );
  }

  /// Each pending task's 1-based place in execution (FIFO) order, computed
  /// once per build rather than once per row.
  static Map<String, int> _queuePositions(List<TaskItem> queue) {
    final positions = <String, int>{};
    var next = 0;
    for (final task in queue) {
      if (task.status == TaskStatus.pending) positions[task.id] = ++next;
    }
    return positions;
  }

  // ── Wide form (≥600) ────────────────────────────────────────────────────────

  Widget _buildWide(
    BuildContext context,
    List<TaskItem> queue,
    _Counts counts,
    ArrangedTasks tasks,
    Map<String, int> positions,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColumnBand(height: 72, child: _buildHeader(context, counts, l10n)),
        _ColumnBand(height: 44, child: _buildFilterRow(context, queue, listState, l10n)),
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyOrFiltered(context, queue, listState, l10n)
              : _buildList(
                  context,
                  tasks,
                  positions,
                  l10n,
                  phone: false,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                ),
        ),
      ],
    );
  }

  /// `B2 · 1a` 头: the 44px plate, title over the five counts, and the queue's
  /// actions. The actions degrade by measurement — labels go first, then both
  /// buttons fold into the ⋮ that already holds 清除全部.
  Widget _buildHeader(BuildContext context, _Counts counts, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;

    final VoidCallback? cancelPending =
        counts.pending == 0 ? null : () => _handleBulkAction('cancel_pending', queue);
    final VoidCallback? clearCompleted =
        counts.settled == 0 ? null : () => _handleBulkAction('clear_completed', queue);
    final VoidCallback? clearAll = counts.clearable == 0 ? null : _confirmClearAll;

    final titleStyle = textTheme.titleLarge!;
    final countStyle = textTheme.bodySmall!.mono;
    final items = _countItems(counts, l10n, scheme, short: false);

    return LayoutBuilder(
      builder: (context, box) {
        const double plate = 44;
        const double plateGap = 12;
        const double groupGap = AppSpace.s16;
        const double buttonGap = AppSpace.s6;

        final block = math.max(
          measureGlassText(context, l10n.taskQueueManager, titleStyle),
          _CountsLine.measure(context, items, countStyle),
        );
        // An outlined button with an icon: 14 padding either side, a 16 glyph
        // and 8 between it and the label.
        final labelStyle = textTheme.labelLarge!;
        double labelled(String label) => measureGlassText(context, label, labelStyle) + 14 + 16 + 8 + 14;
        final labelledWidth = labelled(l10n.cancelAllPending) +
            buttonGap +
            labelled(l10n.clearCompleted) +
            buttonGap +
            AppSize.iconButton;
        const iconsWidth = AppSize.iconButton * 3 + buttonGap * 2;
        final room = box.maxWidth - plate - plateGap - groupGap;

        final fit = block + labelledWidth <= room
            ? _HeaderFit.labelled
            : block + iconsWidth <= room
                ? _HeaderFit.icons
                : _HeaderFit.folded;

        return Row(
          children: [
            Container(
              width: plate,
              height: plate,
              decoration: BoxDecoration(
                color: scheme.accentTint,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(Icons.checklist_rounded, size: 24, color: scheme.primary),
            ),
            const SizedBox(width: plateGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.taskQueueManager,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 2),
                  _CountsLine(items: items, style: countStyle),
                ],
              ),
            ),
            const SizedBox(width: groupGap),
            if (fit == _HeaderFit.labelled) ...[
              AppButton(
                label: l10n.cancelAllPending,
                icon: Icons.block,
                variant: AppButtonVariant.secondary,
                onPressed: cancelPending,
              ),
              const SizedBox(width: buttonGap),
              AppButton(
                label: l10n.clearCompleted,
                icon: Icons.cleaning_services_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: clearCompleted,
              ),
              const SizedBox(width: buttonGap),
            ] else if (fit == _HeaderFit.icons) ...[
              AppIconButton(icon: Icons.block, tooltip: l10n.cancelAllPending, onPressed: cancelPending),
              const SizedBox(width: buttonGap),
              AppIconButton(
                icon: Icons.cleaning_services_outlined,
                tooltip: l10n.clearCompleted,
                onPressed: clearCompleted,
              ),
              const SizedBox(width: buttonGap),
            ],
            MenuAnchor(
              menuChildren: [
                if (fit == _HeaderFit.folded) ...[
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.block, size: AppSize.iconLg),
                    onPressed: cancelPending,
                    child: Text(l10n.cancelAllPending),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.cleaning_services_outlined, size: AppSize.iconLg),
                    onPressed: clearCompleted,
                    child: Text(l10n.clearCompleted),
                  ),
                  const Divider(height: 9),
                ],
                _clearAllItem(scheme, l10n, clearAll),
              ],
              builder: (context, controller, _) => AppIconButton(
                icon: Icons.more_vert,
                tooltip: l10n.more,
                selected: controller.isOpen,
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
        );
      },
    );
  }

  MenuItemButton _clearAllItem(ColorScheme scheme, AppLocalizations l10n, VoidCallback? onPressed,
      {ButtonStyle? style}) {
    final enabled = onPressed != null;
    return MenuItemButton(
      style: style,
      leadingIcon: Icon(
        Icons.delete_sweep_outlined,
        size: AppSize.iconLg,
        color: enabled ? scheme.error : null,
      ),
      onPressed: onPressed,
      child: Text(l10n.clearAll, style: enabled ? TextStyle(color: scheme.error) : null),
    );
  }

  /// The five counts as `(text, colour, weight)`. Processing speaks in the
  /// deep accent and failed in the error ink, each only while it is non-zero —
  /// an empty count is not news.
  List<(String, Color, FontWeight)> _countItems(
    _Counts counts,
    AppLocalizations l10n,
    ColorScheme scheme, {
    required bool short,
  }) {
    final ink2 = scheme.onSurfaceVariant;
    return [
      (
        '${counts.running} ${short ? l10n.statusShortRunning : l10n.processingTasks}',
        counts.running > 0 ? scheme.onAccentTint : ink2,
        counts.running > 0 ? FontWeight.w600 : FontWeight.w400,
      ),
      ('${counts.pending} ${short ? l10n.statusShortPending : l10n.pendingTasks}', ink2, FontWeight.w400),
      ('${counts.done} ${short ? l10n.statusShortDone : l10n.completedTasks}', ink2, FontWeight.w400),
      (
        '${counts.failed} ${short ? l10n.statusShortFailed : l10n.failedTasks}',
        counts.failed > 0 ? scheme.onErrorContainer : ink2,
        counts.failed > 0 ? FontWeight.w600 : FontWeight.w400,
      ),
      (
        short ? l10n.taskTotalShort(counts.total) : '· ${l10n.taskTotalCount(counts.total)}',
        ink2,
        FontWeight.w400,
      ),
    ];
  }

  /// `B2 · 1a` 过滤行: the filter chips, then the sort track and — under 全部
  /// only, the one filter that mixes statuses — the pin switch.
  ///
  /// When the tools and the chips do not both fit, the pin loses its label
  /// (the switch keeps it as a tooltip), then the sort track drops to its
  /// arrows; past that the chips scroll under their edge fade.
  Widget _buildFilterRow(
    BuildContext context,
    List<TaskItem> queue,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final entries = _filterEntries(queue, l10n);

    return LayoutBuilder(
      builder: (context, box) {
        const double toolsGap = AppSpace.s16;
        const double pinGap = AppSpace.s16;
        const double pinLabelGap = 8;

        final chipsWidth = _FilterChips.measure(context, entries);
        final segLabelStyle = textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600);
        // AppSegmentedControl, compact: a 3px track inset, 10 either side of
        // a 14px glyph and 7 before its label.
        final segmentLabels = [l10n.sortNewestFirst, l10n.sortOldestFirst];
        final sortFull = 6 +
            segmentLabels.fold<double>(
                0, (sum, label) => sum + 10 + 14 + 7 + measureGlassText(context, label, segLabelStyle) + 10);
        final sortIcons = 6 + segmentLabels.length * (10 + 14 + 10.0);

        final showPin = listState.filter == TaskFilter.all;
        final pinLabelWidth = measureGlassText(
              context,
              l10n.pinActiveTasks,
              textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500),
            ) +
            pinLabelGap;
        final room = box.maxWidth - toolsGap;

        var pinLabel = showPin;
        var sortIconOnly = false;
        double tools() =>
            (sortIconOnly ? sortIcons : sortFull) +
            (showPin ? pinGap + AppSwitch.size.width + 8 + (pinLabel ? pinLabelWidth : 0) : 0);
        if (chipsWidth + tools() > room) pinLabel = false;
        if (chipsWidth + tools() > room) sortIconOnly = true;

        return Row(
          children: [
            Expanded(
              child: ScrollEdgeFade(
                axis: Axis.horizontal,
                extent: 32,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _FilterChips(
                    entries: entries,
                    selected: listState.filter,
                    onSelect: listState.setFilter,
                  ),
                ),
              ),
            ),
            const SizedBox(width: toolsGap),
            AppSegmentedControl<TaskSortOrder>(
              compact: true,
              style: AppSegmentStyle.raised,
              iconOnly: sortIconOnly,
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
            if (showPin) ...[
              const SizedBox(width: pinGap),
              _PinToggle(
                label: l10n.pinActiveTasks,
                showLabel: pinLabel,
                value: listState.pinActive,
                onChanged: listState.setPinActive,
              ),
            ],
          ],
        );
      },
    );
  }

  List<(TaskFilter, String, int)> _filterEntries(List<TaskItem> queue, AppLocalizations l10n) => [
        for (final (filter, label) in <(TaskFilter, String)>[
          (TaskFilter.all, l10n.filterAll),
          (TaskFilter.running, l10n.processingTasks),
          (TaskFilter.pending, l10n.pendingTasks),
          (TaskFilter.done, l10n.completedTasks),
          (TaskFilter.failed, l10n.failedTasks),
        ])
          (filter, label, queue.where(filter.matches).length),
      ];

  // ── Phone form (<600) ───────────────────────────────────────────────────────

  Widget _buildPhone(
    BuildContext context,
    List<TaskItem> queue,
    _Counts counts,
    ArrangedTasks tasks,
    Map<String, int> positions,
    TaskListState listState,
    AppLocalizations l10n, {
    required bool inBottomSheet,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The shell reports the floating dock as bottom padding; the console sits
    // above it rather than under it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // `B2 · 1c`: the screen's one full-width glass layer.
        flexibleSpace: const AppGlass(
          grade: GlassGrade.bar,
          edges: GlassEdges.bottom,
          shadow: false,
          child: SizedBox.expand(),
        ),
        titleSpacing: AppSpace.s16,
        title: Text(
          l10n.taskQueueManager,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge,
        ),
        actions: [
          _buildPhoneMenu(context, counts, listState, l10n),
          const SizedBox(width: AppSpace.s6),
        ],
      ),
      bottomNavigationBar: inBottomSheet
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: const AppRunConsole(),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The counts are why this screen is opened, so the phone shortens
          // them rather than dropping them.
          _ColumnBand(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _CountsLine(
                items: _countItems(counts, l10n, scheme, short: true),
                style: textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400),
                separator: ' · ',
              ),
            ),
          ),
          _ColumnBand(
            height: 58,
            padding: EdgeInsets.zero,
            child: ScrollEdgeFade(
              axis: Axis.horizontal,
              extent: 32,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Horizontal only: the band hands the scroll view its full
                // height, and the row centres the 36px chips inside it.
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
                child: _FilterChips(
                  entries: _filterEntries(queue, l10n),
                  selected: listState.filter,
                  onSelect: listState.setFilter,
                  height: 36,
                ),
              ),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyOrFiltered(context, queue, listState, l10n)
                : _buildList(
                    context,
                    tasks,
                    positions,
                    l10n,
                    phone: true,
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + (inBottomSheet ? bottomInset : 0)),
                  ),
          ),
        ],
      ),
    );
  }

  /// `B2 · 1c` ⋮: a sort caption over two single-choice rows, the pin switch,
  /// and the three queue-wide actions the wide header carries.
  Widget _buildPhoneMenu(
    BuildContext context,
    _Counts counts,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;
    final rowStyle = MenuItemButton.styleFrom(minimumSize: const Size(250, AppSize.large));

    MenuItemButton choice(TaskSortOrder order, IconData icon, String label) {
      final selected = listState.sortOrder == order;
      return MenuItemButton(
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(250, AppSize.large),
          backgroundColor: selected ? scheme.accentTint : null,
          foregroundColor: selected ? scheme.onAccentTint : null,
        ),
        leadingIcon: Icon(icon, size: AppSize.iconLg, color: selected ? scheme.onAccentTint : null),
        trailingIcon: selected
            ? Icon(Icons.check, size: AppSize.iconMd, color: scheme.onAccentTint)
            : null,
        onPressed: () => listState.setSortOrder(order),
        child: Text(label),
      );
    }

    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            l10n.sortSection.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: AppType.trackedLabelSpacing,
              color: scheme.outline,
            ),
          ),
        ),
        choice(TaskSortOrder.newestFirst, Icons.arrow_downward_rounded, l10n.sortNewestFirst),
        choice(TaskSortOrder.oldestFirst, Icons.arrow_upward_rounded, l10n.sortOldestFirst),
        const Divider(height: 9),
        MenuItemButton(
          style: rowStyle,
          // The switch is a picture of the state; the row is the control, and
          // it stays open so the change can be seen.
          closeOnActivate: false,
          onPressed: () => listState.setPinActive(!listState.pinActive),
          trailingIcon: IgnorePointer(
            child: AppSwitch(value: listState.pinActive, onChanged: (_) {}),
          ),
          child: Text(l10n.pinActiveTasks),
        ),
        const Divider(height: 9),
        MenuItemButton(
          style: rowStyle,
          leadingIcon: const Icon(Icons.block, size: AppSize.iconLg),
          onPressed: counts.pending == 0 ? null : () => _handleBulkAction('cancel_pending', queue),
          child: Text(l10n.cancelAllPending),
        ),
        MenuItemButton(
          style: rowStyle,
          leadingIcon: const Icon(Icons.cleaning_services_outlined, size: AppSize.iconLg),
          onPressed: counts.settled == 0 ? null : () => _handleBulkAction('clear_completed', queue),
          child: Text(l10n.clearCompleted),
        ),
        _clearAllItem(
          scheme,
          l10n,
          counts.clearable == 0 ? null : _confirmClearAll,
          style: rowStyle,
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.more,
        style: IconButton.styleFrom(
          backgroundColor: controller.isOpen ? scheme.accentTint : null,
          foregroundColor: controller.isOpen ? scheme.onAccentTint : null,
        ),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Widget _buildList(
    BuildContext context,
    ArrangedTasks tasks,
    Map<String, int> positions,
    AppLocalizations l10n, {
    required bool phone,
    required EdgeInsets padding,
  }) {
    final statusWidth = phone ? 0.0 : taskStatusColumnWidth(context);

    Widget card(TaskItem task) => Padding(
          key: ValueKey(task.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: TaskQueueCard(
            task: task,
            position: positions[task.id] ?? 0,
            expanded: _expanded.contains(task.id),
            onToggle: () => _toggle(task.id),
            statusColumnWidth: statusWidth,
            compact: phone,
          ),
        );

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

  // ── Empty states — `B2 · 1d` ────────────────────────────────────────────────

  Widget _buildEmptyOrFiltered(
    BuildContext context,
    List<TaskItem> queue,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (queue.isEmpty) {
      // The screen a user lands on while waiting for something, so its empty
      // state carries the way back to where work is started.
      return _EmptyBlock(
        icon: Icons.checklist_rounded,
        title: l10n.noTasksInQueue,
        titleStyle: textTheme.titleLarge,
        description: l10n.submitTaskFromWorkbench,
        action: AppButton(
          label: l10n.goToWorkbench,
          onPressed: () => Provider.of<AppState>(context, listen: false)
              .navigateToScreen(AppDestination.workbench.index),
        ),
        iconColor: scheme.outline,
      );
    }

    // Empty because of the filter, not the queue: the counts above keep their
    // figures, and the one action puts the filter back.
    final title = switch (listState.filter) {
      TaskFilter.running => l10n.noRunningTasks,
      TaskFilter.pending => l10n.noPendingTasks,
      TaskFilter.done => l10n.noCompletedTasks,
      TaskFilter.failed => l10n.noFailedTasks,
      TaskFilter.all => l10n.noTasksInQueue,
    };
    return _EmptyBlock(
      icon: Icons.filter_alt_off_outlined,
      title: title,
      titleStyle: textTheme.titleMedium,
      description: l10n.filteredEmptyHint(queue.length),
      action: AppButton(
        label: l10n.viewAllTasks,
        variant: AppButtonVariant.secondary,
        accentLabel: true,
        onPressed: () => listState.setFilter(TaskFilter.all),
      ),
      iconColor: scheme.outline,
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _handleBulkAction(String action, TaskQueueService queue) {
    if (action == 'clear_completed') {
      final toRemove = queue.queue
          .where((t) =>
              t.status == TaskStatus.completed ||
              t.status == TaskStatus.failed ||
              t.status == TaskStatus.cancelled)
          .map((t) => t.id)
          .toList();
      for (final id in toRemove) {
        queue.removeTask(id);
      }
    } else if (action == 'cancel_pending') {
      final toCancel =
          queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (final id in toCancel) {
        queue.cancelTask(id);
      }
    } else if (action == 'clear_all') {
      final toRemove =
          queue.queue.where((t) => t.status != TaskStatus.processing).map((t) => t.id).toList();
      for (final id in toRemove) {
        queue.removeTask(id);
      }
    }
  }

  /// `B2 · 1b` 清除全部确认: 440 wide, the error plate, and the solid error fill
  /// on the confirm. Cancel takes focus, so Enter is never the key that
  /// clears.
  Future<void> _confirmClearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;
    final running = queue.queue.where((t) => t.status == TaskStatus.processing).length;

    final confirmed = await AppDialog.show<bool>(
      context,
      maxWidth: 440,
      icon: Icons.delete_sweep_outlined,
      iconColor: scheme.error,
      title: l10n.clearAllTasksTitle,
      subtitle: running > 0 ? l10n.clearAllRunningNote(running) : null,
      content: Text(
        l10n.clearAllKeepsFiles,
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: AppType.proseHeight,
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: l10n.clearAll,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (!mounted || confirmed != true) return;
    _handleBulkAction('clear_all', queue);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Bands, counts, chips
// ════════════════════════════════════════════════════════════════════════════

/// An edge-to-edge strip on the column colour, ruled off below.
class _ColumnBand extends StatelessWidget {
  const _ColumnBand({
    required this.height,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final double height;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: child,
    );
  }
}

/// The counts on one line: 10 apart on the wide header, ` · ` between them on
/// the phone. Ellipsizes rather than wrapping, so the header stays 72.
class _CountsLine extends StatelessWidget {
  const _CountsLine({required this.items, required this.style, this.separator});

  final List<(String, Color, FontWeight)> items;
  final TextStyle style;

  /// Null draws a 10px gap instead of a separator.
  final String? separator;

  static const double _gap = AppSpace.s10;

  /// The width of the gapped form at [style].
  static double measure(BuildContext context, List<(String, Color, FontWeight)> items, TextStyle style) {
    var width = _gap * (items.length - 1);
    for (final (text, _, weight) in items) {
      width += measureGlassText(context, text, style.copyWith(fontWeight: weight));
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sep = separator;
    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              sep == null
                  ? const WidgetSpan(child: SizedBox(width: _gap))
                  : TextSpan(text: sep, style: TextStyle(color: scheme.outline)),
            TextSpan(
              text: items[i].$1,
              style: TextStyle(color: items[i].$2, fontWeight: items[i].$3),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The five filter chips.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.entries,
    required this.selected,
    required this.onSelect,
    this.height = 28,
  });

  final List<(TaskFilter, String, int)> entries;
  final TaskFilter selected;
  final ValueChanged<TaskFilter> onSelect;
  final double height;

  static const double _gap = AppSpace.s6;

  /// The strip's natural width.
  static double measure(BuildContext context, List<(TaskFilter, String, int)> entries) {
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600);
    final count = textTheme.bodySmall!.mono;
    var width = _gap * (entries.length - 1);
    for (final (_, text, n) in entries) {
      width += _FilterChip.padX * 2 +
          measureGlassText(context, text, label) +
          _FilterChip.countGap +
          measureGlassText(context, '$n', count);
    }
    return width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          _FilterChip(
            label: entries[i].$2,
            count: entries[i].$3,
            selected: entries[i].$1 == selected,
            danger: entries[i].$1 == TaskFilter.failed,
            height: height,
            onTap: () => onSelect(entries[i].$1),
          ),
        ],
      ],
    );
  }
}

/// `B2` 筛选胶囊: a capsule, the count after its label in mono at .8.
/// Selected is the accent's 12% form with no edge — the 失败 chip takes the
/// error container instead; unselected is a hairline outline on nothing.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.danger,
    required this.height,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool danger;
  final double height;
  final VoidCallback onTap;

  static const double padX = 12;
  static const double countGap = AppSpace.s6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.pill);

    final (Color fill, Color ink) = !selected
        ? (Colors.transparent, scheme.onSurfaceVariant)
        : danger
            ? (scheme.errorContainer, scheme.onErrorContainer)
            : (scheme.accentTint, scheme.onAccentTint);

    return Material(
      color: fill,
      borderRadius: radius,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: radius,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: padX),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: selected ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
              const SizedBox(width: countGap),
              Opacity(
                opacity: 0.8,
                child: Text('$count', style: textTheme.bodySmall?.mono.copyWith(color: ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pin switch beside the sort track, its label dropped to a tooltip when
/// the row is short of room.
class _PinToggle extends StatelessWidget {
  const _PinToggle({
    required this.label,
    required this.showLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool showLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final toggle = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLabel) ...[
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
            ],
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
    return showLabel ? toggle : Tooltip(message: label, child: toggle);
  }
}

/// The seam between the pinned tasks and the rest: a tracked grey caption and
/// a hairline running on from it. Drawn only while both sides have rows.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: AppType.trackedLabelSpacing,
                  color: scheme.outline,
                ),
          ),
          const SizedBox(width: AppSpace.s10),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// A centred glyph, title, explanation and one way out.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleStyle,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final TextStyle? titleStyle;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: titleStyle),
            const SizedBox(height: AppSpace.s6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            action,
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
/// One labelled line of a task's detail.
///
/// Its own widget so the layout can be pinned without standing up the screen's
/// AppState and database — both properties below shipped wrong and neither is
/// visible from reading a call site.
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
        // belonged to the row before.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sits on the first line of text rather than the row's top edge.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
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
