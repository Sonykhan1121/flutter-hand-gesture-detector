import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../models/custom_gesture_detection_result.dart';
import '../models/timed_offset.dart';
import 'hand_geometry_service.dart';

class CustomGestureDetector {
  CustomGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  final ListQueue<TimedOffset> _indexCircleHistory = ListQueue<TimedOffset>();
  DateTime? _lastCancelEverythingDetectedAt;

  CustomGestureDetectionResult detect({
    required Hand hand,
    required Size imageSize,
    required bool isFrontCamera,
  }) {
    return CustomGestureDetectionResult(
      isCancelEverything: _detectCancelEverythingGesture(
        hand: hand,
        imageSize: imageSize,
        isFrontCamera: isFrontCamera,
      ),
      isOk: _isOkGesture(hand),
      isCallMe: _isCallMeGesture(hand),
      isPunch: _isPunchGesture(hand),
    );
  }

  bool _detectCancelEverythingGesture({
    required Hand hand,
    required Size imageSize,
    required bool isFrontCamera,
  }) {
    final now = DateTime.now();

    if (!_isIndexOnlyUpperGesture(hand)) {
      return _recentCancelEverythingDetected(now);
    }

    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    final palmCenter = geometry.palmCenter(hand);

    if (indexTip == null ||
        palmCenter == null ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return _recentCancelEverythingDetected(now);
    }

    final handSize = _handSize(hand);

    if (!_isPointOnUpperPalmSide(
      pointY: indexTip.y,
      palmCenterY: palmCenter.dy,
      handSize: handSize,
    )) {
      return _recentCancelEverythingDetected(now);
    }

    final point = Offset(
      isFrontCamera ? imageSize.width - indexTip.x : indexTip.x,
      indexTip.y,
    );

    _indexCircleHistory.addLast(TimedOffset(point: point, time: now));

    while (_indexCircleHistory.length >
        HandGestureThresholds.indexCircleHistoryMaxLength) {
      _indexCircleHistory.removeFirst();
    }

    while (_indexCircleHistory.isNotEmpty &&
        now.difference(_indexCircleHistory.first.time) >
            HandGestureThresholds.indexCircleWindow) {
      _indexCircleHistory.removeFirst();
    }

    if (_indexCircleHistory.length < 7) {
      return _recentCancelEverythingDetected(now);
    }

    final points = _indexCircleHistory.map((sample) => sample.point).toList();

    final allPointsStayUpper = points.every(
          (point) => _isPointOnUpperPalmSide(
        pointY: point.dy,
        palmCenterY: palmCenter.dy,
        handSize: handSize,
      ),
    );

    if (!allPointsStayUpper) {
      return _recentCancelEverythingDetected(now);
    }

    final minX = points.map((point) => point.dx).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxY = points.map((point) => point.dy).reduce(math.max);

    final circleWidth = maxX - minX;
    final circleHeight = maxY - minY;

    final minCircleRadius = math.max(
      math.min(imageSize.width, imageSize.height) * 0.010,
      handSize * HandGestureThresholds.indexCircleMinRadiusRatio,
    );

    if (circleWidth < minCircleRadius * 2 ||
        circleHeight < minCircleRadius * 2) {
      return _recentCancelEverythingDetected(now);
    }

    final center = Offset(
      geometry.average(points.map((point) => point.dx)),
      geometry.average(points.map((point) => point.dy)),
    );

    if (!_isPointOnUpperPalmSide(
      pointY: center.dy,
      palmCenterY: palmCenter.dy,
      handSize: handSize,
    )) {
      return _recentCancelEverythingDetected(now);
    }

    final radii = points
        .map((point) => geometry.distanceBetweenOffsets(point, center))
        .where((radius) => radius > 0)
        .toList();

    if (radii.length < 7) {
      return _recentCancelEverythingDetected(now);
    }

    final averageRadius = geometry.average(radii);
    final radiusMin = radii.reduce(math.min);
    final radiusMax = radii.reduce(math.max);

    if (averageRadius < minCircleRadius) {
      return _recentCancelEverythingDetected(now);
    }

    if ((radiusMax - radiusMin) >
        averageRadius *
            HandGestureThresholds.indexCircleMaxRadiusVariationRatio) {
      return _recentCancelEverythingDetected(now);
    }

    final totalAngle = _totalCircularAngle(points, center);

    if (totalAngle.abs() >= HandGestureThresholds.indexCircleMinAngleRadians) {
      _lastCancelEverythingDetectedAt = now;
      return true;
    }

    return _recentCancelEverythingDetected(now);
  }

  bool _isIndexOnlyUpperGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbMcp = geometry.visibleLandmark(hand, HandLandmarkType.thumbMCP);

    final indexTip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    final indexDip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerDIP);
    final indexPip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerPIP);
    final indexMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerMCP);

    final middleTip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerTip);
    final middlePip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerPIP);
    final middleMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerMCP);

    final ringTip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerTip);
    final ringPip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerPIP);
    final ringMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerMCP);

    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);
    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);

    if (thumbTip == null ||
        thumbIp == null ||
        thumbMcp == null ||
        indexTip == null ||
        indexDip == null ||
        indexPip == null ||
        indexMcp == null ||
        middleTip == null ||
        middlePip == null ||
        middleMcp == null ||
        ringTip == null ||
        ringPip == null ||
        ringMcp == null ||
        pinkyTip == null ||
        pinkyPip == null ||
        pinkyMcp == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final indexIsOpen = geometry.isFingerExtendedByAngle(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final indexFacesUp = indexTip.y < indexDip.y &&
        indexDip.y < indexPip.y &&
        indexTip.y <
            palmCenter.dy -
                handSize *
                    HandGestureThresholds.indexUpperFacingMinDistanceRatio &&
        indexPip.y < palmCenter.dy - handSize * 0.04 &&
        (indexTip.x - indexMcp.x).abs() <=
            handSize * HandGestureThresholds.indexUprightMaxSideOffsetRatio;

    final thumbIsClosed = _isThumbReallyClosedForIndexOnlyGesture(
      thumbTip: thumbTip,
      thumbIp: thumbIp,
      thumbMcp: thumbMcp,
      indexMcp: indexMcp,
      middleMcp: middleMcp,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final middleIsClosed = geometry.isFingerFoldedByAngle(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
    );

    final ringIsClosed = geometry.isFingerFoldedByAngle(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
    );

    final pinkyIsClosed = geometry.isFingerFoldedByAngle(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
    );

    return indexIsOpen &&
        indexFacesUp &&
        thumbIsClosed &&
        middleIsClosed &&
        ringIsClosed &&
        pinkyIsClosed;
  }

  bool _isOkGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbMcp = geometry.visibleLandmark(hand, HandLandmarkType.thumbMCP);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);

    final indexMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerMCP);
    final indexPip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerPIP);
    final indexTip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);

    final middleMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerMCP);
    final middleTip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerTip);
    final middlePip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerPIP);

    final ringMcp =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerMCP);
    final ringTip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerTip);
    final ringPip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerPIP);

    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (thumbMcp == null ||
        thumbIp == null ||
        thumbTip == null ||
        indexMcp == null ||
        indexPip == null ||
        indexTip == null ||
        middleMcp == null ||
        middleTip == null ||
        middlePip == null ||
        ringMcp == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyMcp == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final thumbIndexDistance =
    geometry.distanceBetweenLandmarks(thumbTip, indexTip);
    final maxTouchDistance = math.max(
      handSize * HandGestureThresholds.okTouchMaxDistanceRatio,
      12.0,
    );

    final thumbAndIndexTouch = thumbIndexDistance <= maxTouchDistance;

    final touchCenter = Offset(
      (thumbTip.x + indexTip.x) / 2,
      (thumbTip.y + indexTip.y) / 2,
    );

    final touchIsAwayFromPalm =
        geometry.distanceBetweenOffsets(touchCenter, palmCenter) >
            handSize * HandGestureThresholds.okTouchMinPalmDistanceRatio;

    final loopGapDistance =
    geometry.distanceBetweenLandmarks(thumbIp, indexMcp);
    final hasLoopGap = loopGapDistance >= handSize * 0.16;

    final indexBendAngle = geometry.fingerJointAngleDegrees(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexTip,
    );

    final indexIsBentForOk = indexBendAngle <= 150.0;

    final middleIsOpen = geometry.isFingerExtendedByAngle(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsOpen = geometry.isFingerExtendedByAngle(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final pinkyIsOpen = geometry.isFingerExtendedByAngle(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    return thumbAndIndexTouch &&
        touchIsAwayFromPalm &&
        hasLoopGap &&
        indexIsBentForOk &&
        middleIsOpen &&
        ringIsOpen &&
        pinkyIsOpen;
  }

  bool _isCallMeGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final indexTip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    final indexPip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerPIP);
    final middleTip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerTip);
    final middlePip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerPIP);
    final ringTip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerTip);
    final ringPip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerPIP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (thumbTip == null ||
        thumbIp == null ||
        indexTip == null ||
        indexPip == null ||
        middleTip == null ||
        middlePip == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);

    final thumbIsOpen = geometry.distance(thumbTip, palmCenter) >
        geometry.distance(thumbIp, palmCenter) *
            HandGestureThresholds.thumbExtendedRatio &&
        geometry.distance(thumbTip, palmCenter) > handSize * 0.23;

    final pinkyIsOpen = geometry.isFingerExtended(
      tip: pinkyTip,
      pip: pinkyPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final indexIsClosed = geometry.isFingerFolded(
      tip: indexTip,
      pip: indexPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final middleIsClosed = geometry.isFingerFolded(
      tip: middleTip,
      pip: middlePip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsClosed = geometry.isFingerFolded(
      tip: ringTip,
      pip: ringPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final thumbAndPinkyAreSeparated =
        geometry.distanceBetweenLandmarks(thumbTip, pinkyTip) > handSize * 0.55;

    return thumbIsOpen &&
        pinkyIsOpen &&
        thumbAndPinkyAreSeparated &&
        indexIsClosed &&
        middleIsClosed &&
        ringIsClosed;
  }

  bool _isPunchGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final wrist = geometry.visibleLandmark(hand, HandLandmarkType.wrist);
    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);

    final indexTip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    final indexPip =
    geometry.visibleLandmark(hand, HandLandmarkType.indexFingerPIP);
    final middleTip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerTip);
    final middlePip =
    geometry.visibleLandmark(hand, HandLandmarkType.middleFingerPIP);
    final ringTip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerTip);
    final ringPip =
    geometry.visibleLandmark(hand, HandLandmarkType.ringFingerPIP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (wrist == null ||
        thumbTip == null ||
        thumbIp == null ||
        indexTip == null ||
        indexPip == null ||
        middleTip == null ||
        middlePip == null ||
        ringTip == null ||
        ringPip == null ||
        pinkyTip == null ||
        pinkyPip == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final indexIsClosed = geometry.isFingerFolded(
      tip: indexTip,
      pip: indexPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final middleIsClosed = geometry.isFingerFolded(
      tip: middleTip,
      pip: middlePip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final ringIsClosed = geometry.isFingerFolded(
      tip: ringTip,
      pip: ringPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final pinkyIsClosed = geometry.isFingerFolded(
      tip: pinkyTip,
      pip: pinkyPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final thumbIsClosed = geometry.distance(thumbTip, palmCenter) <=
        math.max(
          geometry.distance(thumbIp, palmCenter) * 1.06,
          handSize * HandGestureThresholds.punchThumbMaxPalmDistanceRatio,
        );

    final fingertips = [thumbTip, indexTip, middleTip, ringTip, pinkyTip];

    final tipsNearPalm = fingertips.every((tip) {
      final maxDistance = identical(tip, thumbTip)
          ? handSize * HandGestureThresholds.punchThumbMaxPalmDistanceRatio
          : handSize * HandGestureThresholds.punchTipMaxPalmDistanceRatio;

      return geometry.distance(tip, palmCenter) <= maxDistance;
    });

    final tipXs = fingertips.map((tip) => tip.x).toList();
    final tipYs = fingertips.map((tip) => tip.y).toList();
    final tipSpreadX = tipXs.reduce(math.max) - tipXs.reduce(math.min);
    final tipSpreadY = tipYs.reduce(math.max) - tipYs.reduce(math.min);

    final tipsStayCompact =
        tipSpreadX <= handSize * HandGestureThresholds.punchTipMaxSpreadRatio &&
            tipSpreadY <=
                handSize * HandGestureThresholds.punchTipMaxSpreadRatio;

    final otherHandPoints = <Offset>[];

    for (final type in const [
      HandLandmarkType.thumbCMC,
      HandLandmarkType.thumbMCP,
      HandLandmarkType.thumbIP,
      HandLandmarkType.thumbTip,
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
    ]) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark != null) {
        otherHandPoints.add(Offset(landmark.x, landmark.y));
      }
    }

    if (otherHandPoints.length < 8) return false;

    final wristInsideOtherPoints = geometry.isPointInsideConvexHull(
      point: Offset(wrist.x, wrist.y),
      points: otherHandPoints,
    );

    final packageClosedFistSupport = hand.gesture != null &&
        hand.gesture!.type == GestureType.closedFist &&
        hand.gesture!.confidence >=
            HandGestureThresholds.punchGestureMinPackageConfidence;

    final allClosed = thumbIsClosed &&
        indexIsClosed &&
        middleIsClosed &&
        ringIsClosed &&
        pinkyIsClosed;

    final geometryPunchDetected =
        allClosed && tipsNearPalm && tipsStayCompact && wristInsideOtherPoints;

    final packagePunchDetected = packageClosedFistSupport &&
        indexIsClosed &&
        middleIsClosed &&
        ringIsClosed &&
        pinkyIsClosed &&
        wristInsideOtherPoints;

    return geometryPunchDetected || packagePunchDetected;
  }

  bool _isThumbReallyClosedForIndexOnlyGesture({
    required HandLandmark thumbTip,
    required HandLandmark thumbIp,
    required HandLandmark thumbMcp,
    required HandLandmark indexMcp,
    required HandLandmark middleMcp,
    required Offset palmCenter,
    required double handSize,
  }) {
    final thumbTipToPalm = geometry.distance(thumbTip, palmCenter);
    final thumbIpToPalm = geometry.distance(thumbIp, palmCenter);

    final thumbTipToIndexMcp =
    geometry.distanceBetweenLandmarks(thumbTip, indexMcp);
    final thumbTipToMiddleMcp =
    geometry.distanceBetweenLandmarks(thumbTip, middleMcp);
    final thumbTipToThumbMcp =
    geometry.distanceBetweenLandmarks(thumbTip, thumbMcp);

    final thumbTipCloseToPalm =
        thumbTipToPalm <= handSize * HandGestureThresholds.closedThumbMaxPalmDistanceRatio;
    final thumbTipNotPastIp =
        thumbTipToPalm <=
            thumbIpToPalm * HandGestureThresholds.closedThumbTipIpPalmRatio;
    final thumbTipCloseToPalmKnuckles =
        math.min(thumbTipToIndexMcp, thumbTipToMiddleMcp) <=
            handSize * HandGestureThresholds.closedThumbMaxKnuckleDistanceRatio;
    final thumbNotStretchedOut =
        thumbTipToThumbMcp <=
            handSize * HandGestureThresholds.closedThumbMaxTipMcpDistanceRatio;

    return thumbTipCloseToPalm &&
        thumbTipNotPastIp &&
        thumbTipCloseToPalmKnuckles &&
        thumbNotStretchedOut;
  }

  double _totalCircularAngle(List<Offset> points, Offset center) {
    if (points.length < 2) return 0;

    var totalAngle = 0.0;
    var previousAngle = math.atan2(
      points.first.dy - center.dy,
      points.first.dx - center.dx,
    );

    for (var i = 1; i < points.length; i++) {
      final angle = math.atan2(
        points[i].dy - center.dy,
        points[i].dx - center.dx,
      );

      var delta = angle - previousAngle;

      while (delta > math.pi) {
        delta -= math.pi * 2;
      }

      while (delta < -math.pi) {
        delta += math.pi * 2;
      }

      totalAngle += delta;
      previousAngle = angle;
    }

    return totalAngle;
  }

  bool _recentCancelEverythingDetected(DateTime now) {
    final lastDetectedAt = _lastCancelEverythingDetectedAt;
    return lastDetectedAt != null &&
        now.difference(lastDetectedAt) <=
            HandGestureThresholds.cancelEverythingHoldDuration;
  }

  bool _isPointOnUpperPalmSide({
    required double pointY,
    required double palmCenterY,
    required double handSize,
  }) {
    return pointY <=
        palmCenterY -
            handSize * HandGestureThresholds.indexUpperSideCircleMinDistanceRatio;
  }

  double _handSize(Hand hand) {
    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    return math.max(handWidth, handHeight);
  }
}
