import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/ultralytics_yolo_model_preloader.dart';

void main() {
  test(
    'shares one preparation between background and camera callers',
    () async {
      final completer = Completer<Map<String, dynamic>>();
      var calls = 0;
      final preloader = UltralyticsYoloModelPreloader(
        inspectModel: (_) {
          calls++;
          return completer.future;
        },
      );

      final background = preloader.prepare();
      final camera = preloader.prepare();

      expect(background, same(camera));
      expect(preloader.isPreparing, isTrue);
      expect(calls, 1);

      completer.complete({
        'task': 'detect',
        'labels': ['person', 'bottle'],
      });
      expect(await camera, containsPair('task', 'detect'));
      expect(preloader.isPrepared, isTrue);
      expect(preloader.isPreparing, isFalse);
    },
  );

  test('uses cached metadata after preparation succeeds', () async {
    var calls = 0;
    final preloader = UltralyticsYoloModelPreloader(
      inspectModel: (_) async {
        calls++;
        return {'task': 'detect'};
      },
    );

    final first = await preloader.prepare();
    final second = await preloader.prepare();

    expect(second, same(first));
    expect(calls, 1);
  });

  test('allows camera startup to retry after background failure', () async {
    var calls = 0;
    final preloader = UltralyticsYoloModelPreloader(
      inspectModel: (_) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return {'task': 'detect'};
      },
    );

    await expectLater(preloader.prepare(), throwsStateError);
    expect(preloader.isPrepared, isFalse);
    expect(preloader.isPreparing, isFalse);

    expect(await preloader.prepare(), containsPair('task', 'detect'));
    expect(calls, 2);
  });

  test('prefetch absorbs background download errors', () async {
    final preloader = UltralyticsYoloModelPreloader(
      inspectModel: (_) async => throw StateError('offline'),
    );

    await expectLater(preloader.prefetch(), completes);
    expect(preloader.isPrepared, isFalse);
  });
}
