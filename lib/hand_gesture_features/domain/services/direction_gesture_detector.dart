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

    return _detectFingerChainDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );
  }

  HandMoveDirection _detectFingerChainDirection({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    double visibleX(double rawX) =>
        mirrorHorizontally ? imageSize.width - rawX : rawX;

    final fingerChains = <List<HandLandmark>>[];
    final pointXs = <double>[];
    final pointYs = <double>[];

    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes) {
      final chain = geometry.visibleFingerChain(hand, chainTypes);
      if (chain == null) return HandMoveDirection.none;

      if (!_isFingerChainExtended(chain)) continue;

      fingerChains.add(chain);

      for (final landmark in chain) {
        pointXs.add(visibleX(landmark.x));
        pointYs.add(landmark.y);
      }
    }

    if (fingerChains.length <
            HandGestureThresholds.directionFingerChainMinAlignedCount ||
        pointXs.isEmpty ||
        pointYs.isEmpty) {
      return HandMoveDirection.none;
    }

    final fingerPointWidth =
        pointXs.reduce(math.max) - pointXs.reduce(math.min);
    final fingerPointHeight =
        pointYs.reduce(math.max) - pointYs.reduce(math.min);
    final fingerPointSpan = math.max(fingerPointWidth, fingerPointHeight);

    if (fingerPointSpan <= 0) return HandMoveDirection.none;

    final minHorizontalDistance = math.max(
      imageSize.width *
          HandGestureThresholds.directionFingerChainMinHorizontalImageRatio,
      fingerPointSpan *
          HandGestureThresholds.directionFingerChainMinHorizontalSpanRatio,
    );
    final minVerticalDistance = math.max(
      imageSize.height *
          HandGestureThresholds.directionFingerChainMinVerticalImageRatio,
      fingerPointSpan *
          HandGestureThresholds.directionFingerChainMinVerticalSpanRatio,
    );

    var leftPointingFingerCount = 0;
    var rightPointingFingerCount = 0;
    var upPointingFingerCount = 0;
    var downPointingFingerCount = 0;
    var totalDeltaX = 0.0;
    var totalDeltaY = 0.0;

    for (final chain in fingerChains) {
      final deltaX = geometry.fingerChainDeltaX(
        chain,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
      );
      final deltaY = geometry.fingerChainDeltaY(chain);

      if (geometry.isFingerChainDepthDominant(
        chain: chain,
        deltaX: deltaX,
        deltaY: deltaY,
      )) {
        continue;
      }

      totalDeltaX += deltaX;
      totalDeltaY += deltaY;

      if (deltaX.abs() >= minHorizontalDistance) {
        final isUpwardDiagonal =
            deltaY < 0 &&
            deltaX.abs() >=
                deltaY.abs() *
                    HandGestureThresholds
                        .directionFingerChainUpDiagonalHorizontalRatio;

        if (deltaX < 0 &&
            (isUpwardDiagonal ||
                deltaX.abs() >=
                    deltaY.abs() *
                        HandGestureThresholds
                            .directionFingerChainHorizontalDominanceRatio)) {
          leftPointingFingerCount += 1;
        } else if (deltaX > 0 &&
            (isUpwardDiagonal ||
                deltaX.abs() >=
                    deltaY.abs() *
                        HandGestureThresholds
                            .directionFingerChainRightDominanceRatio)) {
          rightPointingFingerCount += 1;
        }
      }

      if (deltaY.abs() >= minVerticalDistance &&
          deltaY.abs() >=
              deltaX.abs() *
                  HandGestureThresholds
                      .directionFingerChainVerticalDominanceRatio) {
        if (deltaY < 0) {
          upPointingFingerCount += 1;
        } else {
          downPointingFingerCount += 1;
        }
      }
    }

    final horizontalDirection =
        leftPointingFingerCount >=
            HandGestureThresholds.directionFingerChainMinAlignedCount
        ? HandMoveDirection.left
        : rightPointingFingerCount >=
              HandGestureThresholds.directionFingerChainMinAlignedCount
        ? HandMoveDirection.right
        : HandMoveDirection.none;
    final verticalDirection =
        upPointingFingerCount >=
            HandGestureThresholds.directionFingerChainMinAlignedCount
        ? HandMoveDirection.up
        : downPointingFingerCount >=
              HandGestureThresholds.directionFingerChainMinAlignedCount
        ? HandMoveDirection.down
        : HandMoveDirection.none;

    final HandMoveDirection selectedDirection;
    if (horizontalDirection != HandMoveDirection.none &&
        verticalDirection != HandMoveDirection.none) {
      selectedDirection = verticalDirection == HandMoveDirection.up
          ? horizontalDirection
          : totalDeltaY.abs() > totalDeltaX.abs()
          ? verticalDirection
          : horizontalDirection;
    } else if (horizontalDirection != HandMoveDirection.none) {
      selectedDirection = horizontalDirection;
    } else {
      selectedDirection = verticalDirection;
    }

    if (selectedDirection == HandMoveDirection.up &&
        !_isBackSideVisible(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
        )) {
      return HandMoveDirection.none;
    }

    if (selectedDirection == HandMoveDirection.down &&
        !_hasClearDownShape(
          hand: hand,
          imageSize: imageSize,
          mirrorHorizontally: mirrorHorizontally,
        )) {
      return HandMoveDirection.none;
    }

    return selectedDirection;
  }

  bool _isFingerChainExtended(List<HandLandmark> chain) {
    return geometry.isFingerChainExtended3D(chain);
  }

  bool _hasClearDownShape({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    final downFingerCount = geometry.downwardExtendedFingerChainCount(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    if (downFingerCount <
        HandGestureThresholds.directionFingerChainMinAlignedCount) {
      return false;
    }

    final palmCenter = geometry.palmCenter3D(hand);
    final handSize = _handSize(hand);

    if (palmCenter == null || handSize <= 0) return false;

    final foldedFingerCount = geometry.foldedLongFingerCount3D(
      hand: hand,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    return foldedFingerCount <
        HandGestureThresholds.directionDownRejectFoldedLongFingerCount;
  }

  bool _isBackSideVisible({
    required Hand hand,
    required bool mirrorHorizontally,
  }) {
    final handedness = hand.handedness;
    final wrist = geometry.visibleLandmark(hand, HandLandmarkType.wrist);
    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );
    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);
    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);

    if (handedness == null ||
        wrist == null ||
        indexMcp == null ||
        pinkyMcp == null ||
        thumbTip == null) {
      return false;
    }

    var expectedPalmSide = handedness == Handedness.right ? 1.0 : -1.0;
    if (mirrorHorizontally) {
      expectedPalmSide *= -1;
    }

    final knuckleSide = _normalizedCross(
      origin: wrist,
      first: indexMcp,
      second: pinkyMcp,
    );
    final thumbSide = _normalizedCross(
      origin: indexMcp,
      first: pinkyMcp,
      second: thumbTip,
    );

    final knuckleBackSideScore = _inverseLerp(
      0.10,
      0.35,
      -knuckleSide * expectedPalmSide,
    );
    final thumbBackSideScore = _inverseLerp(
      0.08,
      0.25,
      -thumbSide * expectedPalmSide,
    );
    final confidence = (knuckleBackSideScore * 0.75 + thumbBackSideScore * 0.25)
        .clamp(0.0, 1.0);

    return confidence >=
        HandGestureThresholds.directionMovingUpMinBackSideConfidence;
  }

  double _normalizedCross({
    required HandLandmark origin,
    required HandLandmark first,
    required HandLandmark second,
  }) {
    final firstX = first.x - origin.x;
    final firstY = first.y - origin.y;
    final secondX = second.x - origin.x;
    final secondY = second.y - origin.y;
    final firstLength = math.sqrt(firstX * firstX + firstY * firstY);
    final secondLength = math.sqrt(secondX * secondX + secondY * secondY);

    if (firstLength == 0 || secondLength == 0) return 0;

    return ((firstX * secondY - firstY * secondX) /
            (firstLength * secondLength))
        .clamp(-1.0, 1.0);
  }

  double _inverseLerp(double start, double end, double value) {
    if (start == end) return value >= end ? 1 : 0;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  double _handSize(Hand hand) {
    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    return math.max(handWidth, handHeight);
  }
}
