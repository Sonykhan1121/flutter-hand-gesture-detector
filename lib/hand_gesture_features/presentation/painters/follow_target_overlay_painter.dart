import 'package:flutter/material.dart';

import '../../domain/enums/follow_target_type.dart';
import '../../domain/models/follow_target.dart';
import '../../domain/utils/camera_preview_geometry.dart';

/// Painter for the locked face/object follow target highlight.
class FollowTargetOverlayPainter extends CustomPainter {
  const FollowTargetOverlayPainter({
    required this.target,
    this.previewQuarterTurns = 0,
  });

  final FollowTarget target;
  final int previewQuarterTurns;

  @override
  /// Dims the rest of the preview and highlights the selected target box.
  void paint(Canvas canvas, Size size) {
    final targetRect = _displayRect(size);
    if (targetRect.isEmpty) return;

    final overlayPath =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRRect(
            RRect.fromRectAndRadius(targetRect, const Radius.circular(14)),
          );

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );

    final color =
        target.type == FollowTargetType.face
            ? const Color(0xFF46D8FF)
            : const Color(0xFF00FB46);

    final glowPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.20);

    final borderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = color;

    final cornerPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..color = Colors.white;

    final rrect = RRect.fromRectAndRadius(
      targetRect,
      const Radius.circular(14),
    );

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, borderPaint);
    _drawCorners(canvas, targetRect, cornerPaint);
  }

  /// Converts the normalized target box into canvas coordinates.
  Rect _displayRect(Size size) {
    return normalizedDisplayRectToCanvasRect(
      target.displayBox,
      size,
      previewQuarterTurns: previewQuarterTurns,
    );
  }

  /// Draws bright corner guides on top of the target rectangle.
  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    final cornerLength = (rect.shortestSide * 0.18).clamp(12.0, 30.0);

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
  /// Repaints when the selected target changes.
  bool shouldRepaint(covariant FollowTargetOverlayPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns;
  }
}
