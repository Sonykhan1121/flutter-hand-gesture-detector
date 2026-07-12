import 'package:flutter/material.dart';

import '../../domain/models/follow_target.dart';
import '../../domain/utils/camera_preview_geometry.dart';

/// Debug painter that draws all face/object candidates on the preview.
class FollowTargetDebugOverlayPainter extends CustomPainter {
  const FollowTargetDebugOverlayPainter({
    required this.targets,
    this.showLabels = true,
    this.color = Colors.red,
    this.labelPrefix = '',
    this.previewQuarterTurns = 0,
  });

  final List<FollowTarget> targets;
  final bool showLabels;
  final Color color;
  final String labelPrefix;
  final int previewQuarterTurns;

  @override
  /// Paints red boxes and labels for each detected follow candidate.
  void paint(Canvas canvas, Size size) {
    if (targets.isEmpty) return;

    final borderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color;

    final labelBackgroundPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.black.withValues(alpha: 0.62);

    for (final target in targets) {
      final rect = _displayRect(target, size);
      if (rect.isEmpty) continue;

      canvas.drawRect(rect, borderPaint);
      if (showLabels) {
        _drawLabel(
          canvas: canvas,
          size: size,
          rect: rect,
          label: '$labelPrefix${target.displayLabel}',
          backgroundPaint: labelBackgroundPaint,
        );
      }
    }
  }

  /// Converts a normalized target display box into canvas coordinates.
  Rect _displayRect(FollowTarget target, Size size) {
    return normalizedDisplayRectToCanvasRect(
      target.displayBox,
      size,
      previewQuarterTurns: previewQuarterTurns,
    );
  }

  /// Draws a clamped label near the target box.
  void _drawLabel({
    required Canvas canvas,
    required Size size,
    required Rect rect,
    required String label,
    required Paint backgroundPaint,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (size.width - 8).clamp(0.0, size.width).toDouble());

    const padding = EdgeInsets.symmetric(horizontal: 5, vertical: 3);
    final labelSize = Size(
      textPainter.width + padding.horizontal,
      textPainter.height + padding.vertical,
    );
    final maxLabelLeft = (size.width - labelSize.width).clamp(0.0, size.width);
    final labelLeft = rect.left.clamp(0.0, maxLabelLeft).toDouble();
    final preferredTop = rect.top - labelSize.height - 2;
    final maxLabelTop = (size.height - labelSize.height).clamp(
      0.0,
      size.height,
    );
    final labelTop =
        preferredTop >= 0
            ? preferredTop
            : (rect.top + 2).clamp(0.0, maxLabelTop).toDouble();
    final labelRect = Offset(labelLeft, labelTop) & labelSize;

    canvas.drawRect(labelRect, backgroundPaint);
    textPainter.paint(
      canvas,
      labelRect.topLeft + Offset(padding.left, padding.top),
    );
  }

  @override
  /// Repaints when the target list reference changes.
  bool shouldRepaint(covariant FollowTargetDebugOverlayPainter oldDelegate) {
    return oldDelegate.targets != targets ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.color != color ||
        oldDelegate.labelPrefix != labelPrefix ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns;
  }
}
