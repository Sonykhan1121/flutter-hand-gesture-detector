import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/utils/detection_debug_log_formatter.dart';

void main() {
  group('formatDetectionDebugLog', () {
    test('prints class name, pixel area, and elapsed time', () {
      final log = formatDetectionDebugLog(
        label: 'Bottle',
        boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
        elapsed: const Duration(milliseconds: 17),
      );

      expect(log, 'Bottle : area=1200, time=17ms');
    });

    test('clamps non-positive area dimensions to zero', () {
      final log = formatDetectionDebugLog(
        label: 'Face',
        boundingBox: const Rect.fromLTWH(10, 20, -30, 40),
        elapsed: const Duration(milliseconds: 8),
      );

      expect(log, 'Face : area=0, time=8ms');
    });
  });
}
