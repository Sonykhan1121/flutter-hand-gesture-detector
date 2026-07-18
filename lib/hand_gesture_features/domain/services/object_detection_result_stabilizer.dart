import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';

/// Prevents one or two empty detector cycles from erasing visible boxes.
///
/// A rejected empty result does not become a new detection cycle. This keeps
/// optical flow aligned to the last real detector frame instead of presenting
/// an old box as if it came from the current camera frame.
class ObjectDetectionResultStabilizer {
  ObjectDetectionResultStabilizer({
    required this.emptyResultHoldDuration,
    required this.emptyResultMissLimit,
  }) : assert(emptyResultMissLimit > 0);

  factory ObjectDetectionResultStabilizer.forBackend(
    ObjectDetectionBackend backend,
  ) {
    final isNative = backend == ObjectDetectionBackend.nativeMethodChannel;
    final isPackage = backend == ObjectDetectionBackend.objectDetectionPackage;
    final isUltralytics = backend == ObjectDetectionBackend.ultralyticsYolo;
    final isGoogleMlKit = backend == ObjectDetectionBackend.googleMlKit;
    final isOpenCv = backend == ObjectDetectionBackend.opencvSdk;
    return ObjectDetectionResultStabilizer(
      emptyResultHoldDuration: isOpenCv
          ? HandGestureThresholds.opencvSdkEmptyResultHoldDuration
          : isNative
          ? HandGestureThresholds.nativeMethodChannelEmptyResultHoldDuration
          : isPackage
          ? HandGestureThresholds.objectDetectionPackageEmptyResultHoldDuration
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloEmptyResultHoldDuration
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitEmptyResultHoldDuration
          : Duration.zero,
      emptyResultMissLimit: isOpenCv
          ? HandGestureThresholds.opencvSdkEmptyResultMissLimit
          : isNative
          ? HandGestureThresholds.nativeMethodChannelEmptyResultMissLimit
          : isPackage
          ? HandGestureThresholds.objectDetectionPackageEmptyResultMissLimit
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloEmptyResultMissLimit
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitEmptyResultMissLimit
          : 1,
    );
  }

  final Duration emptyResultHoldDuration;
  final int emptyResultMissLimit;

  DateTime? _lastNonEmptyResultAt;
  int _consecutiveEmptyResults = 0;

  /// Returns true when the UI/cache should replace its current detections.
  bool shouldReplace({
    required bool hasDetections,
    required DateTime completedAt,
  }) {
    if (hasDetections) {
      _lastNonEmptyResultAt = completedAt;
      _consecutiveEmptyResults = 0;
      return true;
    }

    final lastNonEmptyResultAt = _lastNonEmptyResultAt;
    if (lastNonEmptyResultAt == null ||
        emptyResultHoldDuration <= Duration.zero ||
        emptyResultMissLimit <= 1) {
      _finishEmptyRun();
      return true;
    }

    _consecutiveEmptyResults++;
    final holdExpired =
        completedAt.difference(lastNonEmptyResultAt) > emptyResultHoldDuration;
    if (_consecutiveEmptyResults >= emptyResultMissLimit || holdExpired) {
      _finishEmptyRun();
      return true;
    }

    return false;
  }

  void clear() {
    _lastNonEmptyResultAt = null;
    _consecutiveEmptyResults = 0;
  }

  void _finishEmptyRun() {
    _lastNonEmptyResultAt = null;
    _consecutiveEmptyResults = 0;
  }
}
