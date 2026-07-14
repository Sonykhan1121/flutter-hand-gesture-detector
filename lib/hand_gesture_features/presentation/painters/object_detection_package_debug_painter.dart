import 'package:flutter/material.dart';

import 'object_detection_debug_painter.dart';

/// Debug overlay owned by the `object_detection` package backend.
final class ObjectDetectionPackageDebugPainter
    extends ObjectDetectionDebugPainter {
  const ObjectDetectionPackageDebugPainter({
    required super.targets,
    super.showLabels,
    Color? color,
    super.labelPrefix,
    super.previewQuarterTurns,
  }) : super(color: color ?? const Color(0xFFFFA726));

  @override
  void paint(Canvas canvas, Size size) => paintObjectTargets(canvas, size);

  @override
  bool shouldRepaint(
    covariant ObjectDetectionPackageDebugPainter oldDelegate,
  ) => hasVisualChanges(oldDelegate);
}
