import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/touch_zoom_guide_overlay.dart';

void main() {
  testWidgets('renders two circles and a connecting line', (tester) async {
    await _pumpGuide(tester);

    expect(find.byKey(TouchZoomGuideOverlay.firstCircleKey), findsOneWidget);
    expect(find.byKey(TouchZoomGuideOverlay.secondCircleKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TouchZoomGuideOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ignores one-finger touch', (tester) async {
    final zoomUpdates = <double>[];
    var startCount = 0;
    var endCount = 0;

    await _pumpGuide(
      tester,
      onZoomChanged: zoomUpdates.add,
      onInteractionStart: () => startCount++,
      onInteractionEnd: () => endCount++,
    );

    final firstCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.firstCircleKey),
    );
    final gesture = await tester.createGesture(pointer: 1);

    await gesture.down(firstCenter);
    await tester.pump();
    await gesture.moveTo(firstCenter.translate(-60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(zoomUpdates, isEmpty);
    expect(startCount, 0);
    expect(endCount, 0);
  });

  testWidgets('starts only when both touches begin near both circles', (
    tester,
  ) async {
    final zoomUpdates = <double>[];
    var startCount = 0;

    await _pumpGuide(
      tester,
      onZoomChanged: zoomUpdates.add,
      onInteractionStart: () => startCount++,
    );

    final secondCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.secondCircleKey),
    );
    final firstGesture = await tester.createGesture(pointer: 1);
    final secondGesture = await tester.createGesture(pointer: 2);

    await firstGesture.down(const Offset(20, 20));
    await tester.pump();
    await secondGesture.down(secondCenter);
    await tester.pump();
    await secondGesture.moveTo(secondCenter.translate(60, 0));
    await tester.pump();

    expect(startCount, 0);
    expect(zoomUpdates, isEmpty);

    await firstGesture.up();
    await secondGesture.up();
  });

  testWidgets('stretching both circles sends a larger zoom level', (
    tester,
  ) async {
    final zoomUpdates = <double>[];
    var startCount = 0;
    var endCount = 0;

    await _pumpGuide(
      tester,
      onZoomChanged: zoomUpdates.add,
      onInteractionStart: () => startCount++,
      onInteractionEnd: () => endCount++,
    );

    final firstCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.firstCircleKey),
    );
    final secondCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.secondCircleKey),
    );

    final firstGesture = await tester.createGesture(pointer: 1);
    final secondGesture = await tester.createGesture(pointer: 2);

    await firstGesture.down(firstCenter);
    await tester.pump();
    await secondGesture.down(secondCenter);
    await tester.pump();

    await firstGesture.moveTo(firstCenter.translate(-45, 0));
    await secondGesture.moveTo(secondCenter.translate(45, 0));
    await tester.pump();

    expect(startCount, 1);
    expect(zoomUpdates, isNotEmpty);
    expect(zoomUpdates.last, greaterThan(2));

    await firstGesture.up();
    await tester.pump();
    await secondGesture.up();
    await tester.pump();

    expect(endCount, 1);
  });

  testWidgets('shrinking both circles sends a smaller zoom level', (
    tester,
  ) async {
    final zoomUpdates = <double>[];

    await _pumpGuide(tester, onZoomChanged: zoomUpdates.add);

    final firstCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.firstCircleKey),
    );
    final secondCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.secondCircleKey),
    );

    final firstGesture = await tester.createGesture(pointer: 1);
    final secondGesture = await tester.createGesture(pointer: 2);

    await firstGesture.down(firstCenter);
    await tester.pump();
    await secondGesture.down(secondCenter);
    await tester.pump();

    await firstGesture.moveTo(firstCenter.translate(35, 0));
    await secondGesture.moveTo(secondCenter.translate(-35, 0));
    await tester.pump();

    expect(zoomUpdates, isNotEmpty);
    expect(zoomUpdates.last, lessThan(2));

    await firstGesture.up();
    await secondGesture.up();
  });

  testWidgets('moving circles almost together sends minimum zoom level', (
    tester,
  ) async {
    final zoomUpdates = <double>[];

    await _pumpGuide(tester, onZoomChanged: zoomUpdates.add);

    final firstCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.firstCircleKey),
    );
    final secondCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.secondCircleKey),
    );
    final center = Offset(
      (firstCenter.dx + secondCenter.dx) / 2,
      firstCenter.dy,
    );

    final firstGesture = await tester.createGesture(pointer: 1);
    final secondGesture = await tester.createGesture(pointer: 2);

    await firstGesture.down(firstCenter);
    await tester.pump();
    await secondGesture.down(secondCenter);
    await tester.pump();

    await firstGesture.moveTo(center);
    await secondGesture.moveTo(center.translate(1, 0));
    await tester.pump();

    expect(zoomUpdates, isNotEmpty);
    expect(zoomUpdates.last, closeTo(1, 0.001));

    await firstGesture.up();
    await secondGesture.up();
  });

  testWidgets('moving circles to max distance sends maximum zoom level', (
    tester,
  ) async {
    final zoomUpdates = <double>[];

    await _pumpGuide(tester, onZoomChanged: zoomUpdates.add);

    final firstCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.firstCircleKey),
    );
    final secondCenter = tester.getCenter(
      find.byKey(TouchZoomGuideOverlay.secondCircleKey),
    );
    final guideTopLeft = tester.getTopLeft(find.byType(TouchZoomGuideOverlay));

    final firstGesture = await tester.createGesture(pointer: 1);
    final secondGesture = await tester.createGesture(pointer: 2);

    await firstGesture.down(firstCenter);
    await tester.pump();
    await secondGesture.down(secondCenter);
    await tester.pump();

    await firstGesture.moveTo(Offset(guideTopLeft.dx + 25, firstCenter.dy));
    await secondGesture.moveTo(Offset(guideTopLeft.dx + 375, secondCenter.dy));
    await tester.pump();

    expect(zoomUpdates, isNotEmpty);
    expect(zoomUpdates.last, closeTo(5, 0.001));

    await firstGesture.up();
    await secondGesture.up();
  });
}

Future<void> _pumpGuide(
  WidgetTester tester, {
  ValueChanged<double>? onZoomChanged,
  VoidCallback? onInteractionStart,
  VoidCallback? onInteractionEnd,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: TouchZoomGuideOverlay(
              currentZoomLevel: 2,
              minZoomLevel: 1,
              maxZoomLevel: 5,
              onZoomChanged: onZoomChanged ?? (_) {},
              onInteractionStart: onInteractionStart ?? () {},
              onInteractionEnd: onInteractionEnd ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
