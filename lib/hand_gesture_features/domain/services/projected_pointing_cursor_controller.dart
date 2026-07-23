import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';

class ProjectedPointingCursorObservation {
  const ProjectedPointingCursorObservation({
    required this.realIndexTip,
    required this.rawProjectedPoint,
    required this.projectedPoint,
    required this.visiblePoint,
    required this.isInFrame,
  });

  final Offset realIndexTip;
  final Offset rawProjectedPoint;
  final Offset projectedPoint;

  /// Projected point clamped only for drawing an off-screen edge indicator.
  final Offset visiblePoint;
  final bool isInFrame;
}

/// Projects a virtual Point 8 beyond the fingertip and smooths display jitter.
class ProjectedPointingCursorController {
  ProjectedPointingCursorController({
    this.distanceMultiplier =
        HandGestureThresholds.followObjectProjectedPointDistanceMultiplier,
    this.smoothingAlpha =
        HandGestureThresholds.followObjectProjectedPointSmoothingAlpha,
  });

  final double distanceMultiplier;
  final double smoothingAlpha;

  Offset? _smoothedPoint;

  Offset? get smoothedPoint => _smoothedPoint;

  ProjectedPointingCursorObservation? observe({
    required Offset indexPip,
    required Offset indexTip,
  }) {
    if (!_isFinitePoint(indexPip) ||
        !_isFinitePoint(indexTip) ||
        !distanceMultiplier.isFinite ||
        distanceMultiplier < 0 ||
        !smoothingAlpha.isFinite ||
        smoothingAlpha <= 0 ||
        smoothingAlpha > 1) {
      return null;
    }

    final direction = indexTip - indexPip;
    if (!direction.distanceSquared.isFinite ||
        direction.distanceSquared <= 1e-12) {
      return null;
    }

    final rawProjectedPoint = indexTip + direction * distanceMultiplier;
    if (!_isFinitePoint(rawProjectedPoint)) return null;

    final previous = _smoothedPoint;
    final projectedPoint = previous == null
        ? rawProjectedPoint
        : Offset(
            previous.dx + (rawProjectedPoint.dx - previous.dx) * smoothingAlpha,
            previous.dy + (rawProjectedPoint.dy - previous.dy) * smoothingAlpha,
          );
    _smoothedPoint = projectedPoint;

    final isInFrame =
        projectedPoint.dx >= 0 &&
        projectedPoint.dx <= 1 &&
        projectedPoint.dy >= 0 &&
        projectedPoint.dy <= 1;
    return ProjectedPointingCursorObservation(
      realIndexTip: indexTip,
      rawProjectedPoint: rawProjectedPoint,
      projectedPoint: projectedPoint,
      visiblePoint: Offset(
        projectedPoint.dx.clamp(0.0, 1.0),
        projectedPoint.dy.clamp(0.0, 1.0),
      ),
      isInFrame: isInFrame,
    );
  }

  void reset() {
    _smoothedPoint = null;
  }

  bool _isFinitePoint(Offset point) => point.dx.isFinite && point.dy.isFinite;
}
