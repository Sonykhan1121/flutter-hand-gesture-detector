import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/moving_down_safe_area_overlay.dart';

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required String? hand,
  required bool inside,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: MovingDownSafeAreaOverlay(
            canvasSize: const Size(360, 640),
            detectedHandLabel: hand,
            handInside: inside,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('asks for a complete hand when none is detected', (tester) async {
    await _pumpOverlay(tester, hand: null, inside: false);

    expect(find.byKey(const Key('movingDownSafeAreaBoundary')), findsOneWidget);
    expect(
      find.text('Place the complete hand inside the safety box'),
      findsOneWidget,
    );
  });

  testWidgets('shows physical handedness and safe state', (tester) async {
    await _pumpOverlay(tester, hand: 'Right', inside: true);

    expect(find.text('Right hand · fully inside'), findsOneWidget);
  });

  testWidgets('warns when the hand approaches an edge', (tester) async {
    await _pumpOverlay(tester, hand: 'Left', inside: false);

    expect(find.text('Left hand · move away from the edge'), findsOneWidget);
  });
}
