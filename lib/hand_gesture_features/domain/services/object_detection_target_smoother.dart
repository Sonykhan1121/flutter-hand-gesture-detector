import 'dart:math' as math;
import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import '../models/follow_target.dart';

/// Smooths only display boxes while retaining raw detector metadata.
///
/// Detector-space boxes remain untouched so source-frame optical-flow
/// correction can continue to use the exact inference result.
class ObjectDetectionTargetSmoother {
  ObjectDetectionTargetSmoother({
    required this.enabled,
    required this.alpha,
    required this.fastAlpha,
    required this.fastMotionThreshold,
    required this.maxCenterDistance,
    required this.partialTrackHoldDuration,
    required this.partialTrackMissLimit,
  });

  factory ObjectDetectionTargetSmoother.forBackend(
    ObjectDetectionBackend backend,
  ) {
    final isPackage = backend == ObjectDetectionBackend.objectDetectionPackage;
    final isUltralytics = backend == ObjectDetectionBackend.ultralyticsYolo;
    final isGoogleMlKit = backend == ObjectDetectionBackend.googleMlKit;
    final isNative = backend == ObjectDetectionBackend.nativeMethodChannel;
    final isOpenCv = backend == ObjectDetectionBackend.opencvSdk;
    return ObjectDetectionTargetSmoother(
      enabled:
          isPackage || isUltralytics || isGoogleMlKit || isNative || isOpenCv,
      alpha: isOpenCv
          ? HandGestureThresholds.opencvSdkBoxSmoothingAlpha
          : isNative
          ? HandGestureThresholds.nativeMethodChannelBoxSmoothingAlpha
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitBoxSmoothingAlpha
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloBoxSmoothingAlpha
          : HandGestureThresholds.objectDetectionPackageBoxSmoothingAlpha,
      fastAlpha: isOpenCv
          ? HandGestureThresholds.opencvSdkFastBoxSmoothingAlpha
          : isNative
          ? HandGestureThresholds.nativeMethodChannelFastBoxSmoothingAlpha
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitFastBoxSmoothingAlpha
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloFastBoxSmoothingAlpha
          : HandGestureThresholds.objectDetectionPackageFastBoxSmoothingAlpha,
      fastMotionThreshold: isOpenCv
          ? HandGestureThresholds.opencvSdkFastMotionThreshold
          : isNative
          ? HandGestureThresholds.nativeMethodChannelFastMotionThreshold
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitFastMotionThreshold
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloFastMotionThreshold
          : HandGestureThresholds.objectDetectionPackageFastMotionThreshold,
      maxCenterDistance: isOpenCv
          ? HandGestureThresholds.opencvSdkTrackMaxCenterDistance
          : isNative
          ? HandGestureThresholds.nativeMethodChannelTrackMaxCenterDistance
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitTrackMaxCenterDistance
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloTrackMaxCenterDistance
          : HandGestureThresholds.objectDetectionPackageTrackMaxCenterDistance,
      partialTrackHoldDuration: isOpenCv
          ? HandGestureThresholds.opencvSdkPartialTrackHoldDuration
          : isNative
          ? HandGestureThresholds.nativeMethodChannelPartialTrackHoldDuration
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitPartialTrackHoldDuration
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloPartialTrackHoldDuration
          : HandGestureThresholds
                .objectDetectionPackagePartialTrackHoldDuration,
      partialTrackMissLimit: isOpenCv
          ? HandGestureThresholds.opencvSdkPartialTrackMissLimit
          : isNative
          ? HandGestureThresholds.nativeMethodChannelPartialTrackMissLimit
          : isGoogleMlKit
          ? HandGestureThresholds.googleMlKitPartialTrackMissLimit
          : isUltralytics
          ? HandGestureThresholds.ultralyticsYoloPartialTrackMissLimit
          : HandGestureThresholds.objectDetectionPackagePartialTrackMissLimit,
    );
  }

  final bool enabled;
  final double alpha;
  final double fastAlpha;
  final double fastMotionThreshold;
  final double maxCenterDistance;
  final Duration partialTrackHoldDuration;
  final int partialTrackMissLimit;

  final List<_VisualTrack> _tracks = [];

  List<FollowTarget> update(
    List<FollowTarget> detections, {
    required DateTime completedAt,
  }) {
    if (!enabled) return detections;
    if (detections.isEmpty) {
      clear();
      return const [];
    }

    final candidates = <_MatchCandidate>[];
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      final track = _tracks[trackIndex];
      for (
        var detectionIndex = 0;
        detectionIndex < detections.length;
        detectionIndex++
      ) {
        final detection = detections[detectionIndex];
        if (!_sameIdentity(track.target, detection)) continue;
        final distance = _centerDistance(
          track.target.displayBox,
          detection.displayBox,
        );
        if (distance > maxCenterDistance) continue;
        candidates.add(
          _MatchCandidate(
            trackIndex: trackIndex,
            detectionIndex: detectionIndex,
            overlap: _intersectionOverUnion(
              track.target.displayBox,
              detection.displayBox,
            ),
            centerDistance: distance,
          ),
        );
      }
    }
    candidates.sort((a, b) {
      final overlapOrder = b.overlap.compareTo(a.overlap);
      return overlapOrder != 0
          ? overlapOrder
          : a.centerDistance.compareTo(b.centerDistance);
    });

    final matchedTracks = <int>{};
    final matchedDetections = <int>{};
    final nextTracks = <_VisualTrack>[];
    final outputByDetection = <int, FollowTarget>{};

    for (final candidate in candidates) {
      if (matchedTracks.contains(candidate.trackIndex) ||
          matchedDetections.contains(candidate.detectionIndex)) {
        continue;
      }
      matchedTracks.add(candidate.trackIndex);
      matchedDetections.add(candidate.detectionIndex);
      final previous = _tracks[candidate.trackIndex];
      final current = detections[candidate.detectionIndex];
      final smoothingAlpha = candidate.centerDistance > fastMotionThreshold
          ? fastAlpha
          : alpha;
      final smoothed = _copyWithDisplayBox(
        current,
        _lerpRect(
          previous.target.displayBox,
          current.displayBox,
          smoothingAlpha,
        ),
      );
      outputByDetection[candidate.detectionIndex] = smoothed;
      nextTracks.add(
        _VisualTrack(target: smoothed, lastSeenAt: completedAt, misses: 0),
      );
    }

    for (var index = 0; index < detections.length; index++) {
      if (matchedDetections.contains(index)) continue;
      final detection = detections[index];
      outputByDetection[index] = detection;
      nextTracks.add(
        _VisualTrack(target: detection, lastSeenAt: completedAt, misses: 0),
      );
    }

    for (var index = 0; index < _tracks.length; index++) {
      if (matchedTracks.contains(index)) continue;
      final track = _tracks[index];
      final misses = track.misses + 1;
      final expired =
          completedAt.difference(track.lastSeenAt) > partialTrackHoldDuration;
      if (misses >= partialTrackMissLimit || expired) continue;
      nextTracks.add(track.copyWith(misses: misses));
    }

    _tracks
      ..clear()
      ..addAll(nextTracks);

    return [
      for (var index = 0; index < detections.length; index++)
        outputByDetection[index]!,
      for (final track in nextTracks)
        if (!outputByDetection.containsValue(track.target)) track.target,
    ];
  }

  void clear() => _tracks.clear();

  bool _sameIdentity(FollowTarget a, FollowTarget b) {
    if (a.trackingId != null && b.trackingId != null) {
      return a.trackingId == b.trackingId;
    }
    if (a.classIndex != null && b.classIndex != null) {
      return a.classIndex == b.classIndex;
    }
    return a.displayLabel.trim().toLowerCase() ==
        b.displayLabel.trim().toLowerCase();
  }

  FollowTarget _copyWithDisplayBox(FollowTarget target, Rect displayBox) {
    return FollowTarget(
      type: target.type,
      boundingBox: target.boundingBox,
      displayBox: displayBox,
      detectedAt: target.detectedAt,
      trackingId: target.trackingId,
      label: target.label,
      classIndex: target.classIndex,
      appearanceSignature: target.appearanceSignature,
      sourceFrameId: target.sourceFrameId,
    );
  }

  Rect _lerpRect(Rect previous, Rect current, double amount) {
    return Rect.fromLTRB(
      _lerp(previous.left, current.left, amount),
      _lerp(previous.top, current.top, amount),
      _lerp(previous.right, current.right, amount),
      _lerp(previous.bottom, current.bottom, amount),
    );
  }

  double _lerp(double previous, double current, double amount) =>
      previous + (current - previous) * amount;

  double _centerDistance(Rect a, Rect b) {
    final dx = a.center.dx - b.center.dx;
    final dy = a.center.dy - b.center.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        a.width * a.height + b.width * b.height - intersectionArea;
    return unionArea > 0 ? intersectionArea / unionArea : 0;
  }
}

class _VisualTrack {
  const _VisualTrack({
    required this.target,
    required this.lastSeenAt,
    required this.misses,
  });

  final FollowTarget target;
  final DateTime lastSeenAt;
  final int misses;

  _VisualTrack copyWith({required int misses}) =>
      _VisualTrack(target: target, lastSeenAt: lastSeenAt, misses: misses);
}

class _MatchCandidate {
  const _MatchCandidate({
    required this.trackIndex,
    required this.detectionIndex,
    required this.overlap,
    required this.centerDistance,
  });

  final int trackIndex;
  final int detectionIndex;
  final double overlap;
  final double centerDistance;
}
