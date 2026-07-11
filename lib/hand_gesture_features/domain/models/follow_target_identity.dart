import 'dart:ui';

import '../enums/follow_target_type.dart';
import 'appearance_signature.dart';
import 'follow_target.dart';

/// Immutable identity captured when the user selects a follow target.
class FollowTargetIdentity {
  const FollowTargetIdentity({
    required this.type,
    required this.normalizedLabel,
    required this.initialBox,
    required this.selectedAt,
    this.classIndex,
    this.faceTrackingId,
    this.appearanceSignature,
  });

  final FollowTargetType type;
  final String normalizedLabel;
  final int? classIndex;
  final int? faceTrackingId;
  final Rect initialBox;
  final DateTime selectedAt;
  final AppearanceSignature? appearanceSignature;

  factory FollowTargetIdentity.fromTarget(FollowTarget target) {
    return FollowTargetIdentity(
      type: target.type,
      normalizedLabel: normalizeLabel(target.label ?? target.type.displayLabel),
      classIndex: target.classIndex,
      faceTrackingId: target.trackingId,
      initialBox: target.displayBox,
      selectedAt: target.detectedAt,
      appearanceSignature: target.appearanceSignature,
    );
  }

  String get displayLabel => normalizedLabel.isEmpty
      ? type.displayLabel.toLowerCase()
      : normalizedLabel;

  static String normalizeLabel(String value) => value.trim().toLowerCase();
}
