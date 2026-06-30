import 'package:hand_detection/hand_detection.dart';

extension GestureTypeLabelMapper on GestureType {
  String get displayLabel {
    switch (this) {
      case GestureType.closedFist:
        return 'Closed fist';
      case GestureType.openPalm:
        return 'Open palm';
      case GestureType.pointingUp:
        return 'Pointing up';
      case GestureType.thumbDown:
        return 'Thumb down';
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

extension HandednessLabelMapper on Handedness? {
  String get displayLabel {
    final handedness = this;

    if (handedness == Handedness.left) return 'Left hand';
    if (handedness == Handedness.right) return 'Right hand';

    return '';
  }
}
