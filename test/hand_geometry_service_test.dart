import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/hand_geometry_service.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('HandGeometryService isReliableHand', () {
    const geometry = HandGeometryService();

    test('accepts hands with landmarks and finite minimum confidence', () {
      expect(geometry.isReliableHand(_handWithLandmark()), isTrue);
    });

    test('rejects hands without landmarks', () {
      expect(geometry.isReliableHand(_handWithoutLandmarks()), isFalse);
    });

    test('rejects hands without any usable visible landmark', () {
      expect(
        geometry.isReliableHand(_handWithLandmark(x: double.nan)),
        isFalse,
      );
      expect(
        geometry.isReliableHand(_handWithLandmark(visibility: 0.2)),
        isFalse,
      );
    });

    test('rejects low and non-finite confidence scores', () {
      expect(geometry.isReliableHand(_handWithLandmark(score: 0.2)), isFalse);
      expect(
        geometry.isReliableHand(_handWithLandmark(score: double.infinity)),
        isFalse,
      );
      expect(
        geometry.isReliableHand(_handWithLandmark(score: double.nan)),
        isFalse,
      );
    });

    test('rejects non-finite or empty bounding boxes', () {
      expect(
        geometry.isReliableHand(
          _handWithLandmark(
            boundingBox: BoundingBox.ltrb(0, 0, double.nan, 100),
          ),
        ),
        isFalse,
      );
      expect(
        geometry.isReliableHand(
          _handWithLandmark(boundingBox: BoundingBox.ltrb(10, 20, 10, 20)),
        ),
        isFalse,
      );
    });

    test('filters only reliable hands', () {
      final reliable = _handWithLandmark(score: 0.9);

      final filtered = geometry.reliableHands([
        _handWithLandmark(score: 0.2),
        _handWithoutLandmarks(),
        _handWithLandmark(score: double.infinity),
        reliable,
      ]);

      expect(filtered, hasLength(1));
      expect(filtered.single, same(reliable));
    });

    test('selects the highest-confidence reliable hand without focus', () {
      final low = _handWithLandmark(score: 0.6);
      final high = _handWithLandmark(score: 0.9);

      expect(
        geometry.bestReliableHand([
          _handWithLandmark(score: double.infinity),
          low,
          high,
        ]),
        same(high),
      );
    });

    test('selects the nearest reliable hand to the focused box', () {
      final near = _handWithLandmark(
        boundingBox: BoundingBox.ltrb(90, 90, 130, 130),
        score: 0.6,
      );
      final far = _handWithLandmark(
        boundingBox: BoundingBox.ltrb(260, 260, 320, 320),
        score: 0.95,
      );

      expect(
        geometry.bestReliableHand([
          _handWithLandmark(
            boundingBox: BoundingBox.ltrb(100, 100, 140, 140),
            score: double.infinity,
          ),
          far,
          near,
        ], focusedHandBox: const Rect.fromLTRB(100, 100, 140, 140)),
        same(near),
      );
    });

    test('returns null when no reliable hand is available', () {
      expect(
        geometry.bestReliableHand([
          _handWithoutLandmarks(),
          _handWithLandmark(score: 0.2),
          _handWithLandmark(score: double.nan),
        ]),
        isNull,
      );
    });
  });

  group('HandGeometryService isReliablePackageGesture', () {
    const geometry = HandGeometryService();

    test('accepts finite package gestures at the confidence threshold', () {
      expect(
        geometry.isReliablePackageGesture(
          const GestureResult(type: GestureType.victory, confidence: 0.5),
          type: GestureType.victory,
        ),
        isTrue,
      );
    });

    test(
      'rejects null, wrong type, low confidence, and non-finite confidence',
      () {
        expect(geometry.isReliablePackageGesture(null), isFalse);
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(type: GestureType.thumbUp, confidence: 1),
            type: GestureType.victory,
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(type: GestureType.victory, confidence: 0.49),
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(
              type: GestureType.victory,
              confidence: double.infinity,
            ),
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(
              type: GestureType.victory,
              confidence: double.nan,
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group('HandGeometryService visibleLandmark', () {
    const geometry = HandGeometryService();

    test('returns visible landmarks with finite coordinates', () {
      final hand = _handWithLandmark();

      expect(
        geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
        isNotNull,
      );
    });

    test('rejects non-finite coordinates and visibility', () {
      for (final hand in [
        _handWithLandmark(x: double.nan),
        _handWithLandmark(y: double.infinity),
        _handWithLandmark(z: double.negativeInfinity),
        _handWithLandmark(visibility: double.nan),
      ]) {
        expect(
          geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
          isNull,
        );
      }
    });

    test('rejects low-visibility landmarks', () {
      final hand = _handWithLandmark(visibility: 0.2);

      expect(
        geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
        isNull,
      );
    });
  });

  group('HandGeometryService handSizeFromBoundingBox', () {
    const geometry = HandGeometryService();

    test('returns the larger finite bounding-box side', () {
      expect(
        geometry.handSizeFromBoundingBox(BoundingBox.ltrb(10, 20, 110, 260)),
        240,
      );
    });

    test('returns zero for non-finite bounding boxes', () {
      expect(
        geometry.handSizeFromBoundingBox(
          BoundingBox.ltrb(0, 0, double.nan, 100),
        ),
        0,
      );
      expect(
        geometry.handSizeFromBoundingBox(
          BoundingBox.ltrb(0, 0, 100, double.infinity),
        ),
        0,
      );
    });
  });

  group('HandGeometryService downwardExtendedFingerChainCount', () {
    const geometry = HandGeometryService();

    test('returns zero for non-finite image sizes', () {
      expect(
        geometry.downwardExtendedFingerChainCount(
          hand: _handWithDownwardFingerChains(),
          imageSize: const Size(double.nan, 400),
          mirrorHorizontally: false,
        ),
        0,
      );

      expect(
        geometry.downwardExtendedFingerChainCount(
          hand: _handWithDownwardFingerChains(),
          imageSize: const Size(400, double.infinity),
          mirrorHorizontally: false,
        ),
        0,
      );
    });
  });
}

Hand _handWithLandmark({
  double x = 120,
  double y = 180,
  double z = 0,
  double visibility = 1,
  double score = 1,
  BoundingBox? boundingBox,
}) {
  return Hand(
    boundingBox: boundingBox ?? BoundingBox.ltrb(0, 0, 400, 400),
    score: score,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.indexFingerTip,
        x: x,
        y: y,
        z: z,
        visibility: visibility,
      ),
    ],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}

Hand _handWithoutLandmarks({double score = 1}) {
  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, 400, 400),
    score: score,
    landmarks: const [],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}

Hand _handWithDownwardFingerChains() {
  final landmarks = <HandLandmark>[];
  final chains = [
    [
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.indexFingerPIP,
      HandLandmarkType.indexFingerDIP,
      HandLandmarkType.indexFingerTip,
    ],
    [
      HandLandmarkType.middleFingerMCP,
      HandLandmarkType.middleFingerPIP,
      HandLandmarkType.middleFingerDIP,
      HandLandmarkType.middleFingerTip,
    ],
    [
      HandLandmarkType.ringFingerMCP,
      HandLandmarkType.ringFingerPIP,
      HandLandmarkType.ringFingerDIP,
      HandLandmarkType.ringFingerTip,
    ],
  ];
  final bases = [
    const Offset(170, 120),
    const Offset(200, 120),
    const Offset(230, 120),
  ];

  for (var fingerIndex = 0; fingerIndex < chains.length; fingerIndex++) {
    final base = bases[fingerIndex];
    for (
      var pointIndex = 0;
      pointIndex < chains[fingerIndex].length;
      pointIndex++
    ) {
      landmarks.add(
        HandLandmark(
          type: chains[fingerIndex][pointIndex],
          x: base.dx,
          y: base.dy + pointIndex * 35,
          z: 0,
          visibility: 1,
        ),
      );
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, 400, 400),
    score: 1,
    landmarks: landmarks,
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}
