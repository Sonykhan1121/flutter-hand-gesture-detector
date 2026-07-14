import 'package:flutter/material.dart';

import '../../domain/enums/object_detection_backend.dart';
import '../../domain/models/follow_target.dart';
import 'google_mlkit_object_debug_painter.dart';
import 'object_detection_debug_painter.dart';
import 'object_detection_package_debug_painter.dart';
import 'ultralytics_yolo_debug_painter.dart';

/// Routes raw object results to the painter owned by the selected package.
abstract final class ObjectDetectionDebugPainterFactory {
  static ObjectDetectionDebugPainter create({
    required ObjectDetectionBackend backend,
    required List<FollowTarget> targets,
    bool showLabels = true,
    Color? color,
    String labelPrefix = '',
    int previewQuarterTurns = 0,
  }) {
    return switch (backend) {
      ObjectDetectionBackend.objectDetectionPackage =>
        ObjectDetectionPackageDebugPainter(
          targets: targets,
          showLabels: showLabels,
          color: color,
          labelPrefix: labelPrefix,
          previewQuarterTurns: previewQuarterTurns,
        ),
      ObjectDetectionBackend.ultralyticsYolo => UltralyticsYoloDebugPainter(
        targets: targets,
        showLabels: showLabels,
        color: color,
        labelPrefix: labelPrefix,
        previewQuarterTurns: previewQuarterTurns,
      ),
      ObjectDetectionBackend.googleMlKit => GoogleMlKitObjectDebugPainter(
        targets: targets,
        showLabels: showLabels,
        color: color,
        labelPrefix: labelPrefix,
        previewQuarterTurns: previewQuarterTurns,
      ),
    };
  }
}
