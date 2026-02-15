import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final appState = Provider.of<AppState>(context);
    final isNarrow = Responsive.isNarrow(context);

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
                  icon: Icon(appState.isSidebarExpanded ? Icons.menu_open : Icons.menu),
                  onPressed: () => appState.setSidebarExpanded(!appState.isSidebarExpanded),
                ),
              
              Expanded(
                child: TabBar(
                  controller: tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: [
                    Tab(child: _buildTabLabel(Icons.image, l10n.imageProcessing, isNarrow)),
                    Tab(child: _buildTabLabel(Icons.compare, l10n.comparator, isNarrow)),
                    Tab(child: _buildTabLabel(Icons.brush, l10n.maskEditor, isNarrow)),
                    Tab(child: _buildTabLabel(Icons.auto_fix_high, l10n.promptOptimizer, isNarrow)),
                  ],
                ),
              ),
              
              if (isNarrow && !Responsive.isMobile(context))
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

  Widget _buildTabLabel(IconData icon, String label, bool isNarrow) {
    if (isNarrow) {
      return Icon(icon, size: 20);
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
}
