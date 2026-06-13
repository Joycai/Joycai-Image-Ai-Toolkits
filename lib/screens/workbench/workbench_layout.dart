import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';

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

  const WorkbenchLayout({
    super.key,
    required this.centerContent,
    this.leftPanel,
    this.rightPanelBuilder,
    this.topBar,
    this.bottomPanel,
    this.showLeftPanel = true,
    this.showRightPanel = true,
  });

  @override
  State<WorkbenchLayout> createState() => _WorkbenchLayoutState();
}

class _WorkbenchLayoutState extends State<WorkbenchLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();     
  double _leftWidth = 300;
  double _rightWidth = 350;

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
        body: Column(
          children: [
            if (widget.topBar != null) widget.topBar!,
            Expanded(
              child: Row(
                children: [
                  // Left Panel
                  if (widget.leftPanel != null && widget.showLeftPanel && !isTablet) ...[
                    SizedBox(
                      width: _leftWidth,
                      child: widget.leftPanel,
                    ),
                    _ResizableDivider(
                      onResize: (delta) {
                        setState(() {
                          _leftWidth = (_leftWidth + delta).clamp(200.0, 500.0);
                        });
                      },
                    ),
                  ],

                  // Center Content
                  Expanded(
                    child: widget.centerContent,
                  ),

                  // Right Panel
                  if (widget.rightPanelBuilder != null && widget.showRightPanel && !isNarrow) ...[
                    _ResizableDivider(
                      onResize: (delta) {
                        setState(() {
                          _rightWidth = (_rightWidth - delta).clamp(250.0, rightMaxWidth);
                        });
                      },
                    ),
                    SizedBox(
                      width: _rightWidth.clamp(250.0, rightMaxWidth),
                      child: widget.rightPanelBuilder!(null),
                    ),
                  ],
                ],
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
    return Provider<WorkbenchLayoutState>.value(
      value: WorkbenchLayoutState(_scaffoldKey),
      child: Scaffold(
        key: _scaffoldKey,
        appBar: widget.topBar != null ? PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 1),
          child: Provider<WorkbenchLayoutState>.value(
            value: WorkbenchLayoutState(_scaffoldKey),
            child: widget.topBar!,
          ),
        ) : null,
        body: widget.centerContent,
        drawer: widget.leftPanel != null ? Drawer(width: mobileDrawerWidth, child: widget.leftPanel) : null,
        floatingActionButton: widget.rightPanelBuilder != null ? FloatingActionButton(
          onPressed: () {
            final workbenchState = WorkbenchLayoutState(_scaffoldKey);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (bottomSheetContext) => Provider<WorkbenchLayoutState>.value(
                value: workbenchState,
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.6,
                  minChildSize: 0.3,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) {
                    return widget.rightPanelBuilder!(scrollController);
                  },
                ),
              ),
            );
          },
          child: const Icon(Icons.tune),
        ) : null,
        bottomNavigationBar: widget.bottomPanel,
      ),
    );
  }
}

class _ResizableDivider extends StatefulWidget {
  final Function(double) onResize;

  const _ResizableDivider({required this.onResize});

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => widget.onResize(details.delta.dx),
        child: Container(
          width: 10, // Increased hit area
          color: Colors.transparent, // Invisible hit area background
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isHovering ? 2 : 1,
              height: double.infinity,
              color: _isHovering ? colorScheme.primary : colorScheme.outlineVariant.withAlpha(100),
            ),
          ),
        ),
      ),
    );
  }
}
