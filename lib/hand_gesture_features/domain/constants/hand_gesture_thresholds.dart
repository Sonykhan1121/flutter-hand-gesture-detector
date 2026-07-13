import 'dart:math' as math;

import 'package:hand_detection/hand_detection.dart';

/// Tunable values used by gesture detectors and the live camera screen.
abstract final class HandGestureThresholds {
  /// Caps detector input size so frame processing stays fast enough live.
  static const int maxDetectionDimension = 640;

  /// Lowest hand confidence accepted before gesture logic trusts the frame.
  static const double minHandScore = 0.45;

  /// Lowest package gesture confidence accepted from `hand_detection`.
  static const double minPackageGestureConfidence = 0.50;

  /// Open-palm hysteresis and smoothing thresholds.
  static const double openPalmEnterConfidence = 0.55;
  static const double openPalmExitConfidence = 0.45;
  static const double openPalmMinFingerConfidence = 0.50;
  static const double openPalmMinSpreadConfidence = 0.50;
  static const double openPalmMinPalmSideConfidence = 0.35;
  static const double openPalmMinYAxisConfidence = 0.55;
  static const double openPalmMinUpperFingerChainConfidence = 0.50;
  static const double openPalmLandmarkOverlapMaxRatio = 0.012;
  static const double openPalmAdjacentTipMinDistanceRatio = 0.045;
  static const double openPalmAdjacentJointMinDistanceRatio = 0.032;
  static const double openPalmMinAdjacentSeparationConfidence = 0.50;
  static const int openPalmSmoothingSampleCount = 4;
  static const int openPalmSmoothingMinPositiveSamples = 2;
  static const Duration openPalmSmoothingMaxAge = Duration(milliseconds: 500);

  /// Follow-object timing, release, tracking, and face-hold thresholds.
  static const Duration followObjectMessageHoldDuration = Duration(
    milliseconds: 1200,
  );
  static const Duration followObjectFirstOpenPalmHoldDuration = Duration(
    seconds: 1,
  );
  static const Duration followObjectHandReturnGraceDuration = Duration(
    seconds: 2,
  );
  static const int followObjectRelaxedReleaseMinExtendedFingers = 1;
  static const int followObjectRelaxedReleaseConfirmationFrames = 2;
  static const int followTargetSelectionConfirmationCycles = 2;
  static const Duration followTargetSelectionMemoryDuration = Duration(
    seconds: 2,
  );
  static const double followTargetSelectionMaxHandMovement = 0.15;
  static const Duration followTargetPostReleaseConfirmationDuration = Duration(
    milliseconds: 1500,
  );
  static const double followObjectRelaxedReleaseMinFingerAngleDegrees = 145;
  static const double followObjectRelaxedReleaseTipPastPipRatio = 1.05;
  static const double followObjectRelaxedReleaseMinReachRatio = 0.22;
  static const double followTargetReleasePointPadding = 0.10;
  static const double followTargetMinTrackingOverlap = 0.08;
  static const double followTargetMaxTrackingDistance = 0.18;
  static const Duration followTargetLostHoldDuration = Duration(
    milliseconds: 900,
  );
  static const Duration followTargetDetectionFreshness = Duration(
    milliseconds: 700,
  );
  static const Duration followTargetFreshDetectionWait = Duration(
    milliseconds: 750,
  );
  static const int followTargetLostDetectionCount = 2;
  static const double followTargetVisibleSimilarity = 0.72;
  static const Duration faceDetectHoldDuration = Duration(seconds: 2);
  static const Duration objectDetectionMinInterval = Duration(
    milliseconds: 350,
  );
  static const Duration iosObjectDetectionMinInterval = Duration(
    milliseconds: 650,
  );

  /// `true` uses `object_detection`; `false` uses Ultralytics YOLO on both
  /// Android (TFLite) and iOS (Core ML).
  static const bool useObjectDetectionPackage = false;
  static const int objectDetectionMaxDimension = 640;
  static const int objectDetectionMaxResults = 5;
  static const double objectDetectionScoreThreshold = 0.60;
  static const int iosObjectDetectionMaxDimension = 320;
  static const double iosObjectDetectionScoreThreshold = 0.35;
  static const String ultralyticsYoloModelId = 'yolo26n';
  static const bool ultralyticsYoloUseGpu = true;
  static const double ultralyticsYoloIouThreshold = 0.50;
  static const int ultralyticsYoloJpegQuality = 90;

  /// Sparse optical-flow tracking used between object detector cycles.
  static const int objectTrackingMaxDimension = 480;
  static const int iosObjectTrackingMaxDimension = 320;
  static const int objectTrackingHistoryLength = 12;
  static const int objectTrackingMaxFeatures = 80;
  static const int objectTrackingMinFeatures = 12;
  static const int objectTrackingReseedFeatureCount = 24;
  static const int objectTrackingReseedFrameCount = 15;
  static const double objectTrackingFeatureQuality = 0.01;
  static const double objectTrackingFeatureMinDistance = 5;
  static const double objectTrackingForwardBackwardError = 1.5;
  static const double objectTrackingMinRetention = 0.40;
  static const double objectTrackingMinInlierRatio = 0.60;
  static const double objectTrackingMaxCenterJump = 0.20;
  static const double objectTrackingMinFrameScale = 0.70;
  static const double objectTrackingMaxFrameScale = 1.40;
  static const double objectTrackingCorrectionBlend = 0.35;
  static const double objectTrackingOneEuroMinCutoff = 1.0;
  static const double objectTrackingOneEuroBeta = 0.10;
  static const double objectTrackingOneEuroDerivativeCutoff = 1.0;
  static const double followTargetFocusMovementDeadband = 0.03;
  static const Duration followTargetFocusMinInterval = Duration(
    milliseconds: 400,
  );

  /// Landmark filtering and depth scaling shared by 3D geometry checks.
  static const double minLandmarkVisibility = 0.35;
  static const double landmarkDepthWeight = 0.65;

  /// Fingertips used for movement direction and fingertip-wiggle detection.
  static const List<HandLandmarkType> directionFingerTipTypes = [
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  /// Long-finger landmark chains ordered from MCP to tip.
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

  /// Knuckle landmarks that describe the palm plane.
  static const List<HandLandmarkType> palmReferenceTypes = [
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.pinkyMCP,
  ];

  /// Direction gesture shape thresholds.
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
  static const int directionFingerWiggleMinAlignedCount = 3;
  static const int directionFingerWiggleHistoryMaxLength = 6;
  static const int directionFingerWiggleMinDirectionChanges = 2;
  static const int directionFingerWiggleCooldownFrames = 3;
  static const double directionFingerWiggleSmoothingAlpha = 0.45;
  static const double directionFingerWiggleMinStepRatio = 0.006;
  static const double directionFingerWiggleVerticalMinStepRatio = 0.005;
  static const double directionFingerWiggleMaxHorizontalStepRatio = 0.035;
  static const double directionFingerWiggleDownVerticalDominanceRatio = 1.45;
  static const double directionFingerWiggleDownMaxHorizontalStepRatio = 0.030;
  static const Duration directionFingerWiggleMaxSampleGap = Duration(
    milliseconds: 350,
  );
  static const Duration movingDownDisplayHoldDuration = Duration(
    milliseconds: 900,
  );
  static const Duration movingUpDisplayHoldDuration = Duration(
    milliseconds: 300,
  );

  /// Palm/finger shape ratios used by custom gesture checks.
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

  /// Fist/punch shape thresholds.
  static const double punchKnuckleMaxYSpreadRatio = 0.12;
  static const double punchKnuckleMaxDepthSpreadRatio = 0.22;
  static const double punchGestureMinPackageConfidence = 0.60;
  static const int punchMaxDownExtendedFingerChainCount = 1;

  /// Index-circle thresholds for the return-to-main-position gesture.
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

  /// Index-only pose thresholds used before accepting an index circle.
  static const double indexUpperFacingMinDistanceRatio = 0.08;
  static const double indexUprightMaxSideOffsetRatio = 0.50;

  static const double closedThumbMaxPalmDistanceRatio = 0.30;
  static const double closedThumbTipIpPalmRatio = 1.00;
  static const double closedThumbMaxKnuckleDistanceRatio = 0.32;
  static const double closedThumbMaxTipMcpDistanceRatio = 0.36;

  /// Pinch/open ratios and stability limits for zoom gestures.
  static const double zoomClosedMaxDistanceRatio = 0.26;
  static const double zoomOpenMinDistanceRatio = 0.27;
  static const double zoomMinChangeRatio = 0.025;
  static const double zoomMaxPalmMovementRatio = 0.08;
  static const int zoomStableFingerMinCount = 2;
  static const double zoomStableFingerMaxMovementRatio = 0.07;
  static const double partialZoomOutOpenMinImageRatio = 0.045;
  static const double partialZoomOutMinChangeImageRatio = 0.018;
  static const double partialZoomOutClosedMaxStartDistanceFactor = 0.72;

  /// Zoom gesture timing and repeat-rate thresholds.
  static const Duration zoomStartPoseHoldDuration = Duration(milliseconds: 300);
  static const double zoomActiveTipMinPalmDistanceRatio = 0.06;
  static const double zoomMinLandmarkVisibility = 0.30;

  static const Duration zoomReleaseResetDuration = Duration(milliseconds: 650);
  static const Duration zoomMaxGestureDuration = Duration(milliseconds: 2600);
  static const Duration zoomMinGestureDuration = Duration(milliseconds: 90);
  static const Duration zoomHoldDuration = Duration(milliseconds: 1200);
  static const Duration gestureZoomRepeatInterval = Duration(milliseconds: 100);

  /// Camera-frame cadence, manual zoom step, and recording hold timings.
  static const Duration minFrameProcessInterval = Duration(milliseconds: 50);
  static const double zoomStep = 0.2;
  static const double gestureZoomStep = 0.08;
  static const Duration recordStartHoldDuration = Duration(seconds: 1);
  static const Duration recordPauseHoldDuration = Duration(seconds: 1);
  static const Duration recordStopHoldDuration = Duration(seconds: 2);
}
