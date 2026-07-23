import 'dart:math' as math;
import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_object_sequence_phase.dart';
import '../enums/gesture_debug_mode.dart';
import '../enums/zoom_direction.dart';
import '../models/custom_gesture_detection_result.dart';
import '../models/gesture_debug_evaluation.dart';
import 'hand_geometry_service.dart';

/// Builds painter diagnostics with the same thresholds and geometry services
/// used by live gesture detection.
class GestureDebugEvaluator {
  const GestureDebugEvaluator({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  GestureDebugEvaluation evaluate({
    required GestureDebugMode mode,
    required Hand? hand,
    required Size imageSize,
    required bool mirrorPalmHorizontally,
    required bool mirrorScreenHorizontally,
    required CustomGestureDetectionResult customResult,
    required double returnMainHoldProgress,
    required ZoomDirection pendingZoomDirection,
    required double zoomHoldProgress,
    required bool zoomPalmStable,
    required bool zoomStableFingers,
    required bool isRecording,
    required bool isRecordingPaused,
    required String recordingActionLabel,
    required double recordingHoldProgress,
    required double callMeHoldProgress,
    required FollowObjectSequencePhase followPhase,
    required bool? followOpenPalm,
    required bool? followClosedFist,
    required int followRelaxedReleaseFrames,
    required double followFirstOpenHoldProgress,
    required double followHandReturnProgress,
    bool? followIndexOnly,
    double followPointHoldProgress = 0,
    double followFinalPalmProgress = 0,
  }) {
    if (hand == null || !geometry.isReliableHand(hand)) {
      return GestureDebugEvaluation(
        title: _title(mode),
        matches: false,
        requirements: const [
          GestureDebugRequirement(
            matches: false,
            text: 'Reliable hand required',
          ),
        ],
        landmarkTypes: const {},
      );
    }

    switch (mode) {
      case GestureDebugMode.zoomIn:
      case GestureDebugMode.zoomOut:
        return _evaluateZoom(
          mode: mode,
          hand: hand,
          imageSize: imageSize,
          mirrorPalmHorizontally: mirrorPalmHorizontally,
          mirrorScreenHorizontally: mirrorScreenHorizontally,
          pendingZoomDirection: pendingZoomDirection,
          holdProgress: zoomHoldProgress,
          palmStable: zoomPalmStable,
          stableFingers: zoomStableFingers,
        );
      case GestureDebugMode.returnMain:
        return _evaluateReturnMain(
          hand: hand,
          imageSize: imageSize,
          mirrorHorizontally: mirrorScreenHorizontally,
          holdProgress: returnMainHoldProgress,
          detected: customResult.isCancelEverything,
        );
      case GestureDebugMode.recording:
        return _evaluateRecording(
          hand: hand,
          isRecording: isRecording,
          isRecordingPaused: isRecordingPaused,
          actionLabel: recordingActionLabel,
          holdProgress: recordingHoldProgress,
          customResult: customResult,
        );
      case GestureDebugMode.callMe:
        return _evaluateCallMe(
          hand: hand,
          holdProgress: callMeHoldProgress,
          detected: customResult.isCallMe,
        );
      case GestureDebugMode.followObject:
        return _evaluateFollowObject(
          hand: hand,
          phase: followPhase,
          openPalm: followOpenPalm,
          closedFist: followClosedFist,
          firstOpenHoldProgress: followFirstOpenHoldProgress,
          handReturnProgress: followHandReturnProgress,
          indexOnly: followIndexOnly,
          pointHoldProgress: followPointHoldProgress,
          finalPalmProgress: followFinalPalmProgress,
        );
      case GestureDebugMode.off:
      case GestureDebugMode.direction:
      case GestureDebugMode.punch:
        return GestureDebugEvaluation(
          title: _title(mode),
          matches: false,
          requirements: const [],
          landmarkTypes: const {},
        );
    }
  }

  GestureDebugEvaluation _evaluateZoom({
    required GestureDebugMode mode,
    required Hand hand,
    required Size imageSize,
    required bool mirrorPalmHorizontally,
    required bool mirrorScreenHorizontally,
    required ZoomDirection pendingZoomDirection,
    required double holdProgress,
    required bool palmStable,
    required bool stableFingers,
  }) {
    final requirements = <GestureDebugRequirement>[];
    final thumbIp = _zoomLandmark(hand, HandLandmarkType.thumbIP);
    final thumbTip = _zoomLandmark(hand, HandLandmarkType.thumbTip);
    final indexDip = _zoomLandmark(hand, HandLandmarkType.indexFingerDIP);
    final indexTip = _zoomLandmark(hand, HandLandmarkType.indexFingerTip);
    final requiredPointsVisible =
        thumbIp != null &&
        thumbTip != null &&
        indexDip != null &&
        indexTip != null;
    requirements.add(
      GestureDebugRequirement(
        matches: requiredPointsVisible,
        text: 'Points 3, 4, 7, 8 visible',
      ),
    );

    final palmSide = geometry.isPalmSideFacingCamera(
      hand: hand,
      mirrorHorizontally: mirrorPalmHorizontally,
      minNormalizedCross: HandGestureThresholds.zoomMinPalmSideCross,
      minLandmarkVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
    requirements.add(
      GestureDebugRequirement(
        matches: palmSide,
        text: 'Palm side facing camera',
      ),
    );

    var foldedCount = 0;
    for (final chain in HandGestureThresholds.directionFingerChainTypes.skip(
      1,
    )) {
      final mcp = _zoomLandmark(hand, chain[0]);
      final pip = _zoomLandmark(hand, chain[1]);
      final tip = _zoomLandmark(hand, chain[3]);
      if (mcp != null &&
          pip != null &&
          tip != null &&
          geometry.isFingerFoldedByAngle3D(mcp: mcp, pip: pip, tip: tip)) {
        foldedCount += 1;
      }
    }
    requirements.add(
      GestureDebugRequirement(
        matches: foldedCount == 3,
        text: 'Middle/ring/pinky folded $foldedCount/3',
      ),
    );

    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
    var indexAboveThumb = false;
    var distance2dRatio = double.infinity;
    var distance3dRatio = double.infinity;
    var validRayRelation = false;
    bool? thumbTucked;
    if (requiredPointsVisible && handSize > 0) {
      indexAboveThumb = geometry.isLandmarkSegmentAbove2D(
        upperStart: indexDip,
        upperEnd: indexTip,
        lowerStart: thumbIp,
        lowerEnd: thumbTip,
        minVerticalGap:
            handSize * HandGestureThresholds.zoomIndexAboveThumbMinGapRatio,
      );
      distance2dRatio =
          geometry.distanceBetweenLandmarks(thumbTip, indexTip) / handSize;
      distance3dRatio =
          geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) / handSize;
      final relation = geometry.forwardRayIntersection2D(
        firstStart: thumbTip,
        firstThrough: thumbIp,
        secondStart: indexTip,
        secondThrough: indexDip,
        minForwardScale: HandGestureThresholds.zoomInMinForwardRayScale,
        parallelToleranceDegrees:
            HandGestureThresholds.zoomInParallelRayToleranceDegrees,
        minParallelLineSeparation:
            handSize *
            HandGestureThresholds.zoomInParallelMinLineSeparationRatio,
      );
      validRayRelation =
          relation != null &&
          geometry.isForwardRayRelationInHandQuadrant2D(
            relation: relation,
            firstStart: thumbTip,
            firstThrough: thumbIp,
            secondStart: indexTip,
            secondThrough: indexDip,
            imageSize: imageSize,
            handedness: hand.handedness,
            mirrorHorizontally: mirrorScreenHorizontally,
          );
      final palmCenter = geometry.palmCenter3D(hand);
      if (palmCenter != null) {
        thumbTucked = geometry.isThumbTuckedForFist3D(
          hand: hand,
          palmCenter: palmCenter,
          handSize: handSize,
        );
      }
    }
    requirements.add(
      GestureDebugRequirement(
        matches: indexAboveThumb,
        text: 'Index segment above thumb segment',
      ),
    );

    final isZoomOut = mode == GestureDebugMode.zoomOut;
    final distanceMatches = isZoomOut
        ? distance2dRatio <=
                  HandGestureThresholds.zoomTouchMax2dDistanceRatio ||
              distance3dRatio <=
                  HandGestureThresholds.zoomClosedMaxDistanceRatio
        : distance2dRatio >= HandGestureThresholds.zoomInMinDistanceRatio &&
              distance3dRatio >= HandGestureThresholds.zoomInMinDistanceRatio;
    requirements.add(
      GestureDebugRequirement(
        id: GestureDebugRequirementId.zoomTipGap,
        matches: distanceMatches,
        text: isZoomOut
            ? 'Tip gap 2D ${(distance2dRatio * 100).toStringAsFixed(1)}%, '
                  '3D ${(distance3dRatio * 100).toStringAsFixed(1)}% (closed)'
            : 'Tip gap 2D ${(distance2dRatio * 100).toStringAsFixed(1)}%, '
                  '3D ${(distance3dRatio * 100).toStringAsFixed(1)}% (open)',
      ),
    );
    if (!isZoomOut) {
      requirements.add(
        GestureDebugRequirement(
          matches: validRayRelation,
          text: 'Forward ray relation in correct hand quadrant',
        ),
      );
    } else {
      requirements.add(
        GestureDebugRequirement(
          matches: thumbTucked != true,
          text: thumbTucked == null
              ? 'Thumb-tucked check unavailable (allowed)'
              : 'Thumb not tucked into fist',
        ),
      );
    }

    final expectedDirection = isZoomOut
        ? ZoomDirection.zoomOut
        : ZoomDirection.zoomIn;
    requirements.addAll([
      GestureDebugRequirement(
        matches: pendingZoomDirection == expectedDirection,
        text: 'Detector pending ${isZoomOut ? 'Zoom Out' : 'Zoom In'}',
      ),
      GestureDebugRequirement(matches: palmStable, text: 'Palm stable'),
      GestureDebugRequirement(
        matches: stableFingers,
        text: 'Folded fingers stable',
      ),
      GestureDebugRequirement(
        matches: holdProgress >= 1,
        text: 'Hold ${(holdProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
    ]);

    final baseMatches =
        requiredPointsVisible &&
        palmSide &&
        foldedCount == 3 &&
        indexAboveThumb &&
        distanceMatches &&
        (!isZoomOut || thumbTucked != true) &&
        (isZoomOut || validRayRelation);
    return GestureDebugEvaluation(
      title: isZoomOut ? 'ZOOM OUT' : 'ZOOM IN',
      matches: baseMatches && holdProgress >= 1,
      requirements: requirements,
      landmarkTypes: const {
        HandLandmarkType.wrist,
        HandLandmarkType.thumbMCP,
        HandLandmarkType.thumbIP,
        HandLandmarkType.thumbTip,
        HandLandmarkType.indexFingerMCP,
        HandLandmarkType.indexFingerPIP,
        HandLandmarkType.indexFingerDIP,
        HandLandmarkType.indexFingerTip,
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerTip,
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerTip,
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyTip,
      },
    );
  }

  GestureDebugEvaluation _evaluateReturnMain({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required double holdProgress,
    required bool detected,
  }) {
    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
    final requirements = <GestureDebugRequirement>[];
    const names = ['Index', 'Middle', 'Ring', 'Pinky'];
    var allChainsMatch = handSize > 0;
    for (
      var index = 0;
      index < HandGestureThresholds.directionFingerChainTypes.length;
      index += 1
    ) {
      final chain = geometry.visibleFingerChain(
        hand,
        HandGestureThresholds.directionFingerChainTypes[index],
      );
      var matches = false;
      var detail = 'missing point';
      if (chain != null && handSize > 0) {
        final descending = geometry.evaluateDescendingFingerChain(
          chain: chain,
          handSize: handSize,
          minAdjacentGapRatio: HandGestureThresholds
              .returnToMainMinAdjacentVerticalGapHandSizeRatio,
        );
        final angle = geometry.fingerJointAngleDegrees3D(
          mcp: chain[0],
          pip: chain[1],
          tip: chain[3],
        );
        final dx = geometry.fingerChainDeltaX(
          chain,
          imageSize: imageSize,
          mirrorHorizontally: mirrorHorizontally,
        );
        final dy = geometry.fingerChainDeltaY(chain);
        final projectedLength = math.sqrt(dx * dx + dy * dy);
        final minLength =
            handSize *
            HandGestureThresholds.returnToMainFingerMinProjectedHandSizeRatio;
        final pointsDescend = descending?.matches ?? false;
        final angleMatches =
            angle >=
            HandGestureThresholds.returnToMainFingerMinJointAngleDegrees;
        final pointsDown =
            projectedLength >= minLength &&
            dy > 0 &&
            dy.abs() >= dx.abs() &&
            !geometry.isFingerChainDepthDominant(
              chain: chain,
              deltaX: dx,
              deltaY: dy,
            );
        matches = pointsDescend && angleMatches && pointsDown;
        final gapValues =
            descending?.adjacentVerticalGapRatios
                .map((gap) => '${(gap * 100).toStringAsFixed(0)}%')
                .join('/') ??
            'missing';
        final projectedRatio = projectedLength / handSize;
        final depthRejected = geometry.isFingerChainDepthDominant(
          chain: chain,
          deltaX: dx,
          deltaY: dy,
        );
        detail =
            '${angle.toStringAsFixed(0)}°≥${HandGestureThresholds.returnToMainFingerMinJointAngleDegrees.toStringAsFixed(0)}° • '
            'gaps $gapValues≥${(HandGestureThresholds.returnToMainMinAdjacentVerticalGapHandSizeRatio * 100).toStringAsFixed(0)}% • '
            'length ${(projectedRatio * 100).toStringAsFixed(0)}%≥${(HandGestureThresholds.returnToMainFingerMinProjectedHandSizeRatio * 100).toStringAsFixed(0)}% • '
            '${pointsDown ? 'DOWN' : 'NOT DOWN'} • ${depthRejected ? 'DEPTH BAD' : 'DEPTH OK'}';
      }
      allChainsMatch = allChainsMatch && matches;
      requirements.add(
        GestureDebugRequirement(
          matches: matches,
          text: '${names[index]}: $detail',
        ),
      );
    }
    requirements.add(
      GestureDebugRequirement(
        matches: holdProgress >= 1 || detected,
        text: 'Hold ${(holdProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
    );
    return GestureDebugEvaluation(
      title: 'RETURN MAIN',
      matches: detected || (allChainsMatch && holdProgress >= 1),
      requirements: requirements,
      landmarkTypes: HandGestureThresholds.directionFingerChainTypes
          .expand((chain) => chain)
          .toSet(),
    );
  }

  GestureDebugEvaluation _evaluateRecording({
    required Hand hand,
    required bool isRecording,
    required bool isRecordingPaused,
    required String actionLabel,
    required double holdProgress,
    required CustomGestureDetectionResult customResult,
  }) {
    final requirements = <GestureDebugRequirement>[];
    bool poseMatches;
    if (!isRecording) {
      final ok = _evaluateOk(hand);
      poseMatches = ok.matches;
      requirements.addAll(ok.requirements);
      requirements.add(
        GestureDebugRequirement(
          matches: customResult.isOk,
          text: 'OK start pose detected',
        ),
      );
    } else {
      final punch = geometry.matchesPunchMiddleFingerCircle(hand);
      final victory = geometry.isReliablePackageGesture(
        hand.gesture,
        type: GestureType.victory,
      );
      poseMatches = punch || victory;
      requirements.addAll([
        GestureDebugRequirement(
          matches: punch,
          text: 'Punch circle (pause/resume)',
        ),
        GestureDebugRequirement(
          matches: victory,
          text: 'Victory package (stop recording)',
        ),
        GestureDebugRequirement(
          matches: true,
          text: isRecordingPaused
              ? 'Recording currently PAUSED'
              : 'Recording active',
        ),
      ]);
    }
    requirements.addAll([
      GestureDebugRequirement(
        matches: actionLabel.isNotEmpty,
        text: actionLabel.isEmpty ? 'No recording action pending' : actionLabel,
      ),
      GestureDebugRequirement(
        matches: holdProgress >= 1,
        text: 'Action hold ${(holdProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
    ]);
    return GestureDebugEvaluation(
      title: isRecording ? 'RECORDING CONTROL' : 'START RECORDING',
      matches: poseMatches && holdProgress >= 1,
      requirements: requirements,
      landmarkTypes: HandLandmarkType.values.toSet(),
    );
  }

  GestureDebugEvaluation _evaluateCallMe({
    required Hand hand,
    required double holdProgress,
    required bool detected,
  }) {
    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
    final palmCenter = geometry.palmCenter3D(hand);
    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);
    final pointsReady =
        handSize > 0 &&
        palmCenter != null &&
        thumbTip != null &&
        thumbIp != null &&
        pinkyTip != null &&
        pinkyPip != null;
    var thumbOpen = false;
    var pinkyOpen = false;
    var separated = false;
    if (pointsReady) {
      thumbOpen =
          geometry.distanceToPoint3D(thumbTip, palmCenter) >
              geometry.distanceToPoint3D(thumbIp, palmCenter) *
                  HandGestureThresholds.thumbExtendedRatio &&
          geometry.distanceToPoint3D(thumbTip, palmCenter) > handSize * 0.23;
      pinkyOpen = geometry.isFingerExtended3D(
        tip: pinkyTip,
        pip: pinkyPip,
        palmCenter: palmCenter,
        handSize: handSize,
      );
      separated =
          geometry.distanceBetweenLandmarks3D(thumbTip, pinkyTip) >
          handSize * 0.55;
    }
    var foldedCount = 0;
    for (final chain in HandGestureThresholds.directionFingerChainTypes.take(
      3,
    )) {
      final tip = geometry.visibleLandmark(hand, chain[3]);
      final pip = geometry.visibleLandmark(hand, chain[1]);
      if (tip != null &&
          pip != null &&
          palmCenter != null &&
          geometry.isFingerFolded3D(
            tip: tip,
            pip: pip,
            palmCenter: palmCenter,
            handSize: handSize,
          )) {
        foldedCount += 1;
      }
    }
    final requirements = [
      GestureDebugRequirement(
        matches: pointsReady,
        text: 'Required thumb and pinky points visible',
      ),
      GestureDebugRequirement(matches: thumbOpen, text: 'Thumb open'),
      GestureDebugRequirement(matches: pinkyOpen, text: 'Pinky open'),
      GestureDebugRequirement(
        matches: separated,
        text: 'Thumb–pinky separation >55% hand',
      ),
      GestureDebugRequirement(
        matches: foldedCount == 3,
        text: 'Index/middle/ring folded $foldedCount/3',
      ),
      GestureDebugRequirement(matches: detected, text: 'Call Me pose detected'),
      GestureDebugRequirement(
        matches: holdProgress >= 1,
        text: 'Face hold ${(holdProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
    ];
    return GestureDebugEvaluation(
      title: 'CALL ME',
      matches: detected && holdProgress >= 1,
      requirements: requirements,
      landmarkTypes: const {
        HandLandmarkType.wrist,
        HandLandmarkType.thumbIP,
        HandLandmarkType.thumbTip,
        HandLandmarkType.indexFingerPIP,
        HandLandmarkType.indexFingerTip,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerTip,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerTip,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyTip,
      },
    );
  }

  GestureDebugEvaluation _evaluateFollowObject({
    required Hand hand,
    required FollowObjectSequencePhase phase,
    required bool? openPalm,
    required bool? closedFist,
    required double firstOpenHoldProgress,
    required double handReturnProgress,
    required bool? indexOnly,
    required double pointHoldProgress,
    required double finalPalmProgress,
  }) {
    final packageGesture = hand.gesture;
    final requirements = [
      GestureDebugRequirement(
        matches: phase != FollowObjectSequencePhase.idle,
        text: 'Phase: ${_followPhaseLabel(phase)}',
      ),
      GestureDebugRequirement(
        matches:
            phase != FollowObjectSequencePhase.holdingFirstOpen ||
            firstOpenHoldProgress >= 1,
        text:
            'First Open Palm hold ${(firstOpenHoldProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
      GestureDebugRequirement(
        matches: openPalm == true,
        text: 'Open Palm ${_boolLabel(openPalm)}',
      ),
      GestureDebugRequirement(
        matches:
            phase != FollowObjectSequencePhase.waitingForHandReturn ||
            handReturnProgress < 1,
        text:
            'Hand-return timeout ${(handReturnProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
      GestureDebugRequirement(
        matches: closedFist == true,
        text: 'Closed Fist ${_boolLabel(closedFist)}',
      ),
      GestureDebugRequirement(
        matches: indexOnly == true,
        text: 'Index-only point ${_boolLabel(indexOnly)}',
      ),
      GestureDebugRequirement(
        matches: pointHoldProgress >= 1,
        text:
            'Target dwell ${(pointHoldProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
      GestureDebugRequirement(
        matches:
            phase != FollowObjectSequencePhase.waitingForFinalPalm ||
            finalPalmProgress <= 1,
        text:
            'Final-palm window ${(finalPalmProgress * 100).toStringAsFixed(0)}% / 100%',
      ),
      GestureDebugRequirement(
        matches: packageGesture != null,
        text: packageGesture == null
            ? 'Package gesture unavailable'
            : 'Package ${packageGesture.type.name} '
                  '${packageGesture.confidence.isFinite ? '${(packageGesture.confidence * 100).toStringAsFixed(0)}%' : packageGesture.confidence}',
      ),
    ];
    return GestureDebugEvaluation(
      title: 'FOLLOW OBJECT',
      matches: phase != FollowObjectSequencePhase.idle,
      requirements: requirements,
      landmarkTypes: HandLandmarkType.values.toSet(),
    );
  }

  GestureDebugEvaluation _evaluateOk(Hand hand) {
    final palmCenter = geometry.palmCenter3D(hand);
    final handSize = geometry.handSizeFromBoundingBox(hand.boundingBox);
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
    final pointsReady =
        palmCenter != null &&
        handSize > 0 &&
        thumbTip != null &&
        indexMcp != null &&
        indexPip != null &&
        indexTip != null;
    var touch = false;
    var bent = false;
    if (pointsReady) {
      touch =
          geometry.distanceBetweenLandmarks3D(thumbTip, indexTip) <=
          math.max(
            handSize * HandGestureThresholds.okTouchMaxDistanceRatio,
            12,
          );
      bent =
          geometry.fingerJointAngleDegrees3D(
            mcp: indexMcp,
            pip: indexPip,
            tip: indexTip,
          ) <=
          150;
    }
    var openCount = 0;
    for (final chain in HandGestureThresholds.directionFingerChainTypes.skip(
      1,
    )) {
      final mcp = geometry.visibleLandmark(hand, chain[0]);
      final pip = geometry.visibleLandmark(hand, chain[1]);
      final tip = geometry.visibleLandmark(hand, chain[3]);
      if (mcp != null &&
          pip != null &&
          tip != null &&
          palmCenter != null &&
          geometry.isFingerExtendedByAngle3D(
            mcp: mcp,
            pip: pip,
            tip: tip,
            palmCenter: palmCenter,
            handSize: handSize,
          )) {
        openCount += 1;
      }
    }
    final requirements = [
      GestureDebugRequirement(matches: pointsReady, text: 'OK points visible'),
      GestureDebugRequirement(
        matches: touch,
        text: 'Thumb and index tips touching',
      ),
      GestureDebugRequirement(matches: bent, text: 'Index bent ≤150°'),
      GestureDebugRequirement(
        matches: openCount == 3,
        text: 'Middle/ring/pinky open $openCount/3',
      ),
    ];
    return GestureDebugEvaluation(
      title: 'OK',
      matches: pointsReady && touch && bent && openCount == 3,
      requirements: requirements,
      landmarkTypes: HandLandmarkType.values.toSet(),
    );
  }

  HandLandmark? _zoomLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

  String _title(GestureDebugMode mode) => switch (mode) {
    GestureDebugMode.off => 'DEBUG OFF',
    GestureDebugMode.direction => 'DIRECTIONS',
    GestureDebugMode.punch => 'PUNCH',
    GestureDebugMode.zoomIn => 'ZOOM IN',
    GestureDebugMode.zoomOut => 'ZOOM OUT',
    GestureDebugMode.returnMain => 'RETURN MAIN',
    GestureDebugMode.recording => 'RECORDING',
    GestureDebugMode.callMe => 'CALL ME',
    GestureDebugMode.followObject => 'FOLLOW OBJECT',
  };

  String _followPhaseLabel(FollowObjectSequencePhase phase) => switch (phase) {
    FollowObjectSequencePhase.idle => 'idle',
    FollowObjectSequencePhase.holdingFirstOpen => 'hold first open palm',
    FollowObjectSequencePhase.waitingForClosed => 'waiting for closed fist',
    FollowObjectSequencePhase.waitingForPoint => 'waiting for index point',
    FollowObjectSequencePhase.holdingPoint => 'holding target',
    FollowObjectSequencePhase.waitingForFinalPalm => 'waiting for final palm',
    FollowObjectSequencePhase.waitingForHandReturn => 'waiting for hand return',
  };

  String _boolLabel(bool? value) => value == null
      ? 'not evaluated'
      : value
      ? 'PASS'
      : 'FAIL';
}
