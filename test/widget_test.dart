import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/stand_control_mode.dart';
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
            disabledModes: const {
              StandControlMode.handGesture,
            },
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
}
