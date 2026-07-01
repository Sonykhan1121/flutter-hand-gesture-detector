import 'package:flutter/material.dart';

class HandFocusOverlayPainter extends CustomPainter {
  const HandFocusOverlayPainter({
    required this.handBox,
    required this.imageSize,
    required this.mirrorHorizontally,
    this.previewQuarterTurns = 0,
  });

  final Rect handBox;
  final Size imageSize;
  final bool mirrorHorizontally;
  final int previewQuarterTurns;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0 || handBox.isEmpty) {
      return;
    }

    final focusRect = _tightenRect(_mapRect(handBox, size));
    final boundedFocusRect = Rect.fromLTRB(
      focusRect.left.clamp(0, size.width),
      focusRect.top.clamp(0, size.height),
      focusRect.right.clamp(0, size.width),
      focusRect.bottom.clamp(0, size.height),
    );

    if (boundedFocusRect.isEmpty) return;

    final overlayPath =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRRect(
            RRect.fromRectAndRadius(
              boundedFocusRect,
              const Radius.circular(14),
            ),
          );

    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.42);
    canvas.drawPath(overlayPath, dimPaint);

    final glowPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF00FB46).withValues(alpha: 0.18);

    final borderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF00FB46);

    final cornerPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white;

    final rrect = RRect.fromRectAndRadius(
      boundedFocusRect,
      const Radius.circular(14),
    );

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, borderPaint);
    _drawCorners(canvas, boundedFocusRect, cornerPaint);
  }

  Rect _tightenRect(Rect rect) {
    final insetX = rect.width * 0.18;
    final insetY = rect.height * 0.14;
    final tightenedRect = rect.deflate(insetX < insetY ? insetX : insetY);
    final padding = (tightenedRect.shortestSide * 0.04).clamp(3.0, 8.0);

    return tightenedRect.inflate(padding);
  }

  Rect _mapRect(Rect rect, Size canvasSize) {
    final topLeft = _mapPoint(rect.left, rect.top, canvasSize);
    final bottomRight = _mapPoint(rect.right, rect.bottom, canvasSize);

    return Rect.fromLTRB(
      topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx,
      topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy,
      topLeft.dx > bottomRight.dx ? topLeft.dx : bottomRight.dx,
      topLeft.dy > bottomRight.dy ? topLeft.dy : bottomRight.dy,
    );
  }

  Offset _mapPoint(double x, double y, Size canvasSize) {
    final normalizedX = (x / imageSize.width).clamp(0.0, 1.0);
    final normalizedY = (y / imageSize.height).clamp(0.0, 1.0);
    final rotatedPoint = _rotateNormalizedPoint(
      Offset(normalizedX, normalizedY),
    );
    final displayPoint =
        mirrorHorizontally
            ? Offset(1.0 - rotatedPoint.dx, rotatedPoint.dy)
            : rotatedPoint;

    return Offset(
      displayPoint.dx * canvasSize.width,
      displayPoint.dy * canvasSize.height,
    );
  }

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

  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    final cornerLength = (rect.shortestSide * 0.18).clamp(12.0, 28.0);

    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, cornerLength),
      paint,
    );

    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      paint,
    );

    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLength),
      paint,
    );

    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant HandFocusOverlayPainter oldDelegate) {
    return oldDelegate.handBox != handBox ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns;
  }
}
