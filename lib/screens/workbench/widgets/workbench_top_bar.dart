import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../workbench_layout.dart';

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
    final isNarrow = Responsive.isNarrow(context);
    final isMobile = Responsive.isMobile(context);

    return Container(
      color: colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (isNarrow)
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => context.read<WorkbenchLayoutState>().openLeftPanel(),
                )
              else
                IconButton(
                  icon: Icon(isSidebarExpanded ? Icons.menu_open : Icons.menu),
                  onPressed: () => context.read<AppState>().setSidebarExpanded(!isSidebarExpanded),
                ),

              Expanded(
                child: TabBar(
                  controller: tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: [
                    Tab(child: _buildTabLabel(Icons.image, l10n.imageProcessing, isNarrow, l10n.imageProcessing)),
                    Tab(child: _buildTabLabel(Icons.compare, l10n.comparator, isNarrow, l10n.comparator)),
                    Tab(child: _buildTabLabel(Icons.brush, l10n.maskEditor, isNarrow, l10n.maskEditor)),
                    Tab(child: _buildTabLabel(Icons.crop, l10n.cropAndResize, isNarrow, l10n.cropAndResize)),
                    Tab(child: _buildTabLabel(Icons.auto_fix_high, l10n.promptOptimizer, isNarrow, l10n.promptOptimizer)),
                    Tab(child: _buildTabLabel(Icons.movie_outlined, l10n.videoGeneration, isNarrow, l10n.videoGeneration)),
                  ],
                ),
              ),

              if (isMobile)
                _buildMobileMoreMenu(context, concurrencyLimit, l10n)
              else if (isNarrow)
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
                ),
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildTabLabel(IconData icon, String label, bool isNarrow, String tooltip) {
    if (isNarrow) {
      return Tooltip(
        message: tooltip,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            Text(label, style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
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
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final appState = Provider.of<AppState>(dialogContext);
          return AlertDialog(
            title: Text(l10n.concurrencyLimit(appState.concurrencyLimit)),
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.close),
              ),
            ],
          );
        },
      ),
    );
  }
}
