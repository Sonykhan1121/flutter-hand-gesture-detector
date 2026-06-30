import 'package:hand_detection/hand_detection.dart';

class FollowObjectSequenceResult {
  const FollowObjectSequenceResult({
    required this.isActive,
    required this.isDetected,
    this.packageGestureType,
  });

  final bool isActive;
  final bool isDetected;
  final GestureType? packageGestureType;
}
