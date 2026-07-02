import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/hand_move_direction.dart';
import 'hand_geometry_service.dart';

class DirectionGestureDetector {
  const DirectionGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  HandMoveDirection detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    if (!hand.hasLandmarks || imageSize.width <= 0 || imageSize.height <= 0) {
      return HandMoveDirection.none;
    }

    if (!_hasOnlyDirectionFingersOpen(hand)) {
      return HandMoveDirection.none;
    }

    final fingerTips = <HandLandmark>[];

    for (final type in HandGestureThresholds.directionFingerTipTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) return HandMoveDirection.none;
      fingerTips.add(landmark);
    }

    double visibleX(double rawX) =>
        mirrorHorizontally ? imageSize.width - rawX : rawX;

    final fingerTipXs =
        fingerTips.map((landmark) => visibleX(landmark.x)).toList();
    final fingerTipYs = fingerTips.map((landmark) => landmark.y).toList();

    final minTipX = fingerTipXs.reduce(math.min);
    final maxTipX = fingerTipXs.reduce(math.max);
    final tipXSpread = maxTipX - minTipX;

    final minTipY = fingerTipYs.reduce(math.min);
    final maxTipY = fingerTipYs.reduce(math.max);
    final tipYSpread = maxTipY - minTipY;

    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    final handSize = math.max(handWidth, handHeight);

    final palmReferenceXs = <double>[];
    final palmReferenceYs = <double>[];

    for (final type in HandGestureThresholds.palmReferenceTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) continue;

      palmReferenceXs.add(visibleX(landmark.x));
      palmReferenceYs.add(landmark.y);
    }

    if (palmReferenceXs.isEmpty || palmReferenceYs.isEmpty) {
      final rawCenterX = (box.left + box.right) / 2;
      final rawCenterY = (box.top + box.bottom) / 2;
      palmReferenceXs
        ..clear()
        ..add(visibleX(rawCenterX));
      palmReferenceYs
        ..clear()
        ..add(rawCenterY);
    }

    final fingerTipCenterX = geometry.average(fingerTipXs);
    final fingerTipCenterY = geometry.average(fingerTipYs);
    final palmCenterX = geometry.average(palmReferenceXs);
    final palmCenterY = geometry.average(palmReferenceYs);

    final maxAllowedTipXSpread = math.max(
      imageSize.width * 0.035,
      handSize * HandGestureThresholds.fingerTipVerticalMaxSpreadRatio,
    );

    final bendDeltaX = fingerTipCenterX - palmCenterX;
    final sideBendRatio =
        bendDeltaX > 0
            ? HandGestureThresholds.rightSideBendMinRatio
            : HandGestureThresholds.sideBendMinRatio;
    final minSideBendDistance = math.max(
      imageSize.width * 0.035,
      handSize * sideBendRatio,
    );
    final minRightFingerTipOffset = math.max(
      imageSize.width * 0.020,
      handSize * HandGestureThresholds.rightFingerTipMinOffsetRatio,
    );
    final rightFingerTipAlignedCount =
        fingerTipXs
            .where((tipX) => tipX - palmCenterX >= minRightFingerTipOffset)
            .length;
    final rightFingerTipCandidate =
        bendDeltaX > 0 &&
        rightFingerTipAlignedCount >=
            HandGestureThresholds.rightFingerTipMinAlignedCount;

    final leftRightCandidate =
        tipXSpread <= maxAllowedTipXSpread &&
        bendDeltaX.abs() >= minSideBendDistance;

    final maxAllowedTipYSpread = math.max(
      imageSize.height * 0.035,
      handSize * HandGestureThresholds.fingerTipHorizontalMaxSpreadRatio,
    );

    final bendDeltaY = fingerTipCenterY - palmCenterY;
    final minVerticalBendDistance = math.max(
      imageSize.height * 0.035,
      handSize * HandGestureThresholds.verticalBendMinRatio,
    );

    final upDownCandidate =
        tipYSpread <= maxAllowedTipYSpread &&
        bendDeltaY.abs() >= minVerticalBendDistance;

    if (leftRightCandidate && upDownCandidate) {
      return HandMoveDirection.none;
    }

    if (leftRightCandidate) {
      if (bendDeltaX < 0) return HandMoveDirection.left;
      return HandMoveDirection.right;
    }

    if (rightFingerTipCandidate && !upDownCandidate) {
      return HandMoveDirection.right;
    }

    if (upDownCandidate) {
      if (!_isWristVeryCloseToPalmReferencePoints(hand)) {
        return HandMoveDirection.none;
      }

      if (bendDeltaY < 0) return HandMoveDirection.up;
      return HandMoveDirection.down;
    }

    return HandMoveDirection.none;
  }

  bool _hasOnlyDirectionFingersOpen(Hand hand) {
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

    if (indexTip == null ||
        indexPip == null ||
        middleTip == null ||
        middlePip == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return false;

    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    final handSize = math.max(handWidth, handHeight);

    final indexIsOpen = geometry.isFingerExtended(
      tip: indexTip,
      pip: indexPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final middleIsOpen = geometry.isFingerExtended(
      tip: middleTip,
      pip: middlePip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsOpen = geometry.isFingerExtended(
      tip: ringTip,
      pip: ringPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final pinkyIsOpen = geometry.isFingerExtended(
      tip: pinkyTip,
      pip: pinkyPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    return indexIsOpen && middleIsOpen && ringIsOpen && pinkyIsOpen;
  }

  bool _isWristVeryCloseToPalmReferencePoints(Hand hand) {
    final wrist = geometry.visibleLandmark(hand, HandLandmarkType.wrist);
    if (wrist == null) return false;

    final palmReferencePoints = <HandLandmark>[];

    for (final type in HandGestureThresholds.palmReferenceTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) return false;
      palmReferencePoints.add(landmark);
    }

    if (palmReferencePoints.length !=
        HandGestureThresholds.palmReferenceTypes.length) {
      return false;
    }

    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    final handSize = math.max(handWidth, handHeight);

    if (handSize <= 0) return false;

    final distances =
        palmReferencePoints
            .map((point) => geometry.distanceBetweenLandmarks(wrist, point))
            .toList();

    final averageDistance = geometry.average(distances);
    final maxDistance = distances.reduce(math.max);

    return averageDistance <=
            handSize * HandGestureThresholds.wristToMcpAverageMaxRatio &&
        maxDistance <=
            handSize * HandGestureThresholds.wristToMcpSingleMaxRatio;
  }
}
