part of '../theme_accent_picker.dart';

/// The hue ring — `1b`: 130px, a 16px band of the hues at the chroma and
/// tone a picked hue is seeded at, and a 14px handle with a white 3px edge.
///
/// Drag or tap anywhere to set the hue by angle; arrow keys step it by 5°.
class _HueRing extends StatefulWidget {
  const _HueRing({required this.hue, required this.seed, required this.onChanged});

  final double hue;
  final Color seed;
  final ValueChanged<double> onChanged;

  static const double size = 130;
  static const double band = 16;

  @override
  State<_HueRing> createState() => _HueRingState();
}

class _HueRingState extends State<_HueRing> {
  bool _focused = false;

  void _fromPosition(Offset local) {
    const Offset centre = Offset(_HueRing.size / 2, _HueRing.size / 2);
    final Offset d = local - centre;
    if (d.distance < 4) return;
    final double degrees = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    widget.onChanged(degrees.roundToDouble());
  }

  void _step(double by) => widget.onChanged(((widget.hue + by) % 360 + 360) % 360);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: l10n.customColor,
      value: '${widget.hue.round()}°',
      increasedValue: '${((widget.hue + 5) % 360).round()}°',
      decreasedValue: '${((widget.hue - 5 + 360) % 360).round()}°',
      onIncrease: () => _step(5),
      onDecrease: () => _step(-5),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _step(5);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _step(-5);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onPanDown: (d) => _fromPosition(d.localPosition),
          onPanUpdate: (d) => _fromPosition(d.localPosition),
          child: SizedBox.square(
            dimension: _HueRing.size,
            child: CustomPaint(
              painter: _HueRingPainter(
                hue: widget.hue,
                seed: widget.seed,
                focusRing: _focused ? colorScheme.accentRing : null,
                stops: _hueStops,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HueRingPainter extends CustomPainter {
  const _HueRingPainter({
    required this.hue,
    required this.seed,
    required this.focusRing,
    required this.stops,
  });

  final double hue;
  final Color seed;
  final Color? focusRing;
  final List<Color> stops;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - _HueRing.band / 2;
    final Rect rect = Rect.fromCircle(center: c, radius: size.shortestSide / 2);

    if (focusRing != null) {
      canvas.drawCircle(
        c,
        size.shortestSide / 2 - _HueRing.band - 3,
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = SweepGradient(colors: stops).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _HueRing.band,
    );

    final double a = hue * math.pi / 180;
    final Offset handle = c + Offset(math.cos(a), math.sin(a)) * radius;
    canvas.drawCircle(
      handle.translate(0, 1),
      8.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(handle, 7, Paint()..color = Colors.white);
    canvas.drawCircle(handle, 4, Paint()..color = seed);
  }

  @override
  bool shouldRepaint(_HueRingPainter old) =>
      old.hue != hue || old.seed != seed || old.focusRing != focusRing;
}
