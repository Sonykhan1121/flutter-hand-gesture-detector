import 'dart:ui';

import '../enums/follow_target_type.dart';

class FollowTarget {
  const FollowTarget({
    required this.type,
    required this.boundingBox,
    required this.displayBox,
    required this.detectedAt,
    this.trackingId,
    this.label,
  });

  final FollowTargetType type;
  final Rect boundingBox;

  /// Preview-space box normalized to 0..1 after rotation and mirroring.
  final Rect displayBox;
  final DateTime detectedAt;
  final int? trackingId;
  final String? label;

  String get displayLabel =>
      label?.isNotEmpty == true ? label! : type.displayLabel;
}
