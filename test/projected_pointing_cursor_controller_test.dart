import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_target_selector.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/projected_pointing_cursor_controller.dart';

void main() {
  group('ProjectedPointingCursorController', () {
    test('projects exactly two PIP-to-tip lengths horizontally', () {
      final controller = ProjectedPointingCursorController();

      final result = controller.observe(
        indexPip: const Offset(0.20, 0.50),
        indexTip: const Offset(0.30, 0.50),
      );

      expect(result, isNotNull);
      expect(result!.rawProjectedPoint.dx, closeTo(0.50, 1e-12));
      expect(result.rawProjectedPoint.dy, closeTo(0.50, 1e-12));
      expect(result.projectedPoint, result.rawProjectedPoint);
      expect(result.isInFrame, isTrue);
    });

    test('projects vertical and diagonal pointing directions', () {
      final vertical = ProjectedPointingCursorController().observe(
        indexPip: const Offset(0.50, 0.60),
        indexTip: const Offset(0.50, 0.50),
      );
      final diagonal = ProjectedPointingCursorController().observe(
        indexPip: const Offset(0.20, 0.20),
        indexTip: const Offset(0.30, 0.30),
      );

      expect(vertical!.projectedPoint.dx, closeTo(0.50, 1e-12));
      expect(vertical.projectedPoint.dy, closeTo(0.30, 1e-12));
      expect(diagonal!.projectedPoint.dx, closeTo(0.50, 1e-12));
      expect(diagonal.projectedPoint.dy, closeTo(0.50, 1e-12));
    });

    test('mirrored display inputs project in the mirrored direction', () {
      final back = ProjectedPointingCursorController().observe(
        indexPip: const Offset(0.20, 0.50),
        indexTip: const Offset(0.30, 0.50),
      );
      final front = ProjectedPointingCursorController().observe(
        indexPip: const Offset(0.80, 0.50),
        indexTip: const Offset(0.70, 0.50),
      );

      expect(back!.projectedPoint.dx, closeTo(0.50, 1e-12));
      expect(front!.projectedPoint.dx, closeTo(0.50, 1e-12));
    });

    test('smooths new samples with a 0.35 current-sample weight', () {
      final controller = ProjectedPointingCursorController();
      controller.observe(
        indexPip: const Offset(0.20, 0.50),
        indexTip: const Offset(0.30, 0.50),
      );

      final moved = controller.observe(
        indexPip: const Offset(0.30, 0.50),
        indexTip: const Offset(0.40, 0.50),
      );

      expect(moved!.rawProjectedPoint.dx, closeTo(0.60, 1e-12));
      expect(moved.projectedPoint.dx, closeTo(0.535, 1e-12));
      controller.reset();
      final afterReset = controller.observe(
        indexPip: const Offset(0.30, 0.50),
        indexTip: const Offset(0.40, 0.50),
      );
      expect(afterReset!.projectedPoint.dx, closeTo(0.60, 1e-12));
    });

    test('reports off-screen projection without making it selectable', () {
      final result = ProjectedPointingCursorController().observe(
        indexPip: const Offset(0.75, 0.50),
        indexTip: const Offset(0.85, 0.50),
      );

      expect(result!.projectedPoint.dx, closeTo(1.05, 1e-12));
      expect(result.visiblePoint.dx, 1);
      expect(result.isInFrame, isFalse);
    });

    test(
      'selection uses the projected point rather than the real fingertip',
      () {
        final cursor = ProjectedPointingCursorController().observe(
          indexPip: const Offset(0.20, 0.50),
          indexTip: const Offset(0.30, 0.50),
        )!;
        final fingertipTarget = _target(
          const Rect.fromLTWH(0.25, 0.45, 0.10, 0.10),
          'fingertip',
        );
        final projectedTarget = _target(
          const Rect.fromLTWH(0.45, 0.45, 0.10, 0.10),
          'projected',
        );

        final selection = const FollowTargetSelector().selectAtPoint(
          selectionPoint: cursor.projectedPoint,
          faces: const [],
          objects: [fingertipTarget, projectedTarget],
        );

        expect(
          fingertipTarget.displayBox.contains(cursor.realIndexTip),
          isTrue,
        );
        expect(selection.target, same(projectedTarget));
      },
    );

    test('rejects zero-length and non-finite pointing geometry', () {
      final controller = ProjectedPointingCursorController();

      expect(
        controller.observe(
          indexPip: const Offset(0.50, 0.50),
          indexTip: const Offset(0.50, 0.50),
        ),
        isNull,
      );
      expect(
        controller.observe(
          indexPip: const Offset(double.nan, 0.50),
          indexTip: const Offset(0.60, 0.50),
        ),
        isNull,
      );
    });
  });
}

FollowTarget _target(Rect box, String label) {
  return FollowTarget(
    type: FollowTargetType.object,
    boundingBox: box,
    displayBox: box,
    detectedAt: DateTime(2026),
    label: label,
    classIndex: 1,
  );
}
