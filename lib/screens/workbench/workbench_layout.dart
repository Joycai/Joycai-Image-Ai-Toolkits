import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/panel_resizer.dart';

class WorkbenchLayoutState {
  final GlobalKey<ScaffoldState> scaffoldKey;
  WorkbenchLayoutState(this.scaffoldKey);

  void openLeftPanel() => scaffoldKey.currentState?.openDrawer();
  void openRightPanel() => scaffoldKey.currentState?.openEndDrawer();
}

typedef WorkbenchRightPanelBuilder = Widget Function(ScrollController? scrollController);

class WorkbenchLayout extends StatefulWidget {
  final Widget centerContent;
  final Widget? leftPanel;
  final WorkbenchRightPanelBuilder? rightPanelBuilder;
  final Widget? topBar;
  final Widget? bottomPanel;
  final bool showLeftPanel;
  final bool showRightPanel;
  final IconData? fabIcon;

  const WorkbenchLayout({
    super.key,
    required this.centerContent,
    this.leftPanel,
    this.rightPanelBuilder,
    this.topBar,
    this.bottomPanel,
    this.showLeftPanel = true,
    this.showRightPanel = true,
    this.fabIcon,
  });

  @override
  State<WorkbenchLayout> createState() => _WorkbenchLayoutState();
}

class _WorkbenchLayoutState extends State<WorkbenchLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late double _leftWidth;
  double _rightWidth = 350;

  @override
  void initState() {
    super.initState();
    // Restore persisted panel widths so the layout matches the last session.
    final appState = Provider.of<AppState>(context, listen: false);
    _leftWidth = appState.sidebarWidth.clamp(200.0, 500.0);
    _loadRightWidth();
  }

  Future<void> _loadRightWidth() async {
    final saved = await DatabaseService().getSetting('workbench_right_panel_width');
    final width = double.tryParse(saved ?? '');
    if (width != null && mounted) {
      setState(() => _rightWidth = width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);
    final isNarrow = Responsive.isNarrow(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (isMobile) {
      return _buildMobileLayout(context, screenWidth);
    }

    // Cap right panel to 40% of screen so content area is never squeezed below 60%
    final rightMaxWidth = (screenWidth * 0.40).clamp(250.0, 600.0);

    return Provider<WorkbenchLayoutState>.value(
      value: WorkbenchLayoutState(_scaffoldKey),
      child: Scaffold(
        key: _scaffoldKey,
        // Inset-panel canvas: panels are rounded cards floating on this
        // tinted background, separated by resizer gutters instead of lines.
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: Column(
          children: [
            if (widget.topBar != null) widget.topBar!,
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, widget.bottomPanel == null ? 8 : 0),
                child: Row(
                  children: [
                    // Left Panel
                    if (widget.leftPanel != null && widget.showLeftPanel && !isTablet) ...[
                      PanelCard(width: _leftWidth, child: widget.leftPanel!),
                      PanelResizer(
                        onDrag: (delta) {
                          setState(() {
                            _leftWidth = (_leftWidth + delta).clamp(200.0, 500.0);
                          });
                        },
                        onDragEnd: () {
                          Provider.of<AppState>(context, listen: false)
                              .setSidebarWidth(_leftWidth);
                        },
                      ),
                    ],

                    // Center Content
                    Expanded(
                      child: PanelCard(child: widget.centerContent),
                    ),

                    // Right Panel
                    if (widget.rightPanelBuilder != null && widget.showRightPanel && !isNarrow) ...[
                      PanelResizer(
                        onDrag: (delta) {
                          setState(() {
                            _rightWidth = (_rightWidth - delta).clamp(250.0, rightMaxWidth);
                          });
                        },
                        onDragEnd: () => DatabaseService().saveSetting(
                            'workbench_right_panel_width', _rightWidth.round().toString()),
                      ),
                      PanelCard(
                        width: _rightWidth.clamp(250.0, rightMaxWidth),
                        child: widget.rightPanelBuilder!(null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.bottomPanel != null) widget.bottomPanel!,
          ],
        ),
        drawer: (isTablet && widget.leftPanel != null)
            ? Drawer(width: (screenWidth * 0.75).clamp(200.0, 300.0), child: widget.leftPanel)
            : null,
        endDrawer: (isNarrow && widget.rightPanelBuilder != null)
            ? Drawer(width: (screenWidth * 0.80).clamp(280.0, 350.0), child: widget.rightPanelBuilder!(null))
            : null,
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, double screenWidth) {
    final mobileDrawerWidth = (screenWidth * 0.80).clamp(200.0, 300.0);
    final layoutState = WorkbenchLayoutState(_scaffoldKey);
    return Provider<WorkbenchLayoutState>.value(
      value: layoutState,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: widget.topBar != null ? PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 8),
          child: Provider<WorkbenchLayoutState>.value(
            value: layoutState,
            child: widget.topBar!,
          ),
        ) : null,
        body: Column(
          children: [
            Expanded(child: widget.centerContent),
            if (widget.bottomPanel != null) widget.bottomPanel!,
          ],
        ),
        drawer: widget.leftPanel != null ? Drawer(width: mobileDrawerWidth, child: widget.leftPanel) : null,
        floatingActionButton: (widget.rightPanelBuilder != null && widget.fabIcon != null)
            ? FloatingActionButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (bottomSheetContext) => Provider<WorkbenchLayoutState>.value(
                      value: layoutState,
                      child: DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.6,
                        minChildSize: 0.3,
                        maxChildSize: 0.95,
                        builder: (ctx, scrollController) {
                          return widget.rightPanelBuilder!(scrollController);
                        },
                      ),
                    ),
                  );
                },
                child: Icon(widget.fabIcon),
              )
            : null,
      ),
    );
  }
}

