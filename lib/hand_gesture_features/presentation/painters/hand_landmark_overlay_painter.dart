import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

/// Painter that draws detected hand skeletons over the live preview.
class HandLandmarkOverlayPainter extends CustomPainter {
  const HandLandmarkOverlayPainter({
    required this.hands,
    required this.imageSize,
    required this.mirrorHorizontally,
    this.previewQuarterTurns = 0,
  });

  final List<Hand> hands;
  final Size imageSize;
  final bool mirrorHorizontally;
  final int previewQuarterTurns;

  @override
  /// Draws landmark connections, landmark points, and optional index labels.
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }

    final skeletonPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF00FB46);

    final pointPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFFFD54F);

    final pointBorderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.black;

    // Local helper keeps all landmark drawing in the same coordinate mapping.
    Offset mapPoint(double x, double y) {
      final normalizedX = (x / imageSize.width).clamp(0.0, 1.0);
      final normalizedY = (y / imageSize.height).clamp(0.0, 1.0);
      final mirroredPoint =
          mirrorHorizontally
              ? Offset(1.0 - normalizedX, normalizedY)
              : Offset(normalizedX, normalizedY);
      final displayPoint = _rotateNormalizedPoint(mirroredPoint);

      return Offset(
        displayPoint.dx * size.width,
        displayPoint.dy * size.height,
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

  /// Rotates a normalized point to match the preview orientation.
  Offset _rotateNormalizedPoint(Offset point) {
    switch (previewQuarterTurns % 4) {
      case 1:
        return Offset(1 - point.dy, point.dx);
      case 2:
        return Offset(1 - point.dx, 1 - point.dy);
      case 3:
        return Offset(point.dy, 1 - point.dx);
      default:
        return point;
    }
  }

  /// Draws the landmark index next to a landmark point.
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
  /// Repaints when landmarks, image size, mirroring, or rotation changes.
  bool shouldRepaint(covariant HandLandmarkOverlayPainter oldDelegate) {
    return oldDelegate.hands != hands ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns;
  }
}
