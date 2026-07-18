import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/stand_control_mode.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/screens/face_object_debug_camera_screen.dart';
import 'package:gesture_detector/hand_gesture_features/stand_control_home_page.dart';

void main() {
  testWidgets('home screen shows hand gesture as the selected mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StandControlHomePage(
          initialMode: StandControlMode.handGesture,
          disabledModes: {
            StandControlMode.automaticDetect,
            StandControlMode.voiceCommand,
          },
        ),
      ),
    );

    expect(find.text('Control Settings'), findsOneWidget);
    expect(find.text('Hand Gesture'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('GESTURE'), findsOneWidget);
    expect(find.text('SOON'), findsNothing);
    expect(
      find.byKey(const Key('faceObjectDebugCameraButton')),
      findsOneWidget,
    );
  });

  testWidgets(
    'disabled visible mode tap calls its callback without changing selection',
    (tester) async {
      var handTapCount = 0;
      var modeChangeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StandControlHomePage(
            initialMode: StandControlMode.handGesture,
            disabledModes: const {StandControlMode.handGesture},
            onModeChanged: (_) {
              modeChangeCount += 1;
            },
            onHandGestureTap: () {
              handTapCount += 1;
            },
          ),
        ),
      );

      await tester.tap(find.text('Hand Gesture'));
      await tester.pumpAndSettle();

      expect(handTapCount, 1);
      expect(modeChangeCount, 0);
      expect(find.text('ON'), findsOneWidget);
      expect(find.text('SOON'), findsOneWidget);
    },
  );

  testWidgets('debug floating button opens face/object debug screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return StandControlHomePage(
              onDebugCameraTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FaceObjectDebugCameraScreen(
                      autoStartCamera: false,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('faceObjectDebugCameraButton')));
    await tester.pumpAndSettle();

    expect(find.byType(FaceObjectDebugCameraScreen), findsOneWidget);
    expect(find.text('Face/Object Debug'), findsOneWidget);
  });

  testWidgets('home feature handlers hide debug and training entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StandControlHomePage(
          showDebugCameraButton: false,
          showMovingDownTraining: false,
        ),
      ),
    );

    expect(find.byKey(const Key('faceObjectDebugCameraButton')), findsNothing);
    expect(find.text('Record Moving Down'), findsNothing);
    expect(find.text('Hand Gesture'), findsOneWidget);
  });

  testWidgets('object detector sheet lists all backends and updates the card', (
    tester,
  ) async {
    var selectedBackend = ObjectDetectionBackend.ultralyticsYolo;
    ObjectDetectionBackend? debugCameraBackend;
    ObjectDetectionBackend? handCameraBackend;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return StandControlHomePage(
              selectedObjectDetectionBackend: selectedBackend,
              supportsNativeMethodChannel: true,
              supportsOpenCvSdk: true,
              onObjectDetectionBackendChanged: (backend) {
                setState(() => selectedBackend = backend);
              },
              onDebugCameraTap: () {
                debugCameraBackend = selectedBackend;
              },
              onHandGestureTap: () {
                handCameraBackend = selectedBackend;
              },
            );
          },
        ),
      ),
    );

    final settingsCard = find.byKey(const Key('objectDetectorSettingsCard'));
    await tester.ensureVisible(settingsCard);
    await tester.tap(settingsCard);
    await tester.pumpAndSettle();

    expect(find.text('Native YOLO'), findsOneWidget);
    expect(find.text('OpenCV SDK'), findsOneWidget);
    expect(find.text('Ultralytics YOLO'), findsOneWidget);
    expect(find.text('Google ML Kit'), findsOneWidget);
    expect(find.text('EfficientDet Lite'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<ObjectDetectionBackend>>(
            find.byType(RadioGroup<ObjectDetectionBackend>),
          )
          .groupValue,
      ObjectDetectionBackend.ultralyticsYolo,
    );

    for (var index = 0; index < objectDetectionBackendOptions.length; index++) {
      final backend = objectDetectionBackendOptions[index];
      await tester.tap(find.text(backend.displayName));
      await tester.pumpAndSettle();

      expect(selectedBackend, backend);
      expect(find.text('Current: ${backend.displayName}'), findsOneWidget);

      if (index < objectDetectionBackendOptions.length - 1) {
        await tester.ensureVisible(settingsCard);
        await tester.tap(settingsCard);
        await tester.pumpAndSettle();
      }
    }

    await tester.tap(find.byKey(const Key('faceObjectDebugCameraButton')));
    final handGestureCard = find.byKey(const Key('handGestureControlCard'));
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(handGestureCard);

    expect(debugCameraBackend, objectDetectionBackendOptions.last);
    expect(handCameraBackend, objectDetectionBackendOptions.last);
  });

  testWidgets(
    'Native YOLO remains visible but disabled without Android support',
    (tester) async {
      ObjectDetectionBackend? changedBackend;

      await tester.pumpWidget(
        MaterialApp(
          home: StandControlHomePage(
            selectedObjectDetectionBackend:
                ObjectDetectionBackend.ultralyticsYolo,
            supportsNativeMethodChannel: false,
            supportsOpenCvSdk: false,
            onObjectDetectionBackendChanged: (backend) {
              changedBackend = backend;
            },
          ),
        ),
      );

      final settingsCard = find.byKey(const Key('objectDetectorSettingsCard'));
      await tester.ensureVisible(settingsCard);
      await tester.tap(settingsCard);
      await tester.pumpAndSettle();

      final nativeOption = find.byKey(
        const Key('objectDetectorOption_nativeMethodChannel'),
      );
      expect(nativeOption, findsOneWidget);
      expect(tester.widget<ListTile>(nativeOption).enabled, isFalse);
      expect(find.textContaining('Android only.'), findsNWidgets(2));
      expect(changedBackend, isNull);

      final openCvOption = find.byKey(
        const Key('objectDetectorOption_opencvSdk'),
      );
      expect(openCvOption, findsOneWidget);
      expect(tester.widget<ListTile>(openCvOption).enabled, isFalse);
    },
  );

  testWidgets('Google ML Kit is disabled outside mobile platforms', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StandControlHomePage(supportsGoogleMlKit: false)),
    );

    final settingsCard = find.byKey(const Key('objectDetectorSettingsCard'));
    await tester.ensureVisible(settingsCard);
    await tester.tap(settingsCard);
    await tester.pumpAndSettle();

    final option = find.byKey(const Key('objectDetectorOption_googleMlKit'));
    expect(option, findsOneWidget);
    expect(tester.widget<ListTile>(option).enabled, isFalse);
    expect(find.textContaining('Android and iOS only.'), findsOneWidget);
  });
}
