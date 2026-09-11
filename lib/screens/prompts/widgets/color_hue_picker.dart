import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

/// Saturation and value every picked hue is drawn at, shared by the bar and
/// the wheel so a category keeps its colour whichever one chose it.
const double _kPickSaturation = 0.8;
const double _kPickValue = 0.9;

/// A horizontal hue bar (`C1 · 1d` 新建分类): a 12px r6 rainbow track and a
/// 20px handle filled with the current colour, ringed 3px in the panel colour.
///
/// Category colours are identity colours; nothing here reads the accent.
class ColorHueBar extends StatelessWidget {
  const ColorHueBar({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  final Color color;
  final ValueChanged<int> onColorChanged;

  static const double _handle = 20;
  static const double _track = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hue = HSVColor.fromColor(color).hue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final usable = math.max(1.0, width - _handle);

        void pick(double dx) {
          final t = ((dx - _handle / 2) / usable).clamp(0.0, 1.0);
          onColorChanged(HSVColor.fromAHSV(1, t * 360, _kPickSaturation, _kPickValue).toColor().toARGB32());
        }

        return Semantics(
          slider: true,
          value: '${hue.round()}',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition.dx),
              onHorizontalDragStart: (d) => pick(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
              child: SizedBox(
                width: width,
                height: _handle,
                child: Stack(
                  children: [
                    Positioned(
                      left: _handle / 2,
                      right: _handle / 2,
                      top: (_handle - _track) / 2,
                      height: _track,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          gradient: LinearGradient(
                            colors: [
                              for (int i = 0; i <= 6; i++)
                                HSVColor.fromAHSV(1, i * 60.0, _kPickSaturation, _kPickValue).toColor(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: usable * hue / 360,
                      top: 0,
                      child: Container(
                        width: _handle,
                        height: _handle,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 3),
                          boxShadow: scheme.shadowRaised,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A simple Hue color picker wheel implementation
class ColorHuePicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<int> onColorChanged;

  const ColorHuePicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorHuePicker> createState() => _ColorHuePickerState();
}

class _ColorHuePickerState extends State<ColorHuePicker> {
  late double _hue;

  @override
  void initState() {
    super.initState();
    _hue = HSVColor.fromColor(widget.initialColor).hue;
  }

  @override
  void didUpdateWidget(ColorHuePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newHue = HSVColor.fromColor(widget.initialColor).hue;
    if ((newHue - _hue).abs() > 1.0) {
      setState(() => _hue = newHue);
    }
  }

  void _handleGesture(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    double rad = (localPosition - center).direction; // -pi to pi
    double deg = (rad * 180 / 3.1415926535) + 90;
    if (deg < 0) deg += 360;

    setState(() {
      _hue = deg % 360;
    });
    
    final color = HSVColor.fromAHSV(1.0, _hue, 0.8, 0.9).toColor();
    widget.onColorChanged(color.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(160, 160);
    return GestureDetector(
      onPanUpdate: (details) => _handleGesture(details.localPosition, size),
      onPanDown: (details) => _handleGesture(details.localPosition, size),
      child: CustomPaint(
        size: size,
        painter: _ColorWheelPainter(hue: _hue),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  _ColorWheelPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 20.0;

    for (double i = 0; i < 360; i += 1) {
      final paint = Paint()
        ..color = HSVColor.fromAHSV(1.0, i, 1.0, 1.0).toColor()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 1;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
        (i - 90) * 3.1415926535 / 180,
        1.5 * 3.1415926535 / 180,
        false,
        paint,
      );
    }

    final indicatorAngle = (hue - 90) * 3.1415926535 / 180;
    final indicatorOffset = Offset(
      center.dx + (radius - (strokeWidth / 2)) * math.cos(indicatorAngle),
      center.dy + (radius - (strokeWidth / 2)) * math.sin(indicatorAngle),
    );

    canvas.drawCircle(
      indicatorOffset, 
      12, 
      Paint()..color = Colors.black26..style = PaintingStyle.fill..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
    );
    canvas.drawCircle(
      indicatorOffset, 
      10, 
      Paint()..color = Colors.white..style = PaintingStyle.fill
    );
    canvas.drawCircle(
      indicatorOffset, 
      7, 
      Paint()..color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor()..style = PaintingStyle.fill
    );

    canvas.drawCircle(
      center, 
      radius - strokeWidth - 12, 
      Paint()..color = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor()..style = PaintingStyle.fill
    );
    canvas.drawCircle(
      center, 
      radius - strokeWidth - 12, 
      Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 2
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) => oldDelegate.hue != hue;
}