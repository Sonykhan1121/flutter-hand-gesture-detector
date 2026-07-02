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
      final chain = <HandLandmark>[];

      for (final type in chainTypes) {
        final landmark = geometry.visibleLandmark(hand, type);
        if (landmark == null) return HandMoveDirection.none;

        chain.add(landmark);
        pointXs.add(visibleX(landmark.x));
        pointYs.add(landmark.y);
      }

      fingerChains.add(chain);
    }

    if (pointXs.isEmpty || pointYs.isEmpty) return HandMoveDirection.none;

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
      final deltaX =
          visibleX(chain[1].x) -
          visibleX(chain[0].x) +
          visibleX(chain[2].x) -
          visibleX(chain[1].x) +
          visibleX(chain[3].x) -
          visibleX(chain[2].x);
      final deltaY =
          chain[1].y -
          chain[0].y +
          chain[2].y -
          chain[1].y +
          chain[3].y -
          chain[2].y;

      totalDeltaX += deltaX;
      totalDeltaY += deltaY;

      if (deltaX.abs() >= minHorizontalDistance &&
          deltaX.abs() >=
              deltaY.abs() *
                  HandGestureThresholds
                      .directionFingerChainHorizontalDominanceRatio) {
        if (deltaX < 0) {
          leftPointingFingerCount += 1;
        } else {
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

    if (horizontalDirection != HandMoveDirection.none &&
        verticalDirection != HandMoveDirection.none) {
      return totalDeltaY.abs() > totalDeltaX.abs()
          ? verticalDirection
          : horizontalDirection;
    }

    if (horizontalDirection != HandMoveDirection.none) {
      return horizontalDirection;
    }

    return verticalDirection;
  }
}
