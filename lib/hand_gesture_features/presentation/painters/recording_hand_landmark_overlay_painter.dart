import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

class RecordingHandLandmarkOverlayPainter extends CustomPainter {
  const RecordingHandLandmarkOverlayPainter({
    required this.hands,
    required this.imageSize,
    required this.mirrorHorizontally,
    this.recordingQuarterTurns = 3,
    this.showLandmarkIndices = false,
  });

  final List<Hand> hands;
  final Size imageSize;
  final bool mirrorHorizontally;
  final int recordingQuarterTurns;
  final bool showLandmarkIndices;

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

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

    final effectiveQuarterTurns = _bestQuarterTurnsForCanvas(size);
    final sourceSize = _sourceSizeForTurns(effectiveQuarterTurns);
    final pointRadius = (size.shortestSide * 0.012).clamp(4.5, 6.5);

    Offset mapPoint(double x, double y) {
      final normalizedPoint = Offset(
        (x / imageSize.width).clamp(0.0, 1.0),
        (y / imageSize.height).clamp(0.0, 1.0),
      );

      final rotatedPoint = _rotateNormalizedPoint(
        normalizedPoint,
        effectiveQuarterTurns,
      );

      final displayPoint =
          mirrorHorizontally
              ? Offset(1.0 - rotatedPoint.dx, rotatedPoint.dy)
              : rotatedPoint;

      return _mapCoverPoint(
        normalizedPoint: displayPoint,
        sourceSize: sourceSize,
        canvasSize: size,
      );
    }

    for (final hand in hands) {
      if (!hand.hasLandmarks) continue;

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
        canvas.drawCircle(center, pointRadius, pointPaint);
        canvas.drawCircle(center, pointRadius, pointBorderPaint);

        if (showLandmarkIndices) {
          _drawLandmarkIndex(canvas, '${landmark.type.index}', center);
        }
      }
    }

    canvas.restore();
  }

  int _bestQuarterTurnsForCanvas(Size canvasSize) {
    final requestedTurns = recordingQuarterTurns % 4;
    final normalDiff = _aspectDiff(imageSize, canvasSize);
    final rotatedDiff = _aspectDiff(
      _sourceSizeForTurns(requestedTurns),
      canvasSize,
    );

    return rotatedDiff < normalDiff ? requestedTurns : 0;
  }

  double _aspectDiff(Size sourceSize, Size canvasSize) {
    if (sourceSize.width <= 0 ||
        sourceSize.height <= 0 ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return double.infinity;
    }

    return ((sourceSize.width / sourceSize.height) -
            (canvasSize.width / canvasSize.height))
        .abs();
  }

  Size _sourceSizeForTurns(int quarterTurns) {
    final normalizedTurns = quarterTurns % 4;
    return normalizedTurns.isOdd
        ? Size(imageSize.height, imageSize.width)
        : imageSize;
  }

  Offset _rotateNormalizedPoint(Offset point, int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return Offset(1.0 - point.dy, point.dx);
      case 2:
        return Offset(1.0 - point.dx, 1.0 - point.dy);
      case 3:
        return Offset(point.dy, 1.0 - point.dx);
      default:
        return point;
    }
  }

  Offset _mapCoverPoint({
    required Offset normalizedPoint,
    required Size sourceSize,
    required Size canvasSize,
  }) {
    final scaleX = canvasSize.width / sourceSize.width;
    final scaleY = canvasSize.height / sourceSize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final fittedWidth = sourceSize.width * scale;
    final fittedHeight = sourceSize.height * scale;
    final offsetX = (canvasSize.width - fittedWidth) / 2;
    final offsetY = (canvasSize.height - fittedHeight) / 2;

    return Offset(
      offsetX + normalizedPoint.dx * sourceSize.width * scale,
      offsetY + normalizedPoint.dy * sourceSize.height * scale,
    );
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
  bool shouldRepaint(
    covariant RecordingHandLandmarkOverlayPainter oldDelegate,
  ) {
    return oldDelegate.hands != hands ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.recordingQuarterTurns != recordingQuarterTurns ||
        oldDelegate.showLandmarkIndices != showLandmarkIndices;
  }
}
