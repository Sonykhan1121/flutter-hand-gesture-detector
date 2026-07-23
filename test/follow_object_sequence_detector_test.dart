import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_object_sequence_phase.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/open_palm_gesture_detection_result.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_object_sequence_detector.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/open_palm_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('FollowObjectSequenceDetector index-point sequence', () {
    test('continuous first palm arms at exactly one second', () {
      final palm = _FakeOpenPalmGestureDetector()..isDetected = true;
      final detector = _detector(palm);
      final start = DateTime(2026);

      detector.update(_baseHand(), start, mirrorHorizontally: false);
      expect(
        detector
            .update(
              _baseHand(),
              start.add(const Duration(milliseconds: 999)),
              mirrorHorizontally: false,
            )
            .isTargetSelectionActive,
        isFalse,
      );
      detector.update(
        _baseHand(),
        start.add(const Duration(seconds: 1)),
        mirrorHorizontally: false,
      );
      expect(detector.debugPhase, FollowObjectSequencePhase.waitingForClosed);
    });

    test('closed fist advances to index-only pointing', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);

      final pointing = detector.update(
        _indexOnlyHand(),
        start.add(const Duration(milliseconds: 1200)),
        mirrorHorizontally: false,
      );

      expect(pointing.isTargetSelectionActive, isTrue);
      expect(pointing.isIndexOnlyPointing, isTrue);
      expect(pointing.indexPip, isNotNull);
      expect(pointing.indexPip!.dx, 135);
      expect(pointing.indexPip!.dy, 155);
      expect(pointing.indexTip, isNotNull);
      expect(pointing.indexTip!.dx, 135);
      expect(pointing.indexTip!.dy, 50);
    });

    test('open palm cannot confirm before target dwell completes', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);

      palm.isDetected = true;
      final earlyPalm = detector.update(
        _baseHand(),
        start.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );

      expect(earlyPalm.isDetected, isFalse);
      expect(earlyPalm.isFinalPalmConfirmation, isFalse);
      expect(detector.debugPhase, FollowObjectSequencePhase.waitingForPoint);
    });

    test('fist or lost point resets only the active dwell phase', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      detector.markPointHoldStarted();
      expect(detector.debugPhase, FollowObjectSequencePhase.holdingPoint);

      detector.update(
        _baseHand(gestureType: GestureType.closedFist),
        start.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );

      expect(detector.debugPhase, FollowObjectSequencePhase.waitingForPoint);
      expect(detector.isTargetSelectionActive, isTrue);
    });

    test('rejects victory, multiple fingers, partial index, and bad hand', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);

      for (final hand in [
        _indexOnlyHand(gestureType: GestureType.victory),
        _indexOnlyHand(openMiddle: true),
        _indexOnlyHand(partialIndex: true),
        _indexOnlyHand(score: 0.2),
      ]) {
        final result = detector.update(
          hand,
          start.add(const Duration(milliseconds: 1300)),
          mirrorHorizontally: false,
        );
        expect(result.isIndexOnlyPointing, isFalse);
        expect(result.indexTip, isNull);
      }
    });

    test('final palm succeeds at exact two-second boundary', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      detector.markPointHoldStarted();
      final deadline = start.add(const Duration(milliseconds: 3200));
      expect(
        detector.markPointHoldComplete(confirmationDeadline: deadline),
        isTrue,
      );

      palm
        ..isDetected = true
        ..confidence = 0.82;
      final confirmed = detector.update(
        _baseHand(),
        deadline,
        mirrorHorizontally: false,
      );

      expect(confirmed.isDetected, isTrue);
      expect(confirmed.isFinalPalmConfirmation, isTrue);
      expect(confirmed.gestureConfidence, closeTo(0.82, 0.001));
      expect(detector.isTargetSelectionActive, isFalse);
    });

    test('final palm later than two seconds cancels', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      detector.markPointHoldStarted();
      final deadline = start.add(const Duration(milliseconds: 3200));
      detector.markPointHoldComplete(confirmationDeadline: deadline);

      palm.isDetected = true;
      final timedOut = detector.update(
        _baseHand(),
        deadline.add(const Duration(milliseconds: 1)),
        mirrorHorizontally: false,
      );

      expect(timedOut.wasCancelled, isTrue);
      expect(timedOut.isDetected, isFalse);
      expect(timedOut.cancellationReason, contains('timed out'));
    });

    test('pre-dwell hand loss gives grace then cancels without release', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      final lostAt = start.add(const Duration(milliseconds: 1200));

      final waiting = detector.handleHandMissing(lostAt);
      expect(waiting.isWaitingForHandReturn, isTrue);
      expect(
        detector
            .handleHandMissing(lostAt.add(const Duration(seconds: 2)))
            .isWaitingForHandReturn,
        isTrue,
      );
      final cancelled = detector.handleHandMissing(
        lostAt.add(const Duration(milliseconds: 2001)),
      );
      expect(cancelled.wasCancelled, isTrue);
      expect(cancelled.releasePoint, isNull);
      expect(cancelled.isDetected, isFalse);
    });

    test('fist returns at exact hand grace boundary and resumes pointing', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      final lostAt = start.add(const Duration(milliseconds: 1200));
      detector.handleHandMissing(lostAt);

      final returned = detector.update(
        _baseHand(gestureType: GestureType.closedFist),
        lostAt.add(const Duration(seconds: 2)),
        mirrorHorizontally: false,
      );

      expect(returned.wasCancelled, isFalse);
      expect(returned.isTargetSelectionActive, isTrue);
      expect(detector.debugPhase, FollowObjectSequencePhase.waitingForPoint);
    });

    test('frozen target deadline is not extended by hand loss', () {
      final palm = _FakeOpenPalmGestureDetector();
      final detector = _detector(palm);
      final start = DateTime(2026);
      _armWithFist(detector, palm, start);
      detector.markPointHoldStarted();
      final deadline = start.add(const Duration(milliseconds: 3200));
      detector.markPointHoldComplete(confirmationDeadline: deadline);
      detector.handleHandMissing(start.add(const Duration(milliseconds: 2500)));

      palm.isDetected = true;
      final confirmed = detector.update(
        _baseHand(),
        deadline,
        mirrorHorizontally: false,
      );
      expect(confirmed.isFinalPalmConfirmation, isTrue);
    });

    test('unreliable hand interrupts the initial palm hold', () {
      final palm = _FakeOpenPalmGestureDetector()..isDetected = true;
      final detector = _detector(palm);
      final start = DateTime(2026);
      detector.update(_baseHand(), start, mirrorHorizontally: false);

      final result = detector.update(
        _baseHand(score: 0.2),
        start.add(const Duration(milliseconds: 500)),
        mirrorHorizontally: false,
      );

      expect(result.isActive, isFalse);
      expect(detector.debugPhase, FollowObjectSequencePhase.idle);
    });
  });
}

FollowObjectSequenceDetector _detector(_FakeOpenPalmGestureDetector palm) {
  return FollowObjectSequenceDetector(openPalmGestureDetector: palm);
}

void _armWithFist(
  FollowObjectSequenceDetector detector,
  _FakeOpenPalmGestureDetector palm,
  DateTime start,
) {
  palm.isDetected = true;
  detector.update(_baseHand(), start, mirrorHorizontally: false);
  detector.update(
    _baseHand(),
    start.add(const Duration(seconds: 1)),
    mirrorHorizontally: false,
  );
  palm.isDetected = false;
  final armed = detector.update(
    _baseHand(gestureType: GestureType.closedFist),
    start.add(const Duration(milliseconds: 1100)),
    mirrorHorizontally: false,
  );
  expect(armed.isTargetSelectionActive, isTrue);
  expect(detector.debugPhase, FollowObjectSequencePhase.waitingForPoint);
}

class _FakeOpenPalmGestureDetector extends OpenPalmGestureDetector {
  bool isDetected = false;
  double confidence = 1;

  @override
  OpenPalmGestureDetectionResult detect({
    required Hand hand,
    required DateTime now,
    required bool mirrorHorizontally,
    bool allowOppositePalmSide = false,
  }) {
    return OpenPalmGestureDetectionResult(
      isDetected: isDetected,
      confidence: isDetected ? confidence : 0,
    );
  }
}

Hand _baseHand({GestureType? gestureType, double score = 1}) {
  return Hand(
    boundingBox: BoundingBox.ltrb(80, 40, 230, 270),
    score: score,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.wrist,
        x: 150,
        y: 255,
        z: 0,
        visibility: 1,
      ),
    ],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
    gesture: gestureType == null
        ? null
        : GestureResult(type: gestureType, confidence: 1),
  );
}

Hand _indexOnlyHand({
  GestureType? gestureType,
  bool openMiddle = false,
  bool partialIndex = false,
  double score = 1,
}) {
  final indexTipY = partialIndex ? 185.0 : 50.0;
  final middle = openMiddle
      ? [
          HandLandmark(
            type: HandLandmarkType.middleFingerMCP,
            x: 160,
            y: 205,
            z: 0,
            visibility: 1,
          ),
          HandLandmark(
            type: HandLandmarkType.middleFingerPIP,
            x: 160,
            y: 155,
            z: 0,
            visibility: 1,
          ),
          HandLandmark(
            type: HandLandmarkType.middleFingerDIP,
            x: 160,
            y: 105,
            z: 0,
            visibility: 1,
          ),
          HandLandmark(
            type: HandLandmarkType.middleFingerTip,
            x: 160,
            y: 55,
            z: 0,
            visibility: 1,
          ),
        ]
      : _foldedChain(
          HandLandmarkType.middleFingerMCP,
          HandLandmarkType.middleFingerPIP,
          HandLandmarkType.middleFingerDIP,
          HandLandmarkType.middleFingerTip,
          160,
        );

  return Hand(
    boundingBox: BoundingBox.ltrb(80, 40, 230, 270),
    score: score,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.wrist,
        x: 150,
        y: 255,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.thumbIP,
        x: 115,
        y: 220,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.thumbTip,
        x: 130,
        y: 220,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerMCP,
        x: 135,
        y: 205,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerPIP,
        x: 135,
        y: 155,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerDIP,
        x: 135,
        y: 105,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerTip,
        x: 135,
        y: indexTipY,
        z: 0,
        visibility: 1,
      ),
      ...middle,
      ..._foldedChain(
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
        180,
      ),
      ..._foldedChain(
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
        200,
      ),
    ],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
    gesture: gestureType == null
        ? null
        : GestureResult(type: gestureType, confidence: 1),
  );
}

List<HandLandmark> _foldedChain(
  HandLandmarkType mcpType,
  HandLandmarkType pipType,
  HandLandmarkType dipType,
  HandLandmarkType tipType,
  double x,
) {
  return [
    HandLandmark(type: mcpType, x: x, y: 205, z: 0, visibility: 1),
    HandLandmark(type: pipType, x: x + 5, y: 175, z: 0, visibility: 1),
    HandLandmark(type: dipType, x: x + 12, y: 188, z: 0, visibility: 1),
    HandLandmark(type: tipType, x: x, y: 198, z: 0, visibility: 1),
  ];
}
