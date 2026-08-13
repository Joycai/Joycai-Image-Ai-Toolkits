import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/panel_resizer.dart';

/// Narrowest the centre panel is allowed to get.
///
/// Below this the tool headers stop fitting their own controls — the prompt
/// assistant's header alone needs ~290px of non-shrinkable chrome — and the
/// gallery cards stop being cards. The two side panels are what has to give.
const double kMinCenterWidth = 400;

class WorkbenchLayoutState {
  final GlobalKey<ScaffoldState> scaffoldKey;

  /// Width the workbench actually got, which is the window minus the app's
  /// navigation rail. Everything laid out inside has to measure against this
  /// and not `MediaQuery.size.width`: the rail is 78px on desktop and 64 on
  /// tablet, enough to put the real content box a whole breakpoint below what
  /// the screen width claims.
  final double contentWidth;

  /// Whether each side panel is reachable only through a drawer right now —
  /// either because the layout is narrow or because it was squeezed out of the
  /// row. Whoever draws the chrome owes the user a button that opens it, so
  /// this is read by [WorkbenchTopBar] rather than re-derived from the screen
  /// width: a panel in a drawer with no button is a panel the user has lost.
  final bool leftInDrawer;
  final bool rightInDrawer;

  WorkbenchLayoutState(
    this.scaffoldKey, {
    required this.contentWidth,
    required this.leftInDrawer,
    required this.rightInDrawer,
  });

  bool get isMobile => contentWidth < Responsive.mobileBreakpoint;
  bool get isNarrow => contentWidth < Responsive.tabletBreakpoint;

  void openLeftPanel() => scaffoldKey.currentState?.openDrawer();
  void openRightPanel() => scaffoldKey.currentState?.openEndDrawer();
}

typedef WorkbenchRightPanelBuilder = Widget Function(ScrollController? scrollController);

/// One frame's answer to "how wide are the side panels, and are they even
/// columns?" — see `_WorkbenchLayoutState._resolvePanels`.
class _PanelWidths {
  final double left;
  final double right;
  final bool leftInline;
  final bool rightInline;

  /// Ceilings for the resizer drags, so a drag stops at the same place the
  /// layout would have clamped it to.
  final double leftMax;
  final double rightMax;

  const _PanelWidths({
    required this.left,
    required this.right,
    required this.leftInline,
    required this.rightInline,
    required this.leftMax,
    required this.rightMax,
  });
}

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
    // The width the workbench is handed, not the width of the window: the app
    // draws a 64–78px navigation rail beside this, so `MediaQuery.size.width`
    // overstates the content box by a whole breakpoint's worth on an iPad-class
    // screen. Measuring the screen is what let a 1024pt window run the desktop
    // three-column branch with only 946px to spend, and squeeze the centre to
    // 152px.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double available) {
    if (available < Responsive.mobileBreakpoint) {
      return _buildMobileLayout(context, available);
    }

    final isTablet = available < Responsive.tabletBreakpoint;

    // Width of the row inside the canvas inset.
    final row = available - 16;
    final panels = _resolvePanels(
      row,
      wantsLeft: widget.leftPanel != null && widget.showLeftPanel && !isTablet,
      wantsRight: widget.rightPanelBuilder != null && widget.showRightPanel && !isTablet,
    );

    // A drawer for whichever panel is not a column. The tab's own `showXPanel`
    // still decides whether the panel exists at all on this tab — a panel the
    // tab switched off has no drawer and no button, same as before.
    final leftInDrawer = widget.leftPanel != null &&
        (isTablet || (widget.showLeftPanel && !panels.leftInline));
    final rightInDrawer = widget.rightPanelBuilder != null &&
        (isTablet || (widget.showRightPanel && !panels.rightInline));

    return Provider<WorkbenchLayoutState>.value(
      value: WorkbenchLayoutState(
        _scaffoldKey,
        contentWidth: available,
        leftInDrawer: leftInDrawer,
        rightInDrawer: rightInDrawer,
      ),
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
                  // Stretch, not the default centre. PanelCard is a SizedBox
                  // with a width and no height, so under the loose vertical
                  // constraint a centred Row hands out, a panel whose body is
                  // a bare SingleChildScrollView shrink-wraps to its content
                  // and then floats in the middle of the canvas with bare
                  // surface above and below it. Panels are columns of a
                  // layout; they should always be the height of the row.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Panel
                    if (panels.leftInline) ...[
                      PanelCard(width: panels.left, child: widget.leftPanel!),
                      PanelResizer(
                        // Clamped to the same ceiling the layout would enforce
                        // anyway, so the drag stops where the panel stops
                        // instead of running on against an invisible wall.
                        onDrag: (delta) {
                          setState(() {
                            _leftWidth = (_leftWidth + delta).clamp(200.0, panels.leftMax);
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
                    if (panels.rightInline) ...[
                      PanelResizer(
                        onDrag: (delta) {
                          setState(() {
                            _rightWidth = (_rightWidth - delta).clamp(250.0, panels.rightMax);
                          });
                        },
                        onDragEnd: () => DatabaseService().saveSetting(
                            'workbench_right_panel_width', _rightWidth.round().toString()),
                      ),
                      PanelCard(
                        width: panels.right,
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
        drawer: leftInDrawer
            ? Drawer(width: (available * 0.75).clamp(200.0, 300.0), child: widget.leftPanel)
            : null,
        endDrawer: rightInDrawer
            ? Drawer(width: (available * 0.80).clamp(280.0, 350.0), child: widget.rightPanelBuilder!(null))
            : null,
      ),
    );
  }

  /// Resolves what the two side panels are actually drawn at, given [row] px of
  /// canvas to share with a centre that may not go below [kMinCenterWidth].
  ///
  /// Only the returned numbers are clamped: `_leftWidth` and `_rightWidth` stay
  /// the width the user dragged to (and `_leftWidth` is also `AppState`'s
  /// sidebar width, shared with the other screens), so both panels come back at
  /// full size when the window grows again rather than being permanently
  /// shrunk by having once been opened small.
  _PanelWidths _resolvePanels(
    double row, {
    required bool wantsLeft,
    required bool wantsRight,
  }) {
    const double gutter = 14; // PanelResizer
    const double leftMin = 200;
    const double rightMin = 250;

    // Unchanged from before: the right panel may not exceed 40% of the row.
    final double rightMax = (row * 0.40).clamp(rightMin, 600.0);

    bool leftInline = wantsLeft;
    bool rightInline = wantsRight;
    double left = wantsLeft ? _leftWidth.clamp(leftMin, 500.0) : 0;
    double right = wantsRight ? _rightWidth.clamp(rightMin, rightMax) : 0;

    double over() =>
        left +
        right +
        (leftInline ? gutter : 0) +
        (rightInline ? gutter : 0) +
        kMinCenterWidth -
        row;

    // The right panel gives way first — it holds settings, which the user can
    // finish with, where the left holds the files they are working through.
    if (rightInline && over() > 0) {
      right = (right - over()).clamp(rightMin, rightMax);
    }
    if (leftInline && over() > 0) {
      left = (left - over()).clamp(leftMin, 500.0);
    }
    // Both already at their minimums and the centre still cannot have its
    // floor: the left panel falls back to the drawer it already uses on tablet.
    // Unreachable at today's numbers — the narrowest row that gets here is 984,
    // which fits 200 + 250 + 28 + 400 with room over — and kept as the floor's
    // actual guarantee rather than something inferred from four constants that
    // are free to move.
    if (leftInline && over() > 0) {
      leftInline = false;
      left = 0;
    }

    // What a drag may reach, so the resizer cannot re-create the squeeze.
    final double leftCeiling = leftInline
        ? (row - right - (rightInline ? gutter : 0) - gutter - kMinCenterWidth)
            .clamp(leftMin, 500.0)
        : 500.0;
    final double rightCeiling = rightInline
        ? (row - left - (leftInline ? gutter : 0) - gutter - kMinCenterWidth)
            .clamp(rightMin, rightMax)
        : rightMax;

    return _PanelWidths(
      left: left,
      right: right,
      leftInline: leftInline,
      rightInline: rightInline,
      leftMax: leftCeiling,
      rightMax: rightCeiling,
    );
  }

  Widget _buildMobileLayout(BuildContext context, double screenWidth) {
    final mobileDrawerWidth = (screenWidth * 0.80).clamp(200.0, 300.0);
    final layoutState = WorkbenchLayoutState(
      _scaffoldKey,
      contentWidth: screenWidth,
      leftInDrawer: widget.leftPanel != null,
      // The right panel is a bottom sheet behind the FAB here, not a drawer.
      rightInDrawer: false,
    );
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

