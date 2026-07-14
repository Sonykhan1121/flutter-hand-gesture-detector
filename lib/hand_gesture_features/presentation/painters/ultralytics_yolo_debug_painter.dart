import 'package:flutter/material.dart';

import 'object_detection_debug_painter.dart';

/// Debug overlay owned by the `ultralytics_yolo` package backend.
final class UltralyticsYoloDebugPainter extends ObjectDetectionDebugPainter {
  const UltralyticsYoloDebugPainter({
    required super.targets,
    super.showLabels,
    Color? color,
    super.labelPrefix,
    super.previewQuarterTurns,
  }) : super(color: color ?? const Color(0xFF00FB46));

  @override
  void paint(Canvas canvas, Size size) => paintObjectTargets(canvas, size);

  @override
  bool shouldRepaint(covariant UltralyticsYoloDebugPainter oldDelegate) =>
      hasVisualChanges(oldDelegate);
}
