import 'package:flutter/material.dart';

/// A hairline dashed rounded rectangle.
///
/// Flutter's [Border] cannot dash, so every place that wanted one grew its own
/// painter: the models grid's "add a model" cell (`D2 14a`), the comparator's
/// two drop targets, and now the task queue's empty-output slot (`C1 10h`).
/// Three copies of the same twenty lines at two different stroke widths and
/// two different comments explaining the same absence in the framework.
///
/// The dash and gap are fixed rather than parameterised. They are what makes a
/// dashed edge read as *dashed* at hairline weight — shorter and it looks like
/// a dotted rule, longer and it looks like a solid line someone erased bits of
/// — and no call site has ever wanted a different rhythm.
class DashedBorder extends StatelessWidget {
  final Color color;
  final double radius;

  /// 1 for an outline that only marks a boundary; 1.5 for a drop target, where
  /// the edge is the affordance and has to survive being dragged over.
  final double strokeWidth;

  final Widget? child;

  const DashedBorder({
    super.key,
    required this.color,
    required this.radius,
    this.strokeWidth = 1,
    this.child,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedBorderPainter(
          color: color,
          radius: radius,
          strokeWidth: strokeWidth,
        ),
        child: child,
      );
}

class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 5;
  static const double _gap = 4;

  final Color color;
  final double radius;
  final double strokeWidth;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + _dash).clamp(0.0, metric.length)),
          paint,
        );
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}
