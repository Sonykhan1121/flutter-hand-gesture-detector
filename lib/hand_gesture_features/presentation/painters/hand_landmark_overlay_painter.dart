import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

class HandLandmarkOverlayPainter extends CustomPainter {
  const HandLandmarkOverlayPainter({
    required this.hands,
    required this.imageSize,
    required this.mirrorHorizontally,
  });

  final List<Hand> hands;
  final Size imageSize;
  final bool mirrorHorizontally;

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }

    final skeletonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF00FB46);

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFD54F);

    final pointBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black;

    Offset mapPoint(double x, double y) {
      final mappedX = x * size.width / imageSize.width;
      final mappedY = y * size.height / imageSize.height;
      return Offset(
        mirrorHorizontally ? size.width - mappedX : mappedX,
        mappedY,
      );
    }

    for (final hand in hands) {
      if (hand.hasLandmarks) {
        for (final connection in handLandmarkConnections) {
          final start = hand.getLandmark(connection[0]);
          final end = hand.getLandmark(connection[1]);

          if (start == null || end == null) continue;

          canvas.drawLine(
            mapPoint(start.x, start.y),
            mapPoint(end.x, end.y),
            skeletonPaint,
          );
        }

        for (final landmark in hand.landmarks) {
          final center = mapPoint(landmark.x, landmark.y);
          canvas.drawCircle(center, 6, pointPaint);
          canvas.drawCircle(center, 6, pointBorderPaint);
          _drawLandmarkIndex(canvas, '${landmark.type.index}', center);
        }
      }
    }
  }

  void _drawLandmarkIndex(Canvas canvas, String text, Offset center) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, center + const Offset(7, -11));
  }

  @override
  bool shouldRepaint(covariant HandLandmarkOverlayPainter oldDelegate) {
    return oldDelegate.hands != hands ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally;
  }
}
