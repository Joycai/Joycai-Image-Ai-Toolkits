part of '../task_queue_screen.dart';

/// The phone form (<600): the G1 top bar and its menu, the counts row, the
/// chip strip.
extension _PhoneForm on _TaskQueueScreenState {
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
              child: const AppRunConsole(onExpand: showTaskQueueSheet),
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
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      12 + (inBottomSheet ? bottomInset : 0),
                    ),
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
}
