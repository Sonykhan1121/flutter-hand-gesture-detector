enum FollowTargetType { face, object }

extension FollowTargetTypeLabel on FollowTargetType {
  String get displayLabel {
    switch (this) {
      case FollowTargetType.face:
        return 'Face';
      case FollowTargetType.object:
        return 'Object';
    }
  }
}
