import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/utils/hand_gesture_label_mapper.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  test('maps package Thumb Down to the Punch display label', () {
    expect(GestureType.closedFist.displayLabel, 'Closed fist');
    expect(GestureType.thumbDown.displayLabel, 'Punch');
  });
}
