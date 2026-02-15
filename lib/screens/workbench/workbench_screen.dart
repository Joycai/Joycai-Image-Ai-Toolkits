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
    _initTabController();
    
    // Sync from AppState to TabController (Programmatic change)
    final appState = Provider.of<AppState>(context, listen: false);
    appState.addListener(() {
      if (!mounted) return;
      
      // Only react if the index ACTUALLY changed in AppState
      // and it's different from our local controller
      if (appState.workbenchTabIndex != _lastKnownTabIndex) {
        _lastKnownTabIndex = appState.workbenchTabIndex;
        // Check bounds before animating
        final targetIndex = _lastKnownTabIndex.clamp(0, _tabController.length - 1);
        if (_tabController.index != targetIndex) {
           _tabController.animateTo(targetIndex);
        }
      }
    });
  }

  void _initTabController() {
    final appState = Provider.of<AppState>(context, listen: false);
    // Ensure we use the latest safe index
    _lastKnownTabIndex = appState.workbenchTabIndex.clamp(0, 3);
    
    _tabController = TabController(length: 4, vsync: this, initialIndex: _lastKnownTabIndex);
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // User finished switching tabs
        if (_tabController.index != _lastKnownTabIndex) {
          _lastKnownTabIndex = _tabController.index;
          appState.setWorkbenchTab(_tabController.index);
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
    // Check for Hot Reload mismatch or length change
    if (_tabController.length != 4) {
       _tabController.dispose();
       _initTabController();
    }

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
          icon: const Icon(Icons.view_sidebar),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: l10n.sidebar,
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
            Tab(text: l10n.promptOptimizer, icon: const Icon(Icons.auto_fix_high)),
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
                        Tab(child: Row(children: [const Icon(Icons.auto_fix_high, size: 18), const SizedBox(width: 8), Text(l10n.promptOptimizer)])),
                        Tab(child: Row(children: [const Icon(Icons.auto_awesome, size: 18), const SizedBox(width: 8), Text(l10n.processResults)])),
                        Tab(child: Row(children: [const Icon(Icons.workspaces, size: 18), const SizedBox(width: 8), Text(l10n.tempWorkspace)])),
                      ] : [
                        Tab(text: l10n.sourceGallery, icon: const Icon(Icons.image_search)),
                        Tab(text: l10n.promptOptimizer, icon: const Icon(Icons.auto_fix_high)),
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
                Positioned.fill(
                  bottom: isMobile ? 0 : 40, // Reserve space for the collapsed console bar
                  child: Row(
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
                ),
                
                // Layer 2: Scrim (Dark overlay for sidebar)
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

                // Layer 4: Floating Overlay Console (Desktop only)
                if (!isMobile)
                  Positioned(
                    left: 0,
                    right: isNarrow ? 0 : 351, 
                    bottom: 0,
                    child: _buildResizableConsole(context, appState, l10n),
                  ),
              ],
            ),
          ),
          
          if (isMobile) 
            _buildMobileStatusBar(context, appState, l10n),
        ],
      ),
    );
  }

  Widget _buildResizableConsole(BuildContext context, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      elevation: appState.isConsoleExpanded ? 24 : 0,
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  height: 6,
                  width: double.infinity,
                  color: colorScheme.primary.withValues(alpha: 0.1),
                ),
              ),
            ),
          
          Container(
            height: appState.isConsoleExpanded ? null : 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: appState.isConsoleExpanded ? 0.98 : 0.8),
              border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 1)),
              boxShadow: appState.isConsoleExpanded ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, -3),
                )
              ] : null,
            ),
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
      ),
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
