import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/zoom_direction.dart';
import 'hand_geometry_service.dart';

/// Detects static angle-based zoom-in and closed-pinch zoom-out holds.
class ZoomGestureDetector {
  ZoomGestureDetector({
    this.geometry = const HandGeometryService(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HandGeometryService geometry;
  final DateTime Function() _now;

  static const double _angleComparisonEpsilon = 1e-9;
  static const double _distanceComparisonEpsilon = 1e-9;

  ZoomDirection _pendingDirection = ZoomDirection.none;
  DateTime? _holdStartedAt;
  HandPoint3D? _startPalmCenter;
  double? _startHandSize;
  Map<HandLandmarkType, HandPoint3D>? _startStableFingerOffsets;

  static const List<HandLandmarkType> _stableFingerTypes = [
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  /// True from the first valid hold frame until the pose is lost or blocked.
  bool get isGestureActive => _pendingDirection != ZoomDirection.none;

  /// Direction currently accumulating its one-second hold.
  ZoomDirection get pendingDirection => _pendingDirection;

  /// Returns a direction continuously after its static pose is held for 1s.
  ZoomDirection detect({required Hand hand, required Size imageSize}) {
    if (!geometry.isReliableHand(hand) || !_isFiniteImageSize(imageSize)) {
      clearState();
      return ZoomDirection.none;
    }

    final pose = _staticZoomPose(hand);
    if (pose == null) {
      clearState();
      return ZoomDirection.none;
    }

    final now = _now();
    final startedAt = _holdStartedAt;
    if (_pendingDirection != pose.direction ||
        startedAt == null ||
        now.isBefore(startedAt)) {
      _startHold(pose, now);
      return ZoomDirection.none;
    }

    if (!_isPalmStable(pose) ||
        !_areStableFingersStable(
          currentStableFingerOffsets: pose.stableFingerOffsets,
          currentHandSize: pose.handSize,
        )) {
      _startHold(pose, now);
      return ZoomDirection.none;
    }

    if (now.difference(startedAt) <
        HandGestureThresholds.zoomStaticHoldDuration) {
      return ZoomDirection.none;
    }

    return pose.direction;
  }

  /// Clears the active pose and requires a fresh one-second hold.
  void clearState() {
    _pendingDirection = ZoomDirection.none;
    _holdStartedAt = null;
    _startPalmCenter = null;
    _startHandSize = null;
    _startStableFingerOffsets = null;
  }

  bool _isFiniteImageSize(Size imageSize) {
    return imageSize.width.isFinite &&
        imageSize.height.isFinite &&
        imageSize.width > 0 &&
        imageSize.height > 0;
  }

  void _startHold(_StaticZoomPose pose, DateTime now) {
    _pendingDirection = pose.direction;
    _holdStartedAt = now;
    _startPalmCenter = pose.palmCenter;
    _startHandSize = pose.handSize;
    _startStableFingerOffsets = pose.stableFingerOffsets;
  }

  /// Builds the simplified angle-based zoom-in or closed-pinch zoom-out pose.
  _StaticZoomPose? _staticZoomPose(Hand hand) {
    if (!_hasOtherFingersClosedByAngle(hand)) return null;

    final thumbIp = _zoomVisibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbTip = _zoomVisibleLandmark(hand, HandLandmarkType.thumbTip);
    final indexDip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerDIP,
    );
    final indexTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    if (thumbIp == null ||
        thumbTip == null ||
        indexDip == null ||
        indexTip == null) {
      return null;
    }

    final palmCenter = geometry.palmCenter3D(hand);
    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
    if (palmCenter == null || handSize <= 0) return null;

    final indexIsAboveThumb = geometry.isLandmarkSegmentAbove2D(
      upperStart: indexDip,
      upperEnd: indexTip,
      lowerStart: thumbIp,
      lowerEnd: thumbTip,
      minVerticalGap:
          handSize * HandGestureThresholds.zoomIndexAboveThumbMinGapRatio,
    );
    if (!indexIsAboveThumb) return null;

    final isZoomIn = _hasZoomInThumbIndexAngle(
      thumbIp: thumbIp,
      thumbTip: thumbTip,
      indexDip: indexDip,
      indexTip: indexTip,
    );
    final distance2dRatio =
        geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize;
    final distance3dRatio =
        geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) / handSize;
    final isClosedPinch =
        distance2dRatio <=
            HandGestureThresholds.zoomTouchMax2dDistanceRatio +
                _distanceComparisonEpsilon ||
        distance3dRatio <=
            HandGestureThresholds.zoomClosedMaxDistanceRatio +
                _distanceComparisonEpsilon;
    final isClearlySeparated =
        distance2dRatio + _distanceComparisonEpsilon >=
            HandGestureThresholds.zoomInMinDistanceRatio &&
        distance3dRatio + _distanceComparisonEpsilon >=
            HandGestureThresholds.zoomInMinDistanceRatio;

    // A closed pinch always belongs to Zoom Out, even when its fingertip
    // segments also happen to form the Zoom In angle. The separation gap
    // between the closed and open thresholds keeps noisy frames neutral.
    final direction = isClosedPinch
        ? ZoomDirection.zoomOut
        : isZoomIn && isClearlySeparated
        ? ZoomDirection.zoomIn
        : ZoomDirection.none;
    if (direction == ZoomDirection.none) return null;

    if (direction == ZoomDirection.zoomOut &&
        geometry.isThumbTuckedForFist3D(
              hand: hand,
              palmCenter: palmCenter,
              handSize: handSize,
            ) !=
            false) {
      // A closed thumb belongs to an index-pointing direction or a fist, not
      // to the closed-pinch zoom-out pose.
      return null;
    }

    final stableFingerOffsets = _stableFingerOffsets(
      hand: hand,
      palmCenter: palmCenter,
    );
    if (stableFingerOffsets.length <
        HandGestureThresholds.zoomStableFingerMinCount) {
      return null;
    }

    return _StaticZoomPose(
      direction: direction,
      palmCenter: palmCenter,
      handSize: handSize,
      stableFingerOffsets: stableFingerOffsets,
    );
  }

  /// Requires only middle, ring, and pinky to remain folded for Zoom In.
  bool _hasOtherFingersClosedByAngle(Hand hand) {
    for (final chainTypes
        in HandGestureThresholds.directionFingerChainTypes.skip(1)) {
      final mcp = _zoomVisibleLandmark(hand, chainTypes[0]);
      final pip = _zoomVisibleLandmark(hand, chainTypes[1]);
      final tip = _zoomVisibleLandmark(hand, chainTypes[3]);
      if (mcp == null || pip == null || tip == null) return false;

      if (!geometry.isFingerFoldedByAngle3D(mcp: mcp, pip: pip, tip: tip)) {
        return false;
      }
    }

    return true;
  }

  /// Uses the visible 2D fingertip segments from thumb 3->4 and index 7->8.
  bool _hasZoomInThumbIndexAngle({
    required HandLandmark thumbIp,
    required HandLandmark thumbTip,
    required HandLandmark indexDip,
    required HandLandmark indexTip,
  }) {
    final angle = geometry.angleBetweenLandmarkSegments2D(
      firstStart: thumbIp,
      firstEnd: thumbTip,
      secondStart: indexDip,
      secondEnd: indexTip,
    );
    if (angle == null) return false;

    return angle + _angleComparisonEpsilon >=
            HandGestureThresholds.zoomInThumbIndexMinAngleDegrees &&
        angle - _angleComparisonEpsilon <=
            HandGestureThresholds.zoomInThumbIndexMaxAngleDegrees;
  }

  Map<HandLandmarkType, HandPoint3D> _stableFingerOffsets({
    required Hand hand,
    required HandPoint3D palmCenter,
  }) {
    final offsets = <HandLandmarkType, HandPoint3D>{};

    for (final type in _stableFingerTypes) {
      final landmark = _zoomVisibleLandmark(hand, type);
      if (landmark == null) continue;

      offsets[type] = HandPoint3D(
        x: landmark.x - palmCenter.x,
        y: landmark.y - palmCenter.y,
        z: landmark.z - palmCenter.z,
      );
    }

    return offsets;
  }

  bool _isPalmStable(_StaticZoomPose pose) {
    final startPalmCenter = _startPalmCenter;
    final startHandSize = _startHandSize;
    if (startPalmCenter == null || startHandSize == null) return false;

    final referenceHandSize = math.max(startHandSize, pose.handSize);
    if (referenceHandSize <= 0) return false;

    return geometry.distanceBetweenPoints3D(startPalmCenter, pose.palmCenter) <=
        referenceHandSize * HandGestureThresholds.zoomMaxPalmMovementRatio;
  }

  bool _areStableFingersStable({
    required Map<HandLandmarkType, HandPoint3D> currentStableFingerOffsets,
    required double currentHandSize,
  }) {
    final startStableFingerOffsets = _startStableFingerOffsets;
    final startHandSize = _startHandSize;
    if (startStableFingerOffsets == null || startHandSize == null) return false;

    final referenceHandSize = math.max(startHandSize, currentHandSize);
    if (referenceHandSize <= 0) return false;

    final maxMovement =
        referenceHandSize *
        HandGestureThresholds.zoomStableFingerMaxMovementRatio;
    var stableCount = 0;

    for (final type in _stableFingerTypes) {
      final startOffset = startStableFingerOffsets[type];
      final currentOffset = currentStableFingerOffsets[type];
      if (startOffset == null || currentOffset == null) continue;

      final dx = startOffset.x - currentOffset.x;
      final dy = startOffset.y - currentOffset.y;
      final dz = geometry.weightedDepthValue(startOffset.z - currentOffset.z);
      final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (distance <= maxMovement) stableCount += 1;
    }

    return stableCount >= HandGestureThresholds.zoomStableFingerMinCount;
  }

  HandLandmark? _zoomVisibleLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }
}

class _StaticZoomPose {
  const _StaticZoomPose({
    required this.direction,
    required this.palmCenter,
    required this.handSize,
    required this.stableFingerOffsets,
  });

  final ZoomDirection direction;
  final HandPoint3D palmCenter;
  final double handSize;
  final Map<HandLandmarkType, HandPoint3D> stableFingerOffsets;
}
