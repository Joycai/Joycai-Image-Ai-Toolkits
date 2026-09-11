import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_effects.dart';
import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import 'glass/app_glass.dart';
import 'shell/app_destinations.dart';
import 'shell/nav_lens_group.dart';

/// Whether this build draws its own window chrome.
///
/// Desktop only. On Android and iOS there is no window to frame, and
/// `window_manager` has no implementation there to call into.
bool get usesCustomWindowChrome =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Height of the title bar the app draws for itself (`01 · 1b`).
const double kTitleBarHeight = 36;

/// The window title split into its name and version, read back from the
/// [Title] `MaterialApp.onGenerateTitle` produced (`"<app> v<version>"`), so
/// there is one source for what the window is called.
(String, String?) windowTitleParts(BuildContext context) {
  final raw = context.findAncestorWidgetOfExactType<Title>()?.title ?? '';
  final match = RegExp(r'^(.*) v(\S+)$').firstMatch(raw);
  if (match != null) return (match.group(1)!, match.group(2));
  if (raw.isNotEmpty) return (raw, null);
  return (AppLocalizations.of(context)?.appTitle ?? '', null);
}

/// The app's window: the aurora backdrop, the app's own title bar on desktop,
/// and the app under both.
///
/// Hosted in an [Overlay] of its own. The title bar sits above the
/// [Navigator] (it has to survive every pushed route, or the window loses its
/// close button under the setup wizard), which puts it outside the navigator's
/// overlay — and its navigation tooltips need one to mount into. This one
/// spans the whole window, so a tooltip under the bar is not clipped to it.
class AppWindowFrame extends StatefulWidget {
  final Widget child;

  const AppWindowFrame({super.key, required this.child});

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> {
  late final OverlayEntry _entry = OverlayEntry(builder: _buildFrame);

  @override
  void didUpdateWidget(AppWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The entry built its subtree from the old widget; rebuild it from this one.
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  Widget _buildFrame(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: AuroraBackdrop()),
        if (usesCustomWindowChrome)
          Column(
            children: [
              const AppTitleBar(),
              Expanded(child: widget.child),
            ],
          )
        else
          widget.child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

/// The window ground (`00` 「aurora」): the canvas colour, a faint 28px grid in
/// the hairline, and one wash of the accent — its 12% form, falling off to
/// nothing — from the top-left, with a fainter 7% echo at the bottom-right.
///
/// Most screens cover it with opaque columns; the workbench gallery and the
/// tool canvases sit straight on it, which is what gives the glass bars
/// something to refract. Nothing here scrolls or animates, so it paints once
/// behind a repaint boundary. With *reduce visual effects* on it is the canvas
/// colour alone.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key});

  /// The grid pitch, in logical pixels.
  static const double gridPitch = 28;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (AppEffects.reduced(context)) {
      return ColoredBox(color: scheme.surfaceContainer);
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(
          canvas: scheme.surfaceContainer,
          grid: scheme.outlineVariant.withValues(alpha: 0.55),
          wash: scheme.accentTint,
          echo: scheme.accentEcho,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.canvas,
    required this.grid,
    required this.wash,
    required this.echo,
  });

  final Color canvas;
  final Color grid;
  final Color wash;
  final Color echo;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = canvas);

    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += AuroraBackdrop.gridPitch) {
      c.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), line);
    }
    for (double y = 0; y < size.height; y += AuroraBackdrop.gridPitch) {
      c.drawLine(Offset(0, y + 0.5), Offset(size.width, y + 0.5), line);
    }

    // CSS `radial-gradient(55% 45% at 88% 96%, …, transparent 70%)`, then
    // `(70% 60% at 18% 8%)` on top — an ellipse is a circle scaled on one axis.
    _ellipse(c, size, cx: 0.88, cy: 0.96, rx: 0.55, ry: 0.45, color: echo);
    _ellipse(c, size, cx: 0.18, cy: 0.08, rx: 0.70, ry: 0.60, color: wash);
  }

  void _ellipse(
    Canvas c,
    Size size, {
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required Color color,
  }) {
    final radiusX = size.width * rx;
    final radiusY = size.height * ry;
    if (radiusX <= 0 || radiusY <= 0) return;
    c.save();
    c.translate(size.width * cx, size.height * cy);
    c.scale(1, radiusY / radiusX);
    final rect = Rect.fromCircle(center: Offset.zero, radius: radiusX);
    c.drawRect(
      Rect.fromLTRB(-size.width * 2, -size.height * 2 * radiusX / radiusY,
          size.width * 2, size.height * 2 * radiusX / radiusY),
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 0.7],
        ).createShader(rect),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.canvas != canvas || old.grid != grid || old.wash != wash || old.echo != echo;
}

/// The app mark: a rounded square in the accent swept to its deep ink
/// (`01 · 1b`). Solid accent under reduced effects (`01 · 1k`).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = AppEffects.reduced(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // r4 at 16, r10 at 40 — the same proportion as the design's two sizes.
        borderRadius: BorderRadius.circular(size <= 20 ? AppRadius.xs : AppRadius.control),
        color: reduced ? scheme.primary : null,
        gradient: reduced
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.onAccentTint],
              ),
      ),
    );
  }
}

/// The desktop title bar (`01 · 1b` 「顶栏合一」): window identity, the eight
/// destinations, and the window controls on one 36px layer of G1 glass.
///
/// Everything a native caption did is here: drag anywhere outside a control
/// to move the window, double-click to maximise, and — outside macOS — the
/// three 46×36 caption buttons. macOS keeps its traffic lights and gets a 78px
/// inset for them instead of a second set.
///
/// Degradation is measured, in this order, until the row fits: the version,
/// then the app name, then the current destination's label. Below the phone
/// breakpoint the destinations leave the bar for the phone dock.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key});

  /// Room reserved on the left for macOS's traffic lights.
  static const double macOsButtonInset = 78;

  static const double _captionButtonsWidth = 46.0 * 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMacOs = Platform.isMacOS;
    final showNav = !Responsive.isMobile(context);
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final (title, version) = windowTitleParts(context);

    return SizedBox(
      height: kTitleBarHeight,
      child: AppGlass(
        grade: GlassGrade.bar,
        edges: GlassEdges.bottom,
        shadow: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ink2 = GlassInk.maybeOf(context)?.ink2 ?? theme.colorScheme.onSurfaceVariant;
            final width = constraints.maxWidth;
            final leftInset = isMacOs ? macOsButtonInset : AppSpace.s10;
            final rightReserve = isMacOs ? AppSpace.s10 : _captionButtonsWidth;

            final titleStyle = theme.textTheme.bodySmall!.metricsOnly.copyWith(fontWeight: FontWeight.w500);
            final versionStyle = theme.textTheme.labelSmall!.mono.copyWith(color: ink2, fontWeight: FontWeight.w400);
            double measure(String text, TextStyle style) => (TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout())
                    .width;

            final markWidth = isMacOs ? 0.0 : 16 + AppSpace.s10;
            final titleWidth = measure(title, titleStyle);
            final versionWidth = version == null ? 0.0 : measure('v$version', versionStyle) + AppSpace.s10;

            bool showLabel = true;
            bool showTitle = true;
            bool showVersion = version != null;
            double navWidth() => showNav
                ? NavLensGroup.widthFor(context,
                    density: NavLensDensity.titleBar, current: current, showSelectedLabel: showLabel)
                : 0;
            double leftWidth() =>
                leftInset + markWidth + (showTitle ? titleWidth : 0) + (showVersion ? versionWidth : 0);
            // The nav wants the window's centre; it may slide right of it, but
            // never under the identity or the caption buttons. Without a nav
            // (phone widths) the identity still has to clear the buttons.
            bool fits() {
              final middle = showNav ? AppSpace.s16 + navWidth() + AppSpace.s16 : AppSpace.s16;
              return leftWidth() + middle + rightReserve <= width;
            }

            if (!fits()) showVersion = false;
            if (!fits()) showTitle = false;
            if (!fits()) showLabel = false;

            final nav = navWidth();
            final minLeft = leftWidth() + AppSpace.s16;
            final maxLeft = width - rightReserve - AppSpace.s16 - nav;
            final centred = (width - nav) / 2;
            final navLeft = maxLeft < minLeft ? minLeft : centred.clamp(minLeft, maxLeft);

            return Stack(
              children: [
                Positioned.fill(
                  child: _DragAndMaximise(
                    child: Padding(
                      padding: EdgeInsets.only(left: leftInset),
                      child: Row(
                        children: [
                          if (!isMacOs) ...[
                            const AppMark(),
                            const SizedBox(width: AppSpace.s10),
                          ],
                          if (showTitle)
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: titleStyle,
                              ),
                            ),
                          if (showVersion) ...[
                            const SizedBox(width: AppSpace.s10),
                            Text('v$version', maxLines: 1, style: versionStyle),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (showNav)
                  Positioned(
                    left: navLeft,
                    top: (kTitleBarHeight - NavLensDensity.titleBar.itemHeight) / 2,
                    child: NavLensGroup(
                      density: NavLensDensity.titleBar,
                      showSelectedLabel: showLabel,
                    ),
                  ),
                if (!isMacOs)
                  const Positioned(right: 0, top: 0, bottom: 0, child: _WindowButtons()),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The part of the bar that behaves like a caption: drag to move, double-click
/// to maximise or restore.
class _DragAndMaximise extends StatelessWidget {
  final Widget child;

  const _DragAndMaximise({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: DragToMoveArea(child: child),
    );
  }
}

/// Minimise, maximise/restore and close, each in the 46×36 hit box a caption
/// button actually is.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Icons.remove,
          label: l10n.minimizeWindow,
          onPressed: windowManager.minimize,
        ),
        const _MaximiseButton(),
        _WindowButton(
          icon: Icons.close,
          label: l10n.closeWindow,
          onPressed: windowManager.close,
          danger: true,
        ),
      ],
    );
  }
}

/// The middle button, which is two buttons depending on the window's state —
/// tracked through [WindowListener], because a window can be maximised by
/// dragging it to the top of the screen as well as by this button.
class _MaximiseButton extends StatefulWidget {
  const _MaximiseButton();

  @override
  State<_MaximiseButton> createState() => _MaximiseButtonState();
}

class _MaximiseButtonState extends State<_MaximiseButton> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readWindowState();
  }

  /// Guarded: a `flutter test` run reports as desktop with no plugin to
  /// answer, and an unhandled [MissingPluginException] fails the test.
  Future<void> _readWindowState() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } on MissingPluginException {
      // No window to ask about.
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _WindowButton(
      icon: _maximized ? Icons.filter_none : Icons.crop_square,
      label: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
      onPressed: () =>
          _maximized ? windowManager.unmaximize() : windowManager.maximize(),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurfaceVariant;

    final background = !_hovering
        ? Colors.transparent
        : widget.danger
            ? const Color(0xFFC42B1C)
            : ink.withValues(alpha: 0.08);
    final foreground = _hovering && widget.danger ? Colors.white : ink;

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            width: 46,
            height: kTitleBarHeight,
            color: background,
            child: Icon(widget.icon, size: AppSize.iconMd, color: foreground),
          ),
        ),
      ),
    );
  }
}
