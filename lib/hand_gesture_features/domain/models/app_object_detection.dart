import 'dart:ui';

import 'package:object_detection/object_detection.dart' as od;

enum AppObjectDetectionSource {
  objectDetectionPackage,
  ultralyticsYolo,
  googleMlKit,
}

/// One object candidate returned by the app's object detector.
class AppObjectDetection {
  const AppObjectDetection({
    required this.boundingBox,
    required this.imageSize,
    required this.label,
    required this.confidence,
    required this.classIndex,
    this.trackingId,
    this.source = AppObjectDetectionSource.objectDetectionPackage,
  });

  /// Bounding box in [imageSize] pixel coordinates.
  final Rect boundingBox;
  final Size imageSize;
  final String label;

  /// Detection/classification confidence when the backend exposes one.
  ///
  /// ML Kit's base detector does not expose a box confidence. It is therefore
  /// null when no classified label is returned instead of being fabricated.
  final double? confidence;
  final int classIndex;
  final int? trackingId;
  final AppObjectDetectionSource source;

  bool get isPerson => isPersonLabel(label);

  /// Person candidates are owned exclusively by ML Kit face detection.
  static bool isPersonLabel(String label) =>
      label.trim().toLowerCase() == 'person';

  factory AppObjectDetection.fromDetectedObject(od.DetectedObject object) {
    final box = object.boundingBox;
    return AppObjectDetection(
      boundingBox: Rect.fromLTRB(
        box.topLeft.x,
        box.topLeft.y,
        box.bottomRight.x,
        box.bottomRight.y,
      ),
      imageSize: object.originalSize,
      label: object.categoryName,
      confidence: object.score,
      classIndex: object.category.index,
      source: AppObjectDetectionSource.objectDetectionPackage,
    );
  }
}
