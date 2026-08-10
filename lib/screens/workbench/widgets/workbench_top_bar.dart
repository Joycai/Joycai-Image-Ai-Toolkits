import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
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
    final imageModels = context.select<AppState, List<LLMModel>>((s) => s.imageModels);
    final allChannels = context.select<AppState, List<LLMChannel>>((s) => s.allChannels);
    final lastSelectedModelId = context.select<AppState, String?>((s) => s.lastSelectedModelId);
    final isNarrow = Responsive.isNarrow(context);
    final isMobile = Responsive.isMobile(context);

    // Derive active channel name for the trailing chip.
    String? channelName;
    if (lastSelectedModelId != null && imageModels.isNotEmpty && allChannels.isNotEmpty) {
      final dbId = int.tryParse(lastSelectedModelId);
      LLMModel? model;
      if (dbId != null) {
        try { model = imageModels.firstWhere((m) => m.id == dbId); } catch (_) {}
      }
      if (model != null) {
        try {
          final ch = allChannels.firstWhere((c) => c.id == model!.channelId);
          channelName = ch.displayName;
        } catch (_) {}
      }
    }

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
      // Transparent so the bar floats on the inset-panel canvas on desktop
      // (mobile puts this inside an app-bar slot where the scaffold shows
      // through, which was surface-colored anyway).
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            child: Row(
              children: [
                // Leading: sidebar toggle (desktop) / drawer (narrow)
                if (isNarrow)
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
                else if (isNarrow)
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: l10n.modelSelection,
                    onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
                  )
                else if (channelName != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          channelName,
                          style: TextStyle(fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isToolActive ? colorScheme.primary.withAlpha(28) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.handyman_outlined,
              size: 20,
              color: isToolActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: isToolActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
