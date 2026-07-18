import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_result_stabilizer.dart';

void main() {
  test('native backend holds two empty results then accepts the third', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.nativeMethodChannel,
    );
    final start = DateTime(2026);

    expect(
      stabilizer.shouldReplace(hasDetections: true, completedAt: start),
      isTrue,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 600)),
      ),
      isTrue,
    );
  });

  test('native backend never holds an empty result beyond 800ms', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.nativeMethodChannel,
    );
    final start = DateTime(2026);

    stabilizer.shouldReplace(hasDetections: true, completedAt: start);
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 801)),
      ),
      isTrue,
    );
  });

  test('package backend holds two empty results then accepts the third', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.objectDetectionPackage,
    );
    final start = DateTime(2026);

    expect(
      stabilizer.shouldReplace(hasDetections: true, completedAt: start),
      isTrue,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 600)),
      ),
      isTrue,
    );
  });

  test('OpenCV holds two transient empty results', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.opencvSdk,
    );
    final start = DateTime(2026);

    expect(
      stabilizer.shouldReplace(hasDetections: true, completedAt: start),
      isTrue,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 800)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 1000)),
      ),
      isTrue,
    );
  });

  test('Ultralytics holds transient empty results', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.ultralyticsYolo,
    );
    final start = DateTime(2026);

    expect(
      stabilizer.shouldReplace(hasDetections: true, completedAt: start),
      isTrue,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 350)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 700)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 1050)),
      ),
      isTrue,
    );
  });

  test('Google ML Kit holds two transient empty results', () {
    final stabilizer = ObjectDetectionResultStabilizer.forBackend(
      ObjectDetectionBackend.googleMlKit,
    );
    final start = DateTime(2026);

    expect(
      stabilizer.shouldReplace(hasDetections: true, completedAt: start),
      isTrue,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      stabilizer.shouldReplace(
        hasDetections: false,
        completedAt: start.add(const Duration(milliseconds: 300)),
      ),
      isTrue,
    );
  });
}
