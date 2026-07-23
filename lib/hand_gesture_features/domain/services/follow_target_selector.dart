import 'dart:math' as math;
import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_target_type.dart';
import '../models/follow_target.dart';
import '../models/follow_target_identity.dart';
import '../models/follow_target_selection_memory.dart';

class StrictPointingTargetSelection {
  const StrictPointingTargetSelection._({
    required this.target,
    required this.isAmbiguous,
  });

  const StrictPointingTargetSelection.none()
    : this._(target: null, isAmbiguous: false);

  const StrictPointingTargetSelection.ambiguous()
    : this._(target: null, isAmbiguous: true);

  const StrictPointingTargetSelection.selected(FollowTarget target)
    : this._(target: target, isAmbiguous: false);

  final FollowTarget? target;
  final bool isAmbiguous;
}

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

  /// Selects the unique smallest unpadded face/object box under a display point.
  ///
  /// This intentionally has no nearest-center fallback. Equal minimum areas
  /// are ambiguous because choosing either rectangle would be arbitrary.
  StrictPointingTargetSelection selectAtPoint({
    required Offset selectionPoint,
    required List<FollowTarget> faces,
    required List<FollowTarget> objects,
    DateTime? detectedAfter,
    FollowTarget? activeCandidate,
    double activeCandidateHysteresis = 0,
  }) {
    final eligible = <FollowTarget>[...faces, ...objects]
        .where(
          (candidate) =>
              detectedAfter == null ||
              !candidate.detectedAt.isBefore(detectedAfter),
        )
        .toList(growable: false);
    final containing = eligible
        .where((candidate) => candidate.displayBox.contains(selectionPoint))
        .toList(growable: false);

    final strictSelection = _smallestContainingSelection(containing);
    if (strictSelection.target != null || strictSelection.isAmbiguous) {
      return strictSelection;
    }

    if (activeCandidate == null ||
        activeCandidateHysteresis <= 0 ||
        !activeCandidateHysteresis.isFinite) {
      return const StrictPointingTargetSelection.none();
    }

    final maintained = eligible
        .where(
          (candidate) =>
              isSamePointingCandidate(activeCandidate, candidate) &&
              candidate.displayBox
                  .inflate(activeCandidateHysteresis)
                  .contains(selectionPoint),
        )
        .toList(growable: false);
    if (maintained.length == 1) {
      return StrictPointingTargetSelection.selected(maintained.single);
    }
    return maintained.length > 1
        ? const StrictPointingTargetSelection.ambiguous()
        : const StrictPointingTargetSelection.none();
  }

  /// Backward-compatible strict fingertip entry point.
  StrictPointingTargetSelection selectAtIndexTip({
    required Offset indexTip,
    required List<FollowTarget> faces,
    required List<FollowTarget> objects,
    DateTime? detectedAfter,
  }) {
    return selectAtPoint(
      selectionPoint: indexTip,
      faces: faces,
      objects: objects,
      detectedAfter: detectedAfter,
    );
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

  /// Reacquires one temporarily lost face without transferring to a bystander.
  ///
  /// An exact detector tracking ID wins. If the detector assigned a new ID
  /// after the face left the frame, exactly one appearance match is required.
  FollowTarget? reacquireFace({
    required FollowTargetIdentity identity,
    required List<FollowTarget> candidates,
  }) {
    if (identity.type != FollowTargetType.face) return null;

    final faces = candidates
        .where((candidate) => candidate.type == FollowTargetType.face)
        .toList(growable: false);
    final trackingId = identity.trackingId;
    if (trackingId != null) {
      final exactIdMatches = faces
          .where((candidate) => candidate.trackingId == trackingId)
          .toList(growable: false);
      if (exactIdMatches.length == 1) return exactIdMatches.single;
      if (exactIdMatches.length > 1) return null;
    }

    final appearanceMatches = faces
        .where((candidate) => _visibleAppearanceMatches(identity, candidate))
        .toList(growable: false);
    return appearanceMatches.length == 1 ? appearanceMatches.single : null;
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

  /// Strict-but-jitter-tolerant identity continuity during the pointing dwell.
  bool isSamePointingCandidate(FollowTarget previous, FollowTarget candidate) {
    if (candidate.type != previous.type) return false;

    final previousTrackingId = previous.trackingId;
    final candidateTrackingId = candidate.trackingId;
    if (previousTrackingId != null &&
        candidateTrackingId != null &&
        previousTrackingId == candidateTrackingId) {
      return true;
    }

    final previousLabel = FollowTargetIdentity.normalizeLabel(
      previous.label ?? previous.type.displayLabel,
    );
    final candidateLabel = FollowTargetIdentity.normalizeLabel(
      candidate.label ?? candidate.type.displayLabel,
    );
    if (previousLabel != candidateLabel) return false;
    if (previous.type == FollowTargetType.object &&
        (previous.classIndex == null ||
            candidate.classIndex != previous.classIndex)) {
      return false;
    }
    if (!isSpatiallyContinuous(previous, candidate)) return false;

    final previousAppearance = previous.appearanceSignature;
    final candidateAppearance = candidate.appearanceSignature;
    return previousAppearance == null ||
        candidateAppearance == null ||
        previousAppearance.compositeSimilarity(candidateAppearance) >=
            HandGestureThresholds.followTargetVisibleSimilarity;
  }

  /// Resolves a frozen dwell target without allowing a different box to win.
  FollowTarget? resolveFrozenPointingTarget({
    required FollowTarget frozen,
    required List<FollowTarget> candidates,
  }) {
    final trackingId = frozen.trackingId;
    if (trackingId != null) {
      final exact = candidates
          .where(
            (candidate) =>
                candidate.type == frozen.type &&
                candidate.trackingId == trackingId,
          )
          .toList(growable: false);
      if (exact.length == 1) return exact.single;
      if (exact.length > 1) return null;
    }

    final compatible = candidates
        .where((candidate) => isSamePointingCandidate(frozen, candidate))
        .toList(growable: false);
    return compatible.length == 1 ? compatible.single : null;
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

  StrictPointingTargetSelection _smallestContainingSelection(
    List<FollowTarget> candidates,
  ) {
    if (candidates.isEmpty) {
      return const StrictPointingTargetSelection.none();
    }

    final sorted = List<FollowTarget>.of(candidates)
      ..sort((first, second) {
        final firstArea = first.displayBox.width * first.displayBox.height;
        final secondArea = second.displayBox.width * second.displayBox.height;
        return firstArea.compareTo(secondArea);
      });
    if (sorted.length > 1) {
      final firstArea =
          sorted[0].displayBox.width * sorted[0].displayBox.height;
      final secondArea =
          sorted[1].displayBox.width * sorted[1].displayBox.height;
      if ((secondArea - firstArea).abs() <=
          HandGestureThresholds.followObjectPointingAreaTieTolerance) {
        return const StrictPointingTargetSelection.ambiguous();
      }
    }
    return StrictPointingTargetSelection.selected(sorted.first);
  }
}
