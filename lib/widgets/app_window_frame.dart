import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/design_tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

/// Whether this build draws its own window chrome.
///
/// Desktop only. On Android and iOS there is no window to frame, and
/// `window_manager` has no implementation there to call into.
bool get usesCustomWindowChrome =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Height of the title bar the app draws for itself.
///
/// 36 from the spec — `A1` and `D1` both draw it at 36, `B1` at 38, and the two
/// hand-finished frames win. Deliberately shorter than a Windows caption: the
/// bar carries a mark, a title and three buttons and nothing that needs more
/// room, and the height it gives up goes to the toolbar below it, which does.
const double kTitleBarHeight = 36;

/// The app's window: the spec's backdrop, the app's own title bar, and the app
/// itself under both.
///
/// The backdrop is why this is a [Stack] and not a [Column]. The title bar is
/// frosted — translucent over a real blur — and a blur is worth nothing without
/// something behind it. Painting the mesh across the whole window and floating
/// the bar on top is also what lets the workbench's gallery column show the
/// same mesh through its own transparent background.
class AppWindowFrame extends StatelessWidget {
  final Widget child;

  const AppWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowChrome) return child;

    return Stack(
      children: [
        const Positioned.fill(child: AppWindowBackdrop()),
        Column(
          children: [
            const AppTitleBar(),
            Expanded(child: child),
          ],
        ),
      ],
    );
  }
}

/// The spec's window backdrop: four wide colour fields bleeding in from the
/// corners of a near-neutral ground.
///
/// Every page mockup is drawn on this, and in most of them it is almost
/// entirely covered — the panels are opaque and only the title bar lets it
/// through. The workbench is the exception, and the reason it earns its keep:
/// `A1` gives the gallery column no background of its own, so the image cards
/// sit straight on this.
///
/// Painted as four positioned boxes rather than one shader. CSS states each
/// blob as an ellipse with its own centre and its own pair of radii, which is
/// exactly a [RadialGradient] in a [Positioned] box of twice those radii; and
/// nothing here animates or scrolls, so there is no call for a custom painter.
class AppWindowBackdrop extends StatelessWidget {
  const AppWindowBackdrop({super.key});

  /// One blob: fractional centre within the window, half-extents in logical
  /// pixels, and the colour it fades out from. Straight off the spec.
  static const List<({double x, double y, double rx, double ry, Color color})> blobs = [
    (x: 0.12, y: -0.08, rx: 900, ry: 520, color: Color(0x6B5B8DFF)),
    (x: 0.88, y: 0.02, rx: 760, ry: 480, color: Color(0x619D7BFF)),
    (x: 0.74, y: 1.00, rx: 700, ry: 520, color: Color(0x4740C4D6)),
    (x: 0.22, y: 0.94, rx: 560, ry: 420, color: Color(0x33FFAA5C)),
  ];

  /// How far out each blob has faded to nothing, as a fraction of its radius.
  /// The spec writes 62–64% per blob; the gap between those is well under a
  /// pixel of visible edge on a 900px field, so they share one number.
  static const double falloff = 0.63;

  /// What dark multiplies every blob's alpha by.
  ///
  /// At full strength these read as coloured light on a white ground and as
  /// stains on a near-black one. The ground is what changed, so the paint has
  /// to. `10b` was never restyled and has no backdrop of its own to copy.
  static const double darkAttenuation = 0.5;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return DecoratedBox(
          // The spec's #EAEDF6. Taken from the ramp rather than written out, so
          // dark gets a ground too.
          decoration: BoxDecoration(color: colorScheme.surfaceContainer),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final blob in blobs)
                Positioned(
                  left: w * blob.x - blob.rx,
                  top: h * blob.y - blob.ry,
                  width: blob.rx * 2,
                  height: blob.ry * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          isDark
                              ? blob.color.withValues(alpha: blob.color.a * darkAttenuation)
                              : blob.color,
                          blob.color.withValues(alpha: 0),
                        ],
                        stops: const [0, falloff],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The title bar's frosted glass, honouring the reduce-visual-effects setting.
///
/// A full-width backdrop blur is the single most expensive draw in the app —
/// measured at ~19ms per frame on an integrated GPU at 4K, which alone is more
/// than a whole 60fps frame budget. When the user opts out the bar keeps its
/// translucent fill and loses only the blur.
class _TitleBarFrost extends StatelessWidget {
  const _TitleBarFrost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = context.select<AppState, bool>((s) => s.reduceVisualEffects);
    if (reduce) return child;
    return BackdropFilter(
      // blur(30px) saturate(180%), composed rather than nested: two
      // BackdropFilters would sample the layer twice, and the outer one
      // would be filtering the inner one's output instead of the backdrop.
      //
      // sigma 15 for a 30px CSS blur — CSS states a radius, Skia a standard
      // deviation, and the conversion the platforms agree on is radius/2.
      filter: ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(AppTitleBar.saturationMatrix(1.8)),
        inner: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      ),
      child: child,
    );
  }
}

/// The app's own title bar, drawn because the spec draws one.
///
/// The window's caption is hidden at startup (see `main`), so everything a
/// caption used to provide has to be here: dragging the window, double-click to
/// maximise, and the three buttons. Dropping any of them would lose the user a
/// window control they had before this was a design change.
///
/// macOS keeps its native traffic lights and gets no buttons of its own. A
/// second set on the right of a Mac window would be wrong however faithfully it
/// matched the mockup, which is drawn as a Windows window.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key});

  /// Room reserved on the left for macOS's traffic lights, which sit inside the
  /// window rather than in a bar of their own.
  static const double macOsButtonInset = 78;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMacOs = Platform.isMacOS;

    return SizedBox(
      height: kTitleBarHeight,
      child: ClipRect(
        child: _TitleBarFrost(
          child: DecoratedBox(
            decoration: BoxDecoration(
              // The spec's rgba(255,255,255,.55), left translucent. This is the
              // one surface in the app where what is behind it is the point, so
              // flattening it the way the panels were flattened would leave a
              // blur with nothing to show.
              color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                if (isMacOs) const SizedBox(width: macOsButtonInset),
                Expanded(
                  child: _DragAndMaximise(
                    child: Padding(
                      padding: EdgeInsets.only(left: isMacOs ? 0 : 14),
                      child: Row(
                        children: [
                          if (!isMacOs) ...[
                            const _AppMark(),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              _titleOf(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!isMacOs) const _WindowButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The window title, read back from where `MaterialApp` put it.
  ///
  /// `onGenerateTitle` builds the same `"<app> v<version>"` string the OS caption
  /// used to show and hands it to a [Title] widget; taking it from there rather
  /// than rebuilding it keeps one source for what the window is called.
  static String _titleOf(BuildContext context) {
    final title = context.findAncestorWidgetOfExactType<Title>()?.title;
    if (title != null && title.isNotEmpty) return title;
    return AppLocalizations.of(context)?.appTitle ?? '';
  }

  /// A saturation matrix, in the shape [ColorFilter.matrix] wants.
  ///
  /// CSS `saturate(n)` is a linear blend between a colour and its luminance at
  /// Rec. 709 coefficients, which is what this writes out.
  static List<double> saturationMatrix(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final d = 1 - s;
    return [
      lr * d + s, lg * d, lb * d, 0, 0, //
      lr * d, lg * d + s, lb * d, 0, 0, //
      lr * d, lg * d, lb * d + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}

/// The app's mark: the spec's 16px rounded square in the accent gradient.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs - 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // The spec's #4A72E8 → #3355C4 is the accent and a darker tone of it,
          // so it is expressed that way and follows the user's seed.
          colors: [colorScheme.primary, colorScheme.onAccentTint],
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

/// Minimise, maximise/restore and close.
///
/// Drawn as the spec draws them — bare glyphs, evenly spaced — but each in a hit
/// box the size a caption button actually is. The mockup's spacing is a look,
/// not a target size, and shipping three 13px glyphs as the only way to close
/// the window would be a usability regression dressed up as fidelity.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
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

/// The middle button, which is two buttons depending on the window's state.
///
/// A [WindowListener] rather than a poll: the window can also be maximised by
/// dragging it to the top of the screen or by the OS restoring a session, and a
/// button whose glyph only updates when it is itself clicked would be lying
/// after any of those.
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

  /// Asks the platform whether the window starts out maximised.
  ///
  /// Guarded because this is the one call the button makes eagerly, and it is
  /// made on every host that reports as desktop — including a `flutter test`
  /// run, where the platform is Windows but no plugin is registered to answer.
  /// An unhandled [MissingPluginException] there fails the test that mounted
  /// the widget, which has nothing to do with what that test was checking.
  /// Assuming "not maximised" is right in exactly that case anyway.
  Future<void> _readWindowState() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } on MissingPluginException {
      // No window to ask about. Leave the glyph at its restored state.
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
    final colorScheme = Theme.of(context).colorScheme;

    final background = !_hovering
        ? Colors.transparent
        : widget.danger
            ? colorScheme.error
            : colorScheme.onSurface.withValues(alpha: 0.08);
    final foreground = _hovering && widget.danger
        ? colorScheme.onError
        : colorScheme.onSurfaceVariant;

    // [Semantics] and no [Tooltip]. The title bar is built in
    // `MaterialApp.builder`, which wraps the [Navigator] rather than sitting
    // inside it, so there is no [Overlay] above these buttons for a tooltip to
    // mount into and one throws on build. The label is not lost — it is what
    // screen readers announce, which is the part that was load-bearing.
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
            // The 90 is deliberate — the native Windows caption-button rhythm,
            // documented in plan 002 — but it still routes through durationOf
            // so reduce-motion reaches it like everything else.
            duration: AppMotion.durationOf(context, const Duration(milliseconds: 90)),
            // 46 wide is the Windows caption button, which is what the muscle
            // memory in the top-right corner of every other window expects.
            width: 46,
            height: kTitleBarHeight,
            color: background,
            child: Icon(widget.icon, size: AppSize.iconSm - 2, color: foreground),
          ),
        ),
      ),
    );
  }
}
