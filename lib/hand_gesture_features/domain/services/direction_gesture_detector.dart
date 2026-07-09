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
  final List<_WiggleStep> _wiggleSteps = <_WiggleStep>[];
  int _wiggleCooldownFramesRemaining = 0;
  DateTime? _lastWiggleSampleAt;
  String _debugSummary = 'direction: idle';
  String? _lastPrintedDebugSummary;
  static const double _wiggleAxisDominanceRatio = 1.25;
  static const List<HandMoveDirection> _directionPriority = [
    HandMoveDirection.down,
    HandMoveDirection.right,
    HandMoveDirection.up,
    HandMoveDirection.left,
  ];

  /// Latest short debug explanation for why direction did or did not fire.
  String get debugSummary => _debugSummary;

  /// Clears direction history after a reset, blocked frame, or invalid frame.
  void clearState({String reason = 'reset'}) {
    _resetWiggleState();
    _setDebugSummary('direction: $reason');
  }

  /// Clears the fingertip-wiggle direction state.
  void _resetWiggleState() {
    _smoothedWiggleTips.clear();
    _clearWiggleSteps();
    _wiggleCooldownFramesRemaining = 0;
    _lastWiggleSampleAt = null;
  }

  /// Clears accepted wiggle steps without dropping the smoothed fingertip sample.
  void _clearWiggleSteps() {
    _wiggleSteps.clear();
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
    DateTime? now,
  }) {
    if (!geometry.isReliableHand(hand) ||
        !imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      clearState(reason: 'invalid frame');
      return HandMoveDirection.none;
    }

    final wiggleDirection = _detectFingertipWiggleDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      now: now ?? DateTime.now(),
    );
    final wiggleSummary = _debugSummary;

    // The wiggle path gets priority because it is a deliberate fingertip
    // command. A partial down wiggle also suppresses old left/up/right paths so
    // those directions do not flash while the user completes up -> down -> up.
    if (wiggleDirection != HandMoveDirection.none) {
      if (wiggleDirection == HandMoveDirection.down) {
        return wiggleDirection;
      }
    }

    final fingerChainDirection = _detectFingerChainDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    final selectedDirection = _highestPriorityDirection([
      wiggleDirection,
      fingerChainDirection,
    ]);

    if (selectedDirection == HandMoveDirection.none) {
      return HandMoveDirection.none;
    }

    if (selectedDirection == fingerChainDirection) {
      if (selectedDirection != HandMoveDirection.down &&
          _isDownWiggleInProgress()) {
        _setDebugSummary(
          'direction: down wiggle priority blocked old path '
          '${selectedDirection.name}; $wiggleSummary',
        );
        return HandMoveDirection.none;
      }

      final priorityNote =
          wiggleDirection != HandMoveDirection.none &&
              wiggleDirection != selectedDirection
          ? 'priority selected old path ${selectedDirection.name} '
                'over wiggle ${wiggleDirection.name}'
          : 'old path ${selectedDirection.name}';
      _setDebugSummary('direction: $priorityNote; $wiggleSummary');
      return selectedDirection;
    }

    return selectedDirection;
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

    final candidates = <HandMoveDirection>[];

    if (downPointingFingerCount >=
            HandGestureThresholds.directionFingerChainMinAlignedCount &&
        _hasClearDownShape(
          hand: hand,
          imageSize: imageSize,
          mirrorHorizontally: mirrorHorizontally,
        )) {
      candidates.add(HandMoveDirection.down);
    }

    if (rightPointingFingerCount >=
        HandGestureThresholds.directionFingerChainMinAlignedCount) {
      candidates.add(HandMoveDirection.right);
    }

    if (upPointingFingerCount >=
            HandGestureThresholds.directionFingerChainMinAlignedCount &&
        _isBackSideVisible(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
        )) {
      candidates.add(HandMoveDirection.up);
    }

    if (leftPointingFingerCount >=
        HandGestureThresholds.directionFingerChainMinAlignedCount) {
      candidates.add(HandMoveDirection.left);
    }

    return _highestPriorityDirection(candidates);
  }

  HandMoveDirection _highestPriorityDirection(
    Iterable<HandMoveDirection> candidates,
  ) {
    final candidateSet = candidates
        .where((direction) => direction != HandMoveDirection.none)
        .toSet();

    for (final direction in _directionPriority) {
      if (candidateSet.contains(direction)) return direction;
    }

    return HandMoveDirection.none;
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

  /// Detects small left/right/up/down fingertip wiggles as direction commands.
  HandMoveDirection _detectFingertipWiggleDirection({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required DateTime now,
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

    final lastSampleAt = _lastWiggleSampleAt;
    if (lastSampleAt != null) {
      final sampleGap = now.difference(lastSampleAt);
      if (sampleGap.isNegative) {
        _resetWiggleState();
        _smoothedWiggleTips.addAll(sample.points);
        _lastWiggleSampleAt = now;
        _setDebugSummary(
          'wiggle: clock reset ${sampleGap.inMilliseconds}ms; '
          'baseline tips=${sample.points.length}/4',
        );
        return HandMoveDirection.none;
      }

      if (sampleGap > HandGestureThresholds.directionFingerWiggleMaxSampleGap) {
        _smoothedWiggleTips
          ..clear()
          ..addAll(sample.points);
        _wiggleCooldownFramesRemaining = 0;
        _lastWiggleSampleAt = now;
        _setDebugSummary(
          'wiggle: refreshed baseline after ${sampleGap.inMilliseconds}ms; '
          'tips=${sample.points.length}/4 changes=${_wiggleDirectionChangeCount()}',
        );
        return HandMoveDirection.none;
      }
    }

    if (_smoothedWiggleTips.isEmpty) {
      _smoothedWiggleTips.addAll(sample.points);
      _lastWiggleSampleAt = now;
      _setDebugSummary('wiggle: baseline tips=${sample.points.length}/4');
      return HandMoveDirection.none;
    }

    var movingLeftCount = 0;
    var movingRightCount = 0;
    var movingUpCount = 0;
    var movingDownCount = 0;
    var cleanDownPatternUpCount = 0;
    var cleanDownPatternDownCount = 0;
    var tinyMotionCount = 0;
    var crossAxisDriftCount = 0;
    final nextSmoothedTips = <HandLandmarkType, _NormalizedFingerPoint>{};

    // Smooth fingertip positions relative to the palm so tiny frame-to-frame
    // landmark jitter does not count as a real wiggle.
    for (final type in HandGestureThresholds.directionFingerTipTypes) {
      final current = sample.points[type];
      if (current == null) continue;

      final previous = _smoothedWiggleTips[type];
      final smoothed = previous == null
          ? current
          : previous.lerp(
              current,
              HandGestureThresholds.directionFingerWiggleSmoothingAlpha,
            );
      nextSmoothedTips[type] = smoothed;

      if (previous == null) continue;

      final deltaX = smoothed.x - previous.x;
      final deltaY = smoothed.y - previous.y;
      final absoluteDeltaX = deltaX.abs();
      final absoluteDeltaY = deltaY.abs();
      if (absoluteDeltaX <
              HandGestureThresholds.directionFingerWiggleMinStepRatio &&
          absoluteDeltaY <
              HandGestureThresholds.directionFingerWiggleVerticalMinStepRatio) {
        tinyMotionCount += 1;
        continue;
      }

      final isHorizontalStep =
          absoluteDeltaX >=
              HandGestureThresholds.directionFingerWiggleMinStepRatio &&
          absoluteDeltaX >= absoluteDeltaY * _wiggleAxisDominanceRatio &&
          absoluteDeltaY <=
              HandGestureThresholds.directionFingerWiggleMaxHorizontalStepRatio;
      final isVerticalStep =
          absoluteDeltaY >=
              HandGestureThresholds.directionFingerWiggleVerticalMinStepRatio &&
          absoluteDeltaY >= absoluteDeltaX * _wiggleAxisDominanceRatio &&
          absoluteDeltaX <=
              HandGestureThresholds.directionFingerWiggleMaxHorizontalStepRatio;
      final isCleanDownPatternVerticalStep =
          isVerticalStep &&
          absoluteDeltaY >=
              absoluteDeltaX *
                  HandGestureThresholds
                      .directionFingerWiggleDownVerticalDominanceRatio &&
          absoluteDeltaX <=
              HandGestureThresholds
                  .directionFingerWiggleDownMaxHorizontalStepRatio;

      if (!isHorizontalStep && !isVerticalStep) {
        crossAxisDriftCount += 1;
        continue;
      }

      if (isHorizontalStep) {
        if (deltaX > 0) {
          movingRightCount += 1;
        } else {
          movingLeftCount += 1;
        }
      } else {
        if (deltaY > 0) {
          movingDownCount += 1;
          if (isCleanDownPatternVerticalStep) {
            cleanDownPatternDownCount += 1;
          }
        } else {
          movingUpCount += 1;
          if (isCleanDownPatternVerticalStep) {
            cleanDownPatternUpCount += 1;
          }
        }
      }
    }

    _smoothedWiggleTips
      ..clear()
      ..addAll(nextSmoothedTips);
    _lastWiggleSampleAt = now;

    if (_wiggleCooldownFramesRemaining > 0) {
      _setDebugSummary(
        'wiggle: cooldown=$_wiggleCooldownFramesRemaining '
        'tips=${sample.points.length}/4 left=$movingLeftCount '
        'right=$movingRightCount up=$movingUpCount down=$movingDownCount '
        'tiny=$tinyMotionCount drift=$crossAxisDriftCount',
      );
      _wiggleCooldownFramesRemaining -= 1;
      _clearWiggleSteps();
      return HandMoveDirection.none;
    }

    final alignedDirection = _alignedWiggleStepDirection(
      movingLeftCount: movingLeftCount,
      movingRightCount: movingRightCount,
      movingUpCount: movingUpCount,
      movingDownCount: movingDownCount,
    );

    if (alignedDirection == HandMoveDirection.none) {
      if (crossAxisDriftCount >=
          HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
        _clearWiggleSteps();
      }
      _setDebugSummary(
        'wiggle: waiting tips=${sample.points.length}/4 '
        'left=$movingLeftCount right=$movingRightCount '
        'up=$movingUpCount down=$movingDownCount '
        'tiny=$tinyMotionCount drift=$crossAxisDriftCount '
        'changes=${_wiggleDirectionChangeCount()}',
      );
      return HandMoveDirection.none;
    }

    final isCleanDownPatternStep =
        (alignedDirection == HandMoveDirection.up &&
            cleanDownPatternUpCount >=
                HandGestureThresholds.directionFingerWiggleMinAlignedCount) ||
        (alignedDirection == HandMoveDirection.down &&
            cleanDownPatternDownCount >=
                HandGestureThresholds.directionFingerWiggleMinAlignedCount);

    _recordWiggleStep(
      _WiggleStep(
        direction: alignedDirection,
        isCleanDownPatternStep: isCleanDownPatternStep,
      ),
    );

    final firedDirection = _middleStrokeWiggleDirection();
    if (_wiggleDirectionChangeCount() <
            HandGestureThresholds.directionFingerWiggleMinDirectionChanges ||
        firedDirection == HandMoveDirection.none) {
      _setDebugSummary(
        'wiggle: ${alignedDirection.name} step '
        'tips=${sample.points.length}/4 left=$movingLeftCount '
        'right=$movingRightCount up=$movingUpCount down=$movingDownCount '
        'changes=${_wiggleDirectionChangeCount()}/'
        '${HandGestureThresholds.directionFingerWiggleMinDirectionChanges}',
      );
      return HandMoveDirection.none;
    }

    if (firedDirection == HandMoveDirection.left ||
        firedDirection == HandMoveDirection.up) {
      _setDebugSummary(
        'wiggle: ${firedDirection.name} disabled tips=${sample.points.length}/4 '
        'left=$movingLeftCount right=$movingRightCount '
        'up=$movingUpCount down=$movingDownCount changes='
        '${_wiggleDirectionChangeCount()}',
      );
      _clearWiggleSteps();
      _wiggleCooldownFramesRemaining =
          HandGestureThresholds.directionFingerWiggleCooldownFrames;
      return HandMoveDirection.none;
    }

    _setDebugSummary(
      'wiggle: FIRED ${firedDirection.name} tips=${sample.points.length}/4 '
      'left=$movingLeftCount right=$movingRightCount '
      'up=$movingUpCount down=$movingDownCount changes='
      '${_wiggleDirectionChangeCount()}',
    );
    _clearWiggleSteps();
    _wiggleCooldownFramesRemaining =
        HandGestureThresholds.directionFingerWiggleCooldownFrames;
    return firedDirection;
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

  /// Picks the one direction where enough fingertips moved together.
  HandMoveDirection _alignedWiggleStepDirection({
    required int movingLeftCount,
    required int movingRightCount,
    required int movingUpCount,
    required int movingDownCount,
  }) {
    final alignedDirections = <HandMoveDirection>[];
    if (movingLeftCount >=
        HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
      alignedDirections.add(HandMoveDirection.left);
    }
    if (movingRightCount >=
        HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
      alignedDirections.add(HandMoveDirection.right);
    }
    if (movingUpCount >=
        HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
      alignedDirections.add(HandMoveDirection.up);
    }
    if (movingDownCount >=
        HandGestureThresholds.directionFingerWiggleMinAlignedCount) {
      alignedDirections.add(HandMoveDirection.down);
    }

    return alignedDirections.length == 1
        ? alignedDirections.single
        : HandMoveDirection.none;
  }

  /// Records a new wiggle step, merging repeated frames in the same stroke.
  void _recordWiggleStep(_WiggleStep step) {
    if (_wiggleSteps.isNotEmpty &&
        _wiggleSteps.last.direction == step.direction) {
      final lastIndex = _wiggleSteps.length - 1;
      final lastStep = _wiggleSteps[lastIndex];
      _wiggleSteps[lastIndex] = _WiggleStep(
        direction: lastStep.direction,
        isCleanDownPatternStep:
            lastStep.isCleanDownPatternStep && step.isCleanDownPatternStep,
      );
      return;
    }

    _wiggleSteps.add(step);

    if (_wiggleSteps.length >
        HandGestureThresholds.directionFingerWiggleHistoryMaxLength) {
      _wiggleSteps.removeAt(0);
    }
  }

  /// Counts direction changes in the recent wiggle history.
  int _wiggleDirectionChangeCount() {
    var count = 0;
    for (var i = 1; i < _wiggleSteps.length; i++) {
      if (_wiggleSteps[i].direction != _wiggleSteps[i - 1].direction) {
        count += 1;
      }
    }

    return count;
  }

  /// Returns the middle stroke from an A -> B -> A opposite-direction wiggle.
  HandMoveDirection _middleStrokeWiggleDirection() {
    if (_wiggleSteps.length < 3) return HandMoveDirection.none;

    final lastIndex = _wiggleSteps.length - 1;
    final first = _wiggleSteps[lastIndex - 2];
    final middle = _wiggleSteps[lastIndex - 1];
    final last = _wiggleSteps[lastIndex];

    if (first.direction == last.direction &&
        _areOppositeWiggleDirections(first.direction, middle.direction)) {
      if (middle.direction == HandMoveDirection.down &&
          (!first.isCleanDownPatternStep ||
              !middle.isCleanDownPatternStep ||
              !last.isCleanDownPatternStep)) {
        return HandMoveDirection.none;
      }

      return middle.direction;
    }

    return HandMoveDirection.none;
  }

  bool _isDownWiggleInProgress() {
    if (_wiggleSteps.isEmpty) return false;

    final suffix = <_WiggleStep>[];
    for (final step in _wiggleSteps.reversed) {
      final isVertical =
          step.direction == HandMoveDirection.up ||
          step.direction == HandMoveDirection.down;
      if (!isVertical || !step.isCleanDownPatternStep) break;

      suffix.insert(0, step);
      if (suffix.length == 2) break;
    }

    if (suffix.length == 1) {
      return suffix.first.direction == HandMoveDirection.up;
    }

    if (suffix.length == 2) {
      return suffix.first.direction == HandMoveDirection.up &&
          suffix.last.direction == HandMoveDirection.down;
    }

    return false;
  }

  bool _areOppositeWiggleDirections(
    HandMoveDirection first,
    HandMoveDirection second,
  ) {
    return (first == HandMoveDirection.left &&
            second == HandMoveDirection.right) ||
        (first == HandMoveDirection.right &&
            second == HandMoveDirection.left) ||
        (first == HandMoveDirection.up && second == HandMoveDirection.down) ||
        (first == HandMoveDirection.down && second == HandMoveDirection.up);
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
    return geometry.handSizeFromBoundingBox(hand.boundingBox);
  }
}

/// Snapshot of normalized fingertip positions for wiggle detection.
class _FingerWiggleSample {
  const _FingerWiggleSample(this.points);

  final Map<HandLandmarkType, _NormalizedFingerPoint> points;
}

/// One accepted fingertip wiggle step in recent history.
class _WiggleStep {
  const _WiggleStep({
    required this.direction,
    required this.isCleanDownPatternStep,
  });

  final HandMoveDirection direction;
  final bool isCleanDownPatternStep;
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
