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
    this.isWaitingForHandReturn = false,
    this.handReturnDeadline,
    this.handReturnProgress = 0,
    this.savedHandPoint,
    this.indexPip,
    this.indexTip,
    this.isIndexOnlyPointing = false,
    this.isWaitingForFinalPalm = false,
    this.finalPalmDeadline,
    this.finalPalmProgress = 0,
    this.isFinalPalmConfirmation = false,
    this.wasCancelled = false,
    this.cancellationReason,
  });

  final bool isActive;
  final bool isDetected;
  final bool isTargetSelectionActive;
  final GestureType? packageGestureType;
  final double gestureConfidence;

  /// Center point of the hand box when the final open/release pose is detected.
  final Offset? releasePoint;
  final FollowObjectReleaseReason? releaseReason;

  final bool isWaitingForHandReturn;
  final DateTime? handReturnDeadline;
  final double handReturnProgress;
  final Offset? savedHandPoint;

  /// Raw hand-detection coordinates used to project a virtual Point 8.
  final Offset? indexPip;
  final Offset? indexTip;
  final bool isIndexOnlyPointing;

  /// Final confirmation state after the 500ms target dwell completes.
  final bool isWaitingForFinalPalm;
  final DateTime? finalPalmDeadline;
  final double finalPalmProgress;
  final bool isFinalPalmConfirmation;

  /// True only on the frame where a timeout cancels the active sequence.
  final bool wasCancelled;
  final String? cancellationReason;
}
