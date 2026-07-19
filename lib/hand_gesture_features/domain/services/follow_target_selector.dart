import 'dart:math' as math;
import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_target_type.dart';
import '../models/follow_target.dart';
import '../models/follow_target_identity.dart';
import '../models/follow_target_selection_memory.dart';

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

  /// Removes ML Kit's common "Home goods" false positive around the hand.
  List<FollowTarget> withoutLikelyHandFalsePositives({
    required List<FollowTarget> objects,
    required Rect handDisplayBox,
  }) {
    if (handDisplayBox.isEmpty) return objects;

    final paddedHandBox = handDisplayBox.inflate(
      HandGestureThresholds.googleMlKitHandFalsePositivePadding,
    );
    return objects
        .where((target) {
          final label = FollowTargetIdentity.normalizeLabel(
            target.label ?? target.displayLabel,
          );
          if (label != 'home goods') return true;

          final intersection = paddedHandBox.intersect(target.displayBox);
          if (intersection.isEmpty) return true;
          final intersectionArea = intersection.width * intersection.height;
          final handArea = paddedHandBox.width * paddedHandBox.height;
          final targetArea = target.displayBox.width * target.displayBox.height;
          final smallerArea = math.min(handArea, targetArea);
          if (smallerArea <= 0) return true;

          return intersectionArea / smallerArea <
              HandGestureThresholds.googleMlKitHandFalsePositiveOverlapRatio;
        })
        .toList(growable: false);
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
              (identity == null || _matchesIdentity(identity, candidate)),
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

  /// Ensures repeated detector updates refer to one moving box.
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

  /// Checks whether two selection observations describe the same candidate.
  bool isSameSelectionCandidate(FollowTarget previous, FollowTarget candidate) {
    if (candidate.type != previous.type) return false;

    final previousTrackingId = previous.trackingId;
    final candidateTrackingId = candidate.trackingId;
    if (previousTrackingId != null && candidateTrackingId != null) {
      return previousTrackingId == candidateTrackingId &&
          isSpatiallyContinuous(previous, candidate);
    }

    final previousLabel = FollowTargetIdentity.normalizeLabel(
      previous.label ?? previous.type.displayLabel,
    );
    final candidateLabel = FollowTargetIdentity.normalizeLabel(
      candidate.label ?? candidate.type.displayLabel,
    );
    if (candidateLabel != previousLabel) return false;

    if (candidate.type == FollowTargetType.object &&
        (previous.classIndex == null ||
            candidate.classIndex != previous.classIndex)) {
      return false;
    }

    if (candidate.type == FollowTargetType.face &&
        previousTrackingId != null &&
        candidateTrackingId != null &&
        previousTrackingId != candidateTrackingId) {
      return false;
    }

    return isSpatiallyContinuous(previous, candidate);
  }

  /// Returns a confirmation only when exactly one candidate matches safely.
  FollowTarget? uniqueSelectionConfirmation({
    required FollowTarget remembered,
    required List<FollowTarget> candidates,
  }) {
    final matches = candidates
        .where((candidate) => isSameSelectionCandidate(remembered, candidate))
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  /// Updates the short selection memory without substituting an occluded target.
  FollowTargetSelectionMemoryUpdate updateSelectionMemory({
    required FollowTargetSelectionMemory? previous,
    required Offset handPoint,
    required DateTime now,
    required List<FollowTarget> faces,
    required List<FollowTarget> objects,
    DateTime? facesDetectionCycleAt,
    DateTime? objectsDetectionCycleAt,
    DateTime? detectedAfter,
  }) {
    final closest = selectNearest(
      releasePoint: handPoint,
      faces: faces,
      objects: objects,
      detectedAfter: detectedAfter,
    );

    if (previous != null && previous.isValid(now: now, handPoint: handPoint)) {
      final previousDetectionCycleAt =
          previous.candidate.type == FollowTargetType.face
          ? facesDetectionCycleAt
          : objectsDetectionCycleAt;
      final hasNewPreviousDetectionCycle =
          previousDetectionCycleAt != null &&
          previousDetectionCycleAt != previous.lastDetectionCycle;
      final compatible = <FollowTarget>[...faces, ...objects]
          .where(
            (candidate) =>
                (detectedAfter == null ||
                    !candidate.detectedAt.isBefore(detectedAfter)) &&
                isSameSelectionCandidate(previous.candidate, candidate),
          )
          .toList(growable: false);

      if (compatible.length == 1 &&
          closest != null &&
          isSameSelectionCandidate(compatible.single, closest)) {
        return FollowTargetSelectionMemoryUpdate(
          memory: previous.observeFreshCycle(
            candidate: compatible.single,
            observedAt: now,
            handPoint: handPoint,
            detectionCycleAt: previousDetectionCycleAt,
          ),
          isCandidateHidden: false,
        );
      }

      if (compatible.isEmpty || compatible.length > 1) {
        if (!previous.isReleasable && hasNewPreviousDetectionCycle) {
          return const FollowTargetSelectionMemoryUpdate(
            memory: null,
            isCandidateHidden: false,
          );
        }
        return FollowTargetSelectionMemoryUpdate(
          memory: previous,
          isCandidateHidden: true,
        );
      }
      // The remembered target is visible, but another target is now closest.
    }

    return FollowTargetSelectionMemoryUpdate(
      memory: closest == null
          ? null
          : FollowTargetSelectionMemory.firstObservation(
              candidate: closest,
              observedAt: now,
              handPoint: handPoint,
              detectionCycleAt: closest.type == FollowTargetType.face
                  ? facesDetectionCycleAt
                  : objectsDetectionCycleAt,
            ),
      isCandidateHidden: false,
    );
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

  bool _matchesIdentity(FollowTargetIdentity identity, FollowTarget candidate) {
    if (candidate.type != identity.type) return false;

    final identityTrackingId = identity.trackingId;
    final candidateTrackingId = candidate.trackingId;
    if (identityTrackingId != null && candidateTrackingId != null) {
      return identityTrackingId == candidateTrackingId;
    }

    if (!_matchesIdentityClass(identity, candidate)) return false;
    return identity.type == FollowTargetType.object ||
        _visibleAppearanceMatches(identity, candidate);
  }

  bool _visibleAppearanceMatches(
    FollowTargetIdentity identity,
    FollowTarget candidate,
  ) {
    final reference = identity.appearanceSignature;
    final current = candidate.appearanceSignature;
    if (reference == null || current == null) {
      return identity.type == FollowTargetType.face &&
          identity.trackingId != null &&
          identity.trackingId == candidate.trackingId;
    }
    return reference.compositeSimilarity(current) >=
        HandGestureThresholds.followTargetVisibleSimilarity;
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
