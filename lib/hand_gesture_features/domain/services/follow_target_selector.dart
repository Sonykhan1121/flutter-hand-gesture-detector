import 'dart:math' as math;
import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import '../models/follow_target.dart';

/// Picks and tracks the face/object target selected by a release gesture.
class FollowTargetSelector {
  const FollowTargetSelector();

  /// Selects the smallest target box that contains the release point.
  FollowTarget? select({
    required Offset releasePoint,
    required List<FollowTarget> faces,
    required List<FollowTarget> objects,
  }) {
    return _bestAtPoint(releasePoint, faces) ??
        _bestAtPoint(releasePoint, objects);
  }

  /// Selects the closest available target when no box contains the point.
  FollowTarget? selectNearest({
    required Offset releasePoint,
    required List<FollowTarget> faces,
    required List<FollowTarget> objects,
  }) {
    FollowTarget? bestCandidate;
    var bestDistance = double.infinity;
    var bestArea = double.infinity;

    for (final candidate in [...faces, ...objects]) {
      final distance = _centerDistance(
        releasePoint,
        candidate.displayBox.center,
      );
      final area = candidate.displayBox.width * candidate.displayBox.height;

      if (distance < bestDistance ||
          (distance == bestDistance && area < bestArea)) {
        bestDistance = distance;
        bestArea = area;
        bestCandidate = candidate;
      }
    }

    return bestCandidate;
  }

  /// Matches a previous target to the best current candidate.
  FollowTarget? track({
    required FollowTarget previous,
    required List<FollowTarget> candidates,
  }) {
    final sameTypeCandidates = candidates
        .where((candidate) => candidate.type == previous.type)
        .toList(growable: false);
    if (sameTypeCandidates.isEmpty) return null;

    final previousTrackingId = previous.trackingId;
    if (previousTrackingId != null) {
      for (final candidate in sameTypeCandidates) {
        if (candidate.trackingId == previousTrackingId) {
          return candidate;
        }
      }
    }

    FollowTarget? bestCandidate;
    var bestScore = double.negativeInfinity;

    for (final candidate in sameTypeCandidates) {
      final overlap = _intersectionOverUnion(
        previous.displayBox,
        candidate.displayBox,
      );
      final distance = _centerDistance(
        previous.displayBox.center,
        candidate.displayBox.center,
      );

      if (overlap < HandGestureThresholds.followTargetMinTrackingOverlap &&
          distance > HandGestureThresholds.followTargetMaxTrackingDistance) {
        continue;
      }

      final score = overlap - distance;
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    return bestCandidate;
  }

  /// Finds the smallest padded target box under the release point.
  FollowTarget? _bestAtPoint(
    Offset releasePoint,
    List<FollowTarget> candidates,
  ) {
    FollowTarget? bestCandidate;
    var bestArea = double.infinity;

    for (final candidate in candidates) {
      final paddedBox = candidate.displayBox.inflate(
        HandGestureThresholds.followTargetReleasePointPadding,
      );
      if (!paddedBox.contains(releasePoint)) continue;

      final area = candidate.displayBox.width * candidate.displayBox.height;
      if (area < bestArea) {
        bestArea = area;
        bestCandidate = candidate;
      }
    }

    return bestCandidate;
  }

  /// Measures bounding-box overlap for target tracking.
  double _intersectionOverUnion(Rect first, Rect second) {
    final intersection = first.intersect(second);
    if (intersection.isEmpty) return 0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        first.width * first.height +
        second.width * second.height -
        intersectionArea;

    if (unionArea <= 0) return 0;
    return intersectionArea / unionArea;
  }

  /// Computes normalized 2D distance between two display points.
  double _centerDistance(Offset first, Offset second) {
    final dx = first.dx - second.dx;
    final dy = first.dy - second.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
}
