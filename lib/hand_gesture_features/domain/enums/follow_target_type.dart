/// Types of things that the camera can lock onto after a release gesture.
enum FollowTargetType { face, object }

/// Converts target types into short labels for overlays and status text.
extension FollowTargetTypeLabel on FollowTargetType {
  /// Human-readable name for the target type.
  String get displayLabel {
    switch (this) {
      case FollowTargetType.face:
        return 'Face';
      case FollowTargetType.object:
        return 'Object';
    }
  }
}
