import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/zoom_direction.dart';
import '../enums/zoom_gesture_phase.dart';
import 'hand_geometry_service.dart';

class ZoomGestureDetector {
  ZoomGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  ZoomGesturePhase _phase = ZoomGesturePhase.idle;
  ZoomDirection _directionLock = ZoomDirection.none;
  bool _isPartialZoomOutPhase = false;
  double? _startDistanceRatio;
  DateTime? _phaseStartedAt;
  DateTime? _poseInvalidStartedAt;
  DateTime? _lastZoomInDetectedAt;
  DateTime? _lastZoomOutDetectedAt;

  ZoomDirection _startPoseDirection = ZoomDirection.none;
  DateTime? _startPoseStartedAt;
  double? _startPoseDistanceRatio;

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
    final now = DateTime.now();
    final distanceRatio = _zoomDistanceRatio(hand);

    if (distanceRatio == null) {
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
        );

        if (startPoseReady) {
          final startDistance = _startPoseDistanceRatio ?? distanceRatio;

          _clearStartPoseCandidate();
          _directionLock = ZoomDirection.none;
          _phase = ZoomGesturePhase.armedForZoomIn;
          _startDistanceRatio = startDistance;
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
        );

        if (startPoseReady) {
          final startDistance = _startPoseDistanceRatio ?? distanceRatio;

          _clearStartPoseCandidate();
          _directionLock = ZoomDirection.none;
          _phase = ZoomGesturePhase.armedForZoomOut;
          _startDistanceRatio = startDistance;
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
          );

          if (startPoseReady) {
            final startDistance = _startPoseDistanceRatio ?? distanceRatio;

            _clearStartPoseCandidate();
            _phase = ZoomGesturePhase.armedForZoomIn;
            _startDistanceRatio = startDistance;
            _phaseStartedAt = now;
          }
        } else if (distanceRatio >=
            HandGestureThresholds.zoomOpenMinDistanceRatio) {
          final startPoseReady = _startOrContinueStartPose(
            direction: ZoomDirection.zoomOut,
            distanceRatio: distanceRatio,
            now: now,
          );

          if (startPoseReady) {
            final startDistance = _startPoseDistanceRatio ?? distanceRatio;

            _clearStartPoseCandidate();
            _phase = ZoomGesturePhase.armedForZoomOut;
            _startDistanceRatio = startDistance;
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
    _phaseStartedAt = null;
    _clearStartPoseCandidate();
  }

  void _clearStartPoseCandidate() {
    _startPoseDirection = ZoomDirection.none;
    _startPoseStartedAt = null;
    _startPoseDistanceRatio = null;
  }

  bool _startOrContinueStartPose({
    required ZoomDirection direction,
    required double distanceRatio,
    required DateTime now,
  }) {
    if (_startPoseDirection != direction) {
      _startPoseDirection = direction;
      _startPoseStartedAt = now;
      _startPoseDistanceRatio = distanceRatio;
      return false;
    }

    final startedAt = _startPoseStartedAt;
    if (startedAt == null) {
      _startPoseStartedAt = now;
      _startPoseDistanceRatio = distanceRatio;
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

  double? _zoomDistanceRatio(Hand hand) {
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

    return geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize;
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
}
