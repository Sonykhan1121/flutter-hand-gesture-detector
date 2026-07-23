import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gesture_detector/temp/face_verification_page.dart';

void main() {
  group('permission lifecycle guard', () {
    test('permission dialog lifecycle events do not cancel initialization', () {
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(
          shouldReleaseFaceVerificationCameraForLifecycle(
            state: state,
            requestingPermission: true,
          ),
          isFalse,
          reason: '$state came from the camera permission dialog',
        );
      }
    });

    test('ordinary background lifecycle still releases the camera', () {
      expect(
        shouldReleaseFaceVerificationCameraForLifecycle(
          state: AppLifecycleState.paused,
          requestingPermission: false,
        ),
        isTrue,
      );
      expect(
        shouldReleaseFaceVerificationCameraForLifecycle(
          state: AppLifecycleState.resumed,
          requestingPermission: false,
        ),
        isFalse,
      );
    });
  });

  group('face oval validation', () {
    const viewport = Size(360, 800);

    test('accepts the preview center and rejects centers outside the oval', () {
      expect(
        isNormalizedFaceCenterInsideVerificationOval(
          normalizedFaceCenter: const Offset(0.5, 0.5),
          viewportSize: viewport,
        ),
        isTrue,
      );
      expect(
        isNormalizedFaceCenterInsideVerificationOval(
          normalizedFaceCenter: const Offset(0.05, 0.5),
          viewportSize: viewport,
        ),
        isFalse,
      );
      expect(
        isNormalizedFaceCenterInsideVerificationOval(
          normalizedFaceCenter: const Offset(0.5, 0.1),
          viewportSize: viewport,
        ),
        isFalse,
      );
    });

    test('rejects invalid geometry instead of counting a hold', () {
      expect(
        isNormalizedFaceCenterInsideVerificationOval(
          normalizedFaceCenter: const Offset(double.nan, 0.5),
          viewportSize: viewport,
        ),
        isFalse,
      );
      expect(
        isNormalizedFaceCenterInsideVerificationOval(
          normalizedFaceCenter: const Offset(0.5, 0.5),
          viewportSize: Size.zero,
        ),
        isFalse,
      );
    });
  });

  group('FaceVerificationHoldController', () {
    test('confirms at exactly two seconds, but not one millisecond before', () {
      final controller = FaceVerificationHoldController();
      final startedAt = DateTime(2026, 7, 23, 10);

      final started = controller.observe(now: startedAt, faceCount: 1);
      final almost = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1999)),
        faceCount: 1,
      );
      final exact = controller.observe(
        now: startedAt.add(const Duration(seconds: 2)),
        faceCount: 1,
      );

      expect(started.isValid, isTrue);
      expect(started.progress, 0);
      expect(almost.confirmed, isFalse);
      expect(almost.progress, closeTo(0.9995, 0.00001));
      expect(exact.confirmed, isTrue);
      expect(exact.progress, 1);
    });

    test('face loss resets the continuous hold', () {
      final controller = FaceVerificationHoldController();
      final startedAt = DateTime(2026, 7, 23, 10);

      controller.observe(now: startedAt, faceCount: 1);
      final lost = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1500)),
        faceCount: 0,
      );
      final reacquired = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1900)),
        faceCount: 1,
      );
      final tooSoon = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 2500)),
        faceCount: 1,
      );

      expect(lost.progress, 0);
      expect(reacquired.progress, 0);
      expect(tooSoon.confirmed, isFalse);
      expect(tooSoon.progress, closeTo(0.3, 0.00001));
    });

    test('multiple faces reset progress and require a fresh hold', () {
      final controller = FaceVerificationHoldController();
      final startedAt = DateTime(2026, 7, 23, 10);

      controller.observe(now: startedAt, faceCount: 1);
      final multiple = controller.observe(
        now: startedAt.add(const Duration(seconds: 1)),
        faceCount: 2,
      );
      final reacquired = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1500)),
        faceCount: 1,
      );
      final tooSoon = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 3400)),
        faceCount: 1,
      );

      expect(multiple.isValid, isFalse);
      expect(multiple.progress, 0);
      expect(reacquired.isValid, isTrue);
      expect(reacquired.progress, 0);
      expect(tooSoon.confirmed, isFalse);
      expect(tooSoon.progress, closeTo(0.95, 0.00001));
    });

    test('a detected face outside the oval resets the two-second hold', () {
      final controller = FaceVerificationHoldController();
      final startedAt = DateTime(2026, 7, 23, 10);

      controller.observe(now: startedAt, faceCount: 1);
      final outside = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1500)),
        faceCount: 1,
        faceCentered: false,
      );
      final centeredAgain = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 1800)),
        faceCount: 1,
        faceCentered: true,
      );
      final tooSoon = controller.observe(
        now: startedAt.add(const Duration(milliseconds: 3000)),
        faceCount: 1,
        faceCentered: true,
      );

      expect(outside.isValid, isFalse);
      expect(outside.progress, 0);
      expect(centeredAgain.progress, 0);
      expect(tooSoon.confirmed, isFalse);
      expect(tooSoon.progress, closeTo(0.6, 0.00001));
    });
  });

  testWidgets('camera-free shell matches the supplied loading screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: FaceVerificationPage(autoStartCamera: false)),
    );

    expect(find.text('Initializing Camera...'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('face oval painter renders the supplied masked overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CustomPaint(
              size: Size(360, 640),
              painter: FaceOvalPainter(ovalWidth: 288, ovalHeight: 374.4),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
