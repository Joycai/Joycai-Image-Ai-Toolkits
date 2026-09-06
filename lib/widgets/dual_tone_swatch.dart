import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/theme_accent.dart';

/// A theme-colour swatch that shows both halves of the pair: the light-mode
/// accent on the upper-left, the dark-mode accent on the lower-right, split
/// on the diagonal the way an OS appearance picker splits its "auto" tile.
/// Design `D1a 20a` / `20d` / `20e`.
///
/// Both halves are the **rendered** accents — what `primary` actually is in
/// each brightness — not the pair's stored values. The light half of a
/// [ThemeAccent] is a seed the scheme takes tone 40 of, and is itself drawn
/// nowhere; a swatch that showed it would be promising a colour no button
/// wears. The dark half is drawn verbatim, so for it the two are the same.
/// The dot itself is therefore identical in both modes: it pictures the two
/// values, not the current one.
///
/// Four states, all drawn *outside* the 36px dot so it never changes size:
///
/// - hover: a 3px halo of the accent at 12%, plus a tooltip naming the
///   preset and both values (on touch, a long press);
/// - selected: a 3px gap in the panel colour, then a 2px ring of the accent,
///   and a 20px disc of panel colour in the middle carrying a tick in the
///   darker accent — so the pair stays visible as a ring around the disc;
/// - focused: 2px gap + 2px ring when unselected; when already selected, a
///   further 3px ring at 32% outside the selection ring.
///
/// The box is 44 square — the dot plus [hitInset] each side — so the tap
/// target meets the 44px floor; the rings paint past the box's edge and rely
/// on the parent not clipping, which a [Wrap] does not.
class DualToneSwatch extends StatefulWidget {
  const DualToneSwatch({
    super.key,
    required this.accent,
    required this.name,
    this.pairLabel,
    required this.selected,
    required this.onTap,
  });

  final ThemeAccent accent;

  /// The preset's name, for the tooltip.
  final String name;

  /// The second tooltip line — both values, already formatted. Null draws
  /// the tooltip with the name alone.
  final String? pairLabel;

  final bool selected;
  final VoidCallback onTap;

  static const double dotSize = 36;

  /// How far the hit box extends beyond the dot on each side.
  static const double hitInset = 4;

  static const double hitSize = dotSize + 2 * hitInset;

  @override
  State<DualToneSwatch> createState() => _DualToneSwatchState();
}

class _DualToneSwatchState extends State<DualToneSwatch> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color light =
        buildAppColorScheme(accent: widget.accent, brightness: Brightness.light).primary;
    final Color dark =
        buildAppColorScheme(accent: widget.accent, brightness: Brightness.dark).primary;

    final TextStyle? tipStyle = TooltipTheme.of(context).textStyle;
    final Widget dot = InkWell(
      onTap: widget.onTap,
      onHover: (v) => setState(() => _hovered = v),
      onFocusChange: (v) => setState(() => _focused = v),
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: DualToneSwatch.hitSize,
        height: DualToneSwatch.hitSize,
        child: CustomPaint(
          painter: _DualTonePainter(
            light: light,
            dark: dark,
            selected: widget.selected,
            hovered: _hovered,
            focused: _focused,
            accent: colorScheme.primary,
            accentTint: colorScheme.accentTint,
            accentRing: colorScheme.accentRing,
            onAccentTint: colorScheme.onAccentTint,
            panel: colorScheme.surface,
          ),
        ),
      ),
    );

    return Tooltip(
      richMessage: TextSpan(
        text: widget.name,
        style: tipStyle,
        children: [
          if (widget.pairLabel != null)
            TextSpan(
              text: '\n${widget.pairLabel}',
              // The values in mono, a step quieter than the name, on the
              // tooltip's fixed ink ground.
              style: (tipStyle ?? const TextStyle()).mono.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppOverlay.onInk.withValues(alpha: 0.72),
                  ),
            ),
        ],
      ),
      child: dot,
    );
  }
}

class _DualTonePainter extends CustomPainter {
  const _DualTonePainter({
    required this.light,
    required this.dark,
    required this.selected,
    required this.hovered,
    required this.focused,
    required this.accent,
    required this.accentTint,
    required this.accentRing,
    required this.onAccentTint,
    required this.panel,
  });

  final Color light;
  final Color dark;
  final bool selected;
  final bool hovered;
  final bool focused;
  final Color accent;
  final Color accentTint;
  final Color accentRing;
  final Color onAccentTint;
  final Color panel;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    const double r = DualToneSwatch.dotSize / 2;
    final Rect dotRect = Rect.fromCircle(center: c, radius: r);

    // Rings as strokes, so the gap between dot and ring is whatever the
    // swatch sits on. The design builds them from stacked spread shadows with
    // the gap painted in "the panel colour", but this control lands on a
    // card in the desktop settings and straight on the canvas in the phone's
    // appearance page — a painted gap is the wrong colour on one of them.
    Paint fill(Color color) => Paint()..color = color;
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (selected) {
      // 3px gap, 2px accent ring; keyboard focus adds a 3px 32% ring outside.
      if (focused) canvas.drawCircle(c, r + 6.5, stroke(accentRing, 3));
      canvas.drawCircle(c, r + 4, stroke(accent, 2));
    } else if (focused) {
      // 2px gap, 2px accent ring.
      canvas.drawCircle(c, r + 3, stroke(accent, 2));
    } else if (hovered) {
      canvas.drawCircle(c, r + 3, fill(accentTint));
    }

    // The whole disc in the dark half, then the upper-left half-disc in the
    // light one over it — one seam to anti-alias instead of two meeting.
    // Angles are clockwise from +x on screen: −π/4 is the top-right point of
    // the diagonal, and a negative sweep runs back over the top and left.
    canvas.drawCircle(c, r, fill(dark));
    canvas.drawArc(dotRect, -math.pi / 4, -math.pi, true, fill(light));

    if (selected) {
      canvas.drawCircle(c, 10, fill(panel));
      // The design's tick: `m5 13 4.5 4.5L19 7` in a 24-box, at 12px,
      // stroke 3.2 — drawn rather than an [Icon], which at 12px is a
      // hairline.
      const double k = 12 / 24;
      final Path tick = Path()
        ..moveTo(c.dx + (5 - 12) * k, c.dy + (13 - 12) * k)
        ..lineTo(c.dx + (9.5 - 12) * k, c.dy + (17.5 - 12) * k)
        ..lineTo(c.dx + (19 - 12) * k, c.dy + (7 - 12) * k);
      canvas.drawPath(
        tick,
        Paint()
          ..color = onAccentTint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DualTonePainter old) =>
      old.light != light ||
      old.dark != dark ||
      old.selected != selected ||
      old.hovered != hovered ||
      old.focused != focused ||
      old.accent != accent ||
      old.accentTint != accentTint ||
      old.accentRing != accentRing ||
      old.onAccentTint != onAccentTint ||
      old.panel != panel;
}
