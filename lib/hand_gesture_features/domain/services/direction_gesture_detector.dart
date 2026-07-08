import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/hand_move_direction.dart';
import 'hand_geometry_service.dart';

/// Detects left, right, up, and down movement gestures from finger landmarks.
class DirectionGestureDetector {
  DirectionGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;
  final Map<HandLandmarkType, _NormalizedFingerPoint> _smoothedWiggleTips =
      <HandLandmarkType, _NormalizedFingerPoint>{};
  final List<int> _wiggleStepSigns = <int>[];
  int _wiggleCooldownFramesRemaining = 0;
  String _debugSummary = 'direction: idle';
  String? _lastPrintedDebugSummary;

  /// Latest short debug explanation for why direction did or did not fire.
  String get debugSummary => _debugSummary;

  /// Clears direction history after a reset, blocked frame, or invalid frame.
  void clearState({String reason = 'reset'}) {
    _resetWiggleState();
    _setDebugSummary('direction: $reason');
  }

  /// Clears the fingertip-wiggle moving-down state.
  void _resetWiggleState() {
    _smoothedWiggleTips.clear();
    _wiggleStepSigns.clear();
    _wiggleCooldownFramesRemaining = 0;
  }

  /// Stores and optionally prints one compact debug line.
  void _setDebugSummary(String value) {
    _debugSummary = value;

    if (!kDebugMode || _lastPrintedDebugSummary == value) return;

    _lastPrintedDebugSummary = value;
    debugPrint('[DirectionGestureDetector] $value');
  }

  /// Detects one direction from the current hand frame.
  HandMoveDirection detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    if (!hand.hasLandmarks || imageSize.width <= 0 || imageSize.height <= 0) {
      clearState(reason: 'invalid frame');
      return HandMoveDirection.none;
    }

    final fingerChainDirection = _detectFingerChainDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    final wiggleDirection = _detectFingertipWiggleDown(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );
    final wiggleSummary = _debugSummary;

    // The wiggle path gets priority because it is a deliberate "down" fallback
    // when finger-chain direction is not clear enough.
    if (wiggleDirection == HandMoveDirection.down) {
      return wiggleDirection;
    }

    if (fingerChainDirection != HandMoveDirection.none) {
      _setDebugSummary(
        'direction: old path ${fingerChainDirection.name}; $wiggleSummary',
      );
      return fingerChainDirection;
    }

    return HandMoveDirection.none;
  }

  /// Detects direction by checking aligned extended finger chains.
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

    // Count how many long fingers agree on the same direction. A single finger
    // can be noisy, so the detector requires several aligned chains.
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
      selectedDirection =
          verticalDirection == HandMoveDirection.up
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

  /// Delegates extended-chain testing to the shared 3D geometry service.
  bool _isFingerChainExtended(List<HandLandmark> chain) {
    return geometry.isFingerChainExtended3D(chain);
  }

  /// Ensures "down" is not confused with a folded fist or depth motion.
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

  /// Detects the small up/down fingertip wiggle used as an alternate down cue.
  HandMoveDirection _detectFingertipWiggleDown({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    final sample = _fingerWiggleSample(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    if (sample == null) {
      _resetWiggleState();
      return HandMoveDirection.none;
    }

    if (_smoothedWiggleTips.isEmpty) {
      _smoothedWiggleTips.addAll(sample.points);
      _setDebugSummary('wiggle: baseline tips=${sample.points.length}/4');
      return HandMoveDirection.none;
    }

    var movingUpCount = 0;
    var movingDownCount = 0;
    var tinyMotionCount = 0;
    var horizontalDriftCount = 0;
    final nextSmoothedTips = <HandLandmarkType, _NormalizedFingerPoint>{};

    // Smooth fingertip positions relative to the palm so tiny frame-to-frame
    // landmark jitter does not count as a real wiggle.
    for (final type in HandGestureThresholds.directionFingerTipTypes) {
      final current = sample.points[type];
      if (current == null) continue;

      final previous = _smoothedWiggleTips[type];
      final smoothed =
          previous == null
              ? current
              : previous.lerp(
                current,
                HandGestureThresholds.directionFingerWiggleSmoothingAlpha,
              );
      nextSmoothedTips[type] = smoothed;

      if (previous == null) continue;

      final deltaX = smoothed.x - previous.x;
      final deltaY = smoothed.y - previous.y;
      if (deltaY.abs() <
          HandGestureThresholds.directionFingerWiggleMinStepRatio) {
        tinyMotionCount += 1;
        continue;
      }

      if (deltaX.abs() >
          HandGestureThresholds.directionFingerWiggleMaxHorizontalStepRatio) {
        horizontalDriftCount += 1;
        continue;
      }

      if (deltaY > 0) {
        movingDownCount += 1;
      } else {
        movingUpCount += 1;
      }
    }

    _smoothedWiggleTips
      ..clear()
      ..addAll(nextSmoothedTips);

    if (_wiggleCooldownFramesRemaining > 0) {
      _setDebugSummary(
        'wiggle: cooldown=$_wiggleCooldownFramesRemaining '
        'tips=${sample.points.length}/4 up=$movingUpCount '
        'down=$movingDownCount tiny=$tinyMotionCount '
        'drift=$horizontalDriftCount',
      );
      _wiggleCooldownFramesRemaining -= 1;
      _wiggleStepSigns.clear();
      return HandMoveDirection.none;
    }

    final alignedSign =
        movingDownCount >=
                HandGestureThresholds.directionFingerWiggleMinAlignedCount
            ? 1
            : movingUpCount >=
                HandGestureThresholds.directionFingerWiggleMinAlignedCount
            ? -1
            : 0;

    if (alignedSign == 0) {
      _setDebugSummary(
        'wiggle: waiting tips=${sample.points.length}/4 '
        'up=$movingUpCount down=$movingDownCount '
        'tiny=$tinyMotionCount drift=$horizontalDriftCount '
        'changes=${_wiggleDirectionChangeCount()}',
      );
      return HandMoveDirection.none;
    }

    _recordWiggleStepSign(alignedSign);

    if (_wiggleDirectionChangeCount() <
        HandGestureThresholds.directionFingerWiggleMinDirectionChanges) {
      _setDebugSummary(
        'wiggle: ${alignedSign > 0 ? 'down' : 'up'} step '
        'tips=${sample.points.length}/4 up=$movingUpCount '
        'down=$movingDownCount changes=${_wiggleDirectionChangeCount()}/'
        '${HandGestureThresholds.directionFingerWiggleMinDirectionChanges}',
      );
      return HandMoveDirection.none;
    }

    _setDebugSummary(
      'wiggle: FIRED tips=${sample.points.length}/4 '
      'up=$movingUpCount down=$movingDownCount changes='
      '${_wiggleDirectionChangeCount()}',
    );
    _wiggleStepSigns.clear();
    _wiggleCooldownFramesRemaining =
        HandGestureThresholds.directionFingerWiggleCooldownFrames;
    return HandMoveDirection.down;
  }

  /// Builds a palm-relative fingertip sample for wiggle detection.
  _FingerWiggleSample? _fingerWiggleSample({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    final palmCenter = geometry.palmCenter3D(hand);
    final handSize = _handSize(hand);

    if (palmCenter == null || handSize <= 0) {
      _setDebugSummary('wiggle: no palm/hand size');
      return null;
    }

    double visibleX(double rawX) =>
        mirrorHorizontally ? imageSize.width - rawX : rawX;

    final points = <HandLandmarkType, _NormalizedFingerPoint>{};
    for (final type in HandGestureThresholds.directionFingerTipTypes) {
      final tip = geometry.visibleLandmark(hand, type);
      if (tip == null) continue;

      points[type] = _NormalizedFingerPoint(
        x: (visibleX(tip.x) - visibleX(palmCenter.x)) / handSize,
        y: (tip.y - palmCenter.y) / handSize,
      );
    }

    if (points.length <
        HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
      _setDebugSummary('wiggle: low visibility tips=${points.length}/4');
      return null;
    }

    return _FingerWiggleSample(points);
  }

  /// Records a new up/down step only when it changes direction.
  void _recordWiggleStepSign(int sign) {
    if (_wiggleStepSigns.isNotEmpty && _wiggleStepSigns.last == sign) {
      return;
    }

    _wiggleStepSigns.add(sign);

    if (_wiggleStepSigns.length >
        HandGestureThresholds.directionFingerWiggleHistoryMaxLength) {
      _wiggleStepSigns.removeAt(0);
    }
  }

  /// Counts alternating up/down steps in the recent wiggle history.
  int _wiggleDirectionChangeCount() {
    var count = 0;
    for (var i = 1; i < _wiggleStepSigns.length; i++) {
      if (_wiggleStepSigns[i] != _wiggleStepSigns[i - 1]) {
        count += 1;
      }
    }

    return count;
  }

  /// Confirms the back of the hand is visible before accepting moving up.
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

  /// Normalized signed cross product for palm orientation checks.
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

  /// Converts a threshold range into a clamped 0..1 score.
  double _inverseLerp(double start, double end, double value) {
    if (start == end) return value >= end ? 1 : 0;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  /// Uses hand bounding-box size as the scale reference for thresholds.
  double _handSize(Hand hand) {
    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    return math.max(handWidth, handHeight);
  }
}

/// Snapshot of normalized fingertip positions for wiggle detection.
class _FingerWiggleSample {
  const _FingerWiggleSample(this.points);

  final Map<HandLandmarkType, _NormalizedFingerPoint> points;
}

/// Palm-relative fingertip coordinate normalized by hand size.
class _NormalizedFingerPoint {
  const _NormalizedFingerPoint({required this.x, required this.y});

  final double x;
  final double y;

  /// Moves this point toward [other] by [amount] for exponential smoothing.
  _NormalizedFingerPoint lerp(_NormalizedFingerPoint other, double amount) {
    return _NormalizedFingerPoint(
      x: x + (other.x - x) * amount,
      y: y + (other.y - y) * amount,
    );
  }
}
