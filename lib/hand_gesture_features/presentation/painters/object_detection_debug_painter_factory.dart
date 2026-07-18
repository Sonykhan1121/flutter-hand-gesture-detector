import 'package:flutter/material.dart';

import '../../domain/enums/object_detection_backend.dart';
import '../../domain/models/follow_target.dart';
import 'object_detection_debug_painter.dart';

/// Creates the shared debug painter with the selected backend's color.
abstract final class ObjectDetectionDebugPainterFactory {
  static ObjectDetectionDebugPainter create({
    required ObjectDetectionBackend backend,
    required List<FollowTarget> targets,
    bool showLabels = true,
    Color? color,
    String labelPrefix = '',
    int previewQuarterTurns = 0,
  }) {
    return ObjectDetectionDebugPainter(
      targets: targets,
      showLabels: showLabels,
      color: color ?? _defaultColor(backend),
      labelPrefix: labelPrefix,
      previewQuarterTurns: previewQuarterTurns,
    );
  }

  static Color _defaultColor(ObjectDetectionBackend backend) {
    return switch (backend) {
      ObjectDetectionBackend.objectDetectionPackage ||
      ObjectDetectionBackend.nativeMethodChannel => const Color(0xFFFFA726),
      ObjectDetectionBackend.ultralyticsYolo => const Color(0xFF00FB46),
      ObjectDetectionBackend.googleMlKit => const Color(0xFF29B6F6),
      ObjectDetectionBackend.opencvSdk => const Color(0xFF00A3A3),
    };
  }
}
