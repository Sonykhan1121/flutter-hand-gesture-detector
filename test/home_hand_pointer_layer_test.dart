import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/home_hand_pointer_layer.dart';
import 'package:gesture_detector/hand_gesture_features/stand_control_home_page.dart';

void main() {
  Widget testApp({
    required Offset? cursor,
    required VoidCallback onFirstPressed,
    VoidCallback? onSecondPressed,
    bool firstEnabled = true,
    bool showCursor = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  key: const Key('firstAction'),
                  onPressed: firstEnabled ? onFirstPressed : null,
                  child: const Text('First action'),
                ),
                const SizedBox(height: 80),
                ElevatedButton(
                  key: const Key('secondAction'),
                  onPressed: onSecondPressed,
                  child: const Text('Second action'),
                ),
              ],
            ),
            HomeGestureDwellOverlay(cursor: cursor, showCursor: showCursor),
          ],
        ),
      ),
    );
  }

  testWidgets('transparent overlay preserves ordinary touch input', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      testApp(cursor: null, onFirstPressed: () => activations += 1),
    );

    await tester.tap(find.byKey(const Key('firstAction')));
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('home camera retries after a route-release collision', (
    tester,
  ) async {
    final controller = HomeHandPointerController();
    var startAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const SizedBox.expand(),
            HomeHandPointerLayer(
              controller: controller,
              cameraStartOverride: () async {
                startAttempts += 1;
                if (startAttempts == 2) {
                  throw StateError('previous route is still releasing camera');
                }
              },
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(startAttempts, 1);

    await controller.suspend();
    await controller.resume();
    expect(startAttempts, 2);

    await tester.pump(const Duration(milliseconds: 199));
    expect(startAttempts, 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(startAttempts, 3);
  });

  testWidgets(
    'home camera keeps retrying until a returning route releases it',
    (tester) async {
      final controller = HomeHandPointerController();
      var startAttempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              const SizedBox.expand(),
              HomeHandPointerLayer(
                controller: controller,
                cameraStartOverride: () async {
                  startAttempts += 1;
                  if (startAttempts >= 2 && startAttempts <= 6) {
                    throw StateError('camera is still owned by the old route');
                  }
                },
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(startAttempts, 1);

      await controller.suspend();
      await controller.resume();
      expect(startAttempts, 2);

      await tester.pump(const Duration(milliseconds: 200));
      expect(startAttempts, 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(startAttempts, 4);
      await tester.pump(const Duration(seconds: 1));
      expect(startAttempts, 5);
      await tester.pump(const Duration(seconds: 2));
      expect(startAttempts, 6);
      await tester.pump(const Duration(seconds: 2));
      expect(startAttempts, 7);
    },
  );

  testWidgets('point 8 activates an enabled control at exactly two seconds', (
    tester,
  ) async {
    var activations = 0;
    void onPressed() => activations += 1;
    await tester.pumpWidget(testApp(cursor: null, onFirstPressed: onPressed));
    final targetCenter = tester.getCenter(find.byKey(const Key('firstAction')));

    await tester.pumpWidget(
      testApp(cursor: targetCenter, onFirstPressed: onPressed),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(activations, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(activations, 1);

    await tester.pump(const Duration(seconds: 3));
    expect(activations, 1);
  });

  testWidgets('hidden point 8 remains active without painting the cursor', (
    tester,
  ) async {
    var activations = 0;
    void onPressed() => activations += 1;
    await tester.pumpWidget(testApp(cursor: null, onFirstPressed: onPressed));
    final targetCenter = tester.getCenter(find.byKey(const Key('firstAction')));

    await tester.pumpWidget(
      testApp(
        cursor: targetCenter,
        onFirstPressed: onPressed,
        showCursor: false,
      ),
    );
    await tester.pump();

    final customPaint = tester.widget<CustomPaint>(
      find.byKey(const Key('homeGesturePointerOverlay')),
    );
    final dynamic painter = customPaint.painter;
    expect(painter.cursor, isNull);

    await tester.pump(const Duration(seconds: 2));
    expect(activations, 1);
  });

  testWidgets('leaving a control resets its two-second hold', (tester) async {
    var activations = 0;
    void onPressed() => activations += 1;
    await tester.pumpWidget(testApp(cursor: null, onFirstPressed: onPressed));
    final targetCenter = tester.getCenter(find.byKey(const Key('firstAction')));

    await tester.pumpWidget(
      testApp(cursor: targetCenter, onFirstPressed: onPressed),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(
      testApp(cursor: const Offset(10, 10), onFirstPressed: onPressed),
    );
    await tester.pump();
    await tester.pumpWidget(
      testApp(cursor: targetCenter, onFirstPressed: onPressed),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(activations, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(activations, 1);
  });

  testWidgets('moving to another control starts a fresh hold', (tester) async {
    var firstActivations = 0;
    var secondActivations = 0;
    void onFirst() => firstActivations += 1;
    void onSecond() => secondActivations += 1;
    await tester.pumpWidget(
      testApp(cursor: null, onFirstPressed: onFirst, onSecondPressed: onSecond),
    );
    final firstCenter = tester.getCenter(find.byKey(const Key('firstAction')));
    final secondCenter = tester.getCenter(
      find.byKey(const Key('secondAction')),
    );

    await tester.pumpWidget(
      testApp(
        cursor: firstCenter,
        onFirstPressed: onFirst,
        onSecondPressed: onSecond,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(
      testApp(
        cursor: secondCenter,
        onFirstPressed: onFirst,
        onSecondPressed: onSecond,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(firstActivations, 0);
    expect(secondActivations, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(firstActivations, 0);
    expect(secondActivations, 1);
  });

  testWidgets('disabled controls cannot be gesture-activated', (tester) async {
    var activations = 0;
    void onPressed() => activations += 1;
    await tester.pumpWidget(
      testApp(cursor: null, onFirstPressed: onPressed, firstEnabled: false),
    );
    final targetCenter = tester.getCenter(find.byKey(const Key('firstAction')));

    await tester.pumpWidget(
      testApp(
        cursor: targetCenter,
        onFirstPressed: onPressed,
        firstEnabled: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(activations, 0);
  });

  testWidgets('standard settings list tiles support the same hold action', (
    tester,
  ) async {
    var activations = 0;
    void onTap() => activations += 1;

    Widget settingsApp(Offset? cursor) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ListTile(
                key: const Key('settingsTile'),
                title: const Text('Object Detector'),
                onTap: onTap,
              ),
              HomeGestureDwellOverlay(cursor: cursor),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(settingsApp(null));
    final targetCenter = tester.getCenter(
      find.byKey(const Key('settingsTile')),
    );
    await tester.pumpWidget(settingsApp(targetCenter));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(activations, 1);
  });

  testWidgets('camera pages can drive the root cursor without another camera', (
    tester,
  ) async {
    final controller = HomeHandPointerController();
    final owner = Object();
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            HomeHandPointerLayer(controller: controller),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('cameraPageAction'),
              onPressed: () => activations += 1,
              child: const Text('Camera page action'),
            ),
          ),
        ),
      ),
    );

    final canvasSize = tester.getSize(find.byType(Scaffold));
    final targetCenter = tester.getCenter(
      find.byKey(const Key('cameraPageAction')),
    );
    controller.updateExternalPointer(
      owner: owner,
      indexTip: targetCenter,
      detectionImageSize: canvasSize,
      mirrorHorizontally: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(activations, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(activations, 1);

    controller.clearExternalPointer(owner);
    await tester.pump();
  });

  testWidgets('camera-page hand loss cancels a pending click immediately', (
    tester,
  ) async {
    final controller = HomeHandPointerController();
    final owner = Object();
    var activations = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            HomeHandPointerLayer(controller: controller),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('pendingCameraAction'),
              onPressed: () => activations += 1,
              child: const Text('Pending camera action'),
            ),
          ),
        ),
      ),
    );

    final canvasSize = tester.getSize(find.byType(Scaffold));
    controller.updateExternalPointer(
      owner: owner,
      indexTip: tester.getCenter(find.byKey(const Key('pendingCameraAction'))),
      detectionImageSize: canvasSize,
      mirrorHorizontally: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));

    controller.updateExternalPointer(
      owner: owner,
      indexTip: null,
      detectionImageSize: canvasSize,
      mirrorHorizontally: false,
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(activations, 0);
  });

  testWidgets(
    'point 8 opens real home cards and selects a detector from the modal',
    (tester) async {
      final controller = HomeHandPointerController();
      final owner = Object();
      var handGestureOpens = 0;
      ObjectDetectionBackend? selectedBackend;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              HomeHandPointerLayer(controller: controller),
            ],
          ),
          home: StandControlHomePage(
            showDebugCameraButton: true,
            showMovingDownTraining: true,
            supportsNativeMethodChannel: true,
            supportsOpenCvSdk: true,
            onHandGestureTap: () => handGestureOpens += 1,
            onObjectDetectionBackendChanged: (backend) {
              selectedBackend = backend;
            },
          ),
        ),
      );
      final canvasSize = tester.getSize(find.byType(Scaffold));

      void pointAt(Offset? point) {
        controller.updateExternalPointer(
          owner: owner,
          indexTip: point,
          detectionImageSize: canvasSize,
          mirrorHorizontally: false,
        );
      }

      pointAt(
        tester.getCenter(find.byKey(const Key('handGestureControlCard'))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(handGestureOpens, 1);

      pointAt(null);
      await tester.pump();
      pointAt(
        tester.getCenter(find.byKey(const Key('objectDetectorSettingsCard'))),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      pointAt(null);
      await tester.pumpAndSettle();
      expect(find.text('Native YOLO'), findsOneWidget);

      final option = find.byKey(
        const Key('objectDetectorOption_nativeMethodChannel'),
      );
      pointAt(tester.getCenter(option));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      pointAt(null);
      await tester.pumpAndSettle();

      expect(selectedBackend, ObjectDetectionBackend.nativeMethodChannel);
    },
  );
}
