import 'package:flutter/material.dart';

import 'object_detection_debug_painter.dart';

/// Debug overlay owned by the Google ML Kit object-detection backend.
final class GoogleMlKitObjectDebugPainter extends ObjectDetectionDebugPainter {
  const GoogleMlKitObjectDebugPainter({
    required super.targets,
    super.showLabels,
    Color? color,
    super.labelPrefix,
    super.previewQuarterTurns,
  }) : super(color: color ?? const Color(0xFF29B6F6));

  @override
  void paint(Canvas canvas, Size size) => paintObjectTargets(canvas, size);

  @override
  bool shouldRepaint(covariant GoogleMlKitObjectDebugPainter oldDelegate) =>
      hasVisualChanges(oldDelegate);
}
