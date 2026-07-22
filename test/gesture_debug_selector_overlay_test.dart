import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/gesture_debug_mode.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/gesture_debug_selector_overlay.dart';

void main() {
  const canvasSize = Size(320, 520);
  const directionCenter = Offset(83.75, 98.08333333333333);
  const punchCenter = Offset(236.25, 98.08333333333333);

  Widget selector({
    required Offset? point8,
    required ValueChanged<GestureDebugMode> onSelected,
    required VoidCallback onCancel,
    VoidCallback? onExitDetection,
    GestureDebugMode selectedMode = GestureDebugMode.off,
    bool mirrorHorizontally = false,
    int previewQuarterTurns = 0,
    bool useRecordingPreviewMapping = false,
    Size size = canvasSize,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
            child: GestureDebugSelectorOverlay(
              selectedMode: selectedMode,
              indexTip: point8,
              detectionImageSize: size,
              mirrorHorizontally: mirrorHorizontally,
              previewQuarterTurns: previewQuarterTurns,
              useRecordingPreviewMapping: useRecordingPreviewMapping,
              onModeSelected: onSelected,
              onCancel: onCancel,
              onExitDetection: onExitDetection ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lays out five paired rows and one full-width exit row', (
    tester,
  ) async {
    await tester.pumpWidget(
      selector(point8: null, onSelected: (_) {}, onCancel: () {}),
    );
    await tester.pump();

    final backdrop = tester.widget<ColoredBox>(
      find.byKey(const Key('gestureDebugSelectorBackdrop')),
    );
    expect(backdrop.color, Colors.transparent);

    final tileFinders = <Finder>[
      for (final mode in GestureDebugMode.values)
        if (mode != GestureDebugMode.off)
          find.byKey(Key('gestureDebugTile_${mode.name}')),
      find.byKey(const Key('gestureDebugTile_off')),
      find.byKey(const Key('gestureDebugTile_cancel')),
      find.byKey(const Key('gestureDebugTile_exitDetection')),
    ];
    expect(tileFinders, hasLength(11));
    for (final finder in tileFinders) {
      expect(finder, findsOneWidget);
    }

    final rects = tileFinders.map(tester.getRect).toList(growable: false);
    for (var row = 0; row < 5; row += 1) {
      expect(rects[row * 2].top, closeTo(rects[row * 2 + 1].top, 0.01));
      expect(rects[row * 2].right, lessThan(rects[row * 2 + 1].left));
    }
    expect(rects.last.left, closeTo(rects.first.left, 0.01));
    expect(rects.last.right, closeTo(rects[1].right, 0.01));
    expect(rects.last.top, greaterThan(rects[8].bottom));
  });

  testWidgets('keeps all six rows usable in landscape', (tester) async {
    await tester.pumpWidget(
      selector(
        point8: null,
        size: const Size(520, 292),
        onSelected: (_) {},
        onCancel: () {},
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('gestureDebugTile_direction')), findsOneWidget);
    expect(
      find.byKey(const Key('gestureDebugTile_exitDetection')),
      findsOneWidget,
    );
    final first = tester.getRect(
      find.byKey(const Key('gestureDebugTile_direction')),
    );
    final last = tester.getRect(
      find.byKey(const Key('gestureDebugTile_exitDetection')),
    );
    final grid = tester.getRect(
      find.byKey(const Key('gestureDebugSelectorGrid')),
    );
    expect(first.top, lessThan(last.top));
    expect(last.bottom, lessThanOrEqualTo(grid.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.999 seconds does not select and 2.000 seconds does', (
    tester,
  ) async {
    GestureDebugMode? selected;
    await tester.pumpWidget(
      selector(
        point8: directionCenter,
        onSelected: (mode) => selected = mode,
        onCancel: () {},
      ),
    );
    await tester.pump();

    final cursor = tester.getCenter(
      find.byKey(const Key('gestureDebugPoint8Cursor')),
    );
    final directionTile = tester.getRect(
      find.byKey(const Key('gestureDebugTile_direction')),
    );
    expect(directionTile.contains(cursor), isTrue);

    await tester.pump(const Duration(milliseconds: 1999));
    expect(selected, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(selected, GestureDebugMode.direction);
  });

  testWidgets('leaving a tile resets progress immediately', (tester) async {
    GestureDebugMode? selected;
    void cancel() {}
    void choose(GestureDebugMode mode) => selected = mode;

    await tester.pumpWidget(
      selector(point8: directionCenter, onSelected: choose, onCancel: cancel),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(
      selector(point8: punchCenter, onSelected: choose, onCancel: cancel),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(selected, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(selected, GestureDebugMode.punch);
  });

  testWidgets('losing point 8 resets progress', (tester) async {
    GestureDebugMode? selected;
    void choose(GestureDebugMode mode) => selected = mode;

    await tester.pumpWidget(
      selector(point8: directionCenter, onSelected: choose, onCancel: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(
      selector(point8: null, onSelected: choose, onCancel: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(selected, isNull);

    await tester.pumpWidget(
      selector(point8: directionCenter, onSelected: choose, onCancel: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(selected, GestureDebugMode.direction);
  });

  testWidgets('front-camera mirroring uses the painted point position', (
    tester,
  ) async {
    GestureDebugMode? selected;
    await tester.pumpWidget(
      selector(
        point8: Offset(
          canvasSize.width - directionCenter.dx,
          directionCenter.dy,
        ),
        mirrorHorizontally: true,
        onSelected: (mode) => selected = mode,
        onCancel: () {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(selected, GestureDebugMode.direction);
  });

  testWidgets('Debug Off and Cancel invoke their separate callbacks', (
    tester,
  ) async {
    GestureDebugMode? selected;
    var cancelled = false;
    const debugOffCenter = Offset(83.75, 398.75);
    const cancelCenter = Offset(236.25, 398.75);

    await tester.pumpWidget(
      selector(
        point8: debugOffCenter,
        selectedMode: GestureDebugMode.zoomIn,
        onSelected: (mode) => selected = mode,
        onCancel: () => cancelled = true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(selected, GestureDebugMode.off);
    expect(cancelled, isFalse);

    selected = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      selector(
        point8: cancelCenter,
        selectedMode: GestureDebugMode.zoomIn,
        onSelected: (mode) => selected = mode,
        onCancel: () => cancelled = true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(selected, isNull);
    expect(cancelled, isTrue);
  });

  testWidgets(
    'Exit Detection invokes only its exit callback after two seconds',
    (tester) async {
      GestureDebugMode? selected;
      var cancelled = false;
      var exited = false;
      const exitCenter = Offset(160, 473.91666666666663);

      await tester.pumpWidget(
        selector(
          point8: exitCenter,
          onSelected: (mode) => selected = mode,
          onCancel: () => cancelled = true,
          onExitDetection: () => exited = true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(exited, isFalse);
      await tester.pump(const Duration(milliseconds: 1));

      expect(exited, isTrue);
      expect(selected, isNull);
      expect(cancelled, isFalse);
    },
  );
}
