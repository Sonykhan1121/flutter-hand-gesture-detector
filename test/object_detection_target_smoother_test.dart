import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_target_smoother.dart';

void main() {
  test('reduces small package box jitter without changing raw metadata', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.objectDetectionPackage,
    );
    final start = DateTime(2026);
    final first = _target(
      displayBox: const Rect.fromLTRB(0.20, 0.20, 0.50, 0.60),
      sourceFrameId: 10,
    );
    final second = _target(
      displayBox: const Rect.fromLTRB(0.22, 0.18, 0.52, 0.58),
      boundingBox: const Rect.fromLTRB(22, 18, 52, 58),
      sourceFrameId: 11,
    );

    smoother.update([first], completedAt: start);
    final result = smoother.update([
      second,
    ], completedAt: start.add(const Duration(milliseconds: 350))).single;

    expect(result.displayBox.left, closeTo(0.209, 0.000001));
    expect(result.displayBox.top, closeTo(0.191, 0.000001));
    expect(result.boundingBox, second.boundingBox);
    expect(result.sourceFrameId, 11);
  });

  test('uses faster response for deliberate motion', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.objectDetectionPackage,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.10, 0.20, 0.30, 0.50)),
    ], completedAt: start);

    final result = smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.20, 0.20, 0.40, 0.50)),
    ], completedAt: start.add(const Duration(milliseconds: 350))).single;

    expect(result.displayBox.left, closeTo(0.178, 0.000001));
  });

  test('does not blend different classes or distant same-class objects', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.objectDetectionPackage,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.05, 0.10, 0.20, 0.30)),
    ], completedAt: start);

    final differentClass = _target(
      displayBox: const Rect.fromLTRB(0.06, 0.10, 0.21, 0.30),
      label: 'chair',
      classIndex: 4,
    );
    final result = smoother.update([
      differentClass,
    ], completedAt: start.add(const Duration(milliseconds: 350)));

    expect(result.first.displayBox, differentClass.displayBox);
  });

  test('holds one missing track briefly but clears a fully empty update', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.objectDetectionPackage,
    );
    final start = DateTime(2026);
    final bottle = _target(
      displayBox: const Rect.fromLTRB(0.10, 0.10, 0.30, 0.40),
    );
    final chair = _target(
      displayBox: const Rect.fromLTRB(0.60, 0.10, 0.80, 0.40),
      label: 'chair',
      classIndex: 4,
    );
    smoother.update([bottle, chair], completedAt: start);

    final partial = smoother.update([
      bottle,
    ], completedAt: start.add(const Duration(milliseconds: 300)));
    expect(
      partial.map((target) => target.label),
      containsAll(['bottle', 'chair']),
    );

    expect(
      smoother.update(
        const [],
        completedAt: start.add(const Duration(milliseconds: 400)),
      ),
      isEmpty,
    );
  });

  test('smooths OpenCV boxes by class and preserves raw metadata', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.opencvSdk,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.20, 0.20, 0.50, 0.60)),
    ], completedAt: start);
    final rawBox = const Rect.fromLTRB(22, 18, 52, 58);

    final result = smoother.update([
      _target(
        displayBox: const Rect.fromLTRB(0.22, 0.18, 0.52, 0.58),
        boundingBox: rawBox,
        sourceFrameId: 11,
      ),
    ], completedAt: start.add(const Duration(milliseconds: 400))).single;

    expect(result.displayBox.left, closeTo(0.2084, 0.000001));
    expect(result.displayBox.top, closeTo(0.1916, 0.000001));
    expect(result.boundingBox, rawBox);
    expect(result.sourceFrameId, 11);
  });

  test('smooths ML Kit boxes by tracking ID and preserves raw metadata', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.googleMlKit,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(
        displayBox: const Rect.fromLTRB(0.20, 0.20, 0.50, 0.60),
        trackingId: 7,
      ),
    ], completedAt: start);
    final rawBox = const Rect.fromLTRB(22, 18, 52, 58);

    final result = smoother.update([
      _target(
        displayBox: const Rect.fromLTRB(0.22, 0.18, 0.52, 0.58),
        boundingBox: rawBox,
        trackingId: 7,
        sourceFrameId: 11,
      ),
    ], completedAt: start.add(const Duration(milliseconds: 100))).single;

    expect(result.displayBox.left, closeTo(0.2072, 0.000001));
    expect(result.displayBox.top, closeTo(0.1928, 0.000001));
    expect(result.boundingBox, rawBox);
    expect(result.sourceFrameId, 11);
  });

  test('smooths native boxes by class and preserves raw metadata', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.nativeMethodChannel,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.20, 0.20, 0.50, 0.60)),
    ], completedAt: start);
    final rawBox = const Rect.fromLTRB(22, 18, 52, 58);

    final result = smoother.update([
      _target(
        displayBox: const Rect.fromLTRB(0.22, 0.18, 0.52, 0.58),
        boundingBox: rawBox,
        sourceFrameId: 11,
      ),
    ], completedAt: start.add(const Duration(milliseconds: 250))).single;

    expect(result.displayBox.left, closeTo(0.2084, 0.000001));
    expect(result.displayBox.top, closeTo(0.1916, 0.000001));
    expect(result.boundingBox, rawBox);
    expect(result.sourceFrameId, 11);
  });

  test('smooths Ultralytics display boxes and preserves raw boxes', () {
    final smoother = ObjectDetectionTargetSmoother.forBackend(
      ObjectDetectionBackend.ultralyticsYolo,
    );
    final start = DateTime(2026);
    smoother.update([
      _target(displayBox: const Rect.fromLTRB(0.20, 0.20, 0.50, 0.60)),
    ], completedAt: start);
    final rawBox = const Rect.fromLTRB(22, 18, 52, 58);

    final result = smoother.update([
      _target(
        displayBox: const Rect.fromLTRB(0.22, 0.18, 0.52, 0.58),
        boundingBox: rawBox,
        sourceFrameId: 11,
      ),
    ], completedAt: start.add(const Duration(milliseconds: 350))).single;

    expect(result.displayBox.left, closeTo(0.2084, 0.000001));
    expect(result.displayBox.top, closeTo(0.1916, 0.000001));
    expect(result.boundingBox, rawBox);
    expect(result.sourceFrameId, 11);
  });
}

FollowTarget _target({
  required Rect displayBox,
  Rect boundingBox = const Rect.fromLTRB(10, 20, 30, 40),
  String label = 'bottle',
  int classIndex = 1,
  int? sourceFrameId,
  int? trackingId,
}) {
  return FollowTarget(
    type: FollowTargetType.object,
    boundingBox: boundingBox,
    displayBox: displayBox,
    detectedAt: DateTime(2026),
    label: label,
    classIndex: classIndex,
    sourceFrameId: sourceFrameId,
    trackingId: trackingId,
  );
}
