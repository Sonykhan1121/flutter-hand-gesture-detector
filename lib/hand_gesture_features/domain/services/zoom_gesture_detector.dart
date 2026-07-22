import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/zoom_direction.dart';
import 'hand_geometry_service.dart';

/// Detects static zoom holds and the Zoom Out-to-Zoom In opening transition.
class ZoomGestureDetector {
  ZoomGestureDetector({
    this.geometry = const HandGeometryService(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HandGeometryService geometry;
  final DateTime Function() _now;

  static const double _distanceComparisonEpsilon = 1e-9;

  ZoomDirection _pendingDirection = ZoomDirection.none;
  DateTime? _holdStartedAt;
  HandPoint3D? _startPalmCenter;
  double? _startHandSize;
  Map<HandLandmarkType, HandPoint3D>? _startStableFingerOffsets;
  _ZoomInOpeningPhase _zoomInOpeningPhase = _ZoomInOpeningPhase.idle;
  bool _hasZoomInDebugPose = false;
  bool _debugPalmStable = false;
  bool _debugStableFingers = false;

  static const List<HandLandmarkType> _stableFingerTypes = [
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  /// True during a static hold or an armed Zoom Out-to-Zoom In transition.
  bool get isGestureActive => _pendingDirection != ZoomDirection.none;

  /// Direction currently holding or being prepared by the opening candidate.
  ZoomDirection get pendingDirection => _pendingDirection;

  /// True while directions must yield to an armed or active opening sequence.
  bool get reservesZoomInOpeningTransition =>
      _zoomInOpeningPhase != _ZoomInOpeningPhase.idle;

  /// True in the released-pinch stage before the opening becomes Zoom In.
  bool get isOpeningZoomInCandidate =>
      _zoomInOpeningPhase == _ZoomInOpeningPhase.candidate;

  /// True when the current non-closed pose is being evaluated as Zoom In.
  bool get hasZoomInDebugPose => _hasZoomInDebugPose;

  bool get debugPalmStable => _debugPalmStable;

  bool get debugStableFingers => _debugStableFingers;

  double debugHoldProgress(DateTime now) {
    final startedAt = _holdStartedAt;
    if (startedAt == null || now.isBefore(startedAt)) return 0;
    return (now.difference(startedAt).inMilliseconds /
            HandGestureThresholds.zoomStaticHoldDuration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Returns static directions after 1s, or Zoom In immediately after a
  /// recognized Zoom Out pinch opens through the candidate stage.
  ZoomDirection detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    bool? mirrorScreenHorizontally,
  }) {
    if (!geometry.isReliableHand(hand) || !_isFiniteImageSize(imageSize)) {
      clearState();
      return ZoomDirection.none;
    }

    final pose = _zoomPose(
      hand,
      imageSize: imageSize,
      mirrorPalmHorizontally: mirrorHorizontally,
      mirrorScreenHorizontally: mirrorScreenHorizontally ?? mirrorHorizontally,
    );
    if (pose == null) {
      clearState();
      return ZoomDirection.none;
    }
    final now = _now();
    switch (pose.type) {
      case _ZoomPoseType.zoomOut:
        _hasZoomInDebugPose = false;
        // Closing again ends any previous opening sequence. A new transition
        // is armed only after Zoom Out itself has completed its static hold.
        _zoomInOpeningPhase = _ZoomInOpeningPhase.idle;
        final direction = _detectStaticPose(
          pose: pose,
          direction: ZoomDirection.zoomOut,
          now: now,
        );
        if (direction == ZoomDirection.zoomOut) {
          _zoomInOpeningPhase = _ZoomInOpeningPhase.armed;
        }
        return direction;
      case _ZoomPoseType.openingCandidate:
        _hasZoomInDebugPose = true;
        if (_zoomInOpeningPhase == _ZoomInOpeningPhase.idle) {
          clearState();
          _hasZoomInDebugPose = true;
          return ZoomDirection.none;
        }

        _zoomInOpeningPhase = _ZoomInOpeningPhase.candidate;
        if (_pendingDirection != ZoomDirection.zoomIn) {
          _startPendingPose(pose, ZoomDirection.zoomIn, now);
        }
        return ZoomDirection.none;
      case _ZoomPoseType.zoomIn:
        _hasZoomInDebugPose = true;
        if (_zoomInOpeningPhase == _ZoomInOpeningPhase.candidate ||
            _zoomInOpeningPhase == _ZoomInOpeningPhase.active) {
          _zoomInOpeningPhase = _ZoomInOpeningPhase.active;
          if (_pendingDirection != ZoomDirection.zoomIn) {
            _startPendingPose(pose, ZoomDirection.zoomIn, now);
          }
          return ZoomDirection.zoomIn;
        }

        _zoomInOpeningPhase = _ZoomInOpeningPhase.idle;
        return _detectStaticPose(
          pose: pose,
          direction: ZoomDirection.zoomIn,
          now: now,
        );
    }
  }

  ZoomDirection _detectStaticPose({
    required _ZoomPose pose,
    required ZoomDirection direction,
    required DateTime now,
  }) {
    final startedAt = _holdStartedAt;
    if (_pendingDirection != direction ||
        startedAt == null ||
        now.isBefore(startedAt)) {
      _startPendingPose(pose, direction, now);
      return ZoomDirection.none;
    }

    _debugPalmStable = _isPalmStable(pose);
    _debugStableFingers = _areStableFingersStable(
      currentStableFingerOffsets: pose.stableFingerOffsets,
      currentHandSize: pose.handSize,
    );
    if (!_debugPalmStable || !_debugStableFingers) {
      _startPendingPose(pose, direction, now);
      return ZoomDirection.none;
    }

    if (now.difference(startedAt) <
        HandGestureThresholds.zoomStaticHoldDuration) {
      return ZoomDirection.none;
    }

    return direction;
  }

  /// Clears the active pose and requires a fresh one-second hold.
  void clearState() {
    _pendingDirection = ZoomDirection.none;
    _holdStartedAt = null;
    _startPalmCenter = null;
    _startHandSize = null;
    _startStableFingerOffsets = null;
    _zoomInOpeningPhase = _ZoomInOpeningPhase.idle;
    _hasZoomInDebugPose = false;
    _debugPalmStable = false;
    _debugStableFingers = false;
  }

  bool _isFiniteImageSize(Size imageSize) {
    return imageSize.width.isFinite &&
        imageSize.height.isFinite &&
        imageSize.width > 0 &&
        imageSize.height > 0;
  }

  void _startPendingPose(
    _ZoomPose pose,
    ZoomDirection direction,
    DateTime now,
  ) {
    _pendingDirection = direction;
    _holdStartedAt = now;
    _startPalmCenter = pose.palmCenter;
    _startHandSize = pose.handSize;
    _startStableFingerOffsets = pose.stableFingerOffsets;
    _debugPalmStable = true;
    _debugStableFingers = true;
  }

  /// Classifies a closed pinch, released-pinch candidate, or open Zoom In.
  _ZoomPose? _zoomPose(
    Hand hand, {
    required Size imageSize,
    required bool mirrorPalmHorizontally,
    required bool mirrorScreenHorizontally,
  }) {
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
    if (!geometry.isPalmSideFacingCamera(
      hand: hand,
      mirrorHorizontally: mirrorPalmHorizontally,
      minNormalizedCross: HandGestureThresholds.zoomMinPalmSideCross,
      minLandmarkVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    )) {
      return null;
    }

    final indexIsAboveThumb = geometry.isLandmarkSegmentAbove2D(
      upperStart: indexDip,
      upperEnd: indexTip,
      lowerStart: thumbIp,
      lowerEnd: thumbTip,
      minVerticalGap:
          handSize * HandGestureThresholds.zoomIndexAboveThumbMinGapRatio,
    );
    if (!indexIsAboveThumb) return null;

    final thumbIndexAngle = _zoomInThumbIndexAngleDegrees(
      thumbIp: thumbIp,
      thumbTip: thumbTip,
      indexDip: indexDip,
      indexTip: indexTip,
    );
    final forwardRayIntersection = geometry.forwardRayIntersection2D(
      firstStart: thumbTip,
      firstThrough: thumbIp,
      secondStart: indexTip,
      secondThrough: indexDip,
      minForwardScale: HandGestureThresholds.zoomInMinForwardRayScale,
      parallelToleranceDegrees:
          HandGestureThresholds.zoomInParallelRayToleranceDegrees,
      minParallelLineSeparation:
          handSize * HandGestureThresholds.zoomInParallelMinLineSeparationRatio,
    );
    final hasHandQuadrantRayRelation =
        forwardRayIntersection != null &&
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: forwardRayIntersection,
          firstStart: thumbTip,
          firstThrough: thumbIp,
          secondStart: indexTip,
          secondThrough: indexDip,
          imageSize: imageSize,
          handedness: hand.handedness,
          mirrorHorizontally: mirrorScreenHorizontally,
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

    if (isClosedPinch &&
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

    final type = isClosedPinch
        ? _ZoomPoseType.zoomOut
        : isClearlySeparated && hasHandQuadrantRayRelation
        ? _ZoomPoseType.zoomIn
        : thumbIndexAngle != null
        ? _ZoomPoseType.openingCandidate
        : null;
    if (type == null) return null;

    return _ZoomPose(
      type: type,
      palmCenter: palmCenter,
      handSize: handSize,
      stableFingerOffsets: stableFingerOffsets,
    );
  }

  /// Requires middle, ring, and pinky to remain folded for both zoom poses.
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
  double? _zoomInThumbIndexAngleDegrees({
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
    return angle;
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

  bool _isPalmStable(_ZoomPose pose) {
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

enum _ZoomPoseType { zoomOut, openingCandidate, zoomIn }

enum _ZoomInOpeningPhase { idle, armed, candidate, active }

class _ZoomPose {
  const _ZoomPose({
    required this.type,
    required this.palmCenter,
    required this.handSize,
    required this.stableFingerOffsets,
  });

  final _ZoomPoseType type;
  final HandPoint3D palmCenter;
  final double handSize;
  final Map<HandLandmarkType, HandPoint3D> stableFingerOffsets;
}
