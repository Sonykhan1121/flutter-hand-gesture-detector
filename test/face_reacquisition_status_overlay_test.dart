import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/face_reacquisition_status_overlay.dart';

void main() {
  testWidgets('shows the remaining face reacquisition countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: FaceReacquisitionStatusOverlay.waiting(
              remaining: Duration(milliseconds: 2499),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('faceReacquisitionStatusOverlay')),
      findsOneWidget,
    );
    expect(find.text('Face lost - waiting (2.5s)'), findsOneWidget);
  });

  testWidgets('tells the user to run Detect My Face after timeout', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: FaceReacquisitionStatusOverlay.timedOut()),
        ),
      ),
    );

    expect(find.text('Face lost - use Detect My Face again'), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });
}
