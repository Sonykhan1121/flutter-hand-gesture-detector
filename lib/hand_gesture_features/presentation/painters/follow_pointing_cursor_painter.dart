import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/utils/camera_preview_geometry.dart';

/// Draws the real fingertip, projected Point 8, and 500ms dwell progress.
class FollowPointingCursorPainter extends CustomPainter {
  const FollowPointingCursorPainter({
    required this.realIndexTip,
    required this.projectedPoint,
    required this.progress,
    required this.isInFrame,
    this.previewQuarterTurns = 0,
  });

  final Offset realIndexTip;
  final Offset projectedPoint;
  final double progress;
  final bool isInFrame;
  final int previewQuarterTurns;

  @override
  void paint(Canvas canvas, Size size) {
    if (!_isFinite(realIndexTip) ||
        !_isFinite(projectedPoint) ||
        size.isEmpty) {
      return;
    }
    final rotatedRealTip = rotateNormalizedDisplayPoint(
      realIndexTip,
      previewQuarterTurns,
    );
    final rotatedProjectedPoint = rotateNormalizedDisplayPoint(
      projectedPoint,
      previewQuarterTurns,
    );
    final realCenter = Offset(
      rotatedRealTip.dx * size.width,
      rotatedRealTip.dy * size.height,
    );
    final center = Offset(
      rotatedProjectedPoint.dx * size.width,
      rotatedProjectedPoint.dy * size.height,
    );
    final boundedProgress = progress.clamp(0.0, 1.0);
    final cursorColor = isInFrame
        ? const Color(0xFFFFB020)
        : const Color(0xFFFF233A);

    canvas.drawLine(
      realCenter,
      center,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = cursorColor.withValues(alpha: 0.65),
    );
    canvas.drawCircle(
      realCenter,
      3.5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    canvas.drawCircle(
      center,
      8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = cursorColor,
    );
    if (isInFrame) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 13),
        -math.pi / 2,
        math.pi * 2 * boundedProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = boundedProgress >= 1
              ? const Color(0xFF00FB46)
              : Colors.white,
      );
    } else {
      canvas.drawCircle(
        center,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = cursorColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FollowPointingCursorPainter oldDelegate) {
    return oldDelegate.realIndexTip != realIndexTip ||
        oldDelegate.projectedPoint != projectedPoint ||
        oldDelegate.progress != progress ||
        oldDelegate.isInFrame != isInFrame ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns;
  }

  bool _isFinite(Offset point) => point.dx.isFinite && point.dy.isFinite;
}
