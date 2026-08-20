import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_tool_button.dart';
import '../workbench_layout.dart';

/// Describes a single workbench destination (tab) for the top bar controls.
class _WbDest {
  final int index;
  final IconData icon;
  final String label;
  const _WbDest(this.index, this.icon, this.label);
}

class WorkbenchTopBar extends StatelessWidget {
  final TabController tabController;

  const WorkbenchTopBar({
    super.key,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isSidebarExpanded = context.select<AppState, bool>((s) => s.isSidebarExpanded);
    final concurrencyLimit = context.select<AppState, int>((s) => s.concurrencyLimit);
    // Measured off the layout's own content box, not the screen: the workbench
    // sits beside a 64–78px navigation rail, so on an iPad-class window the
    // panels go into drawers while `MediaQuery` still reads "desktop". Taking
    // the screen's word for it is how the buttons that open those drawers would
    // go missing on exactly the widths that need them.
    final layout = context.watch<WorkbenchLayoutState>();
    final isNarrow = layout.isNarrow;
    final isMobile = layout.isMobile;

    // Primary creation modes — the headline functions of the workbench.
    final primary = <_WbDest>[
      _WbDest(0, Icons.image_outlined, l10n.wbModeImage),
      _WbDest(5, Icons.movie_outlined, l10n.wbModeVideo),
    ];
    // Secondary tools — supporting utilities, presented with lighter weight.
    final tools = <_WbDest>[
      _WbDest(1, Icons.compare, l10n.comparator),
      _WbDest(2, Icons.brush_outlined, l10n.maskEditor),
      _WbDest(3, Icons.crop, l10n.cropAndResize),
      _WbDest(4, Icons.auto_fix_high, l10n.promptOptimizer),
    ];

    return Container(
      // Opaque since the restyle, with a hairline under it. `10c` gives the
      // toolbar a ground of its own — #FAFBFF, the same tone as the two side
      // columns — sitting between the title bar above and the columns below.
      //
      // It floated transparently before, which only worked while there was an
      // inset canvas to float on. Over the window backdrop a transparent bar
      // would put the mesh behind the mode switch, which is the one place in
      // the window where nothing should compete with the controls.
      //
      // Mobile keeps the transparent bar: it goes into an app-bar slot there,
      // where the scaffold behind it is already this colour.
      color: isMobile ? Colors.transparent : colorScheme.surfaceContainerLow,
      foregroundDecoration: isMobile
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.surfaceContainerHigh),
              ),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            child: Row(
              children: [
                // Leading: sidebar toggle (inline panel) / drawer opener
                if (layout.leftInDrawer)
                  IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => context.read<WorkbenchLayoutState>().openLeftPanel(),
                  )
                else
                  IconButton(
                    icon: Icon(isSidebarExpanded ? Icons.menu_open : Icons.menu),
                    tooltip: l10n.workbench,
                    onPressed: () => context.read<AppState>().setSidebarExpanded(!isSidebarExpanded),
                  ),

                const SizedBox(width: 4),

                // Primary modes + secondary tools, scrollable to avoid overflow.
                Expanded(
                  child: AnimatedBuilder(
                    animation: tabController,
                    builder: (context, _) {
                      final active = tabController.index;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            AppSegmentedControl<int>(
                              segments: [
                                for (final d in primary)
                                  AppSegment(value: d.index, label: d.label, icon: d.icon),
                              ],
                              value: primary.any((d) => d.index == active)
                                  // A tool tab is open, so neither mode is
                                  // "current"; keep the one the user last
                                  // created in rather than flicking the
                                  // selection somewhere arbitrary.
                                  ? active
                                  : primary.first.index,
                              onChanged: tabController.animateTo,
                              style: AppSegmentStyle.raised,
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 1,
                              height: 24,
                              color: colorScheme.outlineVariant.withAlpha(90),
                            ),
                            const SizedBox(width: 8),
                            if (isMobile)
                              _ToolsMenu(
                                destinations: tools,
                                activeIndex: active,
                                onSelect: (i) => tabController.animateTo(i),
                              )
                            else
                              ...tools.map((t) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: AppToolButton(
                                      icon: t.icon,
                                      label: t.label,
                                      active: active == t.index,
                                      showLabel: !isNarrow,
                                      onPressed: () => tabController.animateTo(t.index),
                                    ),
                                  )),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Trailing actions
                if (isMobile)
                  _buildMobileMoreMenu(context, concurrencyLimit, l10n)
                else if (layout.rightInDrawer)
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: l10n.modelSelection,
                    onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(80)),
        ],
      ),
    );
  }

  Widget _buildMobileMoreMenu(BuildContext context, int concurrencyLimit, AppLocalizations l10n) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (val) {
        if (val == 'concurrency') {
          _showConcurrencyDialog(context, l10n);
        } else if (val == 'refresh') {
          context.read<AppState>().galleryState.refreshImages();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'concurrency',
          child: ListTile(
            leading: const Icon(Icons.sync_alt),
            title: Text(l10n.concurrencyLimit(concurrencyLimit)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.refresh),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _showConcurrencyDialog(BuildContext context, AppLocalizations l10n) {
    // AppDialog is built directly rather than via AppDialog.show: the heading
    // carries the live value, so the whole dialog has to sit inside the
    // StatefulBuilder.
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final appState = Provider.of<AppState>(dialogContext);
          return AppDialog(
            title: l10n.concurrencyLimit(appState.concurrencyLimit),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: appState.concurrencyLimit.toDouble(),
                  min: 1,
                  max: AppConstants.maxConcurrency.toDouble(),
                  divisions: AppConstants.maxConcurrency - 1,
                  onChanged: (v) {
                    appState.setConcurrency(v.round());
                    setDialogState(() {});
                  },
                ),
                Text(appState.concurrencyLimit.toString()),
              ],
            ),
            actions: [
              AppButton(
                label: l10n.close,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact overflow menu that collapses the secondary tools on mobile.
class _ToolsMenu extends StatelessWidget {
  final List<_WbDest> destinations;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const _ToolsMenu({
    required this.destinations,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isToolActive = destinations.any((d) => d.index == activeIndex);

    return PopupMenuButton<int>(
      tooltip: l10n.wbTools,
      onSelected: onSelect,
      itemBuilder: (context) => destinations.map((d) {
        final selected = d.index == activeIndex;
        return PopupMenuItem<int>(
          value: d.index,
          child: Row(
            children: [
              Icon(d.icon, size: 20, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                d.label,
                style: TextStyle(
                  color: selected ? colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      // The mobile stand-in for the row of AppToolButtons, so it takes the
      // same active treatment they do — the tint ladder and `onAccentTint`,
      // not a hand-picked alpha and `primary` on top of it.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isToolActive ? colorScheme.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(appButtonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.handyman_outlined,
              size: AppSize.iconLg,
              color: isToolActive ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
            ),
            Icon(
              Icons.arrow_drop_down,
              size: AppSize.iconMd,
              color: isToolActive ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
