import 'package:flutter/material.dart';

/// Draws a high-contrast debug crosshair at an exact selection coordinate.
void paintDebugCenterMarker({
  required Canvas canvas,
  required Offset center,
  required Color color,
  String? label,
}) {
  if (!center.dx.isFinite || !center.dy.isFinite) return;

  const armLength = 11.0;
  final outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round
    ..color = Colors.black;
  final markerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..color = color;

  final horizontalStart = center - const Offset(armLength, 0);
  final horizontalEnd = center + const Offset(armLength, 0);
  final verticalStart = center - const Offset(0, armLength);
  final verticalEnd = center + const Offset(0, armLength);

  canvas.drawLine(horizontalStart, horizontalEnd, outlinePaint);
  canvas.drawLine(verticalStart, verticalEnd, outlinePaint);
  canvas.drawLine(horizontalStart, horizontalEnd, markerPaint);
  canvas.drawLine(verticalStart, verticalEnd, markerPaint);
  canvas.drawCircle(center, 5.5, Paint()..color = Colors.black);
  canvas.drawCircle(center, 3.2, Paint()..color = color);

  if (label == null || label.isEmpty) return;
  final labelPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  labelPainter.paint(canvas, center + const Offset(13, -18));
}
