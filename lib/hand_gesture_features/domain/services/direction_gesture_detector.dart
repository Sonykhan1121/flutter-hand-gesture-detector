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
  static const double _distanceComparisonEpsilon = 1e-9;

  HandMoveDirection _activeDirection = HandMoveDirection.none;
  HandMoveDirection _debugCandidateDirection = HandMoveDirection.none;
  int _movingLeftPositiveFrames = 0;
  int _movingRightPositiveFrames = 0;
  int _movingDownPositiveFrames = 0;
  Offset? _steadyHandCenter;
  double? _steadyHandSize;
  int _steadyFrameCount = 0;
  String _debugSummary = 'direction: idle';
  String? _lastPrintedDebugSummary;

  static const List<HandLandmarkType> _horizontalCriticalTypes = [
    HandLandmarkType.wrist,
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.indexFingerPIP,
    HandLandmarkType.indexFingerDIP,
    HandLandmarkType.indexFingerTip,
  ];

  /// Latest short debug explanation for why direction did or did not fire.
  String get debugSummary => _debugSummary;

  /// Direction sector currently being evaluated, including rejected poses.
  HandMoveDirection get debugCandidateDirection => _debugCandidateDirection;

  /// Direction that has passed every pose, steadiness, and frame-count rule.
  HandMoveDirection get debugAcceptedDirection => _activeDirection;

  /// Clears the held sector after a reset, blocked frame, or invalid pose.
  void clearState({String reason = 'reset'}) {
    _resetDirectionDecisionState();
    _debugCandidateDirection = HandMoveDirection.none;
    _steadyHandCenter = null;
    _steadyHandSize = null;
    _steadyFrameCount = 0;
    _setDebugSummary('direction: $reason');
  }

  void _resetDirectionDecisionState() {
    _activeDirection = HandMoveDirection.none;
    _movingLeftPositiveFrames = 0;
    _movingRightPositiveFrames = 0;
    _movingDownPositiveFrames = 0;
  }

  /// Detects one direction from the current static index-pointing pose.
  HandMoveDirection detect({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    bool? mirrorPalmHorizontally,
  }) {
    if (!geometry.isReliableHand(hand) || !_isFiniteImageSize(imageSize)) {
      clearState(reason: 'invalid frame');
      return HandMoveDirection.none;
    }

    final stability = _updateHandStability(hand);
    if (stability == _DirectionHandStability.moving) {
      return HandMoveDirection.none;
    }
    final handIsSteady = stability == _DirectionHandStability.steady;
    _debugCandidateDirection = HandMoveDirection.none;

    final zoomInConflictAngle = _zoomInConflictAngleDegrees(
      hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      mirrorPalmHorizontally: mirrorPalmHorizontally ?? mirrorHorizontally,
    );
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
      _debugCandidateDirection = HandMoveDirection.up;
      if (!handIsSteady) {
        _resetDirectionDecisionState();
        _setSettlingDebugSummary('package pointingUp');
        return HandMoveDirection.none;
      }
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
      _debugCandidateDirection = activeVerticalDirection;
      final activeVertical = _evaluateVerticalDirection(
        hand: hand,
        imageSize: imageSize,
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
      _debugCandidateDirection = HandMoveDirection.none;
    }

    final movingLeft = _evaluateHorizontalDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      mirrorPalmHorizontally: mirrorPalmHorizontally ?? mirrorHorizontally,
      direction: HandMoveDirection.left,
    );
    if (movingLeft.matches) {
      _debugCandidateDirection = HandMoveDirection.left;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _movingLeftPositiveFrames = math.min(
        _movingLeftPositiveFrames + 1,
        HandGestureThresholds.movingLeftRequiredConsecutiveFrames,
      );

      if (_movingLeftPositiveFrames <
              HandGestureThresholds.movingLeftRequiredConsecutiveFrames ||
          !handIsSteady) {
        _activeDirection = HandMoveDirection.none;
        if (handIsSteady) {
          _setDebugSummary(
            'direction: confirming left '
            '$_movingLeftPositiveFrames/'
            '${HandGestureThresholds.movingLeftRequiredConsecutiveFrames}; '
            'angle=${movingLeft.directionAngleDegrees!.toStringAsFixed(1)}deg',
          );
        } else {
          _setSettlingDebugSummary('left pose');
        }
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
      _debugCandidateDirection = HandMoveDirection.left;
      _activeDirection = HandMoveDirection.none;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: left rejected; ${movingLeft.reason}');
      return HandMoveDirection.none;
    }

    final movingRight = _evaluateHorizontalDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      mirrorPalmHorizontally: mirrorPalmHorizontally ?? mirrorHorizontally,
      direction: HandMoveDirection.right,
    );
    if (movingRight.matches) {
      _debugCandidateDirection = HandMoveDirection.right;
      _movingDownPositiveFrames = 0;
      _movingRightPositiveFrames = math.min(
        _movingRightPositiveFrames + 1,
        HandGestureThresholds.movingRightRequiredConsecutiveFrames,
      );

      if (_movingRightPositiveFrames <
              HandGestureThresholds.movingRightRequiredConsecutiveFrames ||
          !handIsSteady) {
        _activeDirection = HandMoveDirection.none;
        if (handIsSteady) {
          _setDebugSummary(
            'direction: confirming right '
            '$_movingRightPositiveFrames/'
            '${HandGestureThresholds.movingRightRequiredConsecutiveFrames}; '
            'angle=${movingRight.directionAngleDegrees!.toStringAsFixed(1)}deg',
          );
        } else {
          _setSettlingDebugSummary('right pose');
        }
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
      _debugCandidateDirection = HandMoveDirection.right;
      _activeDirection = HandMoveDirection.none;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: right rejected; ${movingRight.reason}');
      return HandMoveDirection.none;
    }

    final movingUp = _evaluateVerticalDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.up,
      useActiveDirectionRange: false,
    );
    if (movingUp.matches) {
      _debugCandidateDirection = HandMoveDirection.up;
      _movingLeftPositiveFrames = 0;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = 0;
      if (!handIsSteady) {
        _activeDirection = HandMoveDirection.none;
        _setSettlingDebugSummary('up pose');
        return HandMoveDirection.none;
      }
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
      _debugCandidateDirection = HandMoveDirection.up;
      _activeDirection = HandMoveDirection.none;
      _movingDownPositiveFrames = 0;
      _setDebugSummary('direction: up rejected; ${movingUp.reason}');
      return HandMoveDirection.none;
    }

    final movingDown = _evaluateVerticalDirection(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
      direction: HandMoveDirection.down,
      useActiveDirectionRange: false,
    );
    if (movingDown.matches) {
      _debugCandidateDirection = HandMoveDirection.down;
      _movingLeftPositiveFrames = 0;
      _movingRightPositiveFrames = 0;
      _movingDownPositiveFrames = math.min(
        _movingDownPositiveFrames + 1,
        HandGestureThresholds.movingDownRequiredConsecutiveFrames,
      );

      if (_movingDownPositiveFrames <
              HandGestureThresholds.movingDownRequiredConsecutiveFrames ||
          !handIsSteady) {
        _activeDirection = HandMoveDirection.none;
        if (handIsSteady) {
          _setDebugSummary(
            'direction: confirming down '
            '$_movingDownPositiveFrames/'
            '${HandGestureThresholds.movingDownRequiredConsecutiveFrames}; '
            'angle=${movingDown.directionAngleDegrees!.toStringAsFixed(1)}deg',
          );
        } else {
          _setSettlingDebugSummary('down pose');
        }
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
      _debugCandidateDirection = HandMoveDirection.down;
      _activeDirection = HandMoveDirection.none;
      _setDebugSummary('direction: down rejected; ${movingDown.reason}');
      return HandMoveDirection.none;
    }

    _activeDirection = HandMoveDirection.none;
    _debugCandidateDirection = HandMoveDirection.none;
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

  _DirectionHandStability _updateHandStability(Hand hand) {
    final box = hand.boundingBox;
    final currentCenter = Offset(
      (box.left + box.right) / 2,
      (box.top + box.bottom) / 2,
    );
    final currentHandSize = geometry.handSizeFromBoundingBox(box);
    final anchorCenter = _steadyHandCenter;
    final anchorHandSize = _steadyHandSize;

    if (anchorCenter == null || anchorHandSize == null) {
      _steadyHandCenter = currentCenter;
      _steadyHandSize = currentHandSize;
      _steadyFrameCount = 1;
      return _DirectionHandStability.settling;
    }

    final referenceHandSize = math.max(anchorHandSize, currentHandSize);
    final movementRatio =
        geometry.distanceBetweenOffsets(anchorCenter, currentCenter) /
        referenceHandSize;
    if (!movementRatio.isFinite ||
        movementRatio >
            HandGestureThresholds.directionMaxHandCenterMovementRatio +
                _distanceComparisonEpsilon) {
      _resetDirectionDecisionState();
      _debugCandidateDirection = HandMoveDirection.none;
      _steadyHandCenter = currentCenter;
      _steadyHandSize = currentHandSize;
      // The frame that proved movement is deliberately not a steady frame.
      _steadyFrameCount = 0;
      _setDebugSummary(
        'direction: hand moving; '
        'center movement=${(movementRatio * 100).toStringAsFixed(1)}% '
        'of hand size',
      );
      return _DirectionHandStability.moving;
    }

    _steadyFrameCount = math.min(
      _steadyFrameCount + 1,
      HandGestureThresholds.directionRequiredSteadyFrames,
    );
    return _steadyFrameCount >=
            HandGestureThresholds.directionRequiredSteadyFrames
        ? _DirectionHandStability.steady
        : _DirectionHandStability.settling;
  }

  void _setSettlingDebugSummary(String candidate) {
    _setDebugSummary(
      'direction: hand settling '
      '$_steadyFrameCount/'
      '${HandGestureThresholds.directionRequiredSteadyFrames}; '
      '$candidate',
    );
  }

  /// Returns the 2D angle between thumb points 3->4 and index points 7->8 when
  /// the hand has a likely open zoom-in shape. This intentionally runs before
  /// package `pointingUp` so zoom-in gets the frame first.
  double? _zoomInConflictAngleDegrees(
    Hand hand, {
    required Size imageSize,
    required bool mirrorHorizontally,
    required bool mirrorPalmHorizontally,
  }) {
    if (!geometry.isPalmSideFacingCamera(
      hand: hand,
      mirrorHorizontally: mirrorPalmHorizontally,
      minNormalizedCross: HandGestureThresholds.zoomMinPalmSideCross,
      minLandmarkVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    )) {
      return null;
    }

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
    final palmCenter = geometry.palmCenter3D(hand);
    if (handSize <= 0 ||
        palmCenter == null ||
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

    final distance2dRatio =
        geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize;
    final distance3dRatio =
        geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) / handSize;
    if (distance2dRatio + _distanceComparisonEpsilon <
            HandGestureThresholds.zoomInMinDistanceRatio ||
        distance3dRatio + _distanceComparisonEpsilon <
            HandGestureThresholds.zoomInMinDistanceRatio) {
      return null;
    }

    // A zoom-in pose still requires the other three fingers to be folded.
    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes
        .skip(1)) {
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
    final forwardRayIntersection = geometry.forwardRayIntersection2D(
      firstStart: thumbTip,
      firstThrough: thumbIp,
      secondStart: indexTip,
      secondThrough: indexDip,
      minForwardScale: HandGestureThresholds.zoomInMinForwardRayScale,
      parallelToleranceDegrees:
          HandGestureThresholds.zoomInParallelRayToleranceDegrees,
      minParallelLineSeparation:
          handSize * HandGestureThresholds.zoomInParallelMinLineSeparationRatio,
    );
    if (angle == null ||
        forwardRayIntersection == null ||
        !geometry.isForwardRayRelationInHandQuadrant2D(
          relation: forwardRayIntersection,
          firstStart: thumbTip,
          firstThrough: thumbIp,
          secondStart: indexTip,
          secondThrough: indexDip,
          imageSize: imageSize,
          handedness: hand.handedness,
          mirrorHorizontally: mirrorHorizontally,
        )) {
      return null;
    }

    return angle;
  }

  HandLandmark? _zoomConflictLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

  /// Identifies a touching thumb/index pose that a relaxed Moving-right check
  /// must leave for Zoom Out. Directions run before zoom in the live pipeline.
  bool _isZoomOutConflict(Hand hand, {required bool mirrorPalmHorizontally}) {
    if (!geometry.isPalmSideFacingCamera(
      hand: hand,
      mirrorHorizontally: mirrorPalmHorizontally,
      minNormalizedCross: HandGestureThresholds.zoomMinPalmSideCross,
      minLandmarkVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    )) {
      return false;
    }

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
      return false;
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
      return false;
    }

    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes
        .skip(1)) {
      final mcp = _zoomConflictLandmark(hand, chainTypes[0]);
      final pip = _zoomConflictLandmark(hand, chainTypes[1]);
      final tip = _zoomConflictLandmark(hand, chainTypes[3]);
      if (mcp == null ||
          pip == null ||
          tip == null ||
          !geometry.isFingerFoldedByAngle3D(mcp: mcp, pip: pip, tip: tip)) {
        return false;
      }
    }

    final distance2dRatio =
        geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize;
    final distance3dRatio =
        geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) / handSize;
    final isClosedPinch =
        distance2dRatio <=
            HandGestureThresholds.zoomTouchMax2dDistanceRatio +
                _distanceComparisonEpsilon ||
        distance3dRatio <=
            HandGestureThresholds.zoomClosedMaxDistanceRatio +
                _distanceComparisonEpsilon;
    if (!isClosedPinch) return false;

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;
    return geometry.isThumbTuckedForFist3D(
          hand: hand,
          palmCenter: palmCenter,
          handSize: handSize,
        ) ==
        false;
  }

  _VerticalDirectionEvaluation _evaluateVerticalDirection({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required HandMoveDirection direction,
    required bool useActiveDirectionRange,
  }) {
    final isUp = direction == HandMoveDirection.up;
    final requiredTypes =
        isUp
            ? const [
              HandLandmarkType.indexFingerMCP,
              HandLandmarkType.indexFingerPIP,
              HandLandmarkType.indexFingerDIP,
              HandLandmarkType.indexFingerTip,
            ]
            : const [
              HandLandmarkType.indexFingerPIP,
              HandLandmarkType.indexFingerDIP,
              HandLandmarkType.indexFingerTip,
            ];
    final landmarks = <HandLandmarkType, HandLandmark>{};
    for (final type in requiredTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) {
        return _VerticalDirectionEvaluation(
          matches: false,
          reason: 'missing required index point ${isUp ? '5-8' : '6-8'}',
        );
      }
      landmarks[type] = landmark;
    }

    HandLandmark point(HandLandmarkType type) => landmarks[type]!;
    HandLandmark? visiblePoint(HandLandmarkType type) =>
        geometry.visibleLandmark(hand, type);
    final indexMcp =
        isUp
            ? point(HandLandmarkType.indexFingerMCP)
            : visiblePoint(HandLandmarkType.indexFingerMCP);
    final indexPip = point(HandLandmarkType.indexFingerPIP);
    final indexDip = point(HandLandmarkType.indexFingerDIP);
    final indexTip = point(HandLandmarkType.indexFingerTip);
    final palmMcps =
        <HandLandmark?>[
          indexMcp,
          visiblePoint(HandLandmarkType.middleFingerMCP),
          visiblePoint(HandLandmarkType.ringFingerMCP),
          visiblePoint(HandLandmarkType.pinkyMCP),
        ].whereType<HandLandmark>().toList();
    final palmWidth = _maximumLandmarkDistance(palmMcps);
    if (!palmWidth.isFinite || palmWidth <= 0) {
      return const _VerticalDirectionEvaluation(
        matches: false,
        reason: 'invalid palm width',
      );
    }
    final foldPalmWidth = _foldReferencePalmWidth(hand);
    if (!foldPalmWidth.isFinite || foldPalmWidth <= 0) {
      return const _VerticalDirectionEvaluation(
        matches: false,
        reason: 'invalid folded-finger palm reference',
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

      if (angle567 <
              HandGestureThresholds.movingUpMinMcpPipDipJointAngleDegrees ||
          angle678 + _angleComparisonEpsilon <
              HandGestureThresholds.verticalDirectionIndexMinAngleDegrees) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason:
              'index joints ${angle567.toStringAsFixed(1)}/'
              '${angle678.toStringAsFixed(1)} below required '
              '${HandGestureThresholds.movingUpMinMcpPipDipJointAngleDegrees.toStringAsFixed(0)}/'
              '${HandGestureThresholds.verticalDirectionIndexMinAngleDegrees.toStringAsFixed(0)}',
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

      if (angle678 + _angleComparisonEpsilon <
          HandGestureThresholds.verticalDirectionIndexMinAngleDegrees) {
        return _VerticalDirectionEvaluation(
          matches: false,
          directionAngleDegrees: directionAngle,
          reason:
              'points 6-8 joint ${angle678.toStringAsFixed(1)} below '
              '${HandGestureThresholds.verticalDirectionIndexMinAngleDegrees.toStringAsFixed(0)}',
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

    var foldedFingerCount = 0;
    var openFingerCount = 0;
    var uncertainFingerCount = 0;
    var unavailableFingerCount = 0;
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
      final foldState = _directionFingerFoldState(
        mcp: visiblePoint(finger.$2),
        pip: visiblePoint(finger.$3),
        dip: visiblePoint(finger.$4),
        tip: visiblePoint(finger.$5),
        palmWidth: foldPalmWidth,
      );
      if (foldState == _DirectionFingerFoldState.folded) {
        foldedFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.open) {
        openFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.uncertain) {
        uncertainFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.unavailable) {
        unavailableFingerCount += 1;
      }
    }

    final compactPalmCircleMatches = _compactPalmCircleMatches(
      hand,
      imageSize: imageSize,
    );
    if (foldedFingerCount <
            HandGestureThresholds.directionMinConfirmedFoldedFingerCount &&
        !compactPalmCircleMatches) {
      return _VerticalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'only $foldedFingerCount/3 folded fingers; '
            '$openFingerCount open, '
            '$uncertainFingerCount uncertain, '
            '$unavailableFingerCount unavailable; need '
            '${HandGestureThresholds.directionMinConfirmedFoldedFingerCount}; '
            'compact palm circle failed',
      );
    }

    return _VerticalDirectionEvaluation(
      matches: true,
      directionAngleDegrees: directionAngle,
      reason:
          compactPalmCircleMatches && foldedFingerCount == 0
              ? 'matched compact palm circle'
              : 'matched',
    );
  }

  bool _compactPalmCircleMatches(Hand hand, {required Size imageSize}) {
    return geometry
            .evaluatePalmLandmarkCircle2D(
              hand: hand,
              imageSize: imageSize,
              requiredTypes:
                  HandGestureThresholds.directionCompactPalmCircleTypes,
              radiusPalmWidthRatio:
                  HandGestureThresholds
                      .directionCompactPalmCircleRadiusPalmWidthRatio,
              minimumRadiusImageShortSideRatio:
                  HandGestureThresholds
                      .directionCompactPalmCircleMinImageShortSideRatio,
            )
            ?.allRequiredInside ??
        false;
  }

  _DirectionFingerFoldState _directionFingerFoldState({
    required HandLandmark? mcp,
    required HandLandmark? pip,
    required HandLandmark? dip,
    required HandLandmark? tip,
    required double palmWidth,
  }) {
    if (mcp == null || pip == null || dip == null || tip == null) {
      return _DirectionFingerFoldState.unavailable;
    }

    // Closed-finger classification is intentionally angle-free. All values
    // are normalized 3D area/compression percentages, so palm-side and
    // back-side views use the same rules.
    if (geometry.isFingerTopClusterFolded3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: palmWidth,
        ) ||
        geometry.isFingerFoldedByCompression3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: palmWidth,
        )) {
      return _DirectionFingerFoldState.folded;
    }

    if (geometry.isFingerClearlyOpenByArea3D(
      mcp: mcp,
      pip: pip,
      dip: dip,
      tip: tip,
      palmWidth: palmWidth,
    )) {
      return _DirectionFingerFoldState.open;
    }
    return _DirectionFingerFoldState.uncertain;
  }

  double _foldReferencePalmWidth(Hand hand) {
    final mcps = const [
          HandLandmarkType.indexFingerMCP,
          HandLandmarkType.middleFingerMCP,
          HandLandmarkType.ringFingerMCP,
          HandLandmarkType.pinkyMCP,
        ]
        .map((type) => geometry.visibleLandmark(hand, type))
        .whereType<HandLandmark>()
        .toList(growable: false);
    var maximumDistance = 0.0;
    for (var first = 0; first < mcps.length; first += 1) {
      for (var second = first + 1; second < mcps.length; second += 1) {
        maximumDistance = math.max(
          maximumDistance,
          geometry.distanceBetweenLandmarks3D(mcps[first], mcps[second]),
        );
      }
    }
    return maximumDistance;
  }

  double _maximumLandmarkDistance(List<HandLandmark> landmarks) {
    var maximumDistance = 0.0;
    for (var first = 0; first < landmarks.length; first += 1) {
      for (var second = first + 1; second < landmarks.length; second += 1) {
        maximumDistance = math.max(
          maximumDistance,
          geometry.distanceBetweenLandmarks(
            landmarks[first],
            landmarks[second],
          ),
        );
      }
    }
    return maximumDistance;
  }

  _HorizontalDirectionEvaluation _evaluateHorizontalDirection({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required bool mirrorPalmHorizontally,
    required HandMoveDirection direction,
  }) {
    final landmarks = <HandLandmarkType, HandLandmark>{};
    for (final type in _horizontalCriticalTypes) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) {
        return const _HorizontalDirectionEvaluation(
          matches: false,
          reason: 'missing required point 0 or index point 5-8',
        );
      }
      landmarks[type] = landmark;
    }

    HandLandmark point(HandLandmarkType type) => landmarks[type]!;
    HandLandmark? visiblePoint(HandLandmarkType type) =>
        geometry.visibleLandmark(hand, type);
    final wrist = point(HandLandmarkType.wrist);
    final indexMcp = point(HandLandmarkType.indexFingerMCP);
    final indexPip = point(HandLandmarkType.indexFingerPIP);
    final indexDip = point(HandLandmarkType.indexFingerDIP);
    final indexTip = point(HandLandmarkType.indexFingerTip);
    final palmMcps = <HandLandmark>[
      indexMcp,
      ...[
        visiblePoint(HandLandmarkType.middleFingerMCP),
        visiblePoint(HandLandmarkType.ringFingerMCP),
        visiblePoint(HandLandmarkType.pinkyMCP),
      ].whereType<HandLandmark>(),
    ];
    final palmAnchors = [wrist, ...palmMcps];
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
    final pinkyMcp = visiblePoint(HandLandmarkType.pinkyMCP);
    final palmWidth =
        pinkyMcp != null
            ? geometry.distanceBetweenLandmarks(indexMcp, pinkyMcp)
            : _maximumLandmarkDistance(palmMcps);
    if (!palmWidth.isFinite || palmWidth <= 0) {
      return const _HorizontalDirectionEvaluation(
        matches: false,
        reason: 'invalid palm width',
      );
    }
    final foldPalmWidth = _foldReferencePalmWidth(hand);
    if (!foldPalmWidth.isFinite || foldPalmWidth <= 0) {
      return const _HorizontalDirectionEvaluation(
        matches: false,
        reason: 'invalid folded-finger palm reference',
      );
    }

    final directionAngle = _indexDirectionAngleDegrees(
      indexMcp: indexMcp,
      indexTip: indexTip,
      mirrorHorizontally: mirrorHorizontally,
    );
    final isLeft = direction == HandMoveDirection.left;
    if (!isLeft &&
        _isZoomOutConflict(
          hand,
          mirrorPalmHorizontally: mirrorPalmHorizontally,
        )) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason: 'zoom-out closed pinch',
      );
    }
    final minIndexStraightness =
        isLeft
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
    if (isLeft &&
        (angle567 < HandGestureThresholds.movingLeftIndexMinJointAngleDegrees ||
            angle678 <
                HandGestureThresholds.movingLeftIndexMinJointAngleDegrees)) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'index joints ${angle567.toStringAsFixed(1)}/'
            '${angle678.toStringAsFixed(1)} below '
            '${HandGestureThresholds.movingLeftIndexMinJointAngleDegrees.toStringAsFixed(0)}',
      );
    }

    final indexPathLength =
        geometry.distanceBetweenLandmarks(indexMcp, indexPip) +
        geometry.distanceBetweenLandmarks(indexPip, indexDip) +
        geometry.distanceBetweenLandmarks(indexDip, indexTip);
    final indexStraightness =
        indexPathLength > 0
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
    final indexTipBeyondPalm =
        isLeft
            ? indexTipScreenX <=
                palmCenter.dx - palmWidth * tipPalmWidthOffsetRatio
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

    var foldedFingerCount = 0;
    var openFingerCount = 0;
    var uncertainFingerCount = 0;
    var unavailableFingerCount = 0;
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
      final foldState = _directionFingerFoldState(
        mcp: visiblePoint(finger.$2),
        pip: visiblePoint(finger.$3),
        dip: visiblePoint(finger.$4),
        tip: visiblePoint(finger.$5),
        palmWidth: foldPalmWidth,
      );
      if (foldState == _DirectionFingerFoldState.folded) {
        foldedFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.open) {
        openFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.uncertain) {
        uncertainFingerCount += 1;
      } else if (foldState == _DirectionFingerFoldState.unavailable) {
        unavailableFingerCount += 1;
      }
    }

    final compactPalmCircleMatches = _compactPalmCircleMatches(
      hand,
      imageSize: imageSize,
    );
    if (foldedFingerCount <
            HandGestureThresholds.directionMinConfirmedFoldedFingerCount &&
        !compactPalmCircleMatches) {
      return _HorizontalDirectionEvaluation(
        matches: false,
        directionAngleDegrees: directionAngle,
        reason:
            'only $foldedFingerCount/3 folded fingers; '
            '$openFingerCount open, '
            '$uncertainFingerCount uncertain, '
            '$unavailableFingerCount unavailable; need '
            '${HandGestureThresholds.directionMinConfirmedFoldedFingerCount}; '
            'compact palm circle failed',
      );
    }

    return _HorizontalDirectionEvaluation(
      matches: true,
      directionAngleDegrees: directionAngle,
      reason:
          compactPalmCircleMatches && foldedFingerCount == 0
              ? 'matched compact palm circle'
              : 'matched',
    );
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
    final fartherProgress =
        maxDepthDelta > 0
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
    final baseType =
        direction == HandMoveDirection.down
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

  void _setDebugSummary(String value) {
    _debugSummary = value;

    if (!kDebugMode || _lastPrintedDebugSummary == value) return;

    _lastPrintedDebugSummary = value;
    debugPrint('[DirectionGestureDetector] $value');
  }
}

enum _DirectionHandStability { settling, steady, moving }

enum _DirectionFingerFoldState { folded, open, uncertain, unavailable }

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
