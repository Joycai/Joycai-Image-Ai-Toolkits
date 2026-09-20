import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import 'app_glass.dart';

/// One line of an [AppGlassMenu]: an [AppGlassMenuItem], an
/// [AppGlassMenuDivider], an [AppGlassMenuHeading], an [AppGlassMenuGrid] or
/// an [AppGlassMenuQuickBlock].
abstract class AppGlassMenuEntry {
  const AppGlassMenuEntry();
}

/// An action row (`00` / `B1a · 1b` 右键菜单): 28 tall at r6 — glyph, label,
/// an optional mono hint at the end, and under a disabled row an optional
/// second line saying why.
///
/// A row given [children] is a submenu row instead (`A1 · 2a`: 「文件 ▸」,
/// 「导出 ▸」): it ends in a chevron, and hovering, tapping or pressing → on
/// it opens a second float-grade panel beside the menu, its first row level
/// with this one. Such a row has no [onSelected] of its own.
class AppGlassMenuItem extends AppGlassMenuEntry {
  const AppGlassMenuItem({
    this.icon,
    required this.label,
    this.onSelected,
    this.children,
    this.trailing,
    this.note,
    this.hint,
    this.checked,
    this.radio = false,
    this.enabled = true,
    this.danger = false,
  })  : assert(onSelected == null || children == null, 'a submenu row has no action of its own'),
        assert(icon == null || checked == null, 'a row is marked either by its icon or by its check');

  final IconData? icon;
  final String label;

  /// A choice row (`B1a · 1f`): draws a radio ([radio]) or a checkbox in the
  /// icon's place, filled with the accent when `true`. Null for a plain
  /// action row. A checked checkbox row also sits on the 8% wash.
  final bool? checked;
  final bool radio;

  /// A second line under the label that is always shown — what the choice
  /// does, or when it applies (`1f`: 「勾选 ≥ 2 个目录时生效」). Two lines at
  /// most; the row grows to hold them. Unlike [note], not tied to being
  /// disabled.
  final String? hint;

  /// Runs once the menu has been popped, so a dialog it opens is not stacked
  /// over a route on its way out. Null disables the row — unless the row
  /// opens a submenu.
  final VoidCallback? onSelected;

  /// The rows of this row's submenu; null for a plain action row.
  final List<AppGlassMenuEntry>? children;

  /// A key the action really has (`F2`, `Alt+↑`) or a count the label would
  /// otherwise carry, in mono at the glass's secondary ink.
  final String? trailing;

  /// Why the row is disabled — shown only while it is (`B1b · 1d`: 「根目录
  /// 不可移动」 under Move to…).
  final String? note;

  final bool enabled;

  /// The error ink, for the destructive row.
  final bool danger;

  bool get hasSubmenu => children != null && children!.isNotEmpty;

  bool get isEnabled => enabled && (onSelected != null || hasSubmenu);
}

/// The rule between two groups of rows.
class AppGlassMenuDivider extends AppGlassMenuEntry {
  const AppGlassMenuDivider();
}

/// A small label over a group of rows (`A1 · 2a`: 「设为」 over the 2×2 grid
/// of assignments). Not focusable, not a row.
class AppGlassMenuHeading extends AppGlassMenuEntry {
  const AppGlassMenuHeading(this.label);

  final String label;
}

/// Rows laid two (or more) across instead of one under the other (`A1 · 2a`:
/// the four mutually exclusive 「设为 ×」 assignments as a 2×2 grid). Each cell
/// is an ordinary [AppGlassMenuItem] at the row height; a label that does not
/// fit its half ends in an ellipsis.
class AppGlassMenuGrid extends AppGlassMenuEntry {
  const AppGlassMenuGrid(this.items, {this.columns = 2}) : assert(columns > 0);

  final List<AppGlassMenuItem> items;
  final int columns;
}

/// One cell of an [AppGlassMenuQuickBlock]: a glyph over a short label.
class AppGlassMenuQuickCell {
  const AppGlassMenuQuickCell({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final IconData icon;
  final String label;

  /// Runs once the menu has been popped, like [AppGlassMenuItem.onSelected].
  final VoidCallback? onSelected;
  final bool enabled;

  bool get isEnabled => enabled && onSelected != null;
}

/// The strip of square cells across the top of a menu (`A1 · 2a`: the four
/// high-frequency actions — preview · mask · crop · assistant — matching the
/// card's hover strip one for one). 48 tall at r10, cells 2 apart, sharing
/// the width equally.
class AppGlassMenuQuickBlock extends AppGlassMenuEntry {
  const AppGlassMenuQuickBlock(this.cells) : assert(cells.length > 0);

  final List<AppGlassMenuQuickCell> cells;
}

/// The width most menus take (`B1a`, `D1a`: 「右键菜单 G2 230」).
const double kAppGlassMenuWidth = 230;

/// The width of a submenu panel (`A1 · 2a`: 「子菜单 200 宽」).
const double kAppGlassSubmenuWidth = 200;

/// Opens a float-grade glass menu with its top-left corner at the global
/// [position], flipped to the other side of the point and then clamped where
/// the window runs out.
///
/// Its own route rather than [showMenu]: Material's popup route paints its
/// panel behind its own clip, where a backdrop filter has nothing of the page
/// to sample — which is why the theme's `popupMenuTheme` is the opaque reduced
/// form. This route lays an [AppGlass] straight onto the overlay, and reduce
/// visual effects still turns it into the opaque panel through [AppGlass].
///
/// The first enabled row takes focus; arrows move, Enter activates, → opens a
/// submenu row and ← closes the submenu again, Esc and a tap outside dismiss.
Future<void> showAppGlassMenu(
  BuildContext context, {
  required Offset position,
  required List<AppGlassMenuEntry> entries,
  double width = kAppGlassMenuWidth,
  Alignment anchor = Alignment.topLeft,
}) async {
  final navigator = Navigator.of(context);
  final MediaQueryData media = MediaQuery.of(context);
  // [position] is a global point — a pointer's `globalPosition`, or a
  // button's `localToGlobal` — but the menu is laid out inside the
  // navigator's overlay, which is not the window: the custom window frame
  // wraps the navigator (`MaterialApp.builder`), so the overlay starts under
  // the title bar. Laying a global point out in overlay space put every menu
  // one title bar lower than the thing it hung off.
  final RenderBox? overlayBox = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final bool hasOverlay = overlayBox != null && overlayBox.hasSize;
  final Offset local = hasOverlay ? overlayBox.globalToLocal(position) : position;
  final Size hostSize = hasOverlay ? overlayBox.size : media.size;
  // Measured the way the delegate will constrain it, so a menu longer than the
  // window is measured at the height it will actually get.
  final double maxHeight = math.max(
    0,
    hostSize.height - media.padding.vertical - _AppGlassMenuLayout._margin * 2,
  );
  final action = await navigator.push<VoidCallback>(
    _AppGlassMenuRoute(
      position: local,
      entries: entries,
      width: width,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      duration: AppMotion.durationOf(context, AppMotion.state),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      origin: _menuOrigin(
        position: local,
        childSize: Size(width, math.min(appGlassMenuHeight(entries), maxHeight)),
        screenSize: hostSize,
        padding: media.padding,
        anchor: anchor,
      ),
    ),
  );
  action?.call();
}

/// Opens a menu under the button [anchor] belongs to, its right edge on the
/// button's right edge — and growing out of that corner.
Future<void> showAppGlassMenuBelow(
  BuildContext anchor, {
  required List<AppGlassMenuEntry> entries,
  double width = kAppGlassMenuWidth,
}) {
  return showAppGlassMenu(
    anchor,
    position: appGlassMenuPositionBelow(anchor, width: width),
    entries: entries,
    width: width,
    anchor: Alignment.topRight,
  );
}

/// Where a menu dropping from a button at [anchor] should open: its right edge
/// on the button's right edge, 4px below it.
Offset appGlassMenuPositionBelow(BuildContext anchor, {double width = kAppGlassMenuWidth}) {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Offset.zero;
  return box.localToGlobal(Offset(box.size.width - width, box.size.height + AppSpace.s4));
}

/// The height an [AppGlassMenu] built from [entries] wants: 6 of padding at
/// each end, a 28 row each — 42 under a disabled row carrying its reason — a
/// 1px rule in 4 of padding for each divider, 48 for a quick block, 20 for a
/// heading, and a grid's rows 2 apart.
///
/// Not a layout input; the menu is still laid out by its own content. This is
/// what [showAppGlassMenu] needs *before* the route exists, to know which
/// corner the panel will be anchored by and therefore which corner it should
/// scale out of — and what a submenu needs to know whether it fits below its
/// row.
double appGlassMenuHeight(List<AppGlassMenuEntry> entries) {
  double height = AppSpace.s6 * 2;
  for (final AppGlassMenuEntry entry in entries) {
    height += switch (entry) {
      AppGlassMenuItem(:final bool isEnabled, :final String? note, :final String? hint) => hint != null
          ? _AppGlassMenuRow._hintHeight
          : !isEnabled && note != null
              ? _AppGlassMenuRow._noteHeight
              : AppSize.compact,
      AppGlassMenuQuickBlock() => _AppGlassMenuQuickBlock.height,
      AppGlassMenuHeading() => _AppGlassMenuHeading.height,
      AppGlassMenuGrid(:final List<AppGlassMenuItem> items, :final int columns) =>
        _gridHeight(items.length, columns),
      _ => 1 + AppSpace.s4 * 2,
    };
  }
  return height;
}

double _gridHeight(int count, int columns) {
  final int rows = (count / columns).ceil();
  return rows * AppSize.compact + math.max(0, rows - 1) * _AppGlassMenuGrid.gap;
}

/// Which corner of the menu ends up on [position] — the corner it should
/// therefore scale out of.
///
/// [anchor] is where the *caller* put the point: `topLeft` for a right-click,
/// where the menu hangs off the pointer, and `topRight` for a dropdown laid
/// under a button's right edge. [_AppGlassMenuLayout.getPositionForChild] then
/// flips an axis where the menu would run off the window, and a flipped axis
/// always leaves that far edge on the point.
Alignment _menuOrigin({
  required Offset position,
  required Size childSize,
  required Size screenSize,
  required EdgeInsets padding,
  required Alignment anchor,
}) {
  const double margin = _AppGlassMenuLayout._margin;
  final double minX = padding.left + margin;
  final double minY = padding.top + margin;
  final double maxX = math.max(minX, screenSize.width - padding.right - margin - childSize.width);
  final double maxY = math.max(minY, screenSize.height - padding.bottom - margin - childSize.height);
  return Alignment(
    position.dx > maxX ? 1 : anchor.x,
    position.dy > maxY ? 1 : anchor.y,
  );
}

class _AppGlassMenuRoute extends PopupRoute<VoidCallback> {
  _AppGlassMenuRoute({
    required this.position,
    required this.entries,
    required this.width,
    required this.themes,
    required this.duration,
    required this.barrierLabel,
    required this.origin,
  });

  final Offset position;
  final List<AppGlassMenuEntry> entries;
  final double width;
  final CapturedThemes themes;
  final Duration duration;

  /// Which corner the panel grows out of — see [_menuOrigin].
  final Alignment origin;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  /// M2 in (`00 · 1e`: a menu opening is a state change), M1 out.
  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration == Duration.zero ? Duration.zero : AppMotion.hover;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return themes.wrap(
      _AppGlassMenuHost(position: position, entries: entries, width: width),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.prefersReduced(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: origin,
        child: child,
      ),
    );
  }
}

/// The route's page: the menu panel, and beside it whichever submenu is open.
///
/// One submenu at a time. It opens on hover, tap or → of its row and closes
/// when the pointer reaches any *other* row of the menu (crossing the 4px gap
/// to the submenu itself does not close it), on ← inside it, or with the
/// menu. Its panel's top is one padding above its row, so its first row is
/// level with the row that opened it; where the window runs out on the right
/// it opens on the left instead, and it is clamped vertically.
class _AppGlassMenuHost extends StatefulWidget {
  const _AppGlassMenuHost({required this.position, required this.entries, required this.width});

  final Offset position;
  final List<AppGlassMenuEntry> entries;
  final double width;

  @override
  State<_AppGlassMenuHost> createState() => _AppGlassMenuHostState();
}

class _AppGlassMenuHostState extends State<_AppGlassMenuHost> {
  final GlobalKey _menuKey = GlobalKey();

  AppGlassMenuItem? _open;
  Offset _submenuOrigin = Offset.zero;
  double _submenuMaxHeight = double.infinity;
  bool _openedByKeyboard = false;

  bool _isOpen(AppGlassMenuItem item) => identical(_open, item);

  bool _isInSubmenu(AppGlassMenuEntry entry) {
    final open = _open;
    return open != null && open.children!.any((AppGlassMenuEntry e) => identical(e, entry));
  }

  /// A pointer over a row of the menu: opens that row's submenu, or closes the
  /// open one if the row is another.
  void _hover(AppGlassMenuEntry? entry, BuildContext rowContext) {
    if (entry != null && _isInSubmenu(entry)) return;
    if (entry is AppGlassMenuItem && entry.hasSubmenu && entry.isEnabled) {
      if (!_isOpen(entry)) _openSubmenu(entry, rowContext, keyboard: false);
      return;
    }
    _closeSubmenu();
  }

  void _toggle(AppGlassMenuItem item, BuildContext rowContext, {required bool keyboard}) {
    if (_isOpen(item)) {
      if (keyboard) {
        // → on a row whose submenu is already open moves into it.
        setState(() => _openedByKeyboard = true);
      } else {
        _closeSubmenu();
      }
      return;
    }
    _openSubmenu(item, rowContext, keyboard: keyboard);
  }

  void _openSubmenu(AppGlassMenuItem item, BuildContext rowContext, {required bool keyboard}) {
    final RenderBox? host = context.findRenderObject() as RenderBox?;
    final RenderBox? row = rowContext.findRenderObject() as RenderBox?;
    final RenderBox? menu = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (host == null || row == null || menu == null || !host.hasSize || !row.hasSize || !menu.hasSize) {
      return;
    }

    final EdgeInsets padding = MediaQuery.paddingOf(context);
    const double margin = _AppGlassMenuLayout._margin;
    const double width = kAppGlassSubmenuWidth;
    final double rowTop = row.localToGlobal(Offset.zero, ancestor: host).dy;
    final Rect menuRect = menu.localToGlobal(Offset.zero, ancestor: host) & menu.size;

    final double maxHeight = math.max(0, host.size.height - padding.vertical - margin * 2);
    final double height = math.min(appGlassMenuHeight(item.children!), maxHeight);

    final double minX = padding.left + margin;
    final double maxX = math.max(minX, host.size.width - padding.right - margin - width);
    double x = menuRect.right + AppSpace.s4;
    if (x > maxX) x = menuRect.left - AppSpace.s4 - width;

    final double minY = padding.top + margin;
    final double maxY = math.max(minY, host.size.height - padding.bottom - margin - height);
    final double y = rowTop - AppSpace.s6;

    setState(() {
      _open = item;
      _submenuOrigin = Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
      _submenuMaxHeight = maxHeight;
      _openedByKeyboard = keyboard;
    });
  }

  void _closeSubmenu() {
    if (_open == null) return;
    setState(() {
      _open = null;
      _openedByKeyboard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return _AppGlassMenuScope(
      host: this,
      child: Stack(
        children: [
          CustomSingleChildLayout(
            delegate: _AppGlassMenuLayout(position: widget.position, padding: MediaQuery.paddingOf(context)),
            child: AppGlassMenu(key: _menuKey, width: widget.width, entries: widget.entries),
          ),
          if (open != null)
            Positioned(
              left: _submenuOrigin.dx,
              top: _submenuOrigin.dy,
              child: _AppGlassSubmenuAppear(
                key: ObjectKey(open),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: _submenuMaxHeight),
                  // Its own scope: an autofocus is honoured only where nothing
                  // in the scope has focus yet, and the row that opened this
                  // still has it. When the scope goes, focus falls back to
                  // that row.
                  child: FocusScope(
                    child: AppGlassMenu(
                      width: kAppGlassSubmenuWidth,
                      entries: open.children!,
                      // Opened by hover the pointer is what is in the submenu,
                      // and the focus ring stays where the keyboard left it.
                      autofocus: _openedByKeyboard,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A submenu's entrance: M1 fade, nothing more — the menu it belongs to has
/// already made the state-change motion.
class _AppGlassSubmenuAppear extends StatelessWidget {
  const _AppGlassSubmenuAppear({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.enter,
      child: child,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
    );
  }
}

/// How a row reaches the host that owns the submenu state.
class _AppGlassMenuScope extends InheritedWidget {
  const _AppGlassMenuScope({required this.host, required super.child});

  final _AppGlassMenuHostState host;

  static _AppGlassMenuHostState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppGlassMenuScope>()?.host;

  @override
  bool updateShouldNotify(_AppGlassMenuScope oldWidget) => host != oldWidget.host;
}

class _AppGlassMenuLayout extends SingleChildLayoutDelegate {
  _AppGlassMenuLayout({required this.position, required this.padding});

  final Offset position;
  final EdgeInsets padding;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding + const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double minX = padding.left + _margin;
    final double minY = padding.top + _margin;
    final double maxX = math.max(minX, size.width - padding.right - _margin - childSize.width);
    final double maxY = math.max(minY, size.height - padding.bottom - _margin - childSize.height);

    // Flip to the other side of the point before clamping: a menu opened near
    // the bottom-right corner still has its corner at the click.
    double x = position.dx;
    double y = position.dy;
    if (x > maxX) x = position.dx - childSize.width;
    if (y > maxY) y = position.dy - childSize.height;
    return Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_AppGlassMenuLayout oldDelegate) =>
      oldDelegate.position != position || oldDelegate.padding != padding;
}

/// The menu panel itself: G2 glass at r16 with 6 of padding around the rows.
///
/// Public so tests can find a menu's rows through it; open one with
/// [showAppGlassMenu]. A submenu is another one of these, 200 wide.
class AppGlassMenu extends StatelessWidget {
  const AppGlassMenu({
    super.key,
    required this.entries,
    this.width = kAppGlassMenuWidth,
    this.autofocus = true,
  });

  final List<AppGlassMenuEntry> entries;
  final double width;

  /// Whether the first enabled row takes focus as the panel appears.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final firstEnabled = autofocus ? _firstFocusable(entries) : null;

    return SizedBox(
      width: width,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // A transparent Material for the rows' ink and a default text style:
        // a route page has neither of its own.
        child: Material(
          type: MaterialType.transparency,
          child: FocusTraversalGroup(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(AppSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final AppGlassMenuEntry entry in entries)
                    switch (entry) {
                      final AppGlassMenuItem item =>
                        _AppGlassMenuRow(item: item, autofocus: identical(item, firstEnabled)),
                      final AppGlassMenuQuickBlock block =>
                        _AppGlassMenuQuickBlock(block: block, autofocus: firstEnabled),
                      final AppGlassMenuHeading heading => _AppGlassMenuHeading(heading: heading),
                      final AppGlassMenuGrid grid => _AppGlassMenuGrid(grid: grid, autofocus: firstEnabled),
                      _ => const _AppGlassMenuRule(),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The first thing that can take focus, in reading order: a row, a quick
  /// cell or a grid cell.
  static Object? _firstFocusable(List<AppGlassMenuEntry> entries) {
    for (final AppGlassMenuEntry entry in entries) {
      switch (entry) {
        case AppGlassMenuItem(:final bool isEnabled):
          if (isEnabled) return entry;
        case AppGlassMenuQuickBlock(:final List<AppGlassMenuQuickCell> cells):
          for (final AppGlassMenuQuickCell cell in cells) {
            if (cell.isEnabled) return cell;
          }
        case AppGlassMenuGrid(:final List<AppGlassMenuItem> items):
          for (final AppGlassMenuItem item in items) {
            if (item.isEnabled) return item;
          }
        default:
          break;
      }
    }
    return null;
  }
}

class _AppGlassMenuRule extends StatelessWidget {
  const _AppGlassMenuRule();

  @override
  Widget build(BuildContext context) {
    final glass = GlassInk.maybeOf(context);
    // The glass's secondary ink at a hairline's weight: the glass edge colour
    // is a white refraction line and disappears on light glass, which is what
    // a menu mostly sits on. The opaque reduced form keeps the plain hairline.
    final Color color = glass == null || glass.reduced
        ? (glass?.edge ?? Theme.of(context).colorScheme.outlineVariant)
        : glass.ink2.withValues(alpha: 0.2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
      child: SizedBox(height: 1, child: ColoredBox(color: color)),
    );
  }
}

/// `A1 · 2a`: 10.5 medium, tracked, in the secondary ink; 2 above, 3 below.
class _AppGlassMenuHeading extends StatelessWidget {
  const _AppGlassMenuHeading({required this.heading});

  final AppGlassMenuHeading heading;

  static const double height = 20;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink2 = glass?.ink2 ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            heading.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall!.metricsOnly.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
              color: ink2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows in ranks of [AppGlassMenuGrid.columns], 2 apart both ways; a short
/// last rank leaves its remaining cells empty.
class _AppGlassMenuGrid extends StatelessWidget {
  const _AppGlassMenuGrid({required this.grid, required this.autofocus});

  final AppGlassMenuGrid grid;

  /// The entry that takes focus, if it is one of this grid's.
  final Object? autofocus;

  static const double gap = 2;

  @override
  Widget build(BuildContext context) {
    final int columns = grid.columns;
    final int ranks = (grid.items.length / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int r = 0; r < ranks; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          Row(
            children: [
              for (int c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: r * columns + c < grid.items.length
                      ? _AppGlassMenuRow(
                          item: grid.items[r * columns + c],
                          autofocus: identical(grid.items[r * columns + c], autofocus),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// `A1 · 2a`: cells 48 tall at r10, glyph at 20 over a 10.5 label in the
/// secondary ink, hovering to 8% of the ink.
class _AppGlassMenuQuickBlock extends StatelessWidget {
  const _AppGlassMenuQuickBlock({required this.block, required this.autofocus});

  final AppGlassMenuQuickBlock block;

  /// The entry that takes focus, if it is one of this block's cells.
  final Object? autofocus;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (int i = 0; i < block.cells.length; i++) ...[
            if (i > 0) const SizedBox(width: _AppGlassMenuGrid.gap),
            Expanded(
              child: _AppGlassMenuQuickCellView(
                cell: block.cells[i],
                autofocus: identical(block.cells[i], autofocus),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppGlassMenuQuickCellView extends StatelessWidget {
  const _AppGlassMenuQuickCellView({required this.cell, required this.autofocus});

  final AppGlassMenuQuickCell cell;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final host = _AppGlassMenuScope.maybeOf(context);

    final enabled = cell.isEnabled;
    final Color dim = ink2.withValues(alpha: ink2.a * 0.6);
    final radius = BorderRadius.circular(AppRadius.md);

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        autofocus: autofocus,
        borderRadius: radius,
        hoverColor: ink.withValues(alpha: 0.08),
        focusColor: ink.withValues(alpha: 0.10),
        highlightColor: ink.withValues(alpha: 0.12),
        splashFactory: NoSplash.splashFactory,
        onHover: (bool hovering) {
          if (hovering) host?._hover(null, context);
        },
        onTap: enabled ? () => Navigator.of(context).pop<VoidCallback>(cell.onSelected) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(cell.icon, size: AppSize.iconLg, color: enabled ? ink : dim),
            const SizedBox(height: 3),
            Text(
              cell.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall!.metricsOnly.copyWith(
                fontWeight: FontWeight.w400,
                color: enabled ? ink2 : dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppGlassMenuRow extends StatelessWidget {
  const _AppGlassMenuRow({required this.item, required this.autofocus});

  final AppGlassMenuItem item;
  final bool autofocus;

  static const double _noteHeight = 42;

  /// A row carrying a two-line [AppGlassMenuItem.hint]: the label's 28 plus
  /// two 11px lines and a breath under them.
  static const double _hintHeight = 64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final host = _AppGlassMenuScope.maybeOf(context);

    final enabled = item.isEnabled;
    final bool submenu = item.hasSubmenu;
    final bool open = submenu && (host?._isOpen(item) ?? false);
    final bool inSubmenu = host?._isInSubmenu(item) ?? false;
    final Color dim = ink2.withValues(alpha: ink2.a * 0.6);
    final Color labelColor = !enabled ? dim : (item.danger ? scheme.error : ink);
    final Color glyphColor = !enabled ? dim : (item.danger ? scheme.error : ink2);
    final note = !enabled ? item.note : null;
    final hint = item.hint;
    final radius = BorderRadius.circular(AppRadius.sm);

    // `1f`: a choice row's mark — a radio or a checkbox, the accent when on.
    final bool? checked = item.checked;
    final IconData? mark = checked == null
        ? null
        : item.radio
            ? (checked ? Icons.radio_button_checked : Icons.radio_button_unchecked)
            : (checked ? Icons.check_box : Icons.check_box_outline_blank);
    final Color markColor = !enabled ? dim : (checked == true ? scheme.primary : ink2);
    final bool washed = checked == true && !item.radio;

    void activate() {
      if (submenu) {
        host?._toggle(item, context, keyboard: false);
      } else {
        Navigator.of(context).pop<VoidCallback>(item.onSelected);
      }
    }

    return Semantics(
      button: true,
      enabled: enabled,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (submenu && enabled)
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                host?._toggle(item, context, keyboard: true),
          if (inSubmenu)
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => host?._closeSubmenu(),
        },
        child: InkWell(
          autofocus: autofocus,
          borderRadius: radius,
          hoverColor: ink.withValues(alpha: 0.08),
          focusColor: ink.withValues(alpha: 0.10),
          highlightColor: ink.withValues(alpha: 0.12),
          splashFactory: NoSplash.splashFactory,
          onHover: (bool hovering) {
            if (hovering) host?._hover(item, context);
          },
          onTap: enabled ? activate : null,
          child: DecoratedBox(
            // A submenu row stays lit while its submenu is open, so the eye
            // can tell which row the panel beside the menu belongs to.
            decoration: BoxDecoration(
              color: open || washed ? ink.withValues(alpha: 0.08) : null,
              borderRadius: radius,
            ),
            child: SizedBox(
              height: hint != null
                  ? _hintHeight
                  : note == null
                      ? AppSize.compact
                      : _noteHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  // A hinted row keeps its mark on the label's line, not
                  // centred against the hint under it.
                  crossAxisAlignment: hint != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: AppSize.iconMd, color: glyphColor),
                      const SizedBox(width: 8),
                    ],
                    if (mark != null) ...[
                      SizedBox(
                        height: AppSize.compact,
                        child: Center(child: Icon(mark, size: AppSize.iconMd, color: markColor)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: hint != null ? AppSize.compact : null,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall!.metricsOnly.copyWith(color: labelColor),
                              ),
                            ),
                          ),
                          if (hint != null)
                            Text(
                              hint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall!.metricsOnly.copyWith(
                                fontWeight: FontWeight.w400,
                                color: ink2,
                              ),
                            ),
                          if (note != null)
                            Text(
                              note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall!.metricsOnly.copyWith(
                                fontWeight: FontWeight.w400,
                                color: dim,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (item.trailing != null) ...[
                      const SizedBox(width: AppSpace.s10),
                      // Flexible, not free: the label beside it is already
                      // in an `Expanded`, so a trailing wide enough to leave
                      // it no room overflows the row rather than shrinking
                      // anything. A key that is too long for a menu should
                      // be shortened by its caller (`AppKeyLabel.menuHint`),
                      // but the row must not be the thing that breaks.
                      Flexible(
                        child: Text(
                        item.trailing!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall!.mono.metricsOnly.copyWith(
                          fontWeight: FontWeight.w400,
                          color: enabled ? ink2 : dim,
                        ),
                      ),
                      ),
                    ],
                    if (submenu)
                      // `A1 · 2a`: the chevron sits 4 closer to the edge than
                      // the text does, so it reads as the row's end.
                      Transform.translate(
                        offset: const Offset(AppSpace.s4, 0),
                        child: Icon(Icons.chevron_right, size: AppSize.iconMd, color: enabled ? ink2 : dim),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
