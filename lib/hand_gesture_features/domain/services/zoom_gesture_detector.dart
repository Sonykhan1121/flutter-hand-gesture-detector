import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/zoom_direction.dart';
import '../enums/zoom_gesture_phase.dart';
import 'hand_geometry_service.dart';

/// Detects pinch-open zoom in and pinch-close zoom out gestures.
class ZoomGestureDetector {
  ZoomGestureDetector({
    this.geometry = const HandGeometryService(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HandGeometryService geometry;
  final DateTime Function() _now;

  ZoomGesturePhase _phase = ZoomGesturePhase.idle;
  ZoomDirection _directionLock = ZoomDirection.none;
  bool _isPartialZoomOutPhase = false;
  double? _startDistanceRatio;
  HandPoint3D? _startPalmCenter;
  double? _startHandSize;
  Map<HandLandmarkType, HandPoint3D>? _startStableFingerOffsets;
  DateTime? _phaseStartedAt;
  DateTime? _poseInvalidStartedAt;
  DateTime? _lastZoomInDetectedAt;
  DateTime? _lastZoomOutDetectedAt;

  ZoomDirection _startPoseDirection = ZoomDirection.none;
  DateTime? _startPoseStartedAt;
  double? _startPoseDistanceRatio;
  HandPoint3D? _startPosePalmCenter;
  double? _startPoseHandSize;
  Map<HandLandmarkType, HandPoint3D>? _startPoseStableFingerOffsets;

  static const List<HandLandmarkType> _stableFingerTypes = [
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  /// True while any zoom phase, lock, or start-pose candidate is active.
  bool get isGestureActive =>
      _phase != ZoomGesturePhase.idle ||
      _isPartialZoomOutPhase ||
      _directionLock != ZoomDirection.none ||
      _startPoseDirection != ZoomDirection.none;

  /// Updates the zoom state machine from a single hand frame.
  ZoomDirection detect({
    required Hand hand,
    required Size imageSize,
    bool allowPartialZoomOut = false,
  }) {
    final now = _now();

    if (!geometry.isReliableHand(hand) ||
        !imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      markPoseInvalid(now);
      return _recentDetected(now);
    }

    final pose = _zoomPose(hand);

    // Partial zoom-out handles frames where thumb/index are visible but the
    // stricter zoom pose is missing because other fingers are partially hidden.
    if (pose == null) {
      if (allowPartialZoomOut) {
        final partialZoomOutDistanceRatio = _partialZoomOutDistanceRatio(
          hand: hand,
          imageSize: imageSize,
        );
        final stableFingerSample = _zoomStableFingerSample(hand);

        if (partialZoomOutDistanceRatio != null) {
          return _detectPartialZoomOut(
            distanceRatio: partialZoomOutDistanceRatio,
            stableFingerSample: stableFingerSample,
            now: now,
          );
        }
      }

      markPoseInvalid(now);
      return _recentDetected(now);
    }

    final distanceRatio = pose.distanceRatio;

    if (_isPartialZoomOutPhase) {
      _clearActivePhase();
    }

    _poseInvalidStartedAt = null;

    final phaseStartedAt = _phaseStartedAt;
    if (phaseStartedAt != null &&
        now.difference(phaseStartedAt) >
            HandGestureThresholds.zoomMaxGestureDuration) {
      _clearActivePhase();
    }

    if (_directionLock == ZoomDirection.zoomIn) {
      if (distanceRatio <= HandGestureThresholds.zoomClosedMaxDistanceRatio) {
        final startPoseReady = _startOrContinueStartPose(
          direction: ZoomDirection.zoomIn,
          distanceRatio: distanceRatio,
          now: now,
          palmCenter: pose.palmCenter,
          handSize: pose.handSize,
          stableFingerOffsets: pose.stableFingerOffsets,
        );

        if (startPoseReady) {
          _armGestureFromStartPose(
            phase: ZoomGesturePhase.armedForZoomIn,
            distanceRatio: distanceRatio,
            pose: pose,
            now: now,
          );
        }
      } else {
        _clearStartPoseCandidate();
      }

      return _recentDetected(now);
    }

    if (_directionLock == ZoomDirection.zoomOut) {
      if (distanceRatio >= HandGestureThresholds.zoomOpenMinDistanceRatio) {
        final startPoseReady = _startOrContinueStartPose(
          direction: ZoomDirection.zoomOut,
          distanceRatio: distanceRatio,
          now: now,
          palmCenter: pose.palmCenter,
          handSize: pose.handSize,
          stableFingerOffsets: pose.stableFingerOffsets,
        );

        if (startPoseReady) {
          _armGestureFromStartPose(
            phase: ZoomGesturePhase.armedForZoomOut,
            distanceRatio: distanceRatio,
            pose: pose,
            now: now,
          );
        }
      } else {
        _clearStartPoseCandidate();
      }

      return _recentDetected(now);
    }

    switch (_phase) {
      case ZoomGesturePhase.idle:
        if (distanceRatio <= HandGestureThresholds.zoomClosedMaxDistanceRatio) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomIn,
            distanceRatio: distanceRatio,
            now: now,
            palmCenter: pose.palmCenter,
            handSize: pose.handSize,
            stableFingerOffsets: pose.stableFingerOffsets,
          );

          if (startPoseReady) {
            _armGestureFromStartPose(
              phase: ZoomGesturePhase.armedForZoomIn,
              distanceRatio: distanceRatio,
              pose: pose,
              now: now,
            );
          }
        } else if (distanceRatio >=
            HandGestureThresholds.zoomOpenMinDistanceRatio) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomOut,
            distanceRatio: distanceRatio,
            now: now,
            palmCenter: pose.palmCenter,
            handSize: pose.handSize,
            stableFingerOffsets: pose.stableFingerOffsets,
          );

          if (startPoseReady) {
            _armGestureFromStartPose(
              phase: ZoomGesturePhase.armedForZoomOut,
              distanceRatio: distanceRatio,
              pose: pose,
              now: now,
            );
          }
        } else {
          _clearStartPoseCandidate();
        }

        return _recentDetected(now);

      case ZoomGesturePhase.armedForZoomIn:
        final startDistance = _startDistanceRatio;
        final startedAt = _phaseStartedAt;

        if (startDistance == null || startedAt == null) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (!_isPalmStableForActiveGesture(pose)) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (!_areStableFingersStableForActiveGesture(
          currentStableFingerOffsets: pose.stableFingerOffsets,
          currentHandSize: pose.handSize,
        )) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (distanceRatio < startDistance) {
          _startDistanceRatio = distanceRatio;
        }

        final latestStart = _startDistanceRatio ?? startDistance;

        final openedEnough =
            distanceRatio >= HandGestureThresholds.zoomOpenMinDistanceRatio &&
            distanceRatio - latestStart >=
                HandGestureThresholds.zoomMinChangeRatio;

        final stableEnough =
            now.difference(startedAt) >=
            HandGestureThresholds.zoomMinGestureDuration;

        if (openedEnough && stableEnough) {
          return _completeGesture(ZoomDirection.zoomIn, now);
        }

        return _recentDetected(now);

      case ZoomGesturePhase.armedForZoomOut:
        final startDistance = _startDistanceRatio;
        final startedAt = _phaseStartedAt;

        if (startDistance == null || startedAt == null) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (!_isPalmStableForActiveGesture(pose)) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (!_areStableFingersStableForActiveGesture(
          currentStableFingerOffsets: pose.stableFingerOffsets,
          currentHandSize: pose.handSize,
        )) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (distanceRatio > startDistance) {
          _startDistanceRatio = distanceRatio;
        }

        final latestStart = _startDistanceRatio ?? startDistance;

        final closedEnough =
            distanceRatio <= HandGestureThresholds.zoomClosedMaxDistanceRatio &&
            latestStart - distanceRatio >=
                HandGestureThresholds.zoomMinChangeRatio;

        final stableEnough =
            now.difference(startedAt) >=
            HandGestureThresholds.zoomMinGestureDuration;

        if (closedEnough && stableEnough) {
          return _completeGesture(ZoomDirection.zoomOut, now);
        }

        return _recentDetected(now);
    }
  }

  /// Handles a missing/invalid pose and clears zoom state after release.
  void markPoseInvalid(DateTime now) {
    _clearActivePhase();

    _poseInvalidStartedAt ??= now;

    final invalidStartedAt = _poseInvalidStartedAt;
    if (invalidStartedAt != null &&
        now.difference(invalidStartedAt) >=
            HandGestureThresholds.zoomReleaseResetDuration) {
      clearState();
    }
  }

  /// Clears all active zoom state and recent output holds.
  void clearState() {
    _clearActivePhase();
    _directionLock = ZoomDirection.none;
    _poseInvalidStartedAt = null;
    _lastZoomInDetectedAt = null;
    _lastZoomOutDetectedAt = null;
  }

  /// Stores a completed gesture and locks that direction until a new start pose.
  ZoomDirection _completeGesture(ZoomDirection direction, DateTime now) {
    if (direction == ZoomDirection.zoomIn) {
      _lastZoomInDetectedAt = now;
      _lastZoomOutDetectedAt = null;
    } else if (direction == ZoomDirection.zoomOut) {
      _lastZoomOutDetectedAt = now;
      _lastZoomInDetectedAt = null;
    }

    _directionLock = direction;
    _clearActivePhase();

    return direction;
  }

  /// Clears the current armed zoom phase but keeps recent result holds.
  void _clearActivePhase() {
    _phase = ZoomGesturePhase.idle;
    _isPartialZoomOutPhase = false;
    _startDistanceRatio = null;
    _startPalmCenter = null;
    _startHandSize = null;
    _startStableFingerOffsets = null;
    _phaseStartedAt = null;
    _clearStartPoseCandidate();
  }

  /// Clears the candidate pose used before arming a real zoom gesture.
  void _clearStartPoseCandidate() {
    _startPoseDirection = ZoomDirection.none;
    _startPoseStartedAt = null;
    _startPoseDistanceRatio = null;
    _startPosePalmCenter = null;
    _startPoseHandSize = null;
    _startPoseStableFingerOffsets = null;
  }

  /// Starts or validates a held start pose before arming zoom in/out.
  bool _startOrContinueStartPose({
    required ZoomDirection direction,
    required double distanceRatio,
    required DateTime now,
    HandPoint3D? palmCenter,
    double? handSize,
    Map<HandLandmarkType, HandPoint3D>? stableFingerOffsets,
  }) {
    if (stableFingerOffsets == null ||
        stableFingerOffsets.length <
            HandGestureThresholds.zoomStableFingerMinCount) {
      _clearStartPoseCandidate();
      return false;
    }

    if (_startPoseDirection != direction) {
      _setStartPoseCandidate(
        direction: direction,
        distanceRatio: distanceRatio,
        now: now,
        palmCenter: palmCenter,
        handSize: handSize,
        stableFingerOffsets: stableFingerOffsets,
      );
      return false;
    }

    final startedAt = _startPoseStartedAt;
    if (startedAt == null) {
      _setStartPoseCandidate(
        direction: direction,
        distanceRatio: distanceRatio,
        now: now,
        palmCenter: palmCenter,
        handSize: handSize,
        stableFingerOffsets: stableFingerOffsets,
      );
      return false;
    }

    if (!_isPalmStableForStartPose(
      palmCenter: palmCenter,
      handSize: handSize,
    )) {
      _setStartPoseCandidate(
        direction: direction,
        distanceRatio: distanceRatio,
        now: now,
        palmCenter: palmCenter,
        handSize: handSize,
        stableFingerOffsets: stableFingerOffsets,
      );
      return false;
    }

    if (!_areStableFingersStableForStartPose(
      currentStableFingerOffsets: stableFingerOffsets,
      currentHandSize: handSize,
    )) {
      _setStartPoseCandidate(
        direction: direction,
        distanceRatio: distanceRatio,
        now: now,
        palmCenter: palmCenter,
        handSize: handSize,
        stableFingerOffsets: stableFingerOffsets,
      );
      return false;
    }

    final currentStartDistance = _startPoseDistanceRatio;

    // Keep the most extreme start distance while the start pose is held. This
    // gives the gesture more room to confirm the later open/close movement.
    if (currentStartDistance == null) {
      _startPoseDistanceRatio = distanceRatio;
    } else if (direction == ZoomDirection.zoomIn) {
      if (distanceRatio < currentStartDistance) {
        _startPoseDistanceRatio = distanceRatio;
      }
    } else if (direction == ZoomDirection.zoomOut) {
      if (distanceRatio > currentStartDistance) {
        _startPoseDistanceRatio = distanceRatio;
      }
    }

    return now.difference(startedAt) >=
        HandGestureThresholds.zoomStartPoseHoldDuration;
  }

  /// Saves the current frame as the start-pose candidate.
  void _setStartPoseCandidate({
    required ZoomDirection direction,
    required double distanceRatio,
    required DateTime now,
    HandPoint3D? palmCenter,
    double? handSize,
    Map<HandLandmarkType, HandPoint3D>? stableFingerOffsets,
  }) {
    _startPoseDirection = direction;
    _startPoseStartedAt = now;
    _startPoseDistanceRatio = distanceRatio;
    _startPosePalmCenter = palmCenter;
    _startPoseHandSize = handSize;
    _startPoseStableFingerOffsets = stableFingerOffsets;
  }

  /// Converts a stable start pose into an active zoom phase.
  void _armGestureFromStartPose({
    required ZoomGesturePhase phase,
    required double distanceRatio,
    required _ZoomPose pose,
    required DateTime now,
  }) {
    final startDistance = _startPoseDistanceRatio ?? distanceRatio;
    final startPalmCenter = _startPosePalmCenter ?? pose.palmCenter;
    final startHandSize = _startPoseHandSize ?? pose.handSize;
    final startStableFingerOffsets =
        _startPoseStableFingerOffsets ?? pose.stableFingerOffsets;

    _clearStartPoseCandidate();
    _directionLock = ZoomDirection.none;
    _phase = phase;
    _startDistanceRatio = startDistance;
    _startPalmCenter = startPalmCenter;
    _startHandSize = startHandSize;
    _startStableFingerOffsets = startStableFingerOffsets;
    _phaseStartedAt = now;
  }

  /// Detects zoom out when only thumb/index distance can be trusted.
  ZoomDirection _detectPartialZoomOut({
    required double distanceRatio,
    required _ZoomStableFingerSample? stableFingerSample,
    required DateTime now,
  }) {
    _poseInvalidStartedAt = null;

    final phaseStartedAt = _phaseStartedAt;
    if (phaseStartedAt != null &&
        now.difference(phaseStartedAt) >
            HandGestureThresholds.zoomMaxGestureDuration) {
      _clearActivePhase();
    }

    if (_phase == ZoomGesturePhase.armedForZoomIn ||
        (_phase == ZoomGesturePhase.armedForZoomOut &&
            !_isPartialZoomOutPhase)) {
      _clearActivePhase();
    }

    if (_directionLock == ZoomDirection.zoomIn) {
      _directionLock = ZoomDirection.none;
      _clearStartPoseCandidate();
    }

    if (_directionLock == ZoomDirection.zoomOut) {
      if (distanceRatio >=
              HandGestureThresholds.partialZoomOutOpenMinImageRatio &&
          stableFingerSample != null) {
        final startPoseReady = _startOrContinueStartPose(
          direction: ZoomDirection.zoomOut,
          distanceRatio: distanceRatio,
          now: now,
          palmCenter: stableFingerSample.palmCenter,
          handSize: stableFingerSample.handSize,
          stableFingerOffsets: stableFingerSample.stableFingerOffsets,
        );

        if (startPoseReady) {
          final startDistance = _startPoseDistanceRatio ?? distanceRatio;
          _armPartialZoomOut(startDistance: startDistance, now: now);
        }
      } else {
        _clearStartPoseCandidate();
      }

      return _recentDetected(now);
    }

    switch (_phase) {
      case ZoomGesturePhase.idle:
        if (distanceRatio >=
                HandGestureThresholds.partialZoomOutOpenMinImageRatio &&
            stableFingerSample != null) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomOut,
            distanceRatio: distanceRatio,
            now: now,
            palmCenter: stableFingerSample.palmCenter,
            handSize: stableFingerSample.handSize,
            stableFingerOffsets: stableFingerSample.stableFingerOffsets,
          );

          if (startPoseReady) {
            final startDistance = _startPoseDistanceRatio ?? distanceRatio;
            _armPartialZoomOut(startDistance: startDistance, now: now);
          }
        } else {
          _clearStartPoseCandidate();
        }

        return _recentDetected(now);

      case ZoomGesturePhase.armedForZoomIn:
        _clearActivePhase();
        return _recentDetected(now);

      case ZoomGesturePhase.armedForZoomOut:
        if (!_isPartialZoomOutPhase) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        final startDistance = _startDistanceRatio;
        final startedAt = _phaseStartedAt;

        if (startDistance == null || startedAt == null) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (stableFingerSample == null ||
            !_areStableFingersStableForActiveGesture(
              currentStableFingerOffsets:
                  stableFingerSample.stableFingerOffsets,
              currentHandSize: stableFingerSample.handSize,
            )) {
          _clearActivePhase();
          return _recentDetected(now);
        }

        if (distanceRatio > startDistance) {
          _startDistanceRatio = distanceRatio;
        }

        final latestStart = _startDistanceRatio ?? startDistance;

        final closedEnough =
            latestStart - distanceRatio >=
                HandGestureThresholds.partialZoomOutMinChangeImageRatio &&
            distanceRatio <=
                latestStart *
                    HandGestureThresholds
                        .partialZoomOutClosedMaxStartDistanceFactor;

        final stableEnough =
            now.difference(startedAt) >=
            HandGestureThresholds.zoomMinGestureDuration;

        if (closedEnough && stableEnough) {
          return _completeGesture(ZoomDirection.zoomOut, now);
        }

        return _recentDetected(now);
    }
  }

  /// Arms the partial zoom-out phase from the held start pose.
  void _armPartialZoomOut({
    required double startDistance,
    required DateTime now,
  }) {
    final startPalmCenter = _startPosePalmCenter;
    final startHandSize = _startPoseHandSize;
    final startStableFingerOffsets = _startPoseStableFingerOffsets;

    _clearStartPoseCandidate();
    _directionLock = ZoomDirection.none;
    _phase = ZoomGesturePhase.armedForZoomOut;
    _isPartialZoomOutPhase = true;
    _startDistanceRatio = startDistance;
    _startPalmCenter = startPalmCenter;
    _startHandSize = startHandSize;
    _startStableFingerOffsets = startStableFingerOffsets;
    _phaseStartedAt = now;
  }

  /// Requires middle, ring, and pinky to be closed for the pinch gesture.
  bool _hasOtherFingersClosedByAngle(Hand hand) {
    final middleTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );
    final middleMcp = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );

    final ringTip = _zoomVisibleLandmark(hand, HandLandmarkType.ringFingerTip);
    final ringPip = _zoomVisibleLandmark(hand, HandLandmarkType.ringFingerPIP);
    final ringMcp = _zoomVisibleLandmark(hand, HandLandmarkType.ringFingerMCP);

    final pinkyTip = _zoomVisibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = _zoomVisibleLandmark(hand, HandLandmarkType.pinkyPIP);
    final pinkyMcp = _zoomVisibleLandmark(hand, HandLandmarkType.pinkyMCP);

    if (middleTip == null ||
        middlePip == null ||
        middleMcp == null ||
        ringTip == null ||
        ringPip == null ||
        ringMcp == null ||
        pinkyTip == null ||
        pinkyPip == null ||
        pinkyMcp == null) {
      return false;
    }

    final middleIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
    );

    final ringIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
    );

    final pinkyIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
    );

    return middleIsClosed && ringIsClosed && pinkyIsClosed;
  }

  /// Builds the strict zoom pose used by normal zoom in/out.
  _ZoomPose? _zoomPose(Hand hand) {
    if (!_hasOtherFingersClosedByAngle(hand)) {
      return null;
    }

    final thumbTip = _zoomVisibleLandmark(hand, HandLandmarkType.thumbTip);
    final indexTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    if (thumbTip == null || indexTip == null) return null;

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return null;

    final box = hand.boundingBox;
    final handSize = _handSize(box);

    if (handSize <= 0) return null;

    final stableFingerOffsets = _stableFingerOffsets(
      hand: hand,
      palmCenter: palmCenter,
    );

    if (!_hasEnoughStableFingerOffsets(stableFingerOffsets)) {
      return null;
    }

    final tipCenter = HandPoint3D(
      x: (thumbTip.x + indexTip.x) / 2,
      y: (thumbTip.y + indexTip.y) / 2,
      z: (thumbTip.z + indexTip.z) / 2,
    );

    if (geometry.distanceBetweenPoints3D(tipCenter, palmCenter) <=
        handSize * HandGestureThresholds.zoomActiveTipMinPalmDistanceRatio) {
      return null;
    }

    return _ZoomPose(
      distanceRatio:
          geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) / handSize,
      palmCenter: palmCenter,
      handSize: handSize,
      stableFingerOffsets: stableFingerOffsets,
    );
  }

  /// Captures palm and stable-finger offsets without requiring a full pose.
  _ZoomStableFingerSample? _zoomStableFingerSample(Hand hand) {
    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return null;

    final handSize = _handSize(hand.boundingBox);
    if (handSize <= 0) return null;

    final stableFingerOffsets = _stableFingerOffsets(
      hand: hand,
      palmCenter: palmCenter,
    );

    if (!_hasEnoughStableFingerOffsets(stableFingerOffsets)) {
      return null;
    }

    return _ZoomStableFingerSample(
      palmCenter: palmCenter,
      handSize: handSize,
      stableFingerOffsets: stableFingerOffsets,
    );
  }

  /// Uses hand bounding-box size as the zoom ratio denominator.
  double _handSize(BoundingBox box) {
    return geometry.handSizeFromBoundingBox(box);
  }

  /// Stores stable-finger offsets relative to the palm center.
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

  /// Thumb/index distance normalized by image size for partial zoom out.
  double? _partialZoomOutDistanceRatio({
    required Hand hand,
    required Size imageSize,
  }) {
    final thumbTip = _zoomVisibleLandmark(hand, HandLandmarkType.thumbTip);
    final indexTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    if (thumbTip == null || indexTip == null) return null;

    final imageMaxSide = math.max(imageSize.width, imageSize.height);
    if (imageMaxSide <= 0) return null;

    return geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) /
        imageMaxSide;
  }

  /// Returns a landmark using the lower visibility required by zoom logic.
  HandLandmark? _zoomVisibleLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

  /// Holds the last zoom result briefly for repeated UI/application updates.
  ZoomDirection _recentDetected(DateTime now) {
    final lastIn = _lastZoomInDetectedAt;
    if (lastIn != null &&
        now.difference(lastIn) <= HandGestureThresholds.zoomHoldDuration) {
      return ZoomDirection.zoomIn;
    }

    final lastOut = _lastZoomOutDetectedAt;
    if (lastOut != null &&
        now.difference(lastOut) <= HandGestureThresholds.zoomHoldDuration) {
      return ZoomDirection.zoomOut;
    }

    return ZoomDirection.none;
  }

  /// Checks that the palm did not drift while holding a start pose.
  bool _isPalmStableForStartPose({
    required HandPoint3D? palmCenter,
    required double? handSize,
  }) {
    final startPalmCenter = _startPosePalmCenter;
    final startHandSize = _startPoseHandSize;

    if (startPalmCenter == null ||
        startHandSize == null ||
        palmCenter == null ||
        handSize == null) {
      return true;
    }

    return _isPalmMovementWithinLimit(
      startPalmCenter: startPalmCenter,
      startHandSize: startHandSize,
      currentPalmCenter: palmCenter,
      currentHandSize: handSize,
    );
  }

  /// Checks that the palm did not drift during an active zoom gesture.
  bool _isPalmStableForActiveGesture(_ZoomPose pose) {
    final startPalmCenter = _startPalmCenter;
    final startHandSize = _startHandSize;

    if (startPalmCenter == null || startHandSize == null) return true;

    return _isPalmMovementWithinLimit(
      startPalmCenter: startPalmCenter,
      startHandSize: startHandSize,
      currentPalmCenter: pose.palmCenter,
      currentHandSize: pose.handSize,
    );
  }

  /// Checks stable fingers against the saved start-pose offsets.
  bool _areStableFingersStableForStartPose({
    required Map<HandLandmarkType, HandPoint3D> currentStableFingerOffsets,
    required double? currentHandSize,
  }) {
    final startStableFingerOffsets = _startPoseStableFingerOffsets;
    final startHandSize = _startPoseHandSize;

    if (startStableFingerOffsets == null ||
        startHandSize == null ||
        currentHandSize == null) {
      return false;
    }

    return _areStableFingerOffsetsWithinLimit(
      startStableFingerOffsets: startStableFingerOffsets,
      startHandSize: startHandSize,
      currentStableFingerOffsets: currentStableFingerOffsets,
      currentHandSize: currentHandSize,
    );
  }

  /// Checks stable fingers against the saved active-gesture offsets.
  bool _areStableFingersStableForActiveGesture({
    required Map<HandLandmarkType, HandPoint3D> currentStableFingerOffsets,
    required double currentHandSize,
  }) {
    final startStableFingerOffsets = _startStableFingerOffsets;
    final startHandSize = _startHandSize;

    if (startStableFingerOffsets == null || startHandSize == null) {
      return false;
    }

    return _areStableFingerOffsetsWithinLimit(
      startStableFingerOffsets: startStableFingerOffsets,
      startHandSize: startHandSize,
      currentStableFingerOffsets: currentStableFingerOffsets,
      currentHandSize: currentHandSize,
    );
  }

  /// Ensures enough stable-finger landmarks are present to guard the gesture.
  bool _hasEnoughStableFingerOffsets(
    Map<HandLandmarkType, HandPoint3D>? stableFingerOffsets,
  ) {
    return stableFingerOffsets != null &&
        stableFingerOffsets.length >=
            HandGestureThresholds.zoomStableFingerMinCount;
  }

  /// Compares stable-finger offsets and counts how many stayed in place.
  bool _areStableFingerOffsetsWithinLimit({
    required Map<HandLandmarkType, HandPoint3D> startStableFingerOffsets,
    required double startHandSize,
    required Map<HandLandmarkType, HandPoint3D> currentStableFingerOffsets,
    required double currentHandSize,
  }) {
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

      if (_stableFingerOffsetDistance(startOffset, currentOffset) <=
          maxMovement) {
        stableCount += 1;
      }
    }

    return stableCount >= HandGestureThresholds.zoomStableFingerMinCount;
  }

  /// Measures weighted 3D distance between two palm-relative offsets.
  double _stableFingerOffsetDistance(HandPoint3D first, HandPoint3D second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    final dz = geometry.weightedDepthValue(first.z - second.z);

    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Returns true when the palm center moved less than the allowed ratio.
  bool _isPalmMovementWithinLimit({
    required HandPoint3D startPalmCenter,
    required double startHandSize,
    required HandPoint3D currentPalmCenter,
    required double currentHandSize,
  }) {
    final referenceHandSize = math.max(startHandSize, currentHandSize);
    if (referenceHandSize <= 0) return false;

    final maxPalmMovement =
        referenceHandSize * HandGestureThresholds.zoomMaxPalmMovementRatio;

    return geometry.distanceBetweenPoints3D(
          startPalmCenter,
          currentPalmCenter,
        ) <=
        maxPalmMovement;
  }
}

/// Strict zoom pose with thumb/index distance and stability anchors.
class _ZoomPose {
  const _ZoomPose({
    required this.distanceRatio,
    required this.palmCenter,
    required this.handSize,
    required this.stableFingerOffsets,
  });

  final double distanceRatio;
  final HandPoint3D palmCenter;
  final double handSize;
  final Map<HandLandmarkType, HandPoint3D> stableFingerOffsets;
}

/// Stability-only sample used for partial zoom-out recovery.
class _ZoomStableFingerSample {
  const _ZoomStableFingerSample({
    required this.palmCenter,
    required this.handSize,
    required this.stableFingerOffsets,
  });

  final HandPoint3D palmCenter;
  final double handSize;
  final Map<HandLandmarkType, HandPoint3D> stableFingerOffsets;
}
