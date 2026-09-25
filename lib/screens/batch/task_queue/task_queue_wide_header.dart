part of '../task_queue_screen.dart';

/// The wide form's two bands: the header with its counts and queue-wide
/// actions, and the filter row.
extension _WideHeader on _TaskQueueScreenState {
  /// `B2 · 1a` 头: the 44px plate, title over the five counts, and the queue's
  /// actions. The actions degrade by measurement — labels go first, then both
  /// buttons fold into the ⋮ that already holds 清除全部.
  Widget _buildHeader(BuildContext context, _Counts counts, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;

    final VoidCallback? cancelPending = counts.pending == 0
        ? null
        : () => _handleBulkAction('cancel_pending', queue);
    final VoidCallback? clearCompleted = counts.settled == 0
        ? null
        : () => _handleBulkAction('clear_completed', queue);
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
        double labelled(String label) =>
            measureGlassText(context, label, labelStyle) + 14 + 16 + 8 + 14;
        final labelledWidth =
            labelled(l10n.cancelAllPending) +
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
              AppIconButton(
                icon: Icons.block,
                tooltip: l10n.cancelAllPending,
                onPressed: cancelPending,
              ),
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

  MenuItemButton _clearAllItem(
    ColorScheme scheme,
    AppLocalizations l10n,
    VoidCallback? onPressed, {
    ButtonStyle? style,
  }) {
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
      (
        '${counts.pending} ${short ? l10n.statusShortPending : l10n.pendingTasks}',
        ink2,
        FontWeight.w400,
      ),
      (
        '${counts.done} ${short ? l10n.statusShortDone : l10n.completedTasks}',
        ink2,
        FontWeight.w400,
      ),
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
        final sortFull =
            6 +
            segmentLabels.fold<double>(
              0,
              (sum, label) =>
                  sum + 10 + 14 + 7 + measureGlassText(context, label, segLabelStyle) + 10,
            );
        final sortIcons = 6 + segmentLabels.length * (10 + 14 + 10.0);

        final showPin = listState.filter == TaskFilter.all;
        final pinLabelWidth =
            measureGlassText(
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
}
