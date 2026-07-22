import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../models/custom_gesture_detection_result.dart';
import 'hand_geometry_service.dart';

/// Detects custom gestures that are not reliable enough from package labels.
class CustomGestureDetector {
  CustomGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  DateTime? _returnToMainDownStartedAt;
  DateTime? _lastCancelEverythingDetectedAt;
  Offset? _punchSteadyHandCenter;
  double? _punchSteadyHandSize;
  int _punchSteadyFrameCount = 0;
  CustomGestureDetectionResult _debugLastResult =
      CustomGestureDetectionResult.empty;

  /// Current normal-preview Punch confirmation progress for debug drawing.
  int get punchSteadyFrameCount => _punchSteadyFrameCount;

  CustomGestureDetectionResult get debugLastResult => _debugLastResult;

  double returnToMainHoldProgress(DateTime now) {
    final startedAt = _returnToMainDownStartedAt;
    if (startedAt == null || now.isBefore(startedAt)) return 0;
    return (now.difference(startedAt).inMilliseconds /
            HandGestureThresholds.returnToMainDownHoldDuration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Evaluates all custom gestures for the current hand frame.
  CustomGestureDetectionResult detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    bool requirePunchConfirmation = false,
    DateTime? now,
  }) {
    if (!geometry.isReliableHand(hand) ||
        !imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      clearState();
      _debugLastResult = CustomGestureDetectionResult.empty;
      return CustomGestureDetectionResult.empty;
    }

    final frameTime = now ?? DateTime.now();

    final result = CustomGestureDetectionResult(
      isCancelEverything: _detectCancelEverythingGesture(
        hand: hand,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
        now: frameTime,
      ),
      isOk: _isOkGesture(hand),
      isCallMe: _isCallMeGesture(hand),
      isPunch: _detectPunchGesture(
        hand,
        requireConfirmation: requirePunchConfirmation,
      ),
    );
    _debugLastResult = result;
    return result;
  }

  /// Clears gesture history after an invalid frame or external reset.
  void clearState() {
    _returnToMainDownStartedAt = null;
    _lastCancelEverythingDetectedAt = null;
    _clearPunchConfirmationState();
    _debugLastResult = CustomGestureDetectionResult.empty;
  }

  /// Detects return-to-main after all four long fingers point down for 1 second.
  bool _detectCancelEverythingGesture({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required DateTime now,
  }) {
    final allLongFingersPointDown = _areAllLongFingersPointingDown(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    if (!allLongFingersPointDown) {
      _returnToMainDownStartedAt = null;
      return _recentCancelEverythingDetected(now);
    }

    final startedAt = _returnToMainDownStartedAt;
    if (startedAt == null || now.isBefore(startedAt)) {
      _returnToMainDownStartedAt = now;
      return _recentCancelEverythingDetected(now);
    }

    if (now.difference(startedAt) <
        HandGestureThresholds.returnToMainDownHoldDuration) {
      return _recentCancelEverythingDetected(now);
    }

    _lastCancelEverythingDetectedAt = now;
    return true;
  }

  bool _areAllLongFingersPointingDown({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final minProjectedLength =
        handSize *
        HandGestureThresholds.returnToMainFingerMinProjectedHandSizeRatio;

    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes) {
      final chain = geometry.visibleFingerChain(hand, chainTypes);
      if (chain == null) return false;

      final descendingOrder = geometry.evaluateDescendingFingerChain(
        chain: chain,
        handSize: handSize,
        minAdjacentGapRatio: HandGestureThresholds
            .returnToMainMinAdjacentVerticalGapHandSizeRatio,
      );
      if (descendingOrder == null || !descendingOrder.matches) return false;

      final jointAngle = geometry.fingerJointAngleDegrees3D(
        mcp: chain[0],
        pip: chain[1],
        tip: chain[3],
      );
      if (jointAngle <
          HandGestureThresholds.returnToMainFingerMinJointAngleDegrees) {
        return false;
      }

      final deltaX = geometry.fingerChainDeltaX(
        chain,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
      );
      final deltaY = geometry.fingerChainDeltaY(chain);
      final projectedLength = math.sqrt(deltaX * deltaX + deltaY * deltaY);

      if (projectedLength < minProjectedLength ||
          deltaY <= 0 ||
          deltaY.abs() < deltaX.abs() ||
          geometry.isFingerChainDepthDominant(
            chain: chain,
            deltaX: deltaX,
            deltaY: deltaY,
          )) {
        return false;
      }
    }

    return true;
  }

  /// Detects the OK sign used to start recording.
  bool _isOkGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);

    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );
    final indexPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerPIP,
    );
    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    final middleMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );
    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );

    final ringMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerMCP,
    );
    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );

    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (thumbTip == null ||
        indexMcp == null ||
        indexPip == null ||
        indexTip == null ||
        middleMcp == null ||
        middleTip == null ||
        middlePip == null ||
        ringMcp == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyMcp == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final thumbIndexDistance = geometry.distanceBetweenLandmarks3D(
      thumbTip,
      indexTip,
    );
    final maxTouchDistance = math.max(
      handSize * HandGestureThresholds.okTouchMaxDistanceRatio,
      12.0,
    );

    final thumbAndIndexTouch = thumbIndexDistance <= maxTouchDistance;

    final indexBendAngle = geometry.fingerJointAngleDegrees3D(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexTip,
    );

    final indexIsBentForOk = indexBendAngle <= 150.0;

    final middleIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final pinkyIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    return thumbAndIndexTouch &&
        indexIsBentForOk &&
        middleIsOpen &&
        ringIsOpen &&
        pinkyIsOpen;
  }

  /// Detects the call-me sign used to start face detection.
  bool _isCallMeGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    final indexPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerPIP,
    );
    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );
    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (thumbTip == null ||
        thumbIp == null ||
        indexTip == null ||
        indexPip == null ||
        middleTip == null ||
        middlePip == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);

    final thumbIsOpen =
        geometry.distanceToPoint3D(thumbTip, palmCenter) >
            geometry.distanceToPoint3D(thumbIp, palmCenter) *
                HandGestureThresholds.thumbExtendedRatio &&
        geometry.distanceToPoint3D(thumbTip, palmCenter) > handSize * 0.23;

    final pinkyIsOpen = geometry.isFingerExtended3D(
      tip: pinkyTip,
      pip: pinkyPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final indexIsClosed = geometry.isFingerFolded3D(
      tip: indexTip,
      pip: indexPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final middleIsClosed = geometry.isFingerFolded3D(
      tip: middleTip,
      pip: middlePip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsClosed = geometry.isFingerFolded3D(
      tip: ringTip,
      pip: ringPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final thumbAndPinkyAreSeparated =
        geometry.distanceBetweenLandmarks3D(thumbTip, pinkyTip) >
        handSize * 0.55;

    return thumbIsOpen &&
        pinkyIsOpen &&
        thumbAndPinkyAreSeparated &&
        indexIsClosed &&
        middleIsClosed &&
        ringIsClosed;
  }

  /// Detects Punch from the compact landmark circle alone.
  ///
  /// Package gesture type and confidence are deliberately ignored: the
  /// All-21-points circle and wrist-inside checks are the gesture gate.
  bool _isPunchGesture(Hand hand) {
    return geometry.matchesPunchMiddleFingerCircle(hand);
  }

  /// Keeps raw one-frame punch recognition for recording controls, while the
  /// normal preview can opt into a steady three-frame confirmation.
  bool _detectPunchGesture(Hand hand, {required bool requireConfirmation}) {
    final matchesPunch = _isPunchGesture(hand);
    if (!requireConfirmation) {
      _clearPunchConfirmationState();
      return matchesPunch;
    }

    if (!matchesPunch) {
      _clearPunchConfirmationState();
      return false;
    }

    final box = hand.boundingBox;
    final currentCenter = Offset(
      (box.left + box.right) / 2,
      (box.top + box.bottom) / 2,
    );
    final currentHandSize = geometry.handSizeFromBoundingBox(box);
    if (!currentCenter.dx.isFinite ||
        !currentCenter.dy.isFinite ||
        !currentHandSize.isFinite ||
        currentHandSize <= 0) {
      _clearPunchConfirmationState();
      return false;
    }

    final anchorCenter = _punchSteadyHandCenter;
    final anchorHandSize = _punchSteadyHandSize;
    if (anchorCenter == null || anchorHandSize == null) {
      _punchSteadyHandCenter = currentCenter;
      _punchSteadyHandSize = currentHandSize;
      _punchSteadyFrameCount = 1;
      return false;
    }

    final referenceHandSize = math.max(anchorHandSize, currentHandSize);
    final movementRatio =
        geometry.distanceBetweenOffsets(anchorCenter, currentCenter) /
        referenceHandSize;
    if (!movementRatio.isFinite ||
        movementRatio > HandGestureThresholds.punchMaxHandCenterMovementRatio) {
      _punchSteadyHandCenter = currentCenter;
      _punchSteadyHandSize = currentHandSize;
      // The frame that proves movement does not count as a steady frame.
      _punchSteadyFrameCount = 0;
      return false;
    }

    _punchSteadyFrameCount = math.min(
      _punchSteadyFrameCount + 1,
      HandGestureThresholds.punchRequiredConsecutiveFrames,
    );
    return _punchSteadyFrameCount >=
        HandGestureThresholds.punchRequiredConsecutiveFrames;
  }

  void _clearPunchConfirmationState() {
    _punchSteadyHandCenter = null;
    _punchSteadyHandSize = null;
    _punchSteadyFrameCount = 0;
  }

  /// Holds the return-to-main result briefly so the UI does not flicker.
  bool _recentCancelEverythingDetected(DateTime now) {
    final lastDetectedAt = _lastCancelEverythingDetectedAt;
    return lastDetectedAt != null &&
        now.difference(lastDetectedAt) <=
            HandGestureThresholds.cancelEverythingHoldDuration;
  }

  /// Uses the hand bounding box as the scale reference for ratio thresholds.
  double _handSize(Hand hand) {
    return geometry.handSizeFromBoundingBox(hand.boundingBox);
  }
}
