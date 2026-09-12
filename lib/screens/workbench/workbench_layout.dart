import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/panel_resizer.dart';
import 'widgets/workbench_glass_toolbar.dart';

/// Narrowest the centre column is allowed to get. Below this the gallery
/// cards stop being cards; the two side columns are what has to give.
const double kMinCenterWidth = 400;

/// Narrowest each side column may be dragged to.
const double kLeftPanelMin = 200;
const double kRightPanelMin = 250;

/// Widest the left column may ever be, independent of the row.
const double kLeftPanelMax = 500;

/// The right column's width before the user has dragged it (`A1 · 1a`: 300).
const double kRightPanelDefault = 300;

/// How far past a bound a resizer drag keeps accumulating before it stops, so
/// the drag back re-engages within this distance instead of wherever the
/// pointer wandered to. Snapped back into range on release.
const double _kDragSlack = 24;

class WorkbenchLayoutState {
  final GlobalKey<ScaffoldState> scaffoldKey;

  /// Width the workbench actually got — measure against this, not the window.
  final double contentWidth;

  /// Whether this tab has a left panel at all, inline, collapsed or in a
  /// drawer. The toolbar's sidebar toggle is disabled without one.
  final bool hasLeftPanel;

  /// Whether each side panel is reachable only through a drawer right now.
  /// Whoever draws the chrome owes the user a button that opens it.
  final bool leftInDrawer;
  final bool rightInDrawer;

  /// How much of the centre column the toolbar covers from the top, and the
  /// floating overlay from the bottom — content that scrolls under the chrome
  /// pads itself by these.
  final double topClearance;
  final double bottomClearance;

  /// Opens the right panel as the phone's bottom sheet (`01 · 1h`). Null
  /// wherever the panel is inline or in a drawer instead.
  ///
  /// A method tear-off of the layout's state, so it compares equal from one
  /// build to the next and leaves [operator ==] meaningful.
  final VoidCallback? rightSheetOpener;

  WorkbenchLayoutState(
    this.scaffoldKey, {
    required this.contentWidth,
    required this.leftInDrawer,
    required this.rightInDrawer,
    this.hasLeftPanel = true,
    this.topClearance = 0,
    this.bottomClearance = 0,
    this.rightSheetOpener,
  });

  bool get isMobile => contentWidth < Responsive.mobileBreakpoint;
  bool get isNarrow => contentWidth < Responsive.tabletBreakpoint;

  void openLeftPanel() => scaffoldKey.currentState?.openDrawer();
  /// Whether the right panel is off screen until something opens it — a
  /// drawer on a tablet, a sheet on a phone. A control that shows or hides
  /// the panel inline has to open it instead here.
  bool get rightPanelDetached => rightInDrawer || rightSheetOpener != null;

  void openRightPanel() {
    final opener = rightSheetOpener;
    if (opener != null) {
      opener();
    } else {
      scaffoldKey.currentState?.openEndDrawer();
    }
  }

  // Value equality: this is handed to `Provider.value` from a build method,
  // and the layout rebuilds on every frame of a panel drag, where none of
  // these move.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchLayoutState &&
          scaffoldKey == other.scaffoldKey &&
          contentWidth == other.contentWidth &&
          hasLeftPanel == other.hasLeftPanel &&
          leftInDrawer == other.leftInDrawer &&
          rightInDrawer == other.rightInDrawer &&
          topClearance == other.topClearance &&
          bottomClearance == other.bottomClearance &&
          rightSheetOpener == other.rightSheetOpener;

  @override
  int get hashCode => Object.hash(scaffoldKey, contentWidth, hasLeftPanel, leftInDrawer, rightInDrawer,
      topClearance, bottomClearance, rightSheetOpener);
}

typedef WorkbenchRightPanelBuilder = Widget Function(ScrollController? scrollController);

/// Builds the workbench toolbar; [phone] asks for the full-width phone bar.
typedef WorkbenchToolbarBuilder = Widget Function(bool phone);

/// One frame's answer to "how wide are the side panels, and are they even
/// columns?".
class _PanelWidths {
  final double left;
  final double right;
  final bool leftInline;
  final bool rightInline;
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

/// The workbench's frame (`A1 · 1a / 1d / 1e`).
///
/// - **Desktop** — three columns edge to edge: the left and right columns are
///   opaque column-coloured panels, the centre column is bare over the aurora
///   (unless [centerGround] gives it one), and [centerOverlay] floats at the
///   centre's bottom. The toolbar floats 10px inside the top of the *whole
///   row*, across all three columns (`00e · 2b`): its tab strip keeps its
///   window position whichever panel appears or hides, and every column's
///   content starts below it.
/// - **Tablet** — the centre alone; both side panels live in drawers, and the
///   toolbar carries the buttons that open them.
/// - **Phone** — the toolbar becomes the screen's full-width glass bar, the
///   right panel a glass sheet behind a tinted-glass FAB, the left a drawer.
class WorkbenchLayout extends StatefulWidget {
  final Widget centerContent;
  final Widget? leftPanel;
  final WorkbenchRightPanelBuilder? rightPanelBuilder;
  final WorkbenchToolbarBuilder? toolbarBuilder;

  /// A floating control at the bottom centre of the centre column — the
  /// gallery's selection bar.
  final Widget? centerOverlay;
  final Widget? bottomPanel;
  final bool showLeftPanel;
  final bool showRightPanel;

  /// Whether this tab has a left / right panel at all. A tab without one gets
  /// no column, no drawer and no button for it.
  final bool hasLeftPanel;
  final bool hasRightPanel;

  /// Title of the right panel when it is a drawer or a sheet.
  final String? rightPanelTitle;
  final IconData? fabIcon;
  final Color? centerGround;

  /// Whether [centerContent] scrolls under the toolbar and pads itself by
  /// [WorkbenchLayoutState.topClearance] (the gallery). Otherwise the layout
  /// starts it below the toolbar.
  final bool centerScrollsUnderToolbar;

  const WorkbenchLayout({
    super.key,
    required this.centerContent,
    this.leftPanel,
    this.rightPanelBuilder,
    this.toolbarBuilder,
    this.centerOverlay,
    this.bottomPanel,
    this.showLeftPanel = true,
    this.showRightPanel = true,
    this.hasLeftPanel = true,
    this.hasRightPanel = true,
    this.rightPanelTitle,
    this.fabIcon,
    this.centerGround,
    this.centerScrollsUnderToolbar = false,
  });

  @override
  State<WorkbenchLayout> createState() => _WorkbenchLayoutState();
}

class _WorkbenchLayoutState extends State<WorkbenchLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late double _leftWidth;
  double _rightWidth = kRightPanelDefault;

  @override
  void initState() {
    super.initState();
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

  bool get _hasLeft => widget.hasLeftPanel && widget.leftPanel != null;
  bool get _hasRight => widget.hasRightPanel && widget.rightPanelBuilder != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double available) {
    if (available < Responsive.mobileBreakpoint) {
      return _buildPhoneLayout(context, available);
    }

    final isTablet = available < Responsive.tabletBreakpoint;
    final panels = _resolvePanels(
      available,
      wantsLeft: _hasLeft && widget.showLeftPanel && !isTablet,
      wantsRight: _hasRight && widget.showRightPanel && !isTablet,
    );

    final leftInDrawer = _hasLeft && (isTablet || (widget.showLeftPanel && !panels.leftInline));
    final rightInDrawer = _hasRight && (isTablet || (widget.showRightPanel && !panels.rightInline));

    final layoutState = WorkbenchLayoutState(
      _scaffoldKey,
      contentWidth: available,
      hasLeftPanel: _hasLeft,
      leftInDrawer: leftInDrawer,
      rightInDrawer: rightInDrawer,
      topClearance: widget.toolbarBuilder != null ? WorkbenchGlassToolbar.clearance : 0,
      bottomClearance: widget.centerOverlay != null ? _overlayClearance : 0,
    );

    final center = Stack(
      children: [
        Positioned.fill(
          child: PanelCard(
            shape: PanelShape.column,
            ground: widget.centerGround ?? Colors.transparent,
            child: widget.centerScrollsUnderToolbar || widget.toolbarBuilder == null
                ? widget.centerContent
                : Padding(
                    padding: const EdgeInsets.only(top: WorkbenchGlassToolbar.clearance),
                    child: widget.centerContent,
                  ),
          ),
        ),
        if (widget.centerOverlay != null)
          Positioned(
            left: AppSpace.s10,
            right: AppSpace.s10,
            bottom: 12,
            child: Center(child: widget.centerOverlay),
          ),
      ],
    );

    return Provider<WorkbenchLayoutState>.value(
      value: layoutState,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildColumns(context, panels, center)),
                  if (widget.toolbarBuilder != null)
                    Positioned(
                      left: WorkbenchGlassToolbar.inset,
                      right: WorkbenchGlassToolbar.inset,
                      top: WorkbenchGlassToolbar.inset,
                      child: widget.toolbarBuilder!(false),
                    ),
                ],
              ),
            ),
            if (widget.bottomPanel != null) widget.bottomPanel!,
          ],
        ),
        drawer: leftInDrawer
            ? Drawer(
                width: (available * 0.75).clamp(200.0, 300.0),
                shape: const RoundedRectangleBorder(),
                child: widget.leftPanel,
              )
            : null,
        endDrawer: rightInDrawer
            ? Drawer(
                width: (available * 0.9).clamp(280.0, 350.0),
                shape: const RoundedRectangleBorder(),
                child: _DrawerWithHeader(
                  title: widget.rightPanelTitle,
                  child: widget.rightPanelBuilder!(null),
                ),
              )
            : null,
      ),
    );
  }

  /// A side panel's content, started below the full-width toolbar. The
  /// panel's own ground still runs to the top, under the glass.
  Widget _underToolbar(Widget child) => widget.toolbarBuilder == null
      ? child
      : Padding(
          padding: const EdgeInsets.only(top: WorkbenchGlassToolbar.clearance),
          child: child,
        );

  Widget _buildColumns(BuildContext context, _PanelWidths panels, Widget center) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (panels.leftInline) ...[
          PanelCard(
            width: panels.left,
            shape: PanelShape.column,
            child: _underToolbar(widget.leftPanel!),
          ),
          PanelResizer(
            shape: PanelShape.column,
            onDrag: (delta) {
              setState(() {
                _leftWidth = (_leftWidth + delta).clamp(
                  kLeftPanelMin - _kDragSlack,
                  panels.leftMax + _kDragSlack,
                );
              });
            },
            onDragEnd: () {
              setState(() {
                _leftWidth = _leftWidth.clamp(kLeftPanelMin, panels.leftMax);
              });
              Provider.of<AppState>(context, listen: false).setSidebarWidth(_leftWidth);
            },
          ),
        ],
        Expanded(child: center),
        if (panels.rightInline) ...[
          PanelResizer(
            shape: PanelShape.column,
            ruleSide: PanelRuleSide.leading,
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
            child: _underToolbar(widget.rightPanelBuilder!(null)),
          ),
        ],
      ],
    );
  }

  /// The selection bar's height, its 12px lift and a gutter.
  static const double _overlayClearance = 44 + 12 + AppSpace.s10;

  _PanelWidths _resolvePanels(
    double row, {
    required bool wantsLeft,
    required bool wantsRight,
  }) {
    final double gutter = PanelResizer.thicknessOf(PanelShape.column);
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
    if (leftInline && over() > 0) {
      leftInline = false;
      left = 0;
    }

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

  Widget _buildPhoneLayout(BuildContext context, double screenWidth) {
    // The shell reports the phone dock as bottom padding; the workbench sits
    // above it rather than under it.
    final dockClearance = MediaQuery.paddingOf(context).bottom;
    final layoutState = WorkbenchLayoutState(
      _scaffoldKey,
      contentWidth: screenWidth,
      hasLeftPanel: _hasLeft,
      leftInDrawer: _hasLeft,
      rightInDrawer: false,
      topClearance: widget.toolbarBuilder != null ? WorkbenchGlassToolbar.phoneHeight : 0,
      bottomClearance: widget.centerOverlay != null ? _overlayClearance : 0,
      rightSheetOpener: _hasRight ? _openRightSheet : null,
    );
    _phoneLayoutState = layoutState;

    final showFab = _hasRight && widget.fabIcon != null;

    return Provider<WorkbenchLayoutState>.value(
      value: layoutState,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: _hasLeft
            ? Drawer(
                width: (screenWidth * 0.80).clamp(200.0, 300.0),
                shape: const RoundedRectangleBorder(),
                child: widget.leftPanel,
              )
            : null,
        body: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: dockClearance),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _grounded(
                          widget.centerScrollsUnderToolbar || widget.toolbarBuilder == null
                              ? widget.centerContent
                              : Padding(
                                  padding: const EdgeInsets.only(top: WorkbenchGlassToolbar.phoneHeight),
                                  child: widget.centerContent,
                                ),
                        ),
                      ),
                      if (widget.toolbarBuilder != null)
                        Positioned(left: 0, right: 0, top: 0, child: widget.toolbarBuilder!(true)),
                      if (widget.centerOverlay != null)
                        Positioned(
                          left: AppSpace.s10,
                          right: AppSpace.s10,
                          bottom: 12,
                          child: Center(child: widget.centerOverlay),
                        ),
                      if (showFab)
                        Positioned(
                          right: AppSpace.s16,
                          bottom: AppSpace.s16,
                          child: GlassFab(
                            icon: widget.fabIcon!,
                            tooltip: widget.rightPanelTitle,
                            onPressed: () => _showPhoneSheet(context, layoutState),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.bottomPanel != null) widget.bottomPanel!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grounded(Widget child) => widget.centerGround == null
      ? child
      : Material(color: widget.centerGround, child: child);

  /// `01 · 1h` phone sheet: a G2 glass shell (top corners 28, grab handle)
  /// holding an opaque panel at r22.
  /// The phone layout's state as of its last build, for [_openRightSheet].
  WorkbenchLayoutState? _phoneLayoutState;

  /// Opens the phone sheet from a control inside the layout — the same sheet
  /// the FAB opens.
  void _openRightSheet() {
    final sheetHost = _scaffoldKey.currentContext;
    final layoutState = _phoneLayoutState;
    if (sheetHost == null || layoutState == null) return;
    _showPhoneSheet(sheetHost, layoutState);
  }

  void _showPhoneSheet(BuildContext context, WorkbenchLayoutState layoutState) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: scheme.scrim,
      elevation: 0,
      builder: (sheetContext) => Provider<WorkbenchLayoutState>.value(
        value: layoutState,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) => AppGlass(
            grade: GlassGrade.float,
            edges: GlassEdges.top,
            shadow: false,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            child: Builder(builder: (ctx) {
              final handle = GlassInk.maybeOf(ctx)?.ink2 ?? scheme.onSurfaceVariant;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: handle,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.dialog)),
                        child: Material(
                          color: scheme.surface,
                          child: widget.rightPanelBuilder!(scrollController),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// The right panel as a drawer (`A1 · 1d`): a 48px header with its title and
/// a close button over a hairline, then the panel.
class _DrawerWithHeader extends StatelessWidget {
  const _DrawerWithHeader({required this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s6, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
