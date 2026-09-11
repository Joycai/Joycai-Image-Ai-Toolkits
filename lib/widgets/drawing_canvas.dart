import 'package:flutter/material.dart';

class DrawingPath {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isPolygon;

  DrawingPath({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isPolygon = false,
  });
}

class MaskPainter extends CustomPainter {
  final List<DrawingPath> paths;

  MaskPainter({required this.paths});

  @override
  void paint(Canvas canvas, Size size) {
    for (var drawingPath in paths) {
      final paint = Paint()
        ..color = drawingPath.color
        ..strokeWidth = drawingPath.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = drawingPath.isPolygon ? PaintingStyle.fill : PaintingStyle.stroke;

      if (drawingPath.points.length > 1) {
        final path = Path();
        path.moveTo(drawingPath.points.first.dx, drawingPath.points.first.dy);
        for (int i = 1; i < drawingPath.points.length; i++) {
          path.lineTo(drawingPath.points[i].dx, drawingPath.points[i].dy);
        }
        if (drawingPath.isPolygon) {
          path.close();
        }
        canvas.drawPath(path, paint);
      } else if (drawingPath.points.isNotEmpty && !drawingPath.isPolygon) {
        canvas.drawCircle(drawingPath.points.first, drawingPath.strokeWidth / 2, paint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MaskPainter oldDelegate) => true;
}

