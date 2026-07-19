import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/hand_move_direction.dart';
import 'hand_geometry_service.dart';

/// Detects a static left, right, up, or down index-finger pointing pose.
class DirectionGestureDetector {
  DirectionGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  static const double _angleComparisonEpsilon = 1e-9;

  HandMoveDirection _activeDirection = HandMoveDirection.none;
  int _movingLeftPositiveFrames = 0;
  int _movingRightPositiveFrames = 0;
  int _movingDownPositiveFrames = 0;
  String _debugSummary = 'direction: idle';
  String? _lastPrintedDebugSummary;

  static const List<HandLandmarkType> _horizontalRequiredTypes = [
    HandLandmarkType.wrist,
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.indexFingerPIP,
    HandLandmarkType.indexFingerDIP,
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.middleFingerPIP,
    HandLandmarkType.middleFingerDIP,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.ringFingerPIP,
    HandLandmarkType.ringFingerDIP,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyMCP,
    HandLandmarkType.pinkyPIP,
    HandLandmarkType.pinkyDIP,
    HandLandmarkType.pinkyTip,
  ];

  static const List<HandLandmarkType> _verticalRequiredTypes = [
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.indexFingerPIP,
    HandLandmarkType.indexFingerDIP,
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.middleFingerPIP,
    HandLandmarkType.middleFingerDIP,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.ringFingerPIP,
    HandLandmarkType.ringFingerDIP,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyMCP,
    HandLandmarkType.pinkyPIP,
    HandLandmarkType.pinkyDIP,
    HandLandmarkType.pinkyTip,
  ];

  static const List<HandLandmarkType> _movingDownRequiredTypes = [
    HandLandmarkType.indexFingerPIP,
    HandLandmarkType.indexFingerDIP,
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.middleFingerPIP,
    HandLandmarkType.middleFingerDIP,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.ringFingerPIP,
    HandLandmarkType.ringFingerDIP,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyMCP,
    HandLandmarkType.pinkyPIP,
    HandLandmarkType.pinkyDIP,
    HandLandmarkType.pinkyTip,
  ];

  /// Latest short debug explanation for why direction did or did not fire.
  String get debugSummary => _debugSummary;

  /// Clears the held sector after a reset, blocked frame, or invalid pose.
  void clearState({String reason = 'reset'}) {
    _activeDirection = HandMoveDirection.none;
    _movingLeftPositiveFrames = 0;
    _movingRightPositiveFrames = 0;
    _movingDownPositiveFrames = 0;
    _setDebugSummary('direction: $reason');
  }

  /// Detects one direction from the current static index-pointing pose.
  HandMoveDirection detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    if (!geometry.isReliableHand(hand) || !_isFiniteImageSize(imageSize)) {
      clearState(reason: 'invalid frame');
      return HandMoveDirection.none;
    }

    final zoomInConflictAngle = _zoomInConflictAngleDegrees(hand);
    if (zoomInConflictAngle != null) {
      clearState(
        reason:
            'zoom-in thumb/index geometry; '
            'angle=${zoomInConflictAngle.toStringAsFixed(1)}deg',
      );
      return HandMoveDirection.none;
    }

    if (geometry.isReliablePackageGesture(
      hand.gesture,
      type: GestureType.pointingUp,
    )) {
      _activeDirection = HandMoveDirection.up;
      _movingLeftPositiveFrames = 0;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: package pointingUp -> static up');
      return HandMoveDirection.up;
    }

    if (_activeDirection == HandMoveDirection.up ||
        _activeDirection == HandMoveDirection.down) {
      final activeVerticalDirection = _activeDirection;
      final activeVertical = _evaluateVerticalDirection(
        hand: hand,
        mirrorHorizontally: mirrorHorizontally,
        direction: activeVerticalDirection,
        useActiveDirectionRange: true,
      );
      if (activeVertical.matches) {
        _movingLeftPositiveFrames = 0;
        _movingRightPositiveFrames = 0;
        _movingDownPositiveFrames =
            activeVerticalDirection == HandMoveDirection.down
            ? HandGestureThresholds.movingDownRequiredConsecutiveFrames
            : 0;
        _setDebugSummary(
          'direction: static ${activeVerticalDirection.name}; '
          'angle=${activeVertical.directionAngleDegrees!.toStringAsFixed(1)}deg',
        );
        return activeVerticalDirection;
      }

      _movingDownPositiveFrames = 0;
      final activeVerticalCandidateAngle =
          activeVertical.directionAngleDegrees ??
          _visibleVerticalDirectionAngleDegrees(
            hand: hand,
            mirrorHorizontally: mirrorHorizontally,
            direction: activeVerticalDirection,
          );
      if (activeVerticalCandidateAngle case final angle?
          when _isVerticalDirectionAngle(
            angle,
            direction: activeVerticalDirection,
            active: true,
          )) {
        _activeDirection = HandMoveDirection.none;
        _movingLeftPositiveFrames = 0;
        _movingRightPositiveFrames = 0;
        _setDebugSummary(
          'direction: ${activeVerticalDirection.name} rejected; '
          '${activeVertical.reason}',
        );
        return HandMoveDirection.none;
      }

      _activeDirection = HandMoveDirection.none;
    }

    final movingLeft = _evaluateHorizontalDirection(
      hand: hand,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.left,
    );
    if (movingLeft.matches) {
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _movingLeftPositiveFrames = math.min(
        _movingLeftPositiveFrames + 1,
        HandGestureThresholds.movingLeftRequiredConsecutiveFrames,
      );

      if (_movingLeftPositiveFrames <
          HandGestureThresholds.movingLeftRequiredConsecutiveFrames) {
        _activeDirection = HandMoveDirection.none;
        _setDebugSummary(
          'direction: confirming left '
          '$_movingLeftPositiveFrames/'
          '${HandGestureThresholds.movingLeftRequiredConsecutiveFrames}; '
          'angle=${movingLeft.directionAngleDegrees!.toStringAsFixed(1)}deg',
        );
        return HandMoveDirection.none;
      }

      _activeDirection = HandMoveDirection.left;
      _setDebugSummary(
        'direction: static left; '
        'angle=${movingLeft.directionAngleDegrees!.toStringAsFixed(1)}deg',
      );
      return HandMoveDirection.left;
    }

    _movingLeftPositiveFrames = 0;
    final movingLeftCandidateAngle =
        movingLeft.directionAngleDegrees ??
        _visibleIndexDirectionAngleDegrees(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
        );
    if (movingLeftCandidateAngle case final angle?
        when _isHorizontalDirectionAngle(angle, HandMoveDirection.left)) {
      _activeDirection = HandMoveDirection.none;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: left rejected; ${movingLeft.reason}');
      return HandMoveDirection.none;
    }

    final movingRight = _evaluateHorizontalDirection(
      hand: hand,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.right,
    );
    if (movingRight.matches) {
      _movingDownPositiveFrames = 0;
      _movingRightPositiveFrames = math.min(
        _movingRightPositiveFrames + 1,
        HandGestureThresholds.movingRightRequiredConsecutiveFrames,
      );

      if (_movingRightPositiveFrames <
          HandGestureThresholds.movingRightRequiredConsecutiveFrames) {
        _activeDirection = HandMoveDirection.none;
        _setDebugSummary(
          'direction: confirming right '
          '$_movingRightPositiveFrames/'
          '${HandGestureThresholds.movingRightRequiredConsecutiveFrames}; '
          'angle=${movingRight.directionAngleDegrees!.toStringAsFixed(1)}deg',
        );
        return HandMoveDirection.none;
      }

      _activeDirection = HandMoveDirection.right;
      _setDebugSummary(
        'direction: static right; '
        'angle=${movingRight.directionAngleDegrees!.toStringAsFixed(1)}deg',
      );
      return HandMoveDirection.right;
    }

    _movingRightPositiveFrames = 0;
    final movingRightCandidateAngle =
        movingRight.directionAngleDegrees ??
        _visibleIndexDirectionAngleDegrees(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
        );
    if (movingRightCandidateAngle case final angle?
        when _isHorizontalDirectionAngle(angle, HandMoveDirection.right)) {
      _activeDirection = HandMoveDirection.none;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: right rejected; ${movingRight.reason}');
      return HandMoveDirection.none;
    }

    final movingUp = _evaluateVerticalDirection(
      hand: hand,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.up,
      useActiveDirectionRange: false,
    );
    if (movingUp.matches) {
      _movingLeftPositiveFrames = 0;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _activeDirection = HandMoveDirection.up;
      _setDebugSummary(
        'direction: static up; '
        'angle=${movingUp.directionAngleDegrees!.toStringAsFixed(1)}deg',
      );
      return HandMoveDirection.up;
    }

    final movingUpCandidateAngle =
        movingUp.directionAngleDegrees ??
        _visibleIndexDirectionAngleDegrees(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
        );
    if (movingUpCandidateAngle case final angle?
        when _isVerticalDirectionAngle(
          angle,
          direction: HandMoveDirection.up,
          active: false,
        )) {
      _activeDirection = HandMoveDirection.none;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: up rejected; ${movingUp.reason}');
      return HandMoveDirection.none;
    }

    final movingDown = _evaluateVerticalDirection(
      hand: hand,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.down,
      useActiveDirectionRange: false,
    );
    if (movingDown.matches) {
      _movingLeftPositiveFrames = 0;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = math.min(
        _movingDownPositiveFrames + 1,
        HandGestureThresholds.movingDownRequiredConsecutiveFrames,
      );

      if (_movingDownPositiveFrames <
          HandGestureThresholds.movingDownRequiredConsecutiveFrames) {
        _activeDirection = HandMoveDirection.none;
        _setDebugSummary(
          'direction: confirming down '
          '$_movingDownPositiveFrames/'
          '${HandGestureThresholds.movingDownRequiredConsecutiveFrames}; '
          'angle=${movingDown.directionAngleDegrees!.toStringAsFixed(1)}deg',
        );
        return HandMoveDirection.none;
      }

      _activeDirection = HandMoveDirection.down;
      _setDebugSummary(
        'direction: static down; '
        'angle=${movingDown.directionAngleDegrees!.toStringAsFixed(1)}deg',
      );
      return HandMoveDirection.down;
    }

    _movingDownPositiveFrames = 0;
    final movingDownCandidateAngle =
        movingDown.directionAngleDegrees ??
        _visibleVerticalDirectionAngleDegrees(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
          direction: HandMoveDirection.down,
        );
    if (movingDownCandidateAngle case final angle?
        when _isVerticalDirectionAngle(
          angle,
          direction: HandMoveDirection.down,
          active: false,
        )) {
      _activeDirection = HandMoveDirection.none;
      _setDebugSummary('direction: down rejected; ${movingDown.reason}');
      return HandMoveDirection.none;
    }

    _activeDirection = HandMoveDirection.none;
    _movingDownPositiveFrames = 0;
    _setDebugSummary('direction: no matching static direction');
    return HandMoveDirection.none;
  }

  bool _isFiniteImageSize(Size imageSize) {
    return imageSize.width.isFinite &&
        imageSize.height.isFinite &&
        imageSize.width > 0 &&
        imageSize.height > 0;
  }

  /// Returns the 2D angle between thumb points 3->4 and index points 7->8 when
  /// the hand has a likely open zoom-in shape. This intentionally runs before
  /// package `pointingUp` so zoom-in gets the frame first.
  double? _zoomInConflictAngleDegrees(Hand hand) {
    final thumbIp = _zoomConflictLandmark(hand, HandLandmarkType.thumbIP);
    final thumbTip = _zoomConflictLandmark(hand, HandLandmarkType.thumbTip);
    final indexDip = _zoomConflictLandmark(
      hand,
      HandLandmarkType.indexFingerDIP,
    );
    final indexTip = _zoomConflictLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    if (thumbIp == null ||
        thumbTip == null ||
        indexDip == null ||
        indexTip == null) {
      return null;
    }

    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
    if (handSize <= 0 ||
        !geometry.isLandmarkSegmentAbove2D(
          upperStart: indexDip,
          upperEnd: indexTip,
          lowerStart: thumbIp,
          lowerEnd: thumbTip,
          minVerticalGap:
              handSize * HandGestureThresholds.zoomIndexAboveThumbMinGapRatio,
        )) {
      return null;
    }

    // A zoom-in pose still requires the other three fingers to be folded.
    for (final chainTypes
        in HandGestureThresholds.directionFingerChainTypes.skip(1)) {
      final mcp = _zoomConflictLandmark(hand, chainTypes[0]);
      final pip = _zoomConflictLandmark(hand, chainTypes[1]);
      final tip = _zoomConflictLandmark(hand, chainTypes[3]);
      if (mcp == null ||
          pip == null ||
          tip == null ||
          !geometry.isFingerFoldedByAngle3D(mcp: mcp, pip: pip, tip: tip)) {
        return null;
      }
    }

    final angle = geometry.angleBetweenLandmarkSegments2D(
      firstStart: thumbIp,
      firstEnd: thumbTip,
      secondStart: indexDip,
      secondEnd: indexTip,
    );
    if (angle == null) return null;

    return angle + _angleComparisonEpsilon >=
                HandGestureThresholds.zoomInThumbIndexMinAngleDegrees &&
            angle - _angleComparisonEpsilon <=
                HandGestureThresholds.zoomInThumbIndexMaxAngleDegrees
        ? angle
        : null;
  }

  HandLandmark? _zoomConflictLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

  _VerticalDirectionEvaluation _evaluateVerticalDirection({
    required Hand hand,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
    required bool useActiveDirectionRange,
  }) {
    final isUp = direction == HandMoveDirection.up;
    final requiredTypes = isUp
        ? _verticalRequiredTypes
        : _movingDownRequiredTypes;
    final landmarks = <HandLandmarkType, HandLandmark>{};
    for (final type in requiredTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) {
        return _VerticalDirectionEvaluation(
          matches: false,
          reason: 'missing required point ${isUp ? '5-20' : '6-8 or 9-20'}',
        );
      }
      landmarks[type] = landmark;
    }

    HandLandmark point(HandLandmarkType type) => landmarks[type]!;
    final indexMcp = isUp ? point(HandLandmarkType.indexFingerMCP) : null;
    final indexPip = point(HandLandmarkType.indexFingerPIP);
    final indexDip = point(HandLandmarkType.indexFingerDIP);
    final indexTip = point(HandLandmarkType.indexFingerTip);
    final middleMcp = point(HandLandmarkType.middleFingerMCP);
    final ringMcp = point(HandLandmarkType.ringFingerMCP);
    final pinkyMcp = point(HandLandmarkType.pinkyMCP);

    final palmAnchors = isUp
        ? [indexMcp!, middleMcp, ringMcp, pinkyMcp]
        : [middleMcp, ringMcp, pinkyMcp];
    final palmCenter = Offset(
      palmAnchors
              .map((landmark) => _screenX(landmark, mirrorHorizontally))
              .reduce((first, second) => first + second) /
          palmAnchors.length,
      palmAnchors
              .map((landmark) => landmark.y)
              .reduce((first, second) => first + second) /
          palmAnchors.length,
    );
    final palmWidth = geometry.distanceBetweenLandmarks(
      isUp ? indexMcp! : middleMcp,
      pinkyMcp,
    );
    if (!palmWidth.isFinite || palmWidth <= 0) {
      return const _VerticalDirectionEvaluation(
        matches: false,
        reason: 'invalid palm width',
      );
    }

    final directionAngle = _indexDirectionAngleDegrees(
      indexMcp: isUp ? indexMcp! : indexPip,
      indexTip: indexTip,
      mirrorHorizontally: mirrorHorizontally,
    );
    final angle678 = geometry.fingerJointAngleDegrees(
      mcp: indexPip,
      pip: indexDip,
      tip: indexTip,
    );

    if (isUp) {
      final angle567 = geometry.fingerJointAngleDegrees(
        mcp: indexMcp!,
        pip: indexPip,
        tip: indexDip,
      );

      if (indexPip.y >= indexMcp.y ||
          indexDip.y >= indexPip.y ||
          indexTip.y >= indexDip.y) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 5-8 do not rise in order',
        );
      }

      final verticalSpan = indexMcp.y - indexTip.y;
      final minVerticalSpan =
          palmWidth * HandGestureThresholds.movingUpMinMcpToTipPalmWidthRatio;
      if (verticalSpan < minVerticalSpan) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 5-8 vertical span is too short',
        );
      }

      final screenXs = [
        _screenX(indexMcp, mirrorHorizontally),
        _screenX(indexPip, mirrorHorizontally),
        _screenX(indexDip, mirrorHorizontally),
        _screenX(indexTip, mirrorHorizontally),
      ];
      final horizontalSpread =
          screenXs.reduce(math.max) - screenXs.reduce(math.min);
      if (horizontalSpread >
          verticalSpan *
              HandGestureThresholds.movingUpMaxHorizontalToVerticalRatio) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 5-8 are not aligned with the y-axis',
        );
      }

      if (angle567 < HandGestureThresholds.movingUpIndexMinJointAngleDegrees ||
          angle678 < HandGestureThresholds.movingUpIndexMinJointAngleDegrees) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason:
              'index joints ${angle567.toStringAsFixed(1)}/'
              '${angle678.toStringAsFixed(1)} below '
              '${HandGestureThresholds.movingUpIndexMinJointAngleDegrees.toStringAsFixed(0)}',
        );
      }
    } else {
      if (indexDip.y <= indexPip.y || indexTip.y <= indexDip.y) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 6-8 do not descend in order',
        );
      }

      final verticalSpan = indexTip.y - indexPip.y;
      final minVerticalSpan =
          palmWidth * HandGestureThresholds.movingDownMinPipToTipPalmWidthRatio;
      if (verticalSpan < minVerticalSpan) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 6-8 vertical span is too short',
        );
      }

      final screenXs = [
        _screenX(indexPip, mirrorHorizontally),
        _screenX(indexDip, mirrorHorizontally),
        _screenX(indexTip, mirrorHorizontally),
      ];
      final horizontalSpread =
          screenXs.reduce(math.max) - screenXs.reduce(math.min);
      if (horizontalSpread >
          verticalSpan *
              HandGestureThresholds.movingDownMaxHorizontalToVerticalRatio) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: 'points 6-8 are not aligned with the y-axis',
        );
      }

      if (angle678 <
          HandGestureThresholds.movingDownMinPipDipTipJointAngleDegrees) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason:
              'points 6-8 joint ${angle678.toStringAsFixed(1)} below '
              '${HandGestureThresholds.movingDownMinPipDipTipJointAngleDegrees.toStringAsFixed(0)}',
        );
      }
    }

    if (!_isVerticalDirectionAngle(
      directionAngle,
      direction: direction,
      active: useActiveDirectionRange,
    )) {
      return _VerticalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index angle ${directionAngle.toStringAsFixed(1)} outside '
            '${direction.name}',
      );
    }

    for (final finger in const [
      (
        'middle',
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerDIP,
        HandLandmarkType.middleFingerTip,
      ),
      (
        'ring',
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
      ),
      (
        'pinky',
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
      ),
    ]) {
      if (!_isVerticalFingerFolded(
        mcp: point(finger.$2),
        pip: point(finger.$3),
        dip: point(finger.$4),
        tip: point(finger.$5),
        palmCenter: palmCenter,
        mirrorHorizontally: mirrorHorizontally,
        direction: direction,
      )) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: '${finger.$1} finger not folded',
        );
      }
    }

    return _VerticalDirectionEvaluation(
      matches: true,
      directionAngleDegrees: directionAngle,
      reason: 'matched',
    );
  }

  bool _isVerticalFingerFolded({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark dip,
    required HandLandmark tip,
    required Offset palmCenter,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
  }) {
    final jointAngle = geometry.fingerJointAngleDegrees(
      mcp: mcp,
      pip: pip,
      tip: dip,
    );
    final maxJointAngle = direction == HandMoveDirection.up
        ? HandGestureThresholds.movingUpFoldedFingerMaxJointAngleDegrees
        : HandGestureThresholds.movingDownFoldedFingerMaxJointAngleDegrees;
    final maxTipPipDistanceRatio = direction == HandMoveDirection.up
        ? HandGestureThresholds.movingUpFoldedTipMaxPipDistanceRatio
        : HandGestureThresholds.movingDownFoldedTipMaxPipDistanceRatio;
    if (jointAngle >= maxJointAngle) {
      return false;
    }

    final tipDistance =
        (_screenPoint(tip, mirrorHorizontally) - palmCenter).distance;
    final pipDistance =
        (_screenPoint(pip, mirrorHorizontally) - palmCenter).distance;
    return tipDistance < pipDistance * maxTipPipDistanceRatio;
  }

  _HorizontalDirectionEvaluation _evaluateHorizontalDirection({
    required Hand hand,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
  }) {
    final landmarks = <HandLandmarkType, HandLandmark>{};
    for (final type in _horizontalRequiredTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) {
        return const _HorizontalDirectionEvaluation(
          matches: false,
          reason: 'missing required point 0 or 5-20',
        );
      }
      landmarks[type] = landmark;
    }

    HandLandmark point(HandLandmarkType type) => landmarks[type]!;
    final wrist = point(HandLandmarkType.wrist);
    final indexMcp = point(HandLandmarkType.indexFingerMCP);
    final indexPip = point(HandLandmarkType.indexFingerPIP);
    final indexDip = point(HandLandmarkType.indexFingerDIP);
    final indexTip = point(HandLandmarkType.indexFingerTip);
    final middleMcp = point(HandLandmarkType.middleFingerMCP);
    final ringMcp = point(HandLandmarkType.ringFingerMCP);
    final pinkyMcp = point(HandLandmarkType.pinkyMCP);

    final palmAnchors = [wrist, indexMcp, middleMcp, ringMcp, pinkyMcp];
    final palmCenter = Offset(
      palmAnchors
              .map((landmark) => _screenX(landmark, mirrorHorizontally))
              .reduce((first, second) => first + second) /
          palmAnchors.length,
      palmAnchors
              .map((landmark) => landmark.y)
              .reduce((first, second) => first + second) /
          palmAnchors.length,
    );
    final palmWidth = geometry.distanceBetweenLandmarks(indexMcp, pinkyMcp);
    if (!palmWidth.isFinite || palmWidth <= 0) {
      return const _HorizontalDirectionEvaluation(
        matches: false,
        reason: 'invalid palm width',
      );
    }

    final directionAngle = _indexDirectionAngleDegrees(
      indexMcp: indexMcp,
      indexTip: indexTip,
      mirrorHorizontally: mirrorHorizontally,
    );
    final isLeft = direction == HandMoveDirection.left;
    final minIndexJointAngle = isLeft
        ? HandGestureThresholds.movingLeftIndexMinJointAngleDegrees
        : HandGestureThresholds.movingRightIndexMinJointAngleDegrees;
    final minIndexStraightness = isLeft
        ? HandGestureThresholds.movingLeftIndexMinStraightnessRatio
        : HandGestureThresholds.movingRightIndexMinStraightnessRatio;
    final tipPalmWidthOffsetRatio = _depthAwareTipPalmWidthOffsetRatio(
      indexTip: indexTip,
      palmAnchors: palmAnchors,
      palmWidth: palmWidth,
    );

    final angle567 = geometry.fingerJointAngleDegrees(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexDip,
    );
    final angle678 = geometry.fingerJointAngleDegrees(
      mcp: indexPip,
      pip: indexDip,
      tip: indexTip,
    );
    if (angle567 < minIndexJointAngle || angle678 < minIndexJointAngle) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index joints ${angle567.toStringAsFixed(1)}/'
            '${angle678.toStringAsFixed(1)} below '
            '${minIndexJointAngle.toStringAsFixed(0)}',
      );
    }

    final indexPathLength =
        geometry.distanceBetweenLandmarks(indexMcp, indexPip) +
        geometry.distanceBetweenLandmarks(indexPip, indexDip) +
        geometry.distanceBetweenLandmarks(indexDip, indexTip);
    final indexStraightness = indexPathLength > 0
        ? geometry.distanceBetweenLandmarks(indexMcp, indexTip) /
              indexPathLength
        : 0.0;
    if (!indexStraightness.isFinite ||
        indexStraightness < minIndexStraightness) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index straightness ${indexStraightness.toStringAsFixed(2)} below '
            '${minIndexStraightness.toStringAsFixed(2)}',
      );
    }

    if (!_isHorizontalDirectionAngle(directionAngle, direction)) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index angle ${directionAngle.toStringAsFixed(1)} outside '
            '${direction.name}',
      );
    }

    final indexTipScreenX = _screenX(indexTip, mirrorHorizontally);
    final indexTipBeyondPalm = isLeft
        ? indexTipScreenX <= palmCenter.dx - palmWidth * tipPalmWidthOffsetRatio
        : indexTipScreenX >=
              palmCenter.dx + palmWidth * tipPalmWidthOffsetRatio;
    if (!indexTipBeyondPalm) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index tip not clearly ${direction.name} of palm at '
            '${(tipPalmWidthOffsetRatio * 100).toStringAsFixed(1)}%',
      );
    }

    for (final finger in const [
      (
        'middle',
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerDIP,
        HandLandmarkType.middleFingerTip,
      ),
      (
        'ring',
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
      ),
      (
        'pinky',
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
      ),
    ]) {
      if (!_isHorizontalFingerFolded(
        mcp: point(finger.$2),
        pip: point(finger.$3),
        dip: point(finger.$4),
        tip: point(finger.$5),
        palmCenter: palmCenter,
        mirrorHorizontally: mirrorHorizontally,
        direction: direction,
      )) {
        return _HorizontalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason: '${finger.$1} finger not folded',
        );
      }
    }

    return _HorizontalDirectionEvaluation(
      matches: true,
      directionAngleDegrees: directionAngle,
      reason: 'matched',
    );
  }

  bool _isHorizontalFingerFolded({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark dip,
    required HandLandmark tip,
    required Offset palmCenter,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
  }) {
    final jointAngle = geometry.fingerJointAngleDegrees(
      mcp: mcp,
      pip: pip,
      tip: dip,
    );
    final maxJointAngle = direction == HandMoveDirection.left
        ? HandGestureThresholds.movingLeftFoldedFingerMaxJointAngleDegrees
        : HandGestureThresholds.movingRightFoldedFingerMaxJointAngleDegrees;
    final maxTipPipDistanceRatio = direction == HandMoveDirection.left
        ? HandGestureThresholds.movingLeftFoldedTipMaxPipDistanceRatio
        : HandGestureThresholds.movingRightFoldedTipMaxPipDistanceRatio;
    if (jointAngle >= maxJointAngle) {
      return false;
    }

    final tipDistance =
        (_screenPoint(tip, mirrorHorizontally) - palmCenter).distance;
    final pipDistance =
        (_screenPoint(pip, mirrorHorizontally) - palmCenter).distance;
    return tipDistance < pipDistance * maxTipPipDistanceRatio;
  }

  double _depthAwareTipPalmWidthOffsetRatio({
    required HandLandmark indexTip,
    required List<HandLandmark> palmAnchors,
    required double palmWidth,
  }) {
    final palmDepth = geometry.average(
      palmAnchors.map((landmark) => landmark.z),
    );
    final fartherDepthDelta = math.max(0.0, indexTip.z - palmDepth);
    final maxDepthDelta =
        palmWidth *
        HandGestureThresholds.directionTipMaxDepthDeltaPalmWidthRatio;
    final fartherProgress = maxDepthDelta > 0
        ? (fartherDepthDelta / maxDepthDelta).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return HandGestureThresholds.directionTipMinPalmWidthOffsetRatio +
        (HandGestureThresholds.directionTipMaxPalmWidthOffsetRatio -
                HandGestureThresholds.directionTipMinPalmWidthOffsetRatio) *
            fartherProgress;
  }

  double _indexDirectionAngleDegrees({
    required HandLandmark indexMcp,
    required HandLandmark indexTip,
    required bool mirrorHorizontally,
  }) {
    final deltaX =
        _screenX(indexTip, mirrorHorizontally) -
        _screenX(indexMcp, mirrorHorizontally);
    final deltaY = indexTip.y - indexMcp.y;
    var angle = math.atan2(-deltaY, deltaX) * 180 / math.pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  double? _visibleIndexDirectionAngleDegrees({
    required Hand hand,
    required bool mirrorHorizontally,
  }) {
    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );
    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    if (indexMcp == null || indexTip == null) return null;

    return _indexDirectionAngleDegrees(
      indexMcp: indexMcp,
      indexTip: indexTip,
      mirrorHorizontally: mirrorHorizontally,
    );
  }

  double? _visibleVerticalDirectionAngleDegrees({
    required Hand hand,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
  }) {
    final baseType = direction == HandMoveDirection.down
        ? HandLandmarkType.indexFingerPIP
        : HandLandmarkType.indexFingerMCP;
    final base = geometry.visibleLandmark(hand, baseType);
    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    if (base == null || indexTip == null) return null;

    return _indexDirectionAngleDegrees(
      indexMcp: base,
      indexTip: indexTip,
      mirrorHorizontally: mirrorHorizontally,
    );
  }

  bool _isHorizontalDirectionAngle(double angle, HandMoveDirection direction) {
    return switch (direction) {
      HandMoveDirection.left =>
        angle + _angleComparisonEpsilon >=
                HandGestureThresholds.movingLeftMinDirectionAngleDegrees &&
            angle - _angleComparisonEpsilon <=
                HandGestureThresholds.movingLeftMaxDirectionAngleDegrees,
      HandMoveDirection.right =>
        angle + _angleComparisonEpsilon >=
                HandGestureThresholds.movingRightMinDirectionAngleDegrees ||
            angle - _angleComparisonEpsilon <=
                HandGestureThresholds.movingRightMaxDirectionAngleDegrees,
      _ => false,
    };
  }

  bool _isVerticalDirectionAngle(
    double angle, {
    required HandMoveDirection direction,
    required bool active,
  }) {
    final isUp = direction == HandMoveDirection.up;
    final minAngle = switch ((isUp, active)) {
      (true, true) =>
        HandGestureThresholds.movingUpActiveMinDirectionAngleDegrees,
      (true, false) =>
        HandGestureThresholds.movingUpInitialMinDirectionAngleDegrees,
      (false, true) =>
        HandGestureThresholds.movingDownActiveMinDirectionAngleDegrees,
      (false, false) =>
        HandGestureThresholds.movingDownInitialMinDirectionAngleDegrees,
    };
    final maxAngle = switch ((isUp, active)) {
      (true, true) =>
        HandGestureThresholds.movingUpActiveMaxDirectionAngleDegrees,
      (true, false) =>
        HandGestureThresholds.movingUpInitialMaxDirectionAngleDegrees,
      (false, true) =>
        HandGestureThresholds.movingDownActiveMaxDirectionAngleDegrees,
      (false, false) =>
        HandGestureThresholds.movingDownInitialMaxDirectionAngleDegrees,
    };
    return angle + _angleComparisonEpsilon >= minAngle &&
        angle - _angleComparisonEpsilon <= maxAngle;
  }

  double _screenX(HandLandmark landmark, bool mirrorHorizontally) {
    return mirrorHorizontally ? -landmark.x : landmark.x;
  }

  Offset _screenPoint(HandLandmark landmark, bool mirrorHorizontally) {
    return Offset(_screenX(landmark, mirrorHorizontally), landmark.y);
  }

  void _setDebugSummary(String value) {
    _debugSummary = value;

    if (!kDebugMode || _lastPrintedDebugSummary == value) return;

    _lastPrintedDebugSummary = value;
    debugPrint('[DirectionGestureDetector] $value');
  }
}

class _HorizontalDirectionEvaluation {
  const _HorizontalDirectionEvaluation({
    required this.matches,
    required this.reason,
    this.directionAngleDegrees,
  });

  final bool matches;
  final String reason;
  final double? directionAngleDegrees;
}

class _VerticalDirectionEvaluation {
  const _VerticalDirectionEvaluation({
    required this.matches,
    required this.reason,
    this.directionAngleDegrees,
  });

  final bool matches;
  final String reason;
  final double? directionAngleDegrees;
}
