import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/theme_accent.dart';

/// A theme-colour swatch that shows both halves of the pair: the light-mode
/// accent on the upper-left, the dark-mode accent on the lower-right, split
/// on the diagonal the way an OS appearance picker splits its "auto" tile.
///
/// Both halves are the **rendered** accents — what `primary` actually is in
/// each brightness — not the pair's stored values. The light half of a
/// [ThemeAccent] is a seed the scheme takes tone 40 of, and is itself drawn
/// nowhere; a swatch that showed it would be promising a colour no button
/// wears. The dark half is drawn verbatim, so for it the two are the same.
class DualToneSwatch extends StatelessWidget {
  const DualToneSwatch({
    super.key,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  final ThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color light = buildAppColorScheme(accent: accent, brightness: Brightness.light).primary;
    final Color dark = buildAppColorScheme(accent: accent, brightness: Brightness.dark).primary;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // The glow takes the half that is on screen now, so a selected
          // swatch glows in the colour the app is actually wearing.
          boxShadow: [
            if (selected)
              BoxShadow(
                color: (colorScheme.brightness == Brightness.dark ? dark : light).withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
        child: CustomPaint(
          painter: _DualTonePainter(
            light: light,
            dark: dark,
            ring: selected ? colorScheme.onSurface : null,
          ),
          child: selected
              ? const Icon(
                  Icons.check,
                  size: 20,
                  // White with a soft shadow rather than a per-half contrast
                  // pick: the tick straddles the diagonal, so no single
                  // ground exists to pick against.
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 3)],
                )
              : null,
        ),
      ),
    );
  }
}

class _DualTonePainter extends CustomPainter {
  const _DualTonePainter({required this.light, required this.dark, this.ring});

  final Color light;
  final Color dark;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double radius = size.shortestSide / 2;

    // The whole disc in the dark half, then the upper-left half-disc in the
    // light one over it — one seam to anti-alias instead of two meeting.
    // Angles are clockwise from +x on screen: −π/4 is the top-right point of
    // the diagonal, and a negative sweep runs back over the top and left.
    canvas.drawCircle(rect.center, radius, Paint()..color = dark);
    canvas.drawArc(rect, -math.pi / 4, -math.pi, true, Paint()..color = light);

    final Color? ring = this.ring;
    if (ring != null) {
      canvas.drawCircle(
        rect.center,
        radius - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ring,
      );
    }
  }

  @override
  bool shouldRepaint(_DualTonePainter old) =>
      old.light != light || old.dark != dark || old.ring != ring;
}
