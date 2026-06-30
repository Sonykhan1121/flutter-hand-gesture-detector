import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';

class HandGeometryService {
  const HandGeometryService();

  HandLandmark? visibleLandmark(
      Hand hand,
      HandLandmarkType type, {
        double minVisibility = HandGestureThresholds.minLandmarkVisibility,
      }) {
    final landmark = hand.getLandmark(type);
    if (landmark == null || landmark.visibility < minVisibility) return null;
    return landmark;
  }

  Offset? palmCenter(Hand hand) {
    final points = <HandLandmark>[];

    for (final type in const [
      HandLandmarkType.wrist,
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.middleFingerMCP,
      HandLandmarkType.ringFingerMCP,
      HandLandmarkType.pinkyMCP,
    ]) {
      final landmark = visibleLandmark(hand, type);
      if (landmark != null) points.add(landmark);
    }

    if (points.isEmpty) return null;

    return Offset(
      average(points.map((point) => point.x)),
      average(points.map((point) => point.y)),
    );
  }

  bool isFingerExtended({
    required HandLandmark tip,
    required HandLandmark pip,
    required Offset palmCenter,
    required double handSize,
  }) {
    final tipDistance = distance(tip, palmCenter);
    final pipDistance = distance(pip, palmCenter);

    return tipDistance >
        pipDistance * HandGestureThresholds.extendedFingerRatio &&
        tipDistance > handSize * 0.30;
  }

  bool isFingerFolded({
    required HandLandmark tip,
    required HandLandmark pip,
    required Offset palmCenter,
    required double handSize,
  }) {
    final tipDistance = distance(tip, palmCenter);
    final pipDistance = distance(pip, palmCenter);

    return tipDistance <=
        pipDistance * HandGestureThresholds.foldedFingerRatio ||
        tipDistance < handSize * 0.26;
  }

  double fingerJointAngleDegrees({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
  }) {
    final mcpToPipX = mcp.x - pip.x;
    final mcpToPipY = mcp.y - pip.y;
    final tipToPipX = tip.x - pip.x;
    final tipToPipY = tip.y - pip.y;

    final dot = mcpToPipX * tipToPipX + mcpToPipY * tipToPipY;
    final mcpVectorLength = math.sqrt(
      mcpToPipX * mcpToPipX + mcpToPipY * mcpToPipY,
    );
    final tipVectorLength = math.sqrt(
      tipToPipX * tipToPipX + tipToPipY * tipToPipY,
    );

    if (mcpVectorLength == 0 || tipVectorLength == 0) return 180;

    final cosValue =
    (dot / (mcpVectorLength * tipVectorLength)).clamp(-1.0, 1.0);

    return math.acos(cosValue) * 180 / math.pi;
  }

  bool isFingerFoldedByAngle({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
  }) {
    return fingerJointAngleDegrees(mcp: mcp, pip: pip, tip: tip) <=
        HandGestureThresholds.fingerFoldedMaxAngleDegrees;
  }

  bool isFingerExtendedByAngle({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
    required Offset palmCenter,
    required double handSize,
  }) {
    return fingerJointAngleDegrees(mcp: mcp, pip: pip, tip: tip) >=
        HandGestureThresholds.fingerExtendedMinAngleDegrees &&
        distance(tip, palmCenter) > handSize * 0.30;
  }

  double distance(HandLandmark landmark, Offset point) {
    final dx = landmark.x - point.dx;
    final dy = landmark.y - point.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double distanceBetweenLandmarks(HandLandmark first, HandLandmark second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double distanceBetweenOffsets(Offset first, Offset second) {
    final dx = first.dx - second.dx;
    final dy = first.dy - second.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double average(Iterable<double> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (sum, value) => sum + value) / list.length;
  }

  bool isPointInsideConvexHull({
    required Offset point,
    required List<Offset> points,
  }) {
    final hull = convexHull(points);
    if (hull.length < 3) return false;
    return isPointInsidePolygon(point: point, polygon: hull);
  }

  List<Offset> convexHull(List<Offset> points) {
    final sortedPoints = [...points]
      ..sort((a, b) {
        final xCompare = a.dx.compareTo(b.dx);
        if (xCompare != 0) return xCompare;
        return a.dy.compareTo(b.dy);
      });

    final uniquePoints = <Offset>[];

    for (final point in sortedPoints) {
      if (uniquePoints.isEmpty ||
          uniquePoints.last.dx != point.dx ||
          uniquePoints.last.dy != point.dy) {
        uniquePoints.add(point);
      }
    }

    if (uniquePoints.length <= 2) return uniquePoints;

    final lower = <Offset>[];

    for (final point in uniquePoints) {
      while (lower.length >= 2 &&
          crossProduct(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }

    final upper = <Offset>[];

    for (final point in uniquePoints.reversed) {
      while (upper.length >= 2 &&
          crossProduct(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }

    lower.removeLast();
    upper.removeLast();

    return [...lower, ...upper];
  }

  double crossProduct(Offset origin, Offset a, Offset b) {
    return (a.dx - origin.dx) * (b.dy - origin.dy) -
        (a.dy - origin.dy) * (b.dx - origin.dx);
  }

  bool isPointInsidePolygon({
    required Offset point,
    required List<Offset> polygon,
  }) {
    var inside = false;

    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final current = polygon[i];
      final previous = polygon[j];

      if (isPointOnLineSegment(
        point: point,
        segmentStart: previous,
        segmentEnd: current,
      )) {
        return true;
      }

      final intersects = ((current.dy > point.dy) !=
          (previous.dy > point.dy)) &&
          point.dx <
              (previous.dx - current.dx) *
                  (point.dy - current.dy) /
                  (previous.dy - current.dy) +
                  current.dx;

      if (intersects) inside = !inside;
    }

    return inside;
  }

  bool isPointOnLineSegment({
    required Offset point,
    required Offset segmentStart,
    required Offset segmentEnd,
  }) {
    const epsilon = 0.0001;

    final cross = (point.dy - segmentStart.dy) *
        (segmentEnd.dx - segmentStart.dx) -
        (point.dx - segmentStart.dx) * (segmentEnd.dy - segmentStart.dy);

    if (cross.abs() > epsilon) return false;

    final dot = (point.dx - segmentStart.dx) *
        (segmentEnd.dx - segmentStart.dx) +
        (point.dy - segmentStart.dy) * (segmentEnd.dy - segmentStart.dy);

    if (dot < 0) return false;

    final dx = segmentEnd.dx - segmentStart.dx;
    final dy = segmentEnd.dy - segmentStart.dy;
    final squaredLength = dx * dx + dy * dy;

    return dot <= squaredLength;
  }
}
