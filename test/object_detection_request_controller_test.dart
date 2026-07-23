import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_request_controller.dart';

void main() {
  group('ObjectDetectionRequestController', () {
    test(
      'submits only one request while busy and returns cached detections',
      () async {
        final controller = ObjectDetectionRequestController(
          minInterval: const Duration(milliseconds: 350),
        );
        final start = DateTime(2026);
        var submitCount = 0;

        final first = Completer<List<AppObjectDetection>>();
        final initialCache = controller.detectOrReuse(
          now: start,
          detectorBusy: false,
          detect: () {
            submitCount++;
            return first.future;
          },
        );

        expect(initialCache, isEmpty);
        expect(controller.isBusy, isTrue);
        expect(submitCount, 1);

        final busyCache = controller.detectOrReuse(
          now: start.add(const Duration(seconds: 1)),
          detectorBusy: false,
          detect: () {
            submitCount++;
            return Future.value(const []);
          },
        );

        expect(busyCache, isEmpty);
        expect(submitCount, 1);

        final firstDetection = _detection(label: 'First');
        first.complete([firstDetection]);
        await first.future;
        await Future<void>.delayed(Duration.zero);

        expect(controller.isBusy, isFalse);
        expect(controller.cachedDetections, [firstDetection]);
      },
    );

    test(
      'returns cached detections while a later request is in flight',
      () async {
        final controller = ObjectDetectionRequestController(
          minInterval: const Duration(milliseconds: 350),
        );
        final start = DateTime(2026);
        var submitCount = 0;

        final first = Completer<List<AppObjectDetection>>();
        controller.detectOrReuse(
          now: start,
          detectorBusy: false,
          detect: () {
            submitCount++;
            return first.future;
          },
        );
        final firstDetection = _detection(label: 'First');
        first.complete([firstDetection]);
        await first.future;
        await Future<void>.delayed(Duration.zero);

        final second = Completer<List<AppObjectDetection>>();
        final cachedDuringSecond = controller.detectOrReuse(
          now: start.add(const Duration(milliseconds: 500)),
          detectorBusy: false,
          detect: () {
            submitCount++;
            return second.future;
          },
        );

        expect(cachedDuringSecond, [firstDetection]);
        expect(controller.isBusy, isTrue);
        expect(submitCount, 2);

        final cachedWhileBusy = controller.detectOrReuse(
          now: start.add(const Duration(seconds: 1)),
          detectorBusy: false,
          detect: () {
            submitCount++;
            return Future.value(const []);
          },
        );

        expect(cachedWhileBusy, [firstDetection]);
        expect(submitCount, 2);

        final secondDetection = _detection(label: 'Second');
        second.complete([secondDetection]);
        await second.future;
        await Future<void>.delayed(Duration.zero);

        expect(controller.cachedDetections, [secondDetection]);
        expect(controller.isBusy, isFalse);
      },
    );

    test('respects detector busy and throttle window', () {
      final controller = ObjectDetectionRequestController(
        minInterval: const Duration(milliseconds: 350),
      );
      final start = DateTime(2026);
      var submitCount = 0;

      final detectorBusyCache = controller.detectOrReuse(
        now: start,
        detectorBusy: true,
        detect: () {
          submitCount++;
          return Future.value(const []);
        },
      );

      expect(detectorBusyCache, isEmpty);
      expect(submitCount, 0);

      controller.detectOrReuse(
        now: start,
        detectorBusy: false,
        detect: () {
          submitCount++;
          return Future.value(const []);
        },
      );

      final throttledCache = controller.detectOrReuse(
        now: start.add(const Duration(milliseconds: 100)),
        detectorBusy: false,
        detect: () {
          submitCount++;
          return Future.value(const []);
        },
      );

      expect(throttledCache, isEmpty);
      expect(submitCount, 1);
    });

    test(
      'selection override accelerates cadence without overlapping',
      () async {
        final controller = ObjectDetectionRequestController(
          minInterval: const Duration(milliseconds: 650),
        );
        final start = DateTime(2026);
        var submitCount = 0;

        final first = controller.submit(
          now: start,
          detectorBusy: false,
          minIntervalOverride: const Duration(milliseconds: 350),
          detect: () {
            submitCount++;
            return Future.value(const []);
          },
        );
        await first;
        await Future<void>.delayed(Duration.zero);

        expect(
          controller.submit(
            now: start.add(const Duration(milliseconds: 349)),
            detectorBusy: false,
            minIntervalOverride: const Duration(milliseconds: 350),
            detect: () {
              submitCount++;
              return Future.value(const []);
            },
          ),
          isNull,
        );
        final exact = controller.submit(
          now: start.add(const Duration(milliseconds: 350)),
          detectorBusy: false,
          minIntervalOverride: const Duration(milliseconds: 350),
          detect: () {
            submitCount++;
            return Future.value(const []);
          },
        );
        expect(exact, isNotNull);
        expect(submitCount, 2);
      },
    );

    test('clear drops pending and cached results', () async {
      final controller = ObjectDetectionRequestController(
        minInterval: const Duration(milliseconds: 350),
      );
      final start = DateTime(2026);
      var submitCount = 0;
      final pending = Completer<List<AppObjectDetection>>();

      controller.detectOrReuse(
        now: start,
        detectorBusy: false,
        detect: () {
          submitCount++;
          return pending.future;
        },
      );

      controller.clear();
      expect(controller.isBusy, isFalse);
      expect(controller.cachedDetections, isEmpty);

      pending.complete([_detection(label: 'Stale')]);
      await pending.future;
      await Future<void>.delayed(Duration.zero);

      expect(controller.cachedDetections, isEmpty);

      controller.detectOrReuse(
        now: start,
        detectorBusy: false,
        detect: () {
          submitCount++;
          return Future.value([_detection(label: 'Fresh')]);
        },
      );

      expect(submitCount, 2);
    });
  });
}

AppObjectDetection _detection({required String label}) {
  return AppObjectDetection(
    boundingBox: const Rect.fromLTWH(1, 2, 3, 4),
    imageSize: const Size(10, 10),
    label: label,
    confidence: 0.9,
    classIndex: 1,
  );
}
