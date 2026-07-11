import 'app_object_detection.dart';

/// Object detections tied to the camera frame that produced them.
class ObjectDetectionBatch {
  const ObjectDetectionBatch({
    required this.detections,
    required this.sourceFrameId,
    required this.sourceCapturedAt,
    required this.completedAt,
  });

  final List<AppObjectDetection> detections;
  final int sourceFrameId;
  final DateTime sourceCapturedAt;
  final DateTime completedAt;
}
