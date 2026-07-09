import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

import '../enums/follow_object_release_reason.dart';

/// Result returned after each follow-object state-machine update.
class FollowObjectSequenceResult {
  const FollowObjectSequenceResult({
    required this.isActive,
    required this.isDetected,
    required this.isTargetSelectionActive,
    this.packageGestureType,
    this.gestureConfidence = 0,
    this.releasePoint,
    this.releaseReason,
  });

  final bool isActive;
  final bool isDetected;
  final bool isTargetSelectionActive;
  final GestureType? packageGestureType;
  final double gestureConfidence;

  /// Center point of the hand box when the final open/release pose is detected.
  final Offset? releasePoint;
  final FollowObjectReleaseReason? releaseReason;
}
