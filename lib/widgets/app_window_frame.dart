import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import 'baked_backdrop.dart';
import 'glass/app_glass.dart';
import 'shell/app_destinations.dart';
import 'shell/nav_lens_group.dart';
import 'shell/shell_cover.dart';

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
    // A transparent Material under everything: the title bar, the phone dock
    // and the task capsule sit outside any route's Scaffold, and a Text with
    // no Material above it inherits MaterialApp's error style — the yellow
    // double underline — wherever its own style leaves decoration unset. This
    // paints nothing; it only puts the theme's text style in scope.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const WindowGround(),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

/// The window ground, sized to what is actually visible.
///
/// Normally the whole window. While a [FullScreenCoverRoute] is settled the
/// only part still showing is the strip behind the title bar — the bar lives
/// above the [Navigator] in `MaterialApp.builder`, so no route can cover it,
/// and it is real glass that needs something to refract. Everything below
/// that strip is behind an opaque page, so the ground stops being drawn
/// there.
///
/// Shrunk rather than clipped: a clip layer is itself a pass, and the ground
/// is one textured quad — drawing a smaller quad is the cheap way to stop
/// paying for 98% of it. Nothing moves on screen, because the pixels that are
/// dropped are the ones the cover was already hiding.
class WindowGround extends StatelessWidget {
  const WindowGround({super.key});

  @override
  Widget build(BuildContext context) {
    final ShellCoverController? cover = ShellCover.maybeOf(context);
    if (cover == null) return const Positioned.fill(child: AuroraBackdrop());
    return ValueListenableBuilder<int>(
      valueListenable: cover,
      builder: (context, _, _) => cover.covered && usesCustomWindowChrome
          ? const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: kTitleBarHeight,
              child: AuroraBackdrop(),
            )
          : const Positioned.fill(child: AuroraBackdrop()),
    );
  }
}

/// The window ground (`00` 「aurora」): a quiet material wall.
///
/// Liquid Glass blurs what sits behind it, and what it should be refracting is
/// content — gallery thumbnails, video frames, the file grid. So the wall has
/// no texture of its own: a regular pattern competes with the content for what
/// shows through, and blurred grid lines turn into a smear of dirty grey. Its
/// depth comes only from very large, very faint glows. Four layers, bottom to
/// top:
///
/// 1. the canvas colour;
/// 2. an accent glow from beyond the top-left corner, 6% falling to nothing;
/// 3. a fainter 4% glow from beyond the bottom-right;
/// 4. a lift of the surface colour down from the top edge.
///
/// The glows take `primary`, so the wall warms or cools with the theme colour
/// while the greys stay put. Their alphas stay far under 12%: at that weight
/// they match the selected-state wash, and a selection stops reading against
/// the wall.
///
/// Most screens cover it with opaque columns; the workbench gallery, the file
/// browser grid and the downloader results sit straight on it. With *reduce
/// visual effects* on it is the canvas colour alone — the switch that also
/// turns glass opaque.
///
/// **Drawn once into an image, not four fills per frame.** The recipe is
/// static — it moves only with the theme, the accent and the window size —
/// so [BakedAuroraBackdrop] bakes it at quarter resolution and hands the GPU
/// one textured quad. This used to be four stacked `SizedBox.expand`
/// decorations behind a `RepaintBoundary`, with a comment claiming that made
/// it “paint once”; a repaint boundary bounds which Dart paint code re-runs,
/// not what the GPU executes, and the raster cache has a size ceiling a 4K
/// window is far past. Measured on the dev machine’s integrated Radeon,
/// maximized at 4K: 9.91 → 4.84 ms of GPU time a frame, against a floor of
/// 2.58 ms for a blank window. See [BakedBackdrop] and
/// `lib/bench/render_bench.dart`.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const BakedAuroraBackdrop();
}

/// The app mark (`01 · 1b`): the application's own icon, at [size].
///
/// The design draws a rounded square swept from the accent to its deep ink —
/// a stand-in, like the grey boxes it draws for images. The mark is the app's
/// identity rather than a themed swatch, so it does not follow the accent: an
/// icon that changed colour with the theme would stop being the thing the
/// user's eye finds in a taskbar full of windows.
///
/// Decoded at the size it is drawn at, not at the asset's 1024: the same mark
/// is on screen at 16, 20 and 40, and a full-size decode of each would hold
/// four megabytes to paint a 16px square.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 16});

  final double size;

  static const String asset = 'assets/icon/icon.png';

  @override
  Widget build(BuildContext context) {
    final int pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipRRect(
      // r4 at 16, r10 at 40 — the same proportion as the design's two sizes.
      borderRadius: BorderRadius.circular(size <= 20 ? AppRadius.xs : AppRadius.control),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        cacheWidth: pixels,
        cacheHeight: pixels,
        filterQuality: FilterQuality.medium,
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
    final (title, _) = windowTitleParts(context);
    // `01b · 1b`: the current destination is named here, beside the app's
    // name, rather than inside the navigation, whose width must not follow it.
    final destination = current.label(AppLocalizations.of(context)!);

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
            final separatorStyle = titleStyle.copyWith(color: ink2);
            final destinationStyle = titleStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onAccentTint,
            );
            double measure(String text, TextStyle style) => (TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout())
                    .width;

            final markWidth = isMacOs ? 0.0 : 16 + AppSpace.s10;
            final titleWidth = measure(title, titleStyle);
            final separatorWidth = AppSpace.s10 + measure('·', separatorStyle) + AppSpace.s10;
            final destinationWidth = measure(destination, destinationStyle);

            // The app's name folds first: the destination is the one place
            // the current screen is named now.
            bool showTitle = true;
            bool showDestination = true;
            final nav = showNav ? NavLensGroup.widthFor(density: NavLensDensity.titleBar) : 0.0;
            double leftWidth() =>
                leftInset +
                markWidth +
                (showTitle ? titleWidth : 0) +
                (showTitle && showDestination ? separatorWidth : 0) +
                (showDestination ? destinationWidth : 0);
            // Without a nav (phone widths) the identity still has to clear the
            // caption buttons.
            bool fits() {
              final middle = showNav ? AppSpace.s16 + nav + AppSpace.s16 : AppSpace.s16;
              return leftWidth() + middle + rightReserve <= width;
            }

            if (!fits()) showTitle = false;
            if (!fits()) showDestination = false;

            // `01b · 1e`: centred in the span between the leading inset and
            // the caption buttons, not on the window — on the window, the
            // buttons' 138 on one side pull the nav's optical centre off. It
            // may slide right of centre, but never under the identity or the
            // buttons.
            final minLeft = leftWidth() + AppSpace.s16;
            final maxLeft = width - rightReserve - AppSpace.s16 - nav;
            final centred = leftInset + (width - leftInset - rightReserve - nav) / 2;
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
                          if (showTitle && showDestination) ...[
                            const SizedBox(width: AppSpace.s10),
                            Text('·', style: separatorStyle),
                            const SizedBox(width: AppSpace.s10),
                          ],
                          if (showDestination)
                            Text(
                              destination,
                              maxLines: 1,
                              softWrap: false,
                              style: destinationStyle,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showNav)
                  Positioned(
                    left: navLeft,
                    top: (kTitleBarHeight - NavLensDensity.titleBar.itemHeight) / 2,
                    child: const NavLensGroup(density: NavLensDensity.titleBar),
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
