import '../models/app_object_detection.dart';

/// Handles throttled, single-flight object detection requests with a cache.
class ObjectDetectionRequestController {
  ObjectDetectionRequestController({required this.minInterval});

  final Duration minInterval;

  DateTime? _lastSubmittedAt;
  Future<List<AppObjectDetection>>? _pendingRequest;
  List<AppObjectDetection> _cachedDetections = const [];

  bool get isBusy => _pendingRequest != null;

  Future<List<AppObjectDetection>>? get pendingRequest => _pendingRequest;

  List<AppObjectDetection> get cachedDetections => _cachedDetections;

  /// Starts a request when allowed and always returns the latest cached result.
  List<AppObjectDetection> detectOrReuse({
    required DateTime now,
    required bool detectorBusy,
    required Future<List<AppObjectDetection>> Function() detect,
  }) {
    submit(now: now, detectorBusy: detectorBusy, detect: detect);
    return _cachedDetections;
  }

  /// Starts a request when the detector is idle and the throttle window ended.
  Future<List<AppObjectDetection>>? submit({
    required DateTime now,
    required bool detectorBusy,
    required Future<List<AppObjectDetection>> Function() detect,
    Duration? minIntervalOverride,
  }) {
    if (!_canSubmit(
      now: now,
      detectorBusy: detectorBusy,
      minIntervalOverride: minIntervalOverride,
    )) {
      return null;
    }

    final request = detect();
    _lastSubmittedAt = now;
    _pendingRequest = request;

    request
        .then((detections) {
          if (!identical(_pendingRequest, request)) return;
          _cachedDetections = detections;
        }, onError: (_, _) {})
        .whenComplete(() {
          if (identical(_pendingRequest, request)) {
            _pendingRequest = null;
          }
        });

    return request;
  }

  void clear() {
    _lastSubmittedAt = null;
    _pendingRequest = null;
    _cachedDetections = const [];
  }

  bool _canSubmit({
    required DateTime now,
    required bool detectorBusy,
    Duration? minIntervalOverride,
  }) {
    if (detectorBusy || isBusy) return false;

    final lastSubmittedAt = _lastSubmittedAt;
    if (lastSubmittedAt == null) return true;

    return now.difference(lastSubmittedAt) >=
        (minIntervalOverride ?? minInterval);
  }
}
