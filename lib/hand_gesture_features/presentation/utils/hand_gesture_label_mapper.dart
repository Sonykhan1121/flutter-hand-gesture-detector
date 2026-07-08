import 'package:hand_detection/hand_detection.dart';

/// Maps package gesture enum values to user-facing text.
extension GestureTypeLabelMapper on GestureType {
  /// Display label used by the live gesture status panel.
  String get displayLabel {
    switch (this) {
      case GestureType.closedFist:
        return 'Closed fist';
      case GestureType.openPalm:
        return 'Open palm';
      case GestureType.pointingUp:
        return 'Pointing up';
      case GestureType.thumbDown:
        return 'Punch';
      case GestureType.thumbUp:
        return 'Thumb up';
      case GestureType.victory:
        return 'Victory';
      case GestureType.iLoveYou:
        return 'I love you';
      case GestureType.unknown:
        return 'Unknown gesture';
    }
  }
}

/// Maps nullable handedness values to short UI labels.
extension HandednessLabelMapper on Handedness? {
  /// Display label for the detected hand, or empty when unknown.
  String get displayLabel {
    final handedness = this;

    if (handedness == Handedness.left) return 'Left hand';
    if (handedness == Handedness.right) return 'Right hand';

    return '';
  }
}
