import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/collapsible_card.dart';
import '../../widgets/log_console.dart';
import '../../widgets/unified_sidebar.dart';
import 'control_panel.dart';
import 'gallery.dart';
import 'widgets/gallery_toolbar.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  double _consoleHeight = 200.0;
  int _lastKnownTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Initialize with current state
    final appState = Provider.of<AppState>(context, listen: false);
    _lastKnownTabIndex = appState.workbenchTabIndex;
    if (_lastKnownTabIndex != _tabController.index) {
      _tabController.animateTo(_lastKnownTabIndex);
    }
    
    // Sync from TabController to AppState (User interaction)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // User finished switching tabs
        if (_tabController.index != _lastKnownTabIndex) {
          _lastKnownTabIndex = _tabController.index;
          appState.setWorkbenchTab(_tabController.index);
        }
      }
    });
    
    // Sync from AppState to TabController (Programmatic change)
    appState.addListener(() {
      if (!mounted) return;
      
      // Only react if the index ACTUALLY changed in AppState
      // and it's different from our local controller
      if (appState.workbenchTabIndex != _lastKnownTabIndex) {
        _lastKnownTabIndex = appState.workbenchTabIndex;
        if (_tabController.index != _lastKnownTabIndex) {
           _tabController.animateTo(_lastKnownTabIndex);
        }
      }
    });
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
            Tab(text: l10n.sourceGallery, icon: const Icon(Icons.image_search)),
            Tab(text: l10n.processResults, icon: const Icon(Icons.auto_awesome)),
            Tab(text: l10n.tempWorkspace, icon: const Icon(Icons.workspaces)),
          ],
        ),
      ) : null,
      drawer: isNarrow ? const Drawer(width: 300, child: UnifiedSidebar()) : null,
      endDrawer: isNarrow ? const Drawer(width: 350, child: ControlPanelWidget()) : null,
      body: Column(
        children: [
          if (!isNarrow)
            Container(
              color: colorScheme.surface,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(appState.isSidebarExpanded ? Icons.menu_open : Icons.menu),
                    onPressed: () => appState.setSidebarExpanded(!appState.isSidebarExpanded),
                    tooltip: appState.isSidebarExpanded ? "Collapse Sidebar" : "Expand Sidebar",
                  ),
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                      tabs: !isNarrow ? [
                        Tab(child: Row(children: [const Icon(Icons.image_search, size: 18), const SizedBox(width: 8), Text(l10n.sourceGallery)])),
                        Tab(child: Row(children: [const Icon(Icons.auto_awesome, size: 18), const SizedBox(width: 8), Text(l10n.processResults)])),
                        Tab(child: Row(children: [const Icon(Icons.workspaces, size: 18), const SizedBox(width: 8), Text(l10n.tempWorkspace)])),
                      ] : [
                        Tab(text: l10n.sourceGallery, icon: const Icon(Icons.image_search)),
                        Tab(text: l10n.processResults, icon: const Icon(Icons.auto_awesome)),
                        Tab(text: l10n.tempWorkspace, icon: const Icon(Icons.workspaces)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          GalleryToolbar(tabController: _tabController),
          
          Expanded(
            child: Stack(
              children: [
                // Layer 1: Main Content & Control Panel
                Row(
                  children: [
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
                
                // Layer 2: Scrim (Dark overlay)
                if (!isNarrow && appState.isSidebarExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => appState.setSidebarExpanded(false),
                      child: Container(
                        color: Colors.black.withAlpha(100),
                      ),
                    ),
                  ),

                // Layer 3: Overlay Sidebar
                if (!isNarrow)
                  AnimatedPositioned(
                    duration: appState.isSidebarResizing ? Duration.zero : const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    left: appState.isSidebarExpanded ? 0 : -appState.sidebarWidth,
                    top: 0,
                    bottom: 0,
                    width: appState.sidebarWidth,
                    child: Material(
                      elevation: 16,
                      shadowColor: Colors.black54,
                      child: const UnifiedSidebar(),
                    ),
                  ),
              ],
            ),
          ),
          
          if (!isMobile) ...[
            _buildResizableConsole(context, appState, l10n),
          ] else 
            _buildMobileStatusBar(context, appState, l10n),
        ],
      ),
    );
  }

  Widget _buildResizableConsole(BuildContext context, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        // Resize Handle
        if (appState.isConsoleExpanded)
          GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _consoleHeight = (_consoleHeight - details.delta.dy).clamp(100.0, 600.0);
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Container(
                height: 4,
                width: double.infinity,
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
          ),
        
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
            content: SizedBox(
              height: _consoleHeight,
              child: const LogConsoleWidget(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileStatusBar(BuildContext context, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final lastLog = appState.logs.isNotEmpty ? appState.logs.last : null;

    return InkWell(
      onTap: () => _showMobileLogs(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            const Icon(Icons.terminal, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lastLog?.message ?? l10n.executionLogs,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
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
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Expanded(child: LogConsoleWidget()),
          ],
        ),
      ),
    );
  }
}
