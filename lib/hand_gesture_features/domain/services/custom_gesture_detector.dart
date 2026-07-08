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
    required bool mirrorHorizontally,
    DateTime? now,
  }) {
    final frameTime = now ?? DateTime.now();

    return CustomGestureDetectionResult(
      isCancelEverything: _detectCancelEverythingGesture(
        hand: hand,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
        now: frameTime,
      ),
      isOk: _isOkGesture(hand),
      isCallMe: _isCallMeGesture(hand),
      isPunch: _isPunchGesture(
        hand,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
      ),
    );
  }

  bool _detectCancelEverythingGesture({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
    required DateTime now,
  }) {
    if (!_isIndexOnlyNearUpperGesture(hand)) {
      return _recentCancelEverythingDetected(now);
    }

    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );

    if (indexTip == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return _recentCancelEverythingDetected(now);
    }

    final handSize = _handSize(hand);
    if (handSize <= 0) {
      return _recentCancelEverythingDetected(now);
    }

    final point = Offset(
      mirrorHorizontally ? imageSize.width - indexTip.x : indexTip.x,
      indexTip.y,
    );

    _indexCircleHistory.addLast(
      TimedOffset(
        point: point,
        time: now,
        depth: geometry.weightedDepthValue(indexTip.z),
      ),
    );

    while (_indexCircleHistory.length >
        HandGestureThresholds.indexCircleHistoryMaxLength) {
      _indexCircleHistory.removeFirst();
    }

    while (_indexCircleHistory.isNotEmpty &&
        now.difference(_indexCircleHistory.first.time) >
            HandGestureThresholds.indexCircleWindow) {
      _indexCircleHistory.removeFirst();
    }

    if (_indexCircleHistory.length <
        HandGestureThresholds.indexCircleMinSampleCount) {
      return _recentCancelEverythingDetected(now);
    }

    final points = _indexCircleHistory.map((sample) => sample.point).toList();

    final minX = points.map((point) => point.dx).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxY = points.map((point) => point.dy).reduce(math.max);

    final circleWidth = maxX - minX;
    final circleHeight = maxY - minY;

    final minCircleRadius = math.max(
      math.min(imageSize.width, imageSize.height) *
          HandGestureThresholds.indexCircleMinImageRadiusRatio,
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

    final radii = points
        .map((point) => geometry.distanceBetweenOffsets(point, center))
        .where((radius) => radius > 0)
        .toList();

    if (radii.length < HandGestureThresholds.indexCircleMinSampleCount) {
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

    final depths = _indexCircleHistory
        .map((sample) => sample.depth)
        .toList(growable: false);
    final depthRange = depths.reduce(math.max) - depths.reduce(math.min);

    if (depthRange >
        handSize * HandGestureThresholds.indexCircleMaxDepthVariationRatio) {
      return _recentCancelEverythingDetected(now);
    }

    final totalAngle = _totalCircularAngle(points, center);

    if (totalAngle.abs() >= HandGestureThresholds.indexCircleMinAngleRadians) {
      _lastCancelEverythingDetectedAt = now;
      return true;
    }

    return _recentCancelEverythingDetected(now);
  }

  bool _isIndexOnlyNearUpperGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbMcp = geometry.visibleLandmark(hand, HandLandmarkType.thumbMCP);

    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    final indexDip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerDIP,
    );
    final indexPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerPIP,
    );
    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );

    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );
    final middleMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );

    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );
    final ringMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerMCP,
    );

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

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final indexIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final indexFacesNearUp =
        indexTip.y < indexPip.y &&
        indexTip.y <
            palmCenter.y -
                handSize *
                    HandGestureThresholds.indexUpperFacingMinDistanceRatio &&
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

    final middleIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
    );

    final ringIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
    );

    final pinkyIsClosed = geometry.isFingerFoldedByAngle3D(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
    );

    return indexIsOpen &&
        indexFacesNearUp &&
        thumbIsClosed &&
        middleIsClosed &&
        ringIsClosed &&
        pinkyIsClosed;
  }

  bool _isOkGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

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

    final middleMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );
    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );

    final ringMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerMCP,
    );
    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );

    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);
    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);

    if (thumbTip == null ||
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

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final thumbIndexDistance = geometry.distanceBetweenLandmarks3D(
      thumbTip,
      indexTip,
    );
    final maxTouchDistance = math.max(
      handSize * HandGestureThresholds.okTouchMaxDistanceRatio,
      12.0,
    );

    final thumbAndIndexTouch = thumbIndexDistance <= maxTouchDistance;

    final indexBendAngle = geometry.fingerJointAngleDegrees3D(
      mcp: indexMcp,
      pip: indexPip,
      tip: indexTip,
    );

    final indexIsBentForOk = indexBendAngle <= 150.0;

    final middleIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: middleMcp,
      pip: middlePip,
      tip: middleTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: ringMcp,
      pip: ringPip,
      tip: ringTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final pinkyIsOpen = geometry.isFingerExtendedByAngle3D(
      mcp: pinkyMcp,
      pip: pinkyPip,
      tip: pinkyTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    return thumbAndIndexTouch &&
        indexIsBentForOk &&
        middleIsOpen &&
        ringIsOpen &&
        pinkyIsOpen;
  }

  bool _isCallMeGesture(Hand hand) {
    if (!hand.hasLandmarks) return false;

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    final indexPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerPIP,
    );
    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );
    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );
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

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);

    final thumbIsOpen =
        geometry.distanceToPoint3D(thumbTip, palmCenter) >
            geometry.distanceToPoint3D(thumbIp, palmCenter) *
                HandGestureThresholds.thumbExtendedRatio &&
        geometry.distanceToPoint3D(thumbTip, palmCenter) > handSize * 0.23;

    final pinkyIsOpen = geometry.isFingerExtended3D(
      tip: pinkyTip,
      pip: pinkyPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final indexIsClosed = geometry.isFingerFolded3D(
      tip: indexTip,
      pip: indexPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final middleIsClosed = geometry.isFingerFolded3D(
      tip: middleTip,
      pip: middlePip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final ringIsClosed = geometry.isFingerFolded3D(
      tip: ringTip,
      pip: ringPip,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final thumbAndPinkyAreSeparated =
        geometry.distanceBetweenLandmarks3D(thumbTip, pinkyTip) >
        handSize * 0.55;

    return thumbIsOpen &&
        pinkyIsOpen &&
        thumbAndPinkyAreSeparated &&
        indexIsClosed &&
        middleIsClosed &&
        ringIsClosed;
  }

  bool _isPunchGesture(
    Hand hand, {
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    if (_isPackageThumbDownPunch(hand)) return true;

    if (!hand.hasLandmarks) return false;

    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );
    final middleMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );
    final ringMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerMCP,
    );
    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);

    if (indexMcp == null ||
        middleMcp == null ||
        ringMcp == null ||
        pinkyMcp == null) {
      return false;
    }

    final palmCenter = geometry.palmCenter3D(hand);
    if (palmCenter == null) return false;

    final handSize = _handSize(hand);
    if (handSize <= 0) return false;

    final downExtendedFingerCount = geometry.downwardExtendedFingerChainCount(
      hand: hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );

    if (downExtendedFingerCount >
        HandGestureThresholds.punchMaxDownExtendedFingerChainCount) {
      return false;
    }

    final foldedFingerCount = geometry.foldedLongFingerCount3D(
      hand: hand,
      palmCenter: palmCenter,
      handSize: handSize,
    );

    final allLongFingersFolded =
        foldedFingerCount ==
        HandGestureThresholds.directionFingerChainTypes.length;

    final knuckleYs = [indexMcp.y, middleMcp.y, ringMcp.y, pinkyMcp.y];
    final knuckleYSpread =
        knuckleYs.reduce(math.max) - knuckleYs.reduce(math.min);
    final knuckleDepths = [
      indexMcp.z,
      middleMcp.z,
      ringMcp.z,
      pinkyMcp.z,
    ].map(geometry.weightedDepthValue);
    final knuckleDepthSpread =
        knuckleDepths.reduce(math.max) - knuckleDepths.reduce(math.min);
    final knucklesAlignedOnXAxis =
        knuckleYSpread <=
            handSize * HandGestureThresholds.punchKnuckleMaxYSpreadRatio &&
        knuckleDepthSpread <=
            handSize * HandGestureThresholds.punchKnuckleMaxDepthSpreadRatio;

    final thumbTucked = geometry.isThumbTuckedForFist3D(
      hand: hand,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final thumbAllowsFist = thumbTucked ?? true;

    return allLongFingersFolded && knucklesAlignedOnXAxis && thumbAllowsFist;
  }

  bool _isPackageThumbDownPunch(Hand hand) {
    final gesture = hand.gesture;

    return gesture != null &&
        gesture.type == GestureType.thumbDown &&
        gesture.confidence >=
            HandGestureThresholds.punchGestureMinPackageConfidence;
  }

  bool _isThumbReallyClosedForIndexOnlyGesture({
    required HandLandmark thumbTip,
    required HandLandmark thumbIp,
    required HandLandmark thumbMcp,
    required HandLandmark indexMcp,
    required HandLandmark middleMcp,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    return geometry.isThumbTucked3D(
      thumbTip: thumbTip,
      thumbIp: thumbIp,
      thumbMcp: thumbMcp,
      indexMcp: indexMcp,
      middleMcp: middleMcp,
      palmCenter: palmCenter,
      handSize: handSize,
    );
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

  double _handSize(Hand hand) {
    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    return math.max(handWidth, handHeight);
  }
}
