import 'dart:math' as math;

import 'package:hand_detection/hand_detection.dart';

abstract final class HandGestureThresholds {
  static const int maxDetectionDimension = 640;

  static const double minHandScore = 0.60;
  static const double minPackageGestureConfidence = 0.50;

  static const Duration followObjectMessageHoldDuration = Duration(
    milliseconds: 1200,
  );
  static const Duration followObjectFirstOpenPalmHoldDuration = Duration(
    seconds: 2,
  );

  static const double minLandmarkVisibility = 0.60;

  static const List<HandLandmarkType> directionFingerTipTypes = [
    HandLandmarkType.indexFingerTip,
    HandLandmarkType.middleFingerTip,
    HandLandmarkType.ringFingerTip,
    HandLandmarkType.pinkyTip,
  ];

  static const List<HandLandmarkType> palmReferenceTypes = [
    HandLandmarkType.indexFingerMCP,
    HandLandmarkType.middleFingerMCP,
    HandLandmarkType.ringFingerMCP,
    HandLandmarkType.pinkyMCP,
  ];

  static const double fingerTipVerticalMaxSpreadRatio = 0.22;
  static const double fingerTipHorizontalMaxSpreadRatio = 0.22;
  static const double sideBendMinRatio = 0.16;
  static const double verticalBendMinRatio = 0.16;

  static const double wristToMcpAverageMaxRatio = 0.30;
  static const double wristToMcpSingleMaxRatio = 0.40;

  static const double extendedFingerRatio = 1.20;
  static const double foldedFingerRatio = 1.03;
  static const double thumbExtendedRatio = 1.15;

  static const double fingerFoldedMaxAngleDegrees = 145.0;
  static const double fingerExtendedMinAngleDegrees = 160.0;

  static const double okTouchMaxDistanceRatio = 0.11;
  static const double okTouchMinPalmDistanceRatio = 0.22;

  static const double punchTipMaxPalmDistanceRatio = 0.28;
  static const double punchThumbMaxPalmDistanceRatio = 0.36;
  static const double punchTipMaxSpreadRatio = 0.25;
  static const double punchGestureMinPackageConfidence = 0.70;

  static const int indexCircleHistoryMaxLength = 36;
  static const Duration indexCircleWindow = Duration(milliseconds: 1400);
  static const Duration cancelEverythingHoldDuration = Duration(
    milliseconds: 900,
  );
  static const double indexCircleMinAngleRadians = math.pi * 0.90;
  static const double indexCircleMinRadiusRatio = 0.025;
  static const double indexCircleMaxRadiusVariationRatio = 1.60;

  static const double indexUpperFacingMinDistanceRatio = 0.20;
  static const double indexUpperSideCircleMinDistanceRatio = 0.10;
  static const double indexUprightMaxSideOffsetRatio = 0.34;

  static const double closedThumbMaxPalmDistanceRatio = 0.30;
  static const double closedThumbTipIpPalmRatio = 1.00;
  static const double closedThumbMaxKnuckleDistanceRatio = 0.32;
  static const double closedThumbMaxTipMcpDistanceRatio = 0.36;

  static const double zoomClosedMaxDistanceRatio = 0.24;
  static const double zoomOpenMinDistanceRatio = 0.31;
  static const double zoomMinChangeRatio = 0.055;

  static const Duration zoomStartPoseHoldDuration = Duration(milliseconds: 500);
  static const double zoomActiveTipMinPalmDistanceRatio = 0.06;
  static const double zoomMinLandmarkVisibility = 0.30;

  static const Duration zoomReleaseResetDuration = Duration(milliseconds: 650);
  static const Duration zoomMaxGestureDuration = Duration(milliseconds: 2600);
  static const Duration zoomMinGestureDuration = Duration(milliseconds: 90);
  static const Duration zoomHoldDuration = Duration(milliseconds: 650);

  static const Duration minFrameProcessInterval = Duration(milliseconds: 100);
  static const double zoomStep = 0.2;
  static const Duration recordStartHoldDuration = Duration(seconds: 1);
  static const Duration recordPauseHoldDuration = Duration(seconds: 1);
  static const Duration recordStopHoldDuration = Duration(seconds: 2);
}
