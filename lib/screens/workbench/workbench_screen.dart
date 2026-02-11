import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/collapsible_card.dart';
import '../../widgets/log_console.dart';
import 'control_panel.dart';
import 'gallery.dart';
import 'source_explorer.dart';
import 'widgets/gallery_toolbar.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final isNarrow = Responsive.isNarrow(context);
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: isNarrow ? AppBar(
        title: Text(l10n.workbench),
        leading: IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: l10n.sourceExplorer,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: l10n.settings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: l10n.sourceGallery),
            Tab(text: l10n.processResults),
            Tab(text: l10n.tempWorkspace),
          ],
        ),
      ) : null,
      drawer: isNarrow ? const Drawer(width: 300, child: SourceExplorerWidget()) : null,
      endDrawer: isNarrow ? const Drawer(width: 350, child: ControlPanelWidget()) : null,
      body: Column(
        children: [
          if (!isNarrow)
            Container(
              color: colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  Tab(text: l10n.sourceGallery),
                  Tab(text: l10n.processResults),
                  Tab(text: l10n.tempWorkspace),
                ],
              ),
            ),
          
          GalleryToolbar(tabController: _tabController),
          
          Expanded(
            child: Row(
              children: [
                if (!isNarrow) ...[
                  const SizedBox(width: 280, child: SourceExplorerWidget()),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1600),
                      child: GalleryWidget(tabController: _tabController),
                    ),
                  ),
                ),
                if (!isNarrow) ...[
                  const VerticalDivider(width: 1, thickness: 1),
                  const SizedBox(width: 350, child: ControlPanelWidget()),
                ],
              ],
            ),
          ),
          
          if (!isMobile) ...[
            const Divider(height: 1, thickness: 1),
            Container(
              color: colorScheme.surfaceContainerHighest.withAlpha((255 * AppConstants.opacityLow).round()),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CollapsibleCard(
                title: l10n.executionLogs,
                subtitle: appState.isConsoleExpanded ? null : l10n.clickToExpand,
                isExpanded: appState.isConsoleExpanded,
                onToggle: () => appState.setConsoleExpanded(!appState.isConsoleExpanded),
                collapsedIcon: Icons.keyboard_arrow_up,
                expandedIcon: Icons.keyboard_arrow_down,
                content: const SizedBox(
                  height: 200,
                  child: LogConsoleWidget(),
                ),
              ),
            ),
          ] else 
            // Mobile log toggle - maybe a smaller status bar or button
            _buildMobileStatusBar(context, appState, l10n),
        ],
      ),
    );
  }

  Widget _buildMobileStatusBar(BuildContext context, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showMobileLogs(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            const Icon(Icons.terminal, size: 16),
            const SizedBox(width: 8),
            Text(l10n.executionLogs, style: const TextStyle(fontSize: 12)),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_up, size: 16),
          ],
        ),
      ),
    );
  }

  void _showMobileLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: const LogConsoleWidget()),
          ],
        ),
      ),
    );
  }
}