import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_object_sequence_phase.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/gesture_debug_mode.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/zoom_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/custom_gesture_detection_result.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/gesture_debug_evaluation.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/gesture_debug_evaluator.dart';

void main() {
  const evaluator = GestureDebugEvaluator();

  for (final mode in const [
    GestureDebugMode.zoomIn,
    GestureDebugMode.zoomOut,
    GestureDebugMode.returnMain,
    GestureDebugMode.recording,
    GestureDebugMode.callMe,
    GestureDebugMode.followObject,
  ]) {
    test('${mode.name} fails closed without a reliable hand', () {
      final evaluation = evaluator.evaluate(
        mode: mode,
        hand: null,
        imageSize: const Size(640, 480),
        mirrorPalmHorizontally: false,
        mirrorScreenHorizontally: false,
        customResult: CustomGestureDetectionResult.empty,
        returnMainHoldProgress: 0,
        pendingZoomDirection: ZoomDirection.none,
        zoomHoldProgress: 0,
        zoomPalmStable: false,
        zoomStableFingers: false,
        isRecording: false,
        isRecordingPaused: false,
        recordingActionLabel: '',
        recordingHoldProgress: 0,
        callMeHoldProgress: 0,
        followPhase: FollowObjectSequencePhase.idle,
        followOpenPalm: null,
        followClosedFist: null,
        followRelaxedReleaseFrames: 0,
        followFirstOpenHoldProgress: 0,
        followHandReturnProgress: 0,
      );

      expect(evaluation.matches, isFalse);
      expect(evaluation.requirements.single.text, 'Reliable hand required');
      expect(
        () => evaluation.requirements.add(
          const GestureDebugRequirement(matches: true, text: 'mutation'),
        ),
        throwsUnsupportedError,
      );
    });
  }
}
