import 'dart:math' as math;
import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_target_type.dart';
import '../models/follow_target.dart';
import '../models/follow_target_identity.dart';

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
    DateTime? detectedAfter,
  }) {
    FollowTarget? bestCandidate;
    var bestDistance = double.infinity;
    var bestArea = double.infinity;

    for (final candidate in [...faces, ...objects]) {
      if (detectedAfter != null &&
          candidate.detectedAt.isBefore(detectedAfter)) {
        continue;
      }
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
    FollowTargetIdentity? identity,
  }) {
    final sameTypeCandidates = candidates
        .where(
          (candidate) =>
              candidate.type == previous.type &&
              (identity == null || _matchesIdentityClass(identity, candidate)),
        )
        .where(
          (candidate) =>
              identity == null ||
              _visibleAppearanceMatches(identity, candidate),
        )
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
      if (!isSpatiallyContinuous(previous, candidate)) continue;

      final score = overlap - distance;
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    return bestCandidate;
  }

  /// Returns one unambiguous strict identity match, otherwise fails closed.
  FollowTarget? reacquire({
    required FollowTargetIdentity identity,
    required List<FollowTarget> candidates,
  }) {
    if (identity.type == FollowTargetType.face &&
        identity.faceTrackingId != null) {
      final trackedMatches = candidates.where(
        (candidate) =>
            candidate.trackingId == identity.faceTrackingId &&
            _matchesIdentityClass(identity, candidate) &&
            _strictAppearanceScore(identity, candidate) != null,
      );
      if (trackedMatches.length == 1) return trackedMatches.first;
      if (trackedMatches.length > 1) return null;
    }

    final matches = <(FollowTarget, double)>[];
    for (final candidate in candidates) {
      if (!_matchesIdentityClass(identity, candidate)) continue;
      final score = _strictAppearanceScore(identity, candidate);
      if (score != null) matches.add((candidate, score));
    }
    if (matches.isEmpty) return null;

    matches.sort((first, second) => second.$2.compareTo(first.$2));
    if (matches.length > 1 &&
        matches[0].$2 - matches[1].$2 <
            HandGestureThresholds.followTargetAmbiguousScoreDelta) {
      return null;
    }
    return matches.first.$1;
  }

  /// Ensures repeated reacquisition confirmations refer to one moving box.
  bool isSpatiallyContinuous(FollowTarget previous, FollowTarget candidate) {
    final overlap = _intersectionOverUnion(
      previous.displayBox,
      candidate.displayBox,
    );
    final distance = _centerDistance(
      previous.displayBox.center,
      candidate.displayBox.center,
    );
    return overlap >= HandGestureThresholds.followTargetMinTrackingOverlap ||
        distance <= HandGestureThresholds.followTargetMaxTrackingDistance;
  }

  bool _matchesIdentityClass(
    FollowTargetIdentity identity,
    FollowTarget candidate,
  ) {
    if (candidate.type != identity.type) return false;
    final candidateLabel = FollowTargetIdentity.normalizeLabel(
      candidate.label ?? candidate.type.displayLabel,
    );
    if (candidateLabel != identity.normalizedLabel) return false;

    if (identity.type == FollowTargetType.object) {
      return identity.classIndex != null &&
          candidate.classIndex == identity.classIndex;
    }
    return true;
  }

  bool _visibleAppearanceMatches(
    FollowTargetIdentity identity,
    FollowTarget candidate,
  ) {
    final reference = identity.appearanceSignature;
    final current = candidate.appearanceSignature;
    if (reference == null || current == null) {
      return identity.type == FollowTargetType.face &&
          identity.faceTrackingId != null &&
          identity.faceTrackingId == candidate.trackingId;
    }
    return reference.compositeSimilarity(current) >=
        HandGestureThresholds.followTargetVisibleSimilarity;
  }

  double? _strictAppearanceScore(
    FollowTargetIdentity identity,
    FollowTarget candidate,
  ) {
    final reference = identity.appearanceSignature;
    final current = candidate.appearanceSignature;
    if (reference == null || current == null) return null;

    final histogram = reference.histogramSimilarity(current);
    final hash = reference.hashSimilarity(current);
    final aspectSimilarity = reference.aspectRatioSimilarity(current);
    final aspectChange = aspectSimilarity <= 0
        ? double.infinity
        : 1 / aspectSimilarity;
    final composite = reference.compositeSimilarity(current);

    if (histogram < HandGestureThresholds.followTargetHistogramSimilarity ||
        hash < HandGestureThresholds.followTargetHashSimilarity ||
        aspectChange > HandGestureThresholds.followTargetMaxAspectRatioChange ||
        composite < HandGestureThresholds.followTargetReacquisitionSimilarity) {
      return null;
    }
    return composite;
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
