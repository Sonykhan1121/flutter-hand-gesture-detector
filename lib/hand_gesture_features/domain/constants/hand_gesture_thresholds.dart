import 'dart:math' as math;

import 'package:hand_detection/hand_detection.dart';

abstract final class HandGestureThresholds {
  static const int maxDetectionDimension = 640;

  static const double minHandScore = 0.45;
  static const double minPackageGestureConfidence = 0.50;

  static const double openPalmEnterConfidence = 0.55;
  static const double openPalmExitConfidence = 0.45;
  static const double openPalmMinFingerConfidence = 0.50;
  static const double openPalmMinSpreadConfidence = 0.50;
  static const double openPalmMinPalmSideConfidence = 0.35;
  static const double openPalmMinYAxisConfidence = 0.55;
  static const double openPalmMinUpperFingerChainConfidence = 0.50;
  static const int openPalmSmoothingSampleCount = 4;
  static const int openPalmSmoothingMinPositiveSamples = 2;
  static const Duration openPalmSmoothingMaxAge = Duration(milliseconds: 500);

  static const Duration followObjectMessageHoldDuration = Duration(
    milliseconds: 1200,
  );
  static const Duration followObjectFirstOpenPalmHoldDuration = Duration(
    seconds: 1,
  );
  static const double followTargetReleasePointPadding = 0.10;
  static const double followTargetMinTrackingOverlap = 0.08;
  static const double followTargetMaxTrackingDistance = 0.18;
  static const Duration followTargetLostHoldDuration = Duration(
    milliseconds: 900,
  );
  static const Duration faceDetectHoldDuration = Duration(seconds: 2);

  static const double minLandmarkVisibility = 0.35;
  static const double landmarkDepthWeight = 0.65;

  static const List<HandLandmarkType> directionFingerTipTypes = [
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  static const List<List<HandLandmarkType>> directionFingerChainTypes = [
    [
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.indexFingerPIP,
      HandLandmarkType.indexFingerDIP,
      HandLandmarkType.indexFingerTip,
    ],
    [
      HandLandmarkType.middleFingerMCP,
      HandLandmarkType.middleFingerPIP,
      HandLandmarkType.middleFingerDIP,
      HandLandmarkType.middleFingerTip,
    ],
    [
      HandLandmarkType.ringFingerMCP,
      HandLandmarkType.ringFingerPIP,
      HandLandmarkType.ringFingerDIP,
      HandLandmarkType.ringFingerTip,
    ],
    [
      HandLandmarkType.pinkyMCP,
      HandLandmarkType.pinkyPIP,
      HandLandmarkType.pinkyDIP,
      HandLandmarkType.pinkyTip,
    ],
  ];

  static const List<HandLandmarkType> palmReferenceTypes = [
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.pinkyMCP,
  ];

  static const int directionFingerChainMinAlignedCount = 3;
  static const double directionFingerChainMinHorizontalImageRatio = 0.025;
  static const double directionFingerChainMinHorizontalSpanRatio = 0.12;
  static const double directionFingerChainHorizontalDominanceRatio = 1.25;
  static const double directionFingerChainRightDominanceRatio = 1.10;
  static const double directionFingerChainUpDiagonalHorizontalRatio = 0.25;
  static const double directionFingerChainMinVerticalImageRatio = 0.025;
  static const double directionFingerChainMinVerticalSpanRatio = 0.18;
  static const double directionFingerChainVerticalDominanceRatio = 1.25;
  static const double directionMovingUpMinBackSideConfidence = 0.35;
  static const double directionFingerChainMaxDepthProjectionRatio = 1.35;
  static const int directionDownRejectFoldedLongFingerCount = 3;

  static const double fingerTipVerticalMaxSpreadRatio = 0.22;
  static const double fingerTipHorizontalMaxSpreadRatio = 0.22;
  static const double sideBendMinRatio = 0.16;
  static const double rightSideBendMinRatio = 0.11;
  static const double rightFingerTipMinOffsetRatio = 0.08;
  static const int rightFingerTipMinAlignedCount = 3;
  static const double verticalBendMinRatio = 0.16;

  static const double wristToMcpAverageMaxRatio = 0.30;
  static const double wristToMcpSingleMaxRatio = 0.40;

  static const double extendedFingerRatio = 1.20;
  static const double foldedFingerRatio = 1.03;
  static const double thumbExtendedRatio = 1.15;

  static const double fingerFoldedMaxAngleDegrees = 145.0;
  static const double fingerExtendedMinAngleDegrees = 160.0;

  static const double okTouchMaxDistanceRatio = 0.11;

  static const double punchKnuckleMaxYSpreadRatio = 0.12;
  static const double punchKnuckleMaxDepthSpreadRatio = 0.22;
  static const double punchGestureMinPackageConfidence = 0.60;
  static const int punchMaxDownExtendedFingerChainCount = 1;

  static const int indexCircleHistoryMaxLength = 36;
  static const int indexCircleMinSampleCount = 5;
  static const Duration indexCircleWindow = Duration(milliseconds: 1400);
  static const Duration cancelEverythingHoldDuration = Duration(
    milliseconds: 900,
  );
  static const double indexCircleMinAngleRadians = math.pi * 0.90;
  static const double indexCircleMinImageRadiusRatio = 0.006;
  static const double indexCircleMinRadiusRatio = 0.015;
  static const double indexCircleMaxRadiusVariationRatio = 1.60;
  static const double indexCircleMaxDepthVariationRatio = 0.32;

  static const double indexUpperFacingMinDistanceRatio = 0.08;
  static const double indexUprightMaxSideOffsetRatio = 0.50;

  static const double closedThumbMaxPalmDistanceRatio = 0.30;
  static const double closedThumbTipIpPalmRatio = 1.00;
  static const double closedThumbMaxKnuckleDistanceRatio = 0.32;
  static const double closedThumbMaxTipMcpDistanceRatio = 0.36;

  static const double zoomClosedMaxDistanceRatio = 0.26;
  static const double zoomOpenMinDistanceRatio = 0.27;
  static const double zoomMinChangeRatio = 0.025;
  static const double zoomMaxPalmMovementRatio = 0.08;
  static const double partialZoomOutOpenMinImageRatio = 0.045;
  static const double partialZoomOutMinChangeImageRatio = 0.018;
  static const double partialZoomOutClosedMaxStartDistanceFactor = 0.72;

  static const Duration zoomStartPoseHoldDuration = Duration(milliseconds: 300);
  static const double zoomActiveTipMinPalmDistanceRatio = 0.06;
  static const double zoomMinLandmarkVisibility = 0.30;

  static const Duration zoomReleaseResetDuration = Duration(milliseconds: 650);
  static const Duration zoomMaxGestureDuration = Duration(milliseconds: 2600);
  static const Duration zoomMinGestureDuration = Duration(milliseconds: 90);
  static const Duration zoomHoldDuration = Duration(milliseconds: 1200);
  static const Duration gestureZoomRepeatInterval = Duration(milliseconds: 100);

  static const Duration minFrameProcessInterval = Duration(milliseconds: 100);
  static const double zoomStep = 0.2;
  static const double gestureZoomStep = 0.08;
  static const Duration recordStartHoldDuration = Duration(seconds: 1);
  static const Duration recordPauseHoldDuration = Duration(seconds: 1);
  static const Duration recordStopHoldDuration = Duration(seconds: 2);
}
