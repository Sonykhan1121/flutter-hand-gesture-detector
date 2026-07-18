import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/moving_down_capture_contract.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/moving_down_jsonl_review_dialog.dart';

MovingDownJsonlReview _review({required bool canGenerate}) {
  const contents =
      '{"sample_frame_idx":0,"hand_detected":true}\n'
      '{"sample_frame_idx":1,"hand_detected":true}\n';
  return MovingDownJsonlReview(
    records: const <Map<String, dynamic>>[
      <String, dynamic>{'sample_frame_idx': 0},
      <String, dynamic>{'sample_frame_idx': 1},
    ],
    contents: contents,
    sampleId: 'user1000_direction_down_test',
    totalCapturedFrames: 3,
    excludedFrames: 1,
    downwardTravel: canGenerate ? 0.08 : 0.01,
    canGenerate: canGenerate,
    failureReason: canGenerate ? null : 'Downward movement is too small.',
    detectedIsRight: true,
    frameImages: <Uint8List?>[
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      null,
    ],
  );
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required MovingDownJsonlReview review,
  required ValueChanged<bool?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('openReview'),
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (_) => MovingDownJsonlReviewDialog(review: review),
                );
                onResult(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openReview')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows literal JSONL with dynamic counts and two-way scrolling', (
    tester,
  ) async {
    bool? result;
    final review = _review(canGenerate: true);
    await _pumpLauncher(
      tester,
      review: review,
      onResult: (value) => result = value,
    );

    expect(
      find.byKey(const Key('movingDownJsonlReviewDialog')),
      findsOneWidget,
    );
    expect(find.text('Valid hand frames: 2'), findsOneWidget);
    expect(find.text('Excluded frames: 1'), findsOneWidget);
    expect(find.text('Unsafe frames: 0'), findsOneWidget);
    expect(find.text('Detected hand: Right'), findsOneWidget);
    final preview = tester.widget<SelectableText>(
      find.byKey(const Key('jsonlPreviewText')),
    );
    expect(preview.data, review.contents);
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    expect(find.byKey(const Key('selectedFrameImageGallery')), findsOneWidget);
    expect(find.byKey(const Key('selectedFrameImage0')), findsOneWidget);
    expect(find.text('Frame 0'), findsOneWidget);
    expect(find.text('Frame 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('generateJsonlButton')));
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets('invalid review disables generation and Retake discards', (
    tester,
  ) async {
    bool? result;
    final review = _review(canGenerate: false);
    await _pumpLauncher(
      tester,
      review: review,
      onResult: (value) => result = value,
    );

    final generate = tester.widget<FilledButton>(
      find.byKey(const Key('generateJsonlButton')),
    );
    expect(generate.onPressed, isNull);
    expect(find.byKey(const Key('reviewFailureReason')), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancelJsonlReviewButton')));
    await tester.pumpAndSettle();
    expect(result, false);
  });

  testWidgets('unsafe selected image is marked and generation stays disabled', (
    tester,
  ) async {
    bool? result;
    final base = _review(canGenerate: false);
    final review = MovingDownJsonlReview(
      records: base.records,
      contents: base.contents,
      sampleId: base.sampleId,
      totalCapturedFrames: base.totalCapturedFrames,
      excludedFrames: base.excludedFrames,
      downwardTravel: 0.08,
      canGenerate: false,
      failureReason: 'The complete hand must stay inside the safety box.',
      frameImages: base.frameImages,
      unsafeFrameIndexes: const <int>[1],
      detectedIsRight: true,
    );
    await _pumpLauncher(
      tester,
      review: review,
      onResult: (value) => result = value,
    );

    expect(find.text('Unsafe frames: 1'), findsOneWidget);
    expect(find.byKey(const Key('unsafeFrameImage1')), findsOneWidget);
    expect(find.text('Frame 1 · UNSAFE'), findsOneWidget);
    final generate = tester.widget<FilledButton>(
      find.byKey(const Key('generateJsonlButton')),
    );
    expect(generate.onPressed, isNull);

    await tester.tap(find.byKey(const Key('cancelJsonlReviewButton')));
    await tester.pumpAndSettle();
    expect(result, false);
  });
}
