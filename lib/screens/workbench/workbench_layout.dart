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

    if (isMobile) {
      return _buildMobileLayout(context);
    }

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
                    _buildDivider(
                      isLeft: true,
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
                    _buildDivider(
                      isLeft: false,
                      onResize: (delta) {
                        setState(() {
                          _rightWidth = (_rightWidth - delta).clamp(250.0, 600.0);
                        });
                      },
                    ),
                    SizedBox(
                      width: isTablet ? 280 : _rightWidth,
                      child: widget.rightPanelBuilder!(null),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.bottomPanel != null) widget.bottomPanel!,
          ],
        ),
        drawer: (isTablet && widget.leftPanel != null) ? Drawer(width: 300, child: widget.leftPanel) : null,
        endDrawer: (isNarrow && widget.rightPanelBuilder != null) ? Drawer(width: 350, child: widget.rightPanelBuilder!(null)) : null,
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Provider<WorkbenchLayoutState>.value(
      value: WorkbenchLayoutState(_scaffoldKey),
      child: Scaffold(
        key: _scaffoldKey,
        appBar: widget.topBar != null ? PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 1), // +1 for the divider
          child: Provider<WorkbenchLayoutState>.value(
            value: WorkbenchLayoutState(_scaffoldKey),
            child: widget.topBar!,
          ),
        ) : null,
        body: widget.centerContent,
        drawer: widget.leftPanel != null ? Drawer(width: 300, child: widget.leftPanel) : null,
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

  Widget _buildDivider({
    required bool isLeft,
    required Function(double) onResize,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 4,
          color: colorScheme.outlineVariant.withAlpha(50),
          child: Center(
            child: Container(
              width: 1,
              color: colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
