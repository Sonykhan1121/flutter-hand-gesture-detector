import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/zoom_direction.dart';
import '../enums/zoom_gesture_phase.dart';
import 'hand_geometry_service.dart';

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
  Offset? _startPalmCenter;
  double? _startHandSize;
  DateTime? _phaseStartedAt;
  DateTime? _poseInvalidStartedAt;
  DateTime? _lastZoomInDetectedAt;
  DateTime? _lastZoomOutDetectedAt;

  ZoomDirection _startPoseDirection = ZoomDirection.none;
  DateTime? _startPoseStartedAt;
  double? _startPoseDistanceRatio;
  Offset? _startPosePalmCenter;
  double? _startPoseHandSize;

  bool get isGestureActive =>
      _phase != ZoomGesturePhase.idle ||
      _isPartialZoomOutPhase ||
      _directionLock != ZoomDirection.none ||
      _startPoseDirection != ZoomDirection.none;

  ZoomDirection detect({
    required Hand hand,
    required Size imageSize,
    bool allowPartialZoomOut = false,
  }) {
    final now = _now();
    final pose = _zoomPose(hand);

    if (pose == null) {
      if (allowPartialZoomOut) {
        final partialZoomOutDistanceRatio = _partialZoomOutDistanceRatio(
          hand: hand,
          imageSize: imageSize,
        );

        if (partialZoomOutDistanceRatio != null) {
          return _detectPartialZoomOut(
            distanceRatio: partialZoomOutDistanceRatio,
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
        );

        if (startPoseReady) {
          final startDistance = _startPoseDistanceRatio ?? distanceRatio;
          final startPalmCenter = _startPosePalmCenter ?? pose.palmCenter;
          final startHandSize = _startPoseHandSize ?? pose.handSize;

          _clearStartPoseCandidate();
          _directionLock = ZoomDirection.none;
          _phase = ZoomGesturePhase.armedForZoomIn;
          _startDistanceRatio = startDistance;
          _startPalmCenter = startPalmCenter;
          _startHandSize = startHandSize;
          _phaseStartedAt = now;
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
        );

        if (startPoseReady) {
          final startDistance = _startPoseDistanceRatio ?? distanceRatio;
          final startPalmCenter = _startPosePalmCenter ?? pose.palmCenter;
          final startHandSize = _startPoseHandSize ?? pose.handSize;

          _clearStartPoseCandidate();
          _directionLock = ZoomDirection.none;
          _phase = ZoomGesturePhase.armedForZoomOut;
          _startDistanceRatio = startDistance;
          _startPalmCenter = startPalmCenter;
          _startHandSize = startHandSize;
          _phaseStartedAt = now;
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
          );

          if (startPoseReady) {
            final startDistance = _startPoseDistanceRatio ?? distanceRatio;
            final startPalmCenter = _startPosePalmCenter ?? pose.palmCenter;
            final startHandSize = _startPoseHandSize ?? pose.handSize;

            _clearStartPoseCandidate();
            _phase = ZoomGesturePhase.armedForZoomIn;
            _startDistanceRatio = startDistance;
            _startPalmCenter = startPalmCenter;
            _startHandSize = startHandSize;
            _phaseStartedAt = now;
          }
        } else if (distanceRatio >=
            HandGestureThresholds.zoomOpenMinDistanceRatio) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomOut,
            distanceRatio: distanceRatio,
            now: now,
            palmCenter: pose.palmCenter,
            handSize: pose.handSize,
          );

          if (startPoseReady) {
            final startDistance = _startPoseDistanceRatio ?? distanceRatio;
            final startPalmCenter = _startPosePalmCenter ?? pose.palmCenter;
            final startHandSize = _startPoseHandSize ?? pose.handSize;

            _clearStartPoseCandidate();
            _phase = ZoomGesturePhase.armedForZoomOut;
            _startDistanceRatio = startDistance;
            _startPalmCenter = startPalmCenter;
            _startHandSize = startHandSize;
            _phaseStartedAt = now;
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

  void clearState() {
    _clearActivePhase();
    _directionLock = ZoomDirection.none;
    _poseInvalidStartedAt = null;
    _lastZoomInDetectedAt = null;
    _lastZoomOutDetectedAt = null;
  }

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

  void _clearActivePhase() {
    _phase = ZoomGesturePhase.idle;
    _isPartialZoomOutPhase = false;
    _startDistanceRatio = null;
    _startPalmCenter = null;
    _startHandSize = null;
    _phaseStartedAt = null;
    _clearStartPoseCandidate();
  }

  void _clearStartPoseCandidate() {
    _startPoseDirection = ZoomDirection.none;
    _startPoseStartedAt = null;
    _startPoseDistanceRatio = null;
    _startPosePalmCenter = null;
    _startPoseHandSize = null;
  }

  bool _startOrContinueStartPose({
    required ZoomDirection direction,
    required double distanceRatio,
    required DateTime now,
    Offset? palmCenter,
    double? handSize,
  }) {
    if (_startPoseDirection != direction) {
      _setStartPoseCandidate(
        direction: direction,
        distanceRatio: distanceRatio,
        now: now,
        palmCenter: palmCenter,
        handSize: handSize,
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
      );
      return false;
    }

    final currentStartDistance = _startPoseDistanceRatio;

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

  void _setStartPoseCandidate({
    required ZoomDirection direction,
    required double distanceRatio,
    required DateTime now,
    Offset? palmCenter,
    double? handSize,
  }) {
    _startPoseDirection = direction;
    _startPoseStartedAt = now;
    _startPoseDistanceRatio = distanceRatio;
    _startPosePalmCenter = palmCenter;
    _startPoseHandSize = handSize;
  }

  ZoomDirection _detectPartialZoomOut({
    required double distanceRatio,
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
          HandGestureThresholds.partialZoomOutOpenMinImageRatio) {
        final startPoseReady = _startOrContinueStartPose(
          direction: ZoomDirection.zoomOut,
          distanceRatio: distanceRatio,
          now: now,
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
            HandGestureThresholds.partialZoomOutOpenMinImageRatio) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomOut,
            distanceRatio: distanceRatio,
            now: now,
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

  void _armPartialZoomOut({
    required double startDistance,
    required DateTime now,
  }) {
    _clearStartPoseCandidate();
    _directionLock = ZoomDirection.none;
    _phase = ZoomGesturePhase.armedForZoomOut;
    _isPartialZoomOutPhase = true;
    _startDistanceRatio = startDistance;
    _phaseStartedAt = now;
  }

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

    final middleIsClosed = geometry.isFingerFoldedByAngle(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
    );

    final ringIsClosed = geometry.isFingerFoldedByAngle(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
    );

    final pinkyIsClosed = geometry.isFingerFoldedByAngle(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
    );

    return middleIsClosed && ringIsClosed && pinkyIsClosed;
  }

  _ZoomPose? _zoomPose(Hand hand) {
    if (!hand.hasLandmarks) return null;

    if (!_hasOtherFingersClosedByAngle(hand)) {
      return null;
    }

    final thumbTip = _zoomVisibleLandmark(hand, HandLandmarkType.thumbTip);
    final indexTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    if (thumbTip == null || indexTip == null) return null;

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return null;

    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    final handSize = math.max(handWidth, handHeight);

    if (handSize <= 0) return null;

    final tipCenter = Offset(
      (thumbTip.x + indexTip.x) / 2,
      (thumbTip.y + indexTip.y) / 2,
    );

    if (geometry.distanceBetweenOffsets(tipCenter, palmCenter) <=
        handSize * HandGestureThresholds.zoomActiveTipMinPalmDistanceRatio) {
      return null;
    }

    return _ZoomPose(
      distanceRatio:
          geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize,
      palmCenter: palmCenter,
      handSize: handSize,
    );
  }

  double? _partialZoomOutDistanceRatio({
    required Hand hand,
    required Size imageSize,
  }) {
    if (!hand.hasLandmarks || imageSize.width <= 0 || imageSize.height <= 0) {
      return null;
    }

    final thumbTip = _zoomVisibleLandmark(hand, HandLandmarkType.thumbTip);
    final indexTip = _zoomVisibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    if (thumbTip == null || indexTip == null) return null;

    final imageMaxSide = math.max(imageSize.width, imageSize.height);
    if (imageMaxSide <= 0) return null;

    return geometry.distanceBetweenLandmarks(thumbTip, indexTip) / imageMaxSide;
  }

  HandLandmark? _zoomVisibleLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

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

  bool _isPalmStableForStartPose({
    required Offset? palmCenter,
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

  bool _isPalmMovementWithinLimit({
    required Offset startPalmCenter,
    required double startHandSize,
    required Offset currentPalmCenter,
    required double currentHandSize,
  }) {
    final referenceHandSize = math.max(startHandSize, currentHandSize);
    if (referenceHandSize <= 0) return false;

    final maxPalmMovement =
        referenceHandSize * HandGestureThresholds.zoomMaxPalmMovementRatio;

    return geometry.distanceBetweenOffsets(
          startPalmCenter,
          currentPalmCenter,
        ) <=
        maxPalmMovement;
  }
}

class _ZoomPose {
  const _ZoomPose({
    required this.distanceRatio,
    required this.palmCenter,
    required this.handSize,
  });

  final double distanceRatio;
  final Offset palmCenter;
  final double handSize;
}
