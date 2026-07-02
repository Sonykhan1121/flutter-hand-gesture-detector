import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

class FollowObjectSequenceResult {
  const FollowObjectSequenceResult({
    required this.isActive,
    required this.isDetected,
    this.packageGestureType,
    this.releasePoint,
  });

  final bool isActive;
  final bool isDetected;
  final GestureType? packageGestureType;

  /// Center point of the hand box when the final open/release pose is detected.
  final Offset? releasePoint;
}
