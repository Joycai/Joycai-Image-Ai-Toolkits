import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/app_window_frame.dart';
import '../../widgets/panel_resizer.dart';

/// Narrowest the centre panel is allowed to get.
///
/// Below this the tool headers stop fitting their own controls — the prompt
/// assistant's header alone needs ~290px of non-shrinkable chrome — and the
/// gallery cards stop being cards. The two side panels are what has to give.
const double kMinCenterWidth = 400;

/// Narrowest each side panel may be dragged to.
///
/// Hoisted out of `_resolvePanels`, where they were locals, because the two
/// resizer drags have to clamp against the *same* numbers the layout does —
/// they were repeated as literals at the drag sites, which is how a floor
/// drifts.
const double kLeftPanelMin = 200;
const double kRightPanelMin = 250;

/// Widest the left panel may ever be, independent of the row.
const double kLeftPanelMax = 500;

/// How far past a bound a resizer drag keeps accumulating before it stops.
///
/// A hard clamp on the stored width is what made the resizer let go of the
/// pointer. Drag 200px past the ceiling and the width stops at the ceiling
/// while the pointer keeps travelling — so the first 200px of the drag *back*
/// moves nothing, and by the time the panel re-engages the grip is 200px away
/// from the cursor. It is the most reliably noticeable thing about the old
/// resizer, and it reads as the handle having come loose rather than as an
/// edge.
///
/// Not fixed by leaving the width unclamped: the overshoot is then unbounded,
/// and `_leftWidth` is also AppState's sidebar width, so an enthusiastic drag
/// would persist 3000 to every other screen.
///
/// So the width keeps accumulating past the bound, but only this far, and the
/// value is snapped back into range on release. The panel itself is still
/// drawn clamped — `_resolvePanels` sees to that, and the centre column's
/// floor is a hard layout constraint that cannot be rendered through, so the
/// spring-past-the-edge that would be the fuller answer is deliberately not
/// attempted here. What this buys is that the drag back re-engages within
/// 24px whatever the overshoot, which at any real drag speed is under a
/// frame's travel and reads as a firm stop.
const double _kDragSlack = 24;

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

  // Value equality, because this is handed to `Provider.value` from a build
  // method — a fresh instance every time. Without it the default
  // `updateShouldNotify` (`previous != value`) compares identity, so it was
  // always true and every dependent was notified on every build of the
  // layout. [WorkbenchTopBar] watches this, and the layout rebuilds on every
  // frame of a panel drag, where none of these four values move: the drag
  // changes the panel widths, not the row's width or which side is in a
  // drawer. These four are the whole class — the getters and the two openers
  // are derived from them — so equality here is equality of behaviour.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchLayoutState &&
          scaffoldKey == other.scaffoldKey &&
          contentWidth == other.contentWidth &&
          leftInDrawer == other.leftInDrawer &&
          rightInDrawer == other.rightInDrawer;

  @override
  int get hashCode =>
      Object.hash(scaffoldKey, contentWidth, leftInDrawer, rightInDrawer);
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
  /// `A1 16a`'s config column.
  double _rightWidth = 340;

  @override
  void initState() {
    super.initState();
    // Restore persisted panel widths so the layout matches the last session.
    final appState = Provider.of<AppState>(context, listen: false);
    _leftWidth = appState.sidebarWidth.clamp(kLeftPanelMin, kLeftPanelMax);
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
        // Transparent, so the centre column shows [AppWindowBackdrop]. This
        // is the one screen the spec leaves bare: the two side columns are
        // opaque and paint over the backdrop, the gallery between them does
        // not, and the image cards sit straight on the mesh.
        //
        // Falls back to the canvas colour on mobile, where there is no window
        // frame behind this to show.
        backgroundColor: usesCustomWindowChrome
            ? Colors.transparent
            : Theme.of(context).colorScheme.surfaceContainer,
        body: Column(
          children: [
            if (widget.topBar != null) widget.topBar!,
            Expanded(
              // No padding. `A1` runs the three columns edge to edge into the
              // window; the 8px inset belonged to the card layout, where it was
              // what let the canvas read as a ground the cards floated on.
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
                      PanelCard(
                        width: panels.left,
                        shape: PanelShape.column,
                        child: widget.leftPanel!,
                      ),
                      PanelResizer(
                        shape: PanelShape.column,
                        // Clamped to the layout's own ceiling plus [_kDragSlack],
                        // not to the ceiling itself — see that constant for why
                        // the exact clamp matters more than it looks.
                        onDrag: (delta) {
                          setState(() {
                            _leftWidth = (_leftWidth + delta).clamp(
                              kLeftPanelMin - _kDragSlack,
                              panels.leftMax + _kDragSlack,
                            );
                          });
                        },
                        onDragEnd: () {
                          // Settle out of the slack before anything persists it.
                          setState(() {
                            _leftWidth = _leftWidth.clamp(kLeftPanelMin, panels.leftMax);
                          });
                          Provider.of<AppState>(context, listen: false)
                              .setSidebarWidth(_leftWidth);
                        },
                      ),
                    ],

                    // Center Content
                    Expanded(
                      // Transparent, unlike the two side columns. `A1` gives
                      // the gallery area no ground of its own — the image cards
                      // sit straight on the window's backdrop — while the
                      // panels either side stay opaque.
                      child: PanelCard(
                        shape: PanelShape.column,
                        transparent: true,
                        child: widget.centerContent,
                      ),
                    ),

                    // Right Panel
                    if (panels.rightInline) ...[
                      PanelResizer(
                        shape: PanelShape.column,
                        onDrag: (delta) {
                          setState(() {
                            _rightWidth = (_rightWidth - delta).clamp(
                              kRightPanelMin - _kDragSlack,
                              panels.rightMax + _kDragSlack,
                            );
                          });
                        },
                        onDragEnd: () {
                          setState(() {
                            _rightWidth = _rightWidth.clamp(kRightPanelMin, panels.rightMax);
                          });
                          DatabaseService().saveSetting(
                              'workbench_right_panel_width', _rightWidth.round().toString());
                        },
                      ),
                      PanelCard(
                        width: panels.right,
                        shape: PanelShape.column,
                        child: widget.rightPanelBuilder!(null),
                      ),
                    ],
                  ],
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
    // Has to match what the resizers between these panels actually take, or
    // the widths worked out here do not add up to the row.
    final double gutter = PanelResizer.thicknessOf(PanelShape.column);

    // Unchanged from before: the right panel may not exceed 40% of the row.
    final double rightMax = (row * 0.40).clamp(kRightPanelMin, 600.0);

    bool leftInline = wantsLeft;
    bool rightInline = wantsRight;
    double left = wantsLeft ? _leftWidth.clamp(kLeftPanelMin, kLeftPanelMax) : 0;
    double right = wantsRight ? _rightWidth.clamp(kRightPanelMin, rightMax) : 0;

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
      right = (right - over()).clamp(kRightPanelMin, rightMax);
    }
    if (leftInline && over() > 0) {
      left = (left - over()).clamp(kLeftPanelMin, kLeftPanelMax);
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
            .clamp(kLeftPanelMin, kLeftPanelMax)
        : kLeftPanelMax;
    final double rightCeiling = rightInline
        ? (row - left - (leftInline ? gutter : 0) - gutter - kMinCenterWidth)
            .clamp(kRightPanelMin, rightMax)
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

