import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';

/// Simple 3D point wrapper for hand landmark coordinates.
class HandPoint3D {
  const HandPoint3D({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  /// Returns the 2D screen-space position for APIs that only need x/y.
  Offset get offset => Offset(x, y);
}

/// Shared landmark geometry utilities used by all gesture detectors.
class HandGeometryService {
  const HandGeometryService();

  /// Returns true when the hand has landmarks, confidence, and usable bounds.
  bool isReliableHand(Hand hand) {
    return hand.hasLandmarks &&
        hand.score.isFinite &&
        hand.score >= HandGestureThresholds.minHandScore &&
        handSizeFromBoundingBox(hand.boundingBox) > 0 &&
        _hasAnyReliableLandmark(hand);
  }

  /// Returns true when a package gesture has a finite, trusted confidence.
  bool isReliablePackageGesture(
    GestureResult? gesture, {
    GestureType? type,
    double minConfidence = HandGestureThresholds.minPackageGestureConfidence,
  }) {
    return gesture != null &&
        (type == null || gesture.type == type) &&
        gesture.confidence.isFinite &&
        gesture.confidence >= minConfidence;
  }

  /// Returns only hands trusted enough for gesture decisions.
  List<Hand> reliableHands(Iterable<Hand> hands) {
    return hands.where(isReliableHand).toList(growable: false);
  }

  /// Picks the highest-confidence reliable hand, or the nearest to focus.
  Hand? bestReliableHand(Iterable<Hand> hands, {Rect? focusedHandBox}) {
    final candidates = reliableHands(hands);
    if (candidates.isEmpty) return null;

    if (focusedHandBox == null) {
      return candidates.reduce(
        (currentBest, next) =>
            next.score > currentBest.score ? next : currentBest,
      );
    }

    final focusedCenter = focusedHandBox.center;
    return candidates.reduce((currentBest, next) {
      final currentDistance = distanceBetweenOffsets(
        _handBoxCenter(currentBest),
        focusedCenter,
      );
      final nextDistance = distanceBetweenOffsets(
        _handBoxCenter(next),
        focusedCenter,
      );

      return nextDistance < currentDistance ? next : currentBest;
    });
  }

  /// Returns a landmark only when it exists and has enough visibility.
  HandLandmark? visibleLandmark(
    Hand hand,
    HandLandmarkType type, {
    double minVisibility = HandGestureThresholds.minLandmarkVisibility,
  }) {
    final landmark = hand.getLandmark(type);
    if (landmark == null ||
        !landmark.x.isFinite ||
        !landmark.y.isFinite ||
        !landmark.z.isFinite ||
        !landmark.visibility.isFinite ||
        landmark.visibility < minVisibility) {
      return null;
    }

    return landmark;
  }

  /// Averages visible wrist and knuckle points into a 2D palm center.
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

  /// Averages visible wrist and knuckle points into a 3D palm center.
  HandPoint3D? palmCenter3D(Hand hand) {
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

    return HandPoint3D(
      x: average(points.map((point) => point.x)),
      y: average(points.map((point) => point.y)),
      z: average(points.map((point) => point.z)),
    );
  }

  /// Uses the hand bounding box as a finite scale reference for thresholds.
  double handSizeFromBoundingBox(BoundingBox box) {
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    final handSize = math.max(handWidth, handHeight);
    return handSize.isFinite ? handSize : 0;
  }

  /// Checks if a finger tip reaches farther from the palm than its PIP joint.
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

  /// 3D version of [isFingerExtended] that includes weighted depth.
  bool isFingerExtended3D({
    required HandLandmark tip,
    required HandLandmark pip,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    final tipDistance = distanceToPoint3D(tip, palmCenter);
    final pipDistance = distanceToPoint3D(pip, palmCenter);

    return tipDistance >
            pipDistance * HandGestureThresholds.extendedFingerRatio &&
        tipDistance > handSize * 0.30;
  }

  /// Checks if a finger tip is near the palm compared with its PIP joint.
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

  /// 3D version of [isFingerFolded] that includes weighted depth.
  bool isFingerFolded3D({
    required HandLandmark tip,
    required HandLandmark pip,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    final tipDistance = distanceToPoint3D(tip, palmCenter);
    final pipDistance = distanceToPoint3D(pip, palmCenter);

    return tipDistance <=
            pipDistance * HandGestureThresholds.foldedFingerRatio ||
        tipDistance < handSize * 0.26;
  }

  /// Measures the bend angle at the PIP joint in 2D.
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

    final cosValue = (dot / (mcpVectorLength * tipVectorLength)).clamp(
      -1.0,
      1.0,
    );

    return math.acos(cosValue) * 180 / math.pi;
  }

  /// Measures the bend angle at the PIP joint using weighted depth.
  double fingerJointAngleDegrees3D({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
  }) {
    final mcpToPipX = mcp.x - pip.x;
    final mcpToPipY = mcp.y - pip.y;
    final mcpToPipZ = weightedDepthDelta(mcp, pip);
    final tipToPipX = tip.x - pip.x;
    final tipToPipY = tip.y - pip.y;
    final tipToPipZ = weightedDepthDelta(tip, pip);

    final dot =
        mcpToPipX * tipToPipX + mcpToPipY * tipToPipY + mcpToPipZ * tipToPipZ;
    final mcpVectorLength = math.sqrt(
      mcpToPipX * mcpToPipX + mcpToPipY * mcpToPipY + mcpToPipZ * mcpToPipZ,
    );
    final tipVectorLength = math.sqrt(
      tipToPipX * tipToPipX + tipToPipY * tipToPipY + tipToPipZ * tipToPipZ,
    );

    if (mcpVectorLength == 0 || tipVectorLength == 0) return 180;

    final cosValue = (dot / (mcpVectorLength * tipVectorLength)).clamp(
      -1.0,
      1.0,
    );

    return math.acos(cosValue) * 180 / math.pi;
  }

  /// Returns true when a finger is bent enough to count as folded in 2D.
  bool isFingerFoldedByAngle({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
  }) {
    return fingerJointAngleDegrees(mcp: mcp, pip: pip, tip: tip) <=
        HandGestureThresholds.fingerFoldedMaxAngleDegrees;
  }

  /// Returns true when a finger is bent enough to count as folded in 3D.
  bool isFingerFoldedByAngle3D({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
  }) {
    return fingerJointAngleDegrees3D(mcp: mcp, pip: pip, tip: tip) <=
        HandGestureThresholds.fingerFoldedMaxAngleDegrees;
  }

  /// Combines angle and palm distance to confirm a finger is extended in 2D.
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

  /// Combines angle and palm distance to confirm a finger is extended in 3D.
  bool isFingerExtendedByAngle3D({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    return fingerJointAngleDegrees3D(mcp: mcp, pip: pip, tip: tip) >=
            HandGestureThresholds.fingerExtendedMinAngleDegrees &&
        distanceToPoint3D(tip, palmCenter) > handSize * 0.30;
  }

  /// Returns a complete visible finger chain, or null if any point is missing.
  List<HandLandmark>? visibleFingerChain(
    Hand hand,
    List<HandLandmarkType> chainTypes,
  ) {
    final chain = <HandLandmark>[];

    for (final type in chainTypes) {
      final landmark = visibleLandmark(hand, type);
      if (landmark == null) return null;
      chain.add(landmark);
    }

    return chain;
  }

  /// Checks whether a 4-point finger chain is straight enough in 3D.
  bool isFingerChainExtended3D(List<HandLandmark> chain) {
    return chain.length >= 4 &&
        fingerJointAngleDegrees3D(
              mcp: chain[0],
              pip: chain[1],
              tip: chain[3],
            ) >=
            HandGestureThresholds.fingerExtendedMinAngleDegrees;
  }

  /// Checks whether a 4-point finger chain is folded toward the palm in 3D.
  bool isFingerChainFolded3D({
    required List<HandLandmark> chain,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    return chain.length >= 4 &&
        isFingerFolded3D(
          tip: chain[3],
          pip: chain[1],
          palmCenter: palmCenter,
          handSize: handSize,
        ) &&
        isFingerFoldedByAngle3D(mcp: chain[0], pip: chain[1], tip: chain[3]);
  }

  /// Counts how many long fingers are folded for fist and punch checks.
  int foldedLongFingerCount3D({
    required Hand hand,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    var foldedCount = 0;

    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes) {
      final chain = visibleFingerChain(hand, chainTypes);
      if (chain == null) continue;

      if (isFingerChainFolded3D(
        chain: chain,
        palmCenter: palmCenter,
        handSize: handSize,
      )) {
        foldedCount += 1;
      }
    }

    return foldedCount;
  }

  /// Counts extended long fingers that clearly point downward in image space.
  int downwardExtendedFingerChainCount({
    required Hand hand,
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    if (!imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return 0;
    }

    double visibleX(double rawX) =>
        mirrorHorizontally ? imageSize.width - rawX : rawX;

    final fingerChains = <List<HandLandmark>>[];
    final pointXs = <double>[];
    final pointYs = <double>[];

    for (final chainTypes in HandGestureThresholds.directionFingerChainTypes) {
      final chain = visibleFingerChain(hand, chainTypes);
      if (chain == null || !isFingerChainExtended3D(chain)) continue;

      fingerChains.add(chain);

      for (final landmark in chain) {
        pointXs.add(visibleX(landmark.x));
        pointYs.add(landmark.y);
      }
    }

    if (fingerChains.isEmpty || pointXs.isEmpty || pointYs.isEmpty) return 0;

    final fingerPointWidth =
        pointXs.reduce(math.max) - pointXs.reduce(math.min);
    final fingerPointHeight =
        pointYs.reduce(math.max) - pointYs.reduce(math.min);
    final fingerPointSpan = math.max(fingerPointWidth, fingerPointHeight);

    if (fingerPointSpan <= 0) return 0;

    final minVerticalDistance = math.max(
      imageSize.height *
          HandGestureThresholds.directionFingerChainMinVerticalImageRatio,
      fingerPointSpan *
          HandGestureThresholds.directionFingerChainMinVerticalSpanRatio,
    );

    var downPointingFingerCount = 0;

    for (final chain in fingerChains) {
      final deltaX = fingerChainDeltaX(
        chain,
        imageSize: imageSize,
        mirrorHorizontally: mirrorHorizontally,
      );
      final deltaY = fingerChainDeltaY(chain);

      if (isFingerChainDepthDominant(
        chain: chain,
        deltaX: deltaX,
        deltaY: deltaY,
      )) {
        continue;
      }

      if (deltaY >= minVerticalDistance &&
          deltaY >=
              deltaX.abs() *
                  HandGestureThresholds
                      .directionFingerChainVerticalDominanceRatio) {
        downPointingFingerCount += 1;
      }
    }

    return downPointingFingerCount;
  }

  /// Sums horizontal movement along a finger chain after optional mirroring.
  double fingerChainDeltaX(
    List<HandLandmark> chain, {
    required Size imageSize,
    required bool mirrorHorizontally,
  }) {
    double visibleX(double rawX) =>
        mirrorHorizontally ? imageSize.width - rawX : rawX;

    return visibleX(chain[1].x) -
        visibleX(chain[0].x) +
        visibleX(chain[2].x) -
        visibleX(chain[1].x) +
        visibleX(chain[3].x) -
        visibleX(chain[2].x);
  }

  /// Sums vertical movement along a finger chain from MCP to fingertip.
  double fingerChainDeltaY(List<HandLandmark> chain) {
    return chain[1].y -
        chain[0].y +
        chain[2].y -
        chain[1].y +
        chain[3].y -
        chain[2].y;
  }

  /// Sums weighted depth movement along a finger chain.
  double fingerChainDeltaZ(List<HandLandmark> chain) {
    return weightedDepthDelta(chain[1], chain[0]) +
        weightedDepthDelta(chain[2], chain[1]) +
        weightedDepthDelta(chain[3], chain[2]);
  }

  /// Rejects chains pointing mostly toward/away from camera, not across image.
  bool isFingerChainDepthDominant({
    required List<HandLandmark> chain,
    required double deltaX,
    required double deltaY,
  }) {
    final projectedDelta = math.sqrt(deltaX * deltaX + deltaY * deltaY);

    return projectedDelta > 0 &&
        fingerChainDeltaZ(chain).abs() >
            projectedDelta *
                HandGestureThresholds
                    .directionFingerChainMaxDepthProjectionRatio;
  }

  /// Determines whether the thumb is tucked tightly enough for a fist.
  bool? isThumbTuckedForFist3D({
    required Hand hand,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    final thumbTip = visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbMcp = visibleLandmark(hand, HandLandmarkType.thumbMCP);
    final indexMcp = visibleLandmark(hand, HandLandmarkType.indexFingerMCP);
    final middleMcp = visibleLandmark(hand, HandLandmarkType.middleFingerMCP);

    if (thumbTip == null ||
        thumbIp == null ||
        thumbMcp == null ||
        indexMcp == null ||
        middleMcp == null) {
      return null;
    }

    return isThumbTucked3D(
      thumbTip: thumbTip,
      thumbIp: thumbIp,
      thumbMcp: thumbMcp,
      indexMcp: indexMcp,
      middleMcp: middleMcp,
      palmCenter: palmCenter,
      handSize: handSize,
    );
  }

  /// Checks thumb closure against palm and knuckle distances in 3D.
  bool isThumbTucked3D({
    required HandLandmark thumbTip,
    required HandLandmark thumbIp,
    required HandLandmark thumbMcp,
    required HandLandmark indexMcp,
    required HandLandmark middleMcp,
    required HandPoint3D palmCenter,
    required double handSize,
  }) {
    final thumbTipToPalm = distanceToPoint3D(thumbTip, palmCenter);
    final thumbIpToPalm = distanceToPoint3D(thumbIp, palmCenter);

    final thumbTipToIndexMcp = distanceBetweenLandmarks3D(thumbTip, indexMcp);
    final thumbTipToMiddleMcp = distanceBetweenLandmarks3D(thumbTip, middleMcp);
    final thumbTipToThumbMcp = distanceBetweenLandmarks3D(thumbTip, thumbMcp);

    final thumbTipCloseToPalm =
        thumbTipToPalm <=
        handSize * HandGestureThresholds.closedThumbMaxPalmDistanceRatio;
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

  /// Distance from a 2D landmark to a 2D point.
  double distance(HandLandmark landmark, Offset point) {
    final dx = landmark.x - point.dx;
    final dy = landmark.y - point.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Distance from a landmark to a 3D point using weighted depth.
  double distanceToPoint3D(HandLandmark landmark, HandPoint3D point) {
    final dx = landmark.x - point.x;
    final dy = landmark.y - point.y;
    final dz = weightedDepthValue(landmark.z - point.z);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// 2D distance between two landmarks.
  double distanceBetweenLandmarks(HandLandmark first, HandLandmark second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 3D distance between two landmarks using weighted depth.
  double distanceBetweenLandmarks3D(HandLandmark first, HandLandmark second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    final dz = weightedDepthDelta(first, second);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// 2D distance between two Flutter offsets.
  double distanceBetweenOffsets(Offset first, Offset second) {
    final dx = first.dx - second.dx;
    final dy = first.dy - second.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Returns the center of a detected hand bounding box.
  Offset _handBoxCenter(Hand hand) {
    final box = hand.boundingBox;
    return Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  }

  /// Confirms at least one landmark is finite and visible enough to trust.
  bool _hasAnyReliableLandmark(Hand hand) {
    return hand.landmarks.any(
      (landmark) =>
          landmark.x.isFinite &&
          landmark.y.isFinite &&
          landmark.z.isFinite &&
          landmark.visibility.isFinite &&
          landmark.visibility >= HandGestureThresholds.minLandmarkVisibility,
    );
  }

  /// 3D distance between two [HandPoint3D] values using weighted depth.
  double distanceBetweenPoints3D(HandPoint3D first, HandPoint3D second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    final dz = weightedDepthValue(first.z - second.z);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Weighted depth difference between two landmarks.
  double weightedDepthDelta(HandLandmark first, HandLandmark second) {
    return weightedDepthValue(first.z - second.z);
  }

  /// Applies the app-wide depth scaling so z does not dominate x/y.
  double weightedDepthValue(double value) {
    return value * HandGestureThresholds.landmarkDepthWeight;
  }

  /// Returns the arithmetic mean, or zero for an empty iterable.
  double average(Iterable<double> values) {
    final samples = values.toList(growable: false);
    if (samples.isEmpty) return 0;
    return samples.fold<double>(0, (sum, value) => sum + value) /
        samples.length;
  }

  /// Checks whether a point is inside the convex hull of other points.
  bool isPointInsideConvexHull({
    required Offset point,
    required List<Offset> points,
  }) {
    final hull = convexHull(points);
    if (hull.length < 3) return false;
    return isPointInsidePolygon(point: point, polygon: hull);
  }

  /// Builds the convex hull around points using a monotonic chain algorithm.
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

  /// Signed area/cross product used by convex-hull and side tests.
  double crossProduct(Offset origin, Offset a, Offset b) {
    return (a.dx - origin.dx) * (b.dy - origin.dy) -
        (a.dy - origin.dy) * (b.dx - origin.dx);
  }

  /// Ray-casting point-in-polygon test, including points on the boundary.
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

      final intersects =
          ((current.dy > point.dy) != (previous.dy > point.dy)) &&
          point.dx <
              (previous.dx - current.dx) *
                      (point.dy - current.dy) /
                      (previous.dy - current.dy) +
                  current.dx;

      if (intersects) inside = !inside;
    }

    return inside;
  }

  /// Returns true when a point lies exactly on a line segment.
  bool isPointOnLineSegment({
    required Offset point,
    required Offset segmentStart,
    required Offset segmentEnd,
  }) {
    const epsilon = 0.0001;

    final cross =
        (point.dy - segmentStart.dy) * (segmentEnd.dx - segmentStart.dx) -
        (point.dx - segmentStart.dx) * (segmentEnd.dy - segmentStart.dy);

    if (cross.abs() > epsilon) return false;

    final dot =
        (point.dx - segmentStart.dx) * (segmentEnd.dx - segmentStart.dx) +
        (point.dy - segmentStart.dy) * (segmentEnd.dy - segmentStart.dy);

    if (dot < 0) return false;

    final dx = segmentEnd.dx - segmentStart.dx;
    final dy = segmentEnd.dy - segmentStart.dy;
    final squaredLength = dx * dx + dy * dy;

    return dot <= squaredLength;
  }
}
