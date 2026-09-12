import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_effects.dart';
import '../../core/design_tokens.dart';

/// The three glass grades (`00 设计系统 · 1c`).
///
/// Glass is for the **control layer only**: bars, floating toolbars, menus,
/// sheets' shells, the task capsule, segment lenses. Lists, cards, inputs,
/// images and message bodies are opaque content that glass floats over.
///
/// Budget per screen: at most **one full-width** layer ([bar]) and at most
/// three glass layers visible at once, and glass only touches the *edges* of a
/// scrolling area. A full-width backdrop blur costs ~19ms a frame on an
/// integrated GPU at 4K, which is the reason for the budget, not taste.
///
/// Half of that budget is now kept by the class rather than by hand: a [lens]
/// laid on another glass layer paints its fill and edge but skips the
/// backdrop sample, because what it would be blurring is the parent's
/// already blurred output. The workbench had drifted to seven layers before
/// that rule existed — the nav lens on the title bar, and a segmented
/// control's indicator and hover lens on the floating toolbar. Counting the
/// remaining layers is still a per-screen judgement; `rebuild_scope_test`
/// pins the workbench's.
enum GlassGrade {
  /// G1 · the one full-width layer per screen: the title bar, a tablet top bar,
  /// a phone screen's top toolbar.
  bar,

  /// G2 · floating pieces: toolbars, menus, sheet shells, the task capsule,
  /// snackbars, popovers, the phone dock.
  float,

  /// G3 · the lens: a segmented control's indicator, a hover or pressed lens,
  /// a strip of actions over a thumbnail.
  lens,
}

/// Which palette a glass layer uses.
///
/// The design asks for tone to follow the *brightness of what is behind the
/// glass*. Sampling the backdrop is not something Flutter can do per frame at
/// an acceptable cost, so tone is declared: it defaults to the theme's
/// brightness, and a layer that knows it sits over dark content — a media
/// preview bar, a strip over a thumbnail, a snackbar — says [dark].
enum GlassTone { light, dark }

/// Blur, saturation and fill for one grade (CSS values; blur is a CSS radius).
@immutable
class GlassRecipe {
  const GlassRecipe({required this.blur, required this.saturation, required this.fill});

  final double blur;
  final double saturation;
  final double fill;

  static const bar = GlassRecipe(blur: 24, saturation: 1.6, fill: 0.56);
  static const float = GlassRecipe(blur: 20, saturation: 1.5, fill: 0.66);
  static const lens = GlassRecipe(blur: 12, saturation: 1.3, fill: 0.42);

  static GlassRecipe of(GlassGrade grade) => switch (grade) {
        GlassGrade.bar => bar,
        GlassGrade.float => float,
        GlassGrade.lens => lens,
      };
}

/// The colours of glass in one tone (`joycai-ui.css` `--gfill … --gshadow`).
@immutable
class GlassPalette {
  const GlassPalette({
    required this.fill,
    required this.ink,
    required this.ink2,
    required this.highlight,
    required this.lowlight,
    required this.edge,
    required this.shadow,
  });

  /// The fill colour, at full alpha; the grade supplies the alpha.
  final Color fill;

  /// `gink`: labels and glyphs on glass. Vibrant, never pure black or white.
  final Color ink;

  /// `gink2`: secondary labels on glass.
  final Color ink2;

  /// The refraction highlight along the top-left edge.
  final Color highlight;

  /// The shadowed edge along the bottom-right.
  final Color lowlight;

  /// The 1px edge stroke, and dividers drawn on glass.
  final Color edge;

  /// The outer shadow.
  final Color shadow;

  static const light = GlassPalette(
    fill: Color(0xFFFFFFFF),
    ink: Color(0xDB1C1B18),
    ink2: Color(0x941C1B18),
    highlight: Color(0xBFFFFFFF),
    lowlight: Color(0x1A1C1B18),
    edge: Color(0x8CFFFFFF),
    shadow: Color(0x1F1C1B18),
  );

  static const dark = GlassPalette(
    fill: Color(0xFF1E1E1C),
    ink: Color(0xE0F0EEE8),
    ink2: Color(0x99F0EEE8),
    highlight: Color(0x24FFFFFF),
    lowlight: Color(0x8C000000),
    edge: Color(0x1FFFFFFF),
    shadow: Color(0x80000000),
  );

  static GlassPalette of(GlassTone tone) => tone == GlassTone.dark ? dark : light;
}

/// Which sides of a glass layer carry its edge stroke.
enum GlassEdges {
  /// A floating piece: the full rounded outline.
  all,

  /// A bar pinned to the top of the window: one rule along its bottom.
  bottom,

  /// A bar pinned to the bottom: one rule along its top.
  top,

  /// No stroke.
  none,
}

/// Ink colours for whatever sits on the nearest glass layer.
///
/// Children read this instead of the colour scheme so a label on a glass bar
/// takes `gink` with effects on and body ink with them off, without knowing
/// which is in force.
class GlassInk extends InheritedWidget {
  const GlassInk({
    super.key,
    required this.ink,
    required this.ink2,
    required this.edge,
    required this.tone,
    required this.reduced,
    required super.child,
  });

  final Color ink;
  final Color ink2;

  /// A divider drawn on this glass (`--gedge`, or the hairline when reduced).
  final Color edge;
  final GlassTone tone;

  /// Whether the glass above is rendering as its opaque fallback.
  final bool reduced;

  static GlassInk? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassInk>();

  @override
  bool updateShouldNotify(GlassInk oldWidget) =>
      ink != oldWidget.ink ||
      ink2 != oldWidget.ink2 ||
      edge != oldWidget.edge ||
      tone != oldWidget.tone ||
      reduced != oldWidget.reduced;
}

/// A saturation matrix in the shape [ui.ColorFilter.matrix] wants — CSS
/// `saturate(s)`, a blend between a colour and its Rec. 709 luminance.
List<double> glassSaturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final d = 1 - s;
  return [
    lr * d + s, lg * d, lb * d, 0, 0, //
    lr * d, lg * d + s, lb * d, 0, 0, //
    lr * d, lg * d, lb * d + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// The backdrop filter for a CSS `blur(r) saturate(s)` pair.
///
/// Composed rather than nested: two BackdropFilters would sample the layer
/// twice. Sigma is the CSS radius / 2, the conversion the platforms agree on.
ui.ImageFilter glassFilter({required double blur, required double saturation}) =>
    ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(glassSaturationMatrix(saturation)),
      inner: ui.ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
    );

/// A layer of Liquid Glass.
///
/// With effects on: a translucent fill over a blurred, saturated backdrop, a
/// 1px refraction edge (bright top-left, shadowed bottom-right), a faint inner
/// highlight, and — for bars and floats — a soft outer shadow. [pressed]
/// makes it more transparent and brighter-edged (`00`: fill ×0.6, edge +1px
/// outward, shadow +6), which is what a finger on glass looks like.
///
/// With *reduce visual effects* on ([AppEffects]): the same box, opaque — a
/// bar takes the column colour, a float or lens the panel colour, a dark-toned
/// layer the fixed overlay ink — with a hairline instead of the edge and no
/// blur. Layout, size and radius do not move by a pixel.
class AppGlass extends StatelessWidget {
  const AppGlass({
    super.key,
    this.grade = GlassGrade.float,
    this.tone,
    this.borderRadius = BorderRadius.zero,
    this.edges = GlassEdges.all,
    this.pressed = false,
    this.shadow = true,
    this.padding,
    this.reducedColor,
    this.reducedBorder = true,
    required this.child,
  });

  final GlassGrade grade;

  /// Null follows the ambient theme's brightness.
  final GlassTone? tone;

  final BorderRadius borderRadius;
  final GlassEdges edges;
  final bool pressed;

  /// Whether a bar or float casts its outer shadow. Lenses never do.
  final bool shadow;

  final EdgeInsetsGeometry? padding;

  /// Overrides the opaque fill used when effects are reduced — a selected
  /// navigation lens degrades to the accent wash, not to a panel.
  final Color? reducedColor;

  /// Whether the reduced form draws its hairline.
  final bool reducedBorder;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolvedTone = tone ??
        (theme.brightness == Brightness.dark ? GlassTone.dark : GlassTone.light);
    final reduced = AppEffects.reduced(context);

    Widget content = padding == null ? child : Padding(padding: padding!, child: child);

    if (reduced) {
      return _buildReduced(context, scheme, resolvedTone, content);
    }

    final palette = GlassPalette.of(resolvedTone);
    final recipe = GlassRecipe.of(grade);
    final fillAlpha = recipe.fill * (pressed ? 0.6 : 1.0);

    content = GlassInk(
      ink: palette.ink,
      ink2: palette.ink2,
      edge: palette.edge,
      tone: resolvedTone,
      reduced: false,
      child: IconTheme.merge(
        data: IconThemeData(color: palette.ink),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: palette.ink),
          child: content,
        ),
      ),
    );

    Widget surface = CustomPaint(
      foregroundPainter: _GlassEdgePainter(
        borderRadius: borderRadius,
        edges: edges,
        palette: palette,
        pressed: pressed,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fill.withValues(alpha: fillAlpha),
          borderRadius: borderRadius,
        ),
        child: content,
      ),
    );

    // A lens laid on another glass layer does not sample the window again.
    //
    // G3 is defined as something laid *on* a surface — a segment's indicator,
    // a hover or pressed state, a strip over a thumbnail. When that surface is
    // itself glass, the lens's backdrop is the parent's already blurred,
    // already saturated, fill-covered output; blurring it a second time
    // through a 42% fill returns close to nothing and costs a second
    // full-size backdrop pass. The fill, the refraction edge and the
    // highlight all still paint, so the lens looks like a lens.
    //
    // Grade-scoped on purpose: a menu, a sheet or a snackbar is a [float],
    // overhangs whatever it opened from, and keeps its own blur even when the
    // element tree puts it under one — which an OverlayPortal does.
    //
    // This is what holds the budget in the class doc above. Before it the
    // workbench carried seven backdrop filters at once against a documented
    // ceiling of three: the nav lens on the title bar, and the segmented
    // control's indicator and hover lens on the floating toolbar.
    final GlassInk? onGlass = GlassInk.maybeOf(context);
    final bool nestedLens =
        grade == GlassGrade.lens && onGlass != null && !onGlass.reduced;

    surface = ClipRRect(
      borderRadius: borderRadius,
      child: nestedLens
          ? surface
          : BackdropFilter(
              filter: glassFilter(blur: recipe.blur, saturation: recipe.saturation),
              child: surface,
            ),
    );

    if (shadow && grade != GlassGrade.lens) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: palette.shadow.a * 0.5),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: palette.shadow,
              blurRadius: pressed ? 36 : 30,
              offset: Offset(0, pressed ? 12 : 10),
            ),
          ],
        ),
        child: surface,
      );
    }
    return surface;
  }

  Widget _buildReduced(
    BuildContext context,
    ColorScheme scheme,
    GlassTone resolvedTone,
    Widget content,
  ) {
    final themeTone =
        scheme.brightness == Brightness.dark ? GlassTone.dark : GlassTone.light;
    // A layer toned against the theme (a dark snackbar in a light app) cannot
    // borrow the scheme's surfaces — they are the wrong brightness — so it
    // takes the fixed overlay ink, as `01 · 1k` draws.
    final bool offTone = resolvedTone != themeTone && resolvedTone == GlassTone.dark;

    final Color background = reducedColor ??
        (offTone
            ? AppOverlay.ink
            : grade == GlassGrade.bar
                ? scheme.surfaceContainerLow
                : scheme.surface);
    final Color ink = offTone ? const Color(0xFFECEAE4) : scheme.onSurface;
    final Color ink2 = offTone ? const Color(0xFFA9A69E) : scheme.onSurfaceVariant;
    final Color hair = offTone ? Colors.transparent : scheme.outlineVariant;

    BoxBorder? border;
    if (reducedBorder && reducedColor == null) {
      border = switch (edges) {
        GlassEdges.all => Border.all(color: hair),
        GlassEdges.bottom => Border(bottom: BorderSide(color: hair)),
        GlassEdges.top => Border(top: BorderSide(color: hair)),
        GlassEdges.none => null,
      };
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: edges == GlassEdges.all ? borderRadius : null,
        border: border,
        boxShadow: shadow && grade == GlassGrade.float && !offTone
            ? [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: GlassInk(
        ink: ink,
        ink2: ink2,
        edge: offTone ? const Color(0x1FFFFFFF) : scheme.outlineVariant,
        tone: resolvedTone,
        reduced: true,
        child: IconTheme.merge(
          data: IconThemeData(color: ink),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Tinted glass — the accent's **solid** form, when it stands on a glass bar
/// (`00` 「着色玻璃 gp」): `primary` at 74% over a blur, a white 35% edge, a
/// shadow in the accent's own hue.
///
/// Reduced, it is simply the solid accent. Disabled, it is a faint wash of the
/// glass ink under secondary ink (`A3a · 1b`), because a disabled CTA must not
/// glow.
class AppTintedGlass extends StatelessWidget {
  const AppTintedGlass({
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.control)),
    this.enabled = true,
    this.padding,
    required this.child,
  });

  final BorderRadius borderRadius;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = AppEffects.reduced(context);
    final glassInk = GlassInk.maybeOf(context);

    Widget content = padding == null ? child : Padding(padding: padding!, child: child);

    if (!enabled) {
      final ink = glassInk?.ink ?? scheme.onSurface;
      final ink2 = glassInk?.ink2 ?? scheme.onSurfaceVariant;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: reduced ? scheme.surfaceContainerHighest : ink.withValues(alpha: 0.08),
          borderRadius: borderRadius,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: reduced ? scheme.outline : ink2),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: reduced ? scheme.outline : ink2),
            child: content,
          ),
        ),
      );
    }

    content = IconTheme.merge(
      data: IconThemeData(color: scheme.onPrimary),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onPrimary),
        child: content,
      ),
    );

    if (reduced) {
      return DecoratedBox(
        decoration: BoxDecoration(color: scheme.primary, borderRadius: borderRadius),
        child: content,
      );
    }

    // Standing on glass, it does not sample the window again — for the reason
    // [AppGlass] gives a nested lens, and more so here: this fill is the
    // accent at 74%, so what a second blur of an already blurred surface
    // shows through it is very close to nothing. Off glass — on a panel, in a
    // dialog — it is the first layer and keeps its own.
    final bool nested = glassInk != null && !glassInk.reduced;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: scheme.accentGlow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _maybeBlur(
          nested: nested,
          child: CustomPaint(
            foregroundPainter: _TintedEdgePainter(borderRadius: borderRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.accentGlassFill,
                borderRadius: borderRadius,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _maybeBlur({required bool nested, required Widget child}) =>
      nested
          ? child
          : BackdropFilter(
              filter: glassFilter(blur: 16, saturation: 1.4),
              child: child,
            );
}

/// The refraction edge: a 1px stroke that is bright where light would enter
/// (top-left) and shadowed where it would leave (bottom-right), over a base
/// edge colour, plus the inner top highlight.
class _GlassEdgePainter extends CustomPainter {
  _GlassEdgePainter({
    required this.borderRadius,
    required this.edges,
    required this.palette,
    required this.pressed,
  });

  final BorderRadius borderRadius;
  final GlassEdges edges;
  final GlassPalette palette;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges == GlassEdges.none) return;
    final rect = Offset.zero & size;

    if (edges == GlassEdges.bottom || edges == GlassEdges.top) {
      final y = edges == GlassEdges.bottom ? size.height - 0.5 : 0.5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = palette.edge
          ..strokeWidth = 1,
      );
      // The inner highlight still runs along the top of a bar.
      if (edges == GlassEdges.bottom) {
        canvas.drawLine(
          const Offset(0, 0.5),
          Offset(size.width, 0.5),
          Paint()
            ..color = palette.highlight.withValues(alpha: palette.highlight.a * 0.6)
            ..strokeWidth = 1,
        );
      }
      return;
    }

    final rrect = borderRadius.toRRect(rect).deflate(0.5);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.edge,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.highlight,
            palette.highlight.withValues(alpha: 0),
            palette.lowlight.withValues(alpha: 0),
            palette.lowlight,
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
    if (pressed) {
      canvas.drawRRect(
        borderRadius.toRRect(rect).inflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.highlight,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.edges != edges ||
      oldDelegate.palette != palette ||
      oldDelegate.pressed != pressed;
}

class _TintedEdgePainter extends CustomPainter {
  _TintedEdgePainter({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(0.5);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x80FFFFFF), Color(0x40FFFFFF), Color(0x24000000)],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_TintedEdgePainter oldDelegate) => oldDelegate.borderRadius != borderRadius;
}
