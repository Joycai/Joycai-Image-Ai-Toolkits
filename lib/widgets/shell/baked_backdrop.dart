// The window ground, baked once into an image instead of redrawn every frame.
//
// Measured on the dev machine (integrated Radeon, 4K maximized, render target
// 3840x2064, Skia/ANGLE, 60Hz), GPU time per frame:
//
//   blank window                               2.58 ms
//   the four live layers (`AuroraBackdrop`)    9.91 ms
//   three solid fills, no gradient shader      6.94 ms
//   this, one quarter-res textured quad        4.84 ms
//
// So the ground cost 7.33 ms of a 16.7 ms budget, 4.36 ms of that just for
// being three full-window draws blended over the one below and 2.97 ms for
// the gradient shaders on top. Baking removes 69% of it.
//
// `RepaintBoundary` does not do this job and the old comment here claimed it
// did: it bounds which Dart paint code re-runs, not what the GPU executes,
// and the raster cache has a size ceiling a 4K window is far past. The
// numbers above are the ones `lib/bench/render_bench.dart` reproduces.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_effects.dart';

/// The aurora's recipe, as [Gradient] objects so the baked and the live
/// versions cannot drift apart.
///
/// Alphas duplicated from [AuroraBackdrop]; they belong to this wall and stay
/// far under 12% so a selected state still reads against it.
class AuroraRecipe {
  const AuroraRecipe({
    required this.canvas,
    required this.primary,
    required this.surface,
  });

  factory AuroraRecipe.of(ColorScheme scheme) => AuroraRecipe(
        canvas: scheme.surfaceContainer,
        primary: scheme.primary,
        surface: scheme.surface,
      );

  final Color canvas;
  final Color primary;
  final Color surface;

  static const double glowAlpha = 0.06;
  static const double echoAlpha = 0.04;
  static const double liftAlpha = 0.55;

  /// Each layer fades to its own colour at zero alpha rather than to
  /// `Colors.transparent`, which is transparent *black*: the gradient
  /// interpolates unpremultiplied and would grey the middle of the fade.
  List<Gradient> get gradients {
    final glow = primary.withValues(alpha: glowAlpha);
    final echo = primary.withValues(alpha: echoAlpha);
    final lift = surface.withValues(alpha: liftAlpha);
    return <Gradient>[
      RadialGradient(
        center: const Alignment(-0.7, -1.2),
        radius: 1.2,
        colors: [glow, glow.withValues(alpha: 0)],
        stops: const [0, 0.6],
      ),
      RadialGradient(
        center: const Alignment(0.9, 1.1),
        radius: 1.0,
        colors: [echo, echo.withValues(alpha: 0)],
        stops: const [0, 0.62],
      ),
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lift, lift.withValues(alpha: 0)],
        stops: const [0, 0.42],
      ),
    ];
  }

  void paint(Canvas canvas_, Size size) {
    final Rect rect = Offset.zero & size;
    canvas_.drawRect(rect, Paint()..color = canvas);
    for (final Gradient g in gradients) {
      canvas_.drawRect(rect, Paint()..shader = g.createShader(rect));
    }
  }

  /// Anything a change of which must re-bake.
  Object get key => (canvas.toARGB32(), primary.toARGB32(), surface.toARGB32());
}

/// Drop-in replacement for `AuroraBackdrop`, baked.
class BakedAuroraBackdrop extends StatelessWidget {
  const BakedAuroraBackdrop({
    super.key,
    this.child,
    this.filterQuality = FilterQuality.medium,
  });

  final Widget? child;

  /// How the quarter-resolution bake is upscaled. `medium` is trilinear with
  /// mipmaps, `low` plain bilinear — on a smooth gradient both are invisible,
  /// and on an integrated GPU covering 8 megapixels the sampling is not free.
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (AppEffects.reduced(context)) {
      return ColoredBox(color: scheme.surfaceContainer, child: child);
    }
    final recipe = AuroraRecipe.of(scheme);
    return BakedBackdrop(
      paint: recipe.paint,
      recipeKey: recipe.key,
      filterQuality: filterQuality,
      child: child,
    );
  }
}

/// Bakes a static, decorative backdrop into one image and draws it as a single
/// textured quad. Re-bakes only when the size or the recipe changes.
///
/// Only for static decoration: anything that animates per frame would re-bake
/// per frame and be worse. The quarter-resolution trick is fine for gradients
/// and soft washes and nothing else — there is no hard edge here to soften.
///
/// **Quarter resolution only under Skia** ([texelsPerLogicalPixel]). Impeller
/// dithers every gradient with a per-pixel pattern. Painted live that pattern
/// is below notice; baked into a quarter-*logical* image and stretched back
/// out it becomes a visible grid — 8 physical pixels a texel on a Retina Mac,
/// a 16px checker across the whole gallery. So where Impeller renders the
/// bake is made at physical resolution, texel for pixel. Windows pins Skia
/// (`windows/runner/main.cpp`), which is where the quarter-res saving was
/// measured, and keeps it.
class BakedBackdrop extends StatefulWidget {
  const BakedBackdrop({
    super.key,
    required this.paint,
    required this.recipeKey,
    this.filterQuality = FilterQuality.medium,
    this.child,
  });

  /// Paints the backdrop into the given size. Must be pure.
  final void Function(Canvas canvas, Size size) paint;

  /// Anything the backdrop depends on. A change re-bakes.
  final Object recipeKey;

  /// How the bake is upscaled to the window.
  final FilterQuality filterQuality;

  final Widget? child;

  /// Whether this platform's default renderer is Impeller, which dithers
  /// gradients. Windows is pinned to Skia by its runner; Linux defaults to it.
  static final bool _rendererDithers =
      Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

  /// Image pixels to bake per logical pixel of the window.
  ///
  /// Under Skia a quarter: smooth gradients survive it untouched, and
  /// re-baking on a resize costs almost nothing at a sixteenth of the pixels.
  /// Under Impeller one per physical pixel — see the class comment for the
  /// grid a magnified dither draws.
  @visibleForTesting
  static double texelsPerLogicalPixel({
    required double devicePixelRatio,
    required bool rendererDithers,
  }) =>
      rendererDithers ? devicePixelRatio : 1 / 4;

  @override
  State<BakedBackdrop> createState() => _BakedBackdropState();
}

class _BakedBackdropState extends State<BakedBackdrop> {
  ui.Image? _image;
  Size? _bakedFor;
  double? _bakedRatio;
  Object? _bakedKey;
  bool _baking = false;

  /// Well inside every GPU's texture limit, and above a 5K display's width,
  /// so a physical-resolution bake is never stretched.
  static const int _maxTexture = 8192;

  Future<void> _bake(Size size, double ratio) async {
    if (_baking) return;
    _baking = true;
    final double scale = BakedBackdrop.texelsPerLogicalPixel(
      devicePixelRatio: ratio,
      rendererDithers: BakedBackdrop._rendererDithers,
    );
    final int w = (size.width * scale).ceil().clamp(1, _maxTexture);
    final int h = (size.height * scale).ceil().clamp(1, _maxTexture);
    final recorder = ui.PictureRecorder();
    widget.paint(Canvas(recorder), Size(w.toDouble(), h.toDouble()));
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(w, h);
    picture.dispose();
    _baking = false;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _bakedFor = size;
      _bakedRatio = ratio;
      _bakedKey = widget.recipeKey;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = constraints.biggest;
        // Moving the window to a display with another scale re-bakes too.
        final double ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final bool stale = _bakedFor != size ||
            _bakedRatio != ratio ||
            _bakedKey != widget.recipeKey;
        if (stale && size.isFinite && !size.isEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _bake(size, ratio));
        }
        final ui.Image? image = _image;
        // Before the first bake lands, paint the recipe live rather than show
        // a flat stand-in. It is the same picture either way, so there is no
        // visible swap, and it costs the four full-window fills for one or two
        // frames. It also keeps the widget tests honest: `toImage` never
        // completes inside `flutter_test`, so a flat fallback would quietly
        // drain the wall out of every screenshot in the harness.
        final Widget ground = image == null
            ? CustomPaint(painter: _RecipePainter(widget.paint), size: size)
            : RawImage(
                image: image,
                fit: BoxFit.fill,
                filterQuality: widget.filterQuality,
              );
        final Widget? child = widget.child;
        if (child == null) return ground;
        return Stack(fit: StackFit.expand, children: [ground, child]);
      },
    );
  }
}

/// Paints the recipe straight onto the canvas — the pre-bake frames, and the
/// whole of a widget test.
class _RecipePainter extends CustomPainter {
  const _RecipePainter(this.paint_);

  final void Function(Canvas canvas, Size size) paint_;

  @override
  void paint(Canvas canvas, Size size) => paint_(canvas, size);

  @override
  bool shouldRepaint(_RecipePainter oldDelegate) => oldDelegate.paint_ != paint_;
}
