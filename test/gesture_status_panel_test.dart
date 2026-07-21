import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/gesture_status_panel.dart';

void main() {
  group('GestureStatusPanel', () {
    testWidgets(
      'prompts for all movement directions when no hand is detected',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: GestureStatusPanel(
                gestureText: 'No hand detected',
                handText: '',
                gestureConfidence: 0,
                detectedHandsCount: 0,
              ),
            ),
          ),
        );

        expect(
          find.text('Move your hand left, right, up, or down'),
          findsOneWidget,
        );
      },
    );

    testWidgets('hides show-your-hand text once a hand is detected', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GestureStatusPanel(
              gestureText: 'Show your hand',
              handText: 'Right hand',
              gestureConfidence: 0,
              detectedHandsCount: 1,
            ),
          ),
        ),
      );

      expect(find.text('Show your hand'), findsNothing);
      expect(find.textContaining('Hands: 1'), findsOneWidget);
    });

    testWidgets('keeps show-your-hand text when no hand is detected', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GestureStatusPanel(
              gestureText: 'Show your hand',
              handText: '',
              gestureConfidence: 0,
              detectedHandsCount: 0,
            ),
          ),
        ),
      );

      expect(find.text('Show your hand'), findsOneWidget);
    });

    testWidgets('marks every movement direction as detected', (tester) async {
      for (final gestureText in const [
        'Moving left',
        'Moving right',
        'Moving up',
        'Moving down',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureStatusPanel(
                gestureText: gestureText,
                handText: 'Right hand',
                gestureConfidence: 1,
                detectedHandsCount: 1,
              ),
            ),
          ),
        );

        expect(find.textContaining('detected'), findsOneWidget);
        expect(find.textContaining('100%'), findsNothing);
      }
    });
  });
}
