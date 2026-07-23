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
  static const Duration detectMyFaceReacquisitionDuration = Duration(
    milliseconds: 2500,
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
  static const Duration googleMlKitObjectDetectionMinInterval = Duration(
    milliseconds: 100,
  );
  static const Duration iosGoogleMlKitObjectDetectionMinInterval = Duration(
    milliseconds: 200,
  );
  static const Duration googleMlKitEmptyResultHoldDuration = Duration(
    milliseconds: 600,
  );
  static const int googleMlKitEmptyResultMissLimit = 3;
  static const double googleMlKitBoxSmoothingAlpha = 0.36;
  static const double googleMlKitFastBoxSmoothingAlpha = 0.76;
  static const double googleMlKitFastMotionThreshold = 0.06;
  static const double googleMlKitTrackMaxCenterDistance = 0.28;
  static const double googleMlKitHandFalsePositivePadding = 0.025;
  static const double googleMlKitHandFalsePositiveOverlapRatio = 0.45;
  static const Duration googleMlKitPartialTrackHoldDuration = Duration(
    milliseconds: 400,
  );
  static const int googleMlKitPartialTrackMissLimit = 3;
  static const Duration nativeMethodChannelObjectDetectionMinInterval =
      Duration(milliseconds: 250);
  static const Duration opencvSdkObjectDetectionMinInterval = Duration(
    milliseconds: 400,
  );

  static const int objectDetectionMaxDimension = 640;
  static const int objectDetectionMaxResults = 5;
  static const double objectDetectionPackageScoreThreshold = 0.60;
  static const Duration objectDetectionPackageEmptyResultHoldDuration =
      Duration(milliseconds: 800);
  static const int objectDetectionPackageEmptyResultMissLimit = 3;
  static const double objectDetectionPackageBoxSmoothingAlpha = 0.45;
  static const double objectDetectionPackageFastBoxSmoothingAlpha = 0.78;
  static const double objectDetectionPackageFastMotionThreshold = 0.08;
  static const double objectDetectionPackageTrackMaxCenterDistance = 0.24;
  static const Duration objectDetectionPackagePartialTrackHoldDuration =
      Duration(milliseconds: 650);
  static const int objectDetectionPackagePartialTrackMissLimit = 2;
  static const int iosObjectDetectionMaxDimension = 320;
  static const double iosObjectDetectionPackageScoreThreshold = 0.35;
  static const String ultralyticsYoloModelId = 'yolo26n';
  static const bool ultralyticsYoloUseGpu = true;
  static const int ultralyticsYoloMaxDimension = 640;
  static const int iosUltralyticsYoloMaxDimension = 416;
  static const double ultralyticsYoloConfidenceThreshold = 0.45;
  static const double ultralyticsYoloIouThreshold = 0.50;
  static const int ultralyticsYoloJpegQuality = 90;
  static const Duration ultralyticsYoloEmptyResultHoldDuration = Duration(
    milliseconds: 1200,
  );
  static const int ultralyticsYoloEmptyResultMissLimit = 3;
  static const double ultralyticsYoloBoxSmoothingAlpha = 0.42;
  static const double ultralyticsYoloFastBoxSmoothingAlpha = 0.78;
  static const double ultralyticsYoloFastMotionThreshold = 0.08;
  static const double ultralyticsYoloTrackMaxCenterDistance = 0.24;
  static const Duration ultralyticsYoloPartialTrackHoldDuration = Duration(
    milliseconds: 900,
  );
  static const int ultralyticsYoloPartialTrackMissLimit = 2;
  static const Duration ultralyticsYoloStartupRetryDelay = Duration(seconds: 5);
  static const double googleMlKitClassificationScoreThreshold = 0.50;
  static const String nativeMethodChannelModelAsset =
      'assets/models/yolov8n_oiv7.tflite';
  static const int nativeMethodChannelExpectedClassCount = 601;
  static const bool nativeMethodChannelUseGpu = true;
  static const double nativeMethodChannelConfidenceThreshold = 0.25;
  static const double nativeMethodChannelIouThreshold = 0.50;
  static const String opencvSdkModelAsset = 'assets/models/yolov8n_oiv7.onnx';
  static const String opencvSdkMetadataAsset =
      'assets/models/yolov8n_oiv7.tflite';
  static const int opencvSdkExpectedClassCount = 601;
  static const double opencvSdkConfidenceThreshold = 0.25;
  static const double opencvSdkIouThreshold = 0.50;
  static const Duration opencvSdkEmptyResultHoldDuration = Duration(
    milliseconds: 1000,
  );
  static const int opencvSdkEmptyResultMissLimit = 3;
  static const double opencvSdkBoxSmoothingAlpha = 0.42;
  static const double opencvSdkFastBoxSmoothingAlpha = 0.78;
  static const double opencvSdkFastMotionThreshold = 0.08;
  static const double opencvSdkTrackMaxCenterDistance = 0.24;
  static const Duration opencvSdkPartialTrackHoldDuration = Duration(
    milliseconds: 800,
  );
  static const int opencvSdkPartialTrackMissLimit = 2;
  static const Duration opencvSdkStartupRetryDelay = Duration(seconds: 5);
  static const Duration nativeMethodChannelEmptyResultHoldDuration = Duration(
    milliseconds: 800,
  );
  static const int nativeMethodChannelEmptyResultMissLimit = 3;
  static const double nativeMethodChannelBoxSmoothingAlpha = 0.42;
  static const double nativeMethodChannelFastBoxSmoothingAlpha = 0.78;
  static const double nativeMethodChannelFastMotionThreshold = 0.08;
  static const double nativeMethodChannelTrackMaxCenterDistance = 0.24;
  static const Duration nativeMethodChannelPartialTrackHoldDuration = Duration(
    milliseconds: 650,
  );
  static const int nativeMethodChannelPartialTrackMissLimit = 2;
  static const Duration nativeMethodChannelStartupRetryDelay = Duration(
    seconds: 5,
  );

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

  /// Static index-pointing direction thresholds.
  static const double directionIndexMinJointAngleDegrees = 135.0;
  static const double directionIndexMinProjectedHandSizeRatio = 0.20;
  static const double directionSectorHysteresisDegrees = 10.0;

  /// A direction pose is usable only after the detected hand center remains
  /// inside this hand-size-normalized radius for consecutive frames.
  static const double directionMaxHandCenterMovementRatio = 0.03;
  static const int directionRequiredSteadyFrames = 3;

  /// Minimum distal-index angle required by the vertical directions.
  static const double verticalDirectionIndexMinAngleDegrees = 170.0;

  static const double zoomInMinForwardRayScale = 1.0;

  /// Same-direction Zoom In rays within this angle meet at infinity.
  static const double zoomInParallelRayToleranceDegrees = 5.0;

  /// Parallel thumb/index axes must remain visibly separate. This applies only
  /// to the intersection-at-infinity case, not finite forward intersections.
  static const double zoomInParallelMinLineSeparationRatio = 0.10;
  static const double zoomIndexAboveThumbMinGapRatio = 0.02;

  /// Minimum normalized wrist/index/pinky orientation needed to prove that
  /// the palm, rather than the back of the hand, faces the camera for zoom.
  static const double zoomMinPalmSideCross = 0.10;

  /// Palm-extension requirement for the horizontal pointing directions.
  /// A tip at or closer than the palm plane uses 10%. The requirement grows
  /// linearly to 15% as the tip moves farther behind the palm.
  static const double directionTipMinPalmWidthOffsetRatio = 0.10;
  static const double directionTipMaxPalmWidthOffsetRatio = 0.15;
  static const double directionTipMaxDepthDeltaPalmWidthRatio = 0.25;

  /// Static Moving Left thresholds based only on points 0 and 5-20.
  static const double movingLeftIndexMinJointAngleDegrees = 145.0;
  static const double movingLeftIndexMinStraightnessRatio = 0.80;
  static const double movingLeftMinDirectionAngleDegrees = 125.0;
  static const double movingLeftMaxDirectionAngleDegrees = 235.0;
  static const int movingLeftRequiredConsecutiveFrames = 3;

  /// Static Moving Right thresholds based only on points 0 and 5-20.
  static const double movingRightIndexMinStraightnessRatio = 0.80;
  static const double movingRightMinDirectionAngleDegrees = 305.0;
  static const double movingRightMaxDirectionAngleDegrees = 70.0;
  static const int movingRightRequiredConsecutiveFrames = 3;

  /// Easy Moving Up thresholds: index points 5-8 set direction.
  static const double movingUpMinMcpPipDipJointAngleDegrees = 135.0;
  static const double movingUpMinMcpToTipPalmWidthRatio = 0.15;
  static const double movingUpMaxHorizontalToVerticalRatio = 0.75;
  static const double movingUpInitialMinDirectionAngleDegrees = 75.0;
  static const double movingUpInitialMaxDirectionAngleDegrees = 120.0;
  static const double movingUpActiveMinDirectionAngleDegrees = 70.0;
  static const double movingUpActiveMaxDirectionAngleDegrees = 125.0;

  /// Easy Moving Down thresholds: only index points 6-8 set direction.
  static const double movingDownMinPipToTipPalmWidthRatio = 0.15;
  static const double movingDownMaxHorizontalToVerticalRatio = 0.75;
  static const double movingDownInitialMinDirectionAngleDegrees = 245.0;
  static const double movingDownInitialMaxDirectionAngleDegrees = 295.0;
  static const double movingDownActiveMinDirectionAngleDegrees = 235.0;
  static const double movingDownActiveMaxDirectionAngleDegrees = 305.0;

  /// One confirmed folded middle/ring/pinky finger is enough for the normal
  /// direction path. The compact palm-circle alternative remains independent.
  static const int directionMinConfirmedFoldedFingerCount = 1;

  /// Alternative compact-palm direction shape. Point 5 and points 9-20 must
  /// fit inside a circle centered on palm points 0, 5, 9, 13, and 17. Index
  /// points 6-8 are deliberately excluded because they form the pointing ray.
  static const List<HandLandmarkType> directionCompactPalmCircleTypes = [
    HandLandmarkType.indexFingerMCP,
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

  /// White debug-circle radius relative to the 2D MCP palm width. Change this
  /// single value after live testing to make the compact circle larger/smaller.
  static const double directionCompactPalmCircleRadiusPalmWidthRatio = 0.90;

  /// Prevents a far/small hand from collapsing the compact direction circle.
  /// This is a radius ratio of the detection frame's shorter dimension.
  static const double directionCompactPalmCircleMinImageShortSideRatio = 0.15;

  /// Maximum squared MCP-to-tip reach relative to squared palm width.
  /// This is the easier 85% reach boundary represented as 0.85².
  static const double directionFoldedMaxReachAreaRatio = 0.7225;

  /// Maximum squared PIP/DIP/TIP spread relative to squared palm width.
  /// This is the easier 40% top-span boundary represented as 0.40².
  static const double directionFoldedMaxTopClusterAreaRatio = 0.16;

  /// Every clustered top point must remain within the easier 85% reach
  /// distance, represented as a 72.25% occupied-area ratio.
  static const double directionFoldedMaxClusterMcpAreaRatio = 0.7225;

  /// A closed finger's direct MCP-to-tip shortcut is at most 80% of its path.
  static const double directionFoldedMaxCompressionRatio = 0.80;

  /// Strong open evidence starts at 90% reach (0.90²) and 85% compression.
  static const double directionOpenMinReachAreaRatio = 0.81;
  static const double directionOpenMinCompressionRatio = 0.85;
  static const int movingDownRequiredConsecutiveFrames = 3;

  /// Shared projected-finger thresholds used by 3D geometry checks.
  static const double directionFingerChainMinVerticalImageRatio = 0.025;
  static const double directionFingerChainMinVerticalSpanRatio = 0.18;
  static const double directionFingerChainVerticalDominanceRatio = 1.25;
  static const double directionFingerChainMaxDepthProjectionRatio = 1.35;

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

  /// Normal Punch-circle radius relative to detected hand size.
  static const double punchCircleRadiusHandSizeRatio = 0.30;

  /// When points 5 and 13 are available, their distance is the minimum radius.
  static const List<HandLandmarkType> punchCircleMinimumRadiusAnchorTypes = [
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.ringFingerMCP,
  ];

  /// A hand becomes Punch only when all 21 hand landmarks fit inside
  /// the point 9/10-centered circle and point 0 (wrist) is inside. Package
  /// gesture type and confidence do not participate in this decision.
  static const int punchCircleMinInsideLandmarkCount = 21;

  /// Normal-preview punch feedback needs a steady three-frame confirmation.
  /// Recording mode still uses raw punch detection plus its one-second hold.
  static const double punchMaxHandCenterMovementRatio = 0.03;
  static const int punchRequiredConsecutiveFrames = 3;

  /// Static down-pointing hold used to return every task to its main state.
  static const Duration returnToMainDownHoldDuration = Duration(seconds: 1);
  static const double returnToMainFingerMinJointAngleDegrees = 135.0;
  static const double returnToMainFingerMinProjectedHandSizeRatio = 0.20;

  /// Every MCP→PIP→DIP→TIP step must descend by at least 4% of hand size.
  /// This rejects overlapping, congested, or locally reversed landmarks even
  /// when the overall MCP-to-tip direction still points downward.
  static const double returnToMainMinAdjacentVerticalGapHandSizeRatio = 0.04;
  static const Duration cancelEverythingHoldDuration = Duration(
    milliseconds: 900,
  );

  static const double closedThumbMaxPalmDistanceRatio = 0.30;
  static const double closedThumbTipIpPalmRatio = 1.00;
  static const double closedThumbMaxKnuckleDistanceRatio = 0.32;
  static const double closedThumbMaxTipMcpDistanceRatio = 0.36;

  /// Pinch and stability limits for zoom gestures.
  /// Very small 2D gaps override noisy depth and count as fingertip contact.
  static const double zoomTouchMax2dDistanceRatio = 0.08;

  /// The normal closed-pinch limit uses weighted 3D fingertip distance.
  static const double zoomClosedMaxDistanceRatio = 0.18;

  /// Zoom In starts above this gap, leaving 18%-22% neutral.
  static const double zoomInMinDistanceRatio = 0.22;
  static const double zoomMaxPalmMovementRatio = 0.08;
  static const int zoomStableFingerMinCount = 2;
  static const double zoomStableFingerMaxMovementRatio = 0.07;

  /// Static zoom hold timing and repeat-rate thresholds.
  static const Duration zoomStaticHoldDuration = Duration(seconds: 1);
  static const double zoomMinLandmarkVisibility = 0.30;
  static const Duration gestureZoomRepeatInterval = Duration(seconds: 1);

  /// Camera-frame cadence, manual zoom step, and recording hold timings.
  static const Duration minFrameProcessInterval = Duration(milliseconds: 50);
  static const double zoomStep = 0.2;
  static const double gestureZoomStep = 0.20;
  static const Duration recordStartHoldDuration = Duration(seconds: 1);
  static const Duration recordPauseHoldDuration = Duration(seconds: 1);
  static const Duration recordStopHoldDuration = Duration(seconds: 2);
}
