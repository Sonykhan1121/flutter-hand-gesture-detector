import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';

void main() {
  test(
    'recognizes person labels regardless of case and surrounding spaces',
    () {
      expect(AppObjectDetection.isPersonLabel('person'), isTrue);
      expect(AppObjectDetection.isPersonLabel('Person'), isTrue);
      expect(AppObjectDetection.isPersonLabel('  PERSON  '), isTrue);
    },
  );

  test('does not reject non-person object classes', () {
    expect(AppObjectDetection.isPersonLabel('bottle'), isFalse);
    expect(AppObjectDetection.isPersonLabel('chair'), isFalse);
    expect(AppObjectDetection.isPersonLabel('personal care item'), isFalse);
  });
}
