import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/moving_down_capture_contract.dart';
import 'package:gesture_detector/hand_gesture_features/domain/utils/moving_down_capture_metadata.dart';
import 'package:hand_detection/hand_detection.dart';

Map<String, dynamic> _frame({required double wristY, int index = 0}) {
  List<List<double>> landmarks(double y) => List<List<double>>.generate(
    21,
    (point) => <double>[
      0.5 + point * 0.001,
      const <int>{0, 5, 9, 13, 17}.contains(point) ? y : 0.5,
      0,
    ],
  );

  return <String, dynamic>{
    'schema_version': 2,
    'frame_seq': index,
    'timestamp_ms': index * 55,
    'frame_width': 640,
    'frame_height': 480,
    'fps': 30.0,
    'processing_fps': 18.0,
    'device_source': 'phone_camera',
    'media_source': 'front_camera',
    'landmark_backend': 'hand_detection_flutter_3.3.0',
    'camera_flipped': true,
    'palm_count': 1,
    'hand_detected': true,
    'palm_score': null,
    'palm_bbox': <double>[10, 20, 100, 150],
    'palm_bbox_source': 'derived_from_landmarks',
    'roi_corners': const <Object>[],
    'landmark_confidence': null,
    'landmark_confidence_source': null,
    'presence_score': null,
    'handedness_score': 0.98,
    'is_right': true,
    'landmarks_normalized_xyz': landmarks(wristY),
    'landmarks_frame_xyz_px': landmarks(wristY),
    'landmarks_world_xyz_m': landmarks(wristY),
    'landmarks_raw_roi_xyz': const <Object>[],
    'user_id': 'user1000',
    'session_id': 'session_001',
    'sample_id': 'user1000_direction_down_test',
    'gesture_target': 'MOVE_DOWN',
    'static_gesture_label': 'IGNORE_STATIC',
    'static_loss_enabled': false,
    'temporal_action_label': 'DIRECTION_DOWN',
    'sample_frame_idx': index,
    'pc_received_timestamp_ms': 1000 + index,
    'input_orientation_degrees': 90,
    'landmark_coordinate_space': 'display_upright',
    'display_orientation': 'portrait',
    'camera_facing': 'front',
    'landmark_fps': 0.0,
    'device_recorded_timestamp_ms': 1000 + index,
  };
}

Map<String, dynamic> _undetectedFrame({int index = 0}) {
  return _frame(wristY: 0, index: index)
    ..['palm_count'] = 0
    ..['hand_detected'] = false
    ..['palm_bbox'] = <Object>[]
    ..['palm_bbox_source'] = null
    ..['handedness_score'] = null
    ..['is_right'] = null
    ..['landmarks_normalized_xyz'] = <Object>[]
    ..['landmarks_frame_xyz_px'] = <Object>[]
    ..['landmarks_world_xyz_m'] = <Object>[];
}

void main() {
  group('trainer JSONL contract and validation', () {
    test('raw collector records for exactly two seconds', () {
      expect(movingDownRawCaptureDuration, const Duration(seconds: 2));
    });
    test('accepts additive v2 fields with three 21 by 3 arrays', () {
      final frame = _frame(wristY: 0.4);
      expect(frame.keys.toList(), movingDownJsonlFields);
      expect(movingDownLegacyJsonlFields.length, 35);
      expect(movingDownJsonlFields.length, 41);
      expect(
        frame.keys.take(movingDownLegacyJsonlFields.length),
        movingDownLegacyJsonlFields,
      );
      expect(isCompleteMovingDownJsonlFrame(frame), true);
    });

    test('accepts the Python source shape for a no-hand frame', () {
      final frame = _undetectedFrame();
      expect(frame.keys.toList(), movingDownJsonlFields);
      expect(isCompleteMovingDownJsonlFrame(frame), true);
    });

    test('rejects missing, extra, or incomplete world landmark data', () {
      final missing = _frame(wristY: 0.4)..remove('handedness_score');
      final extra = _frame(wristY: 0.4)..['extra'] = true;
      final incomplete = _frame(wristY: 0.4)
        ..['landmarks_world_xyz_m'] = <Object>[];
      expect(isCompleteMovingDownJsonlFrame(missing), false);
      expect(isCompleteMovingDownJsonlFrame(extra), false);
      expect(isCompleteMovingDownJsonlFrame(incomplete), false);
    });

    test('rejects invalid v2 orientation and mismatched timestamp alias', () {
      final orientation = _frame(wristY: 0.4)
        ..['input_orientation_degrees'] = 45;
      final timestamp = _frame(wristY: 0.4)
        ..['device_recorded_timestamp_ms'] = 2000;
      expect(isCompleteMovingDownJsonlFrame(orientation), false);
      expect(isCompleteMovingDownJsonlFrame(timestamp), false);
    });

    test('accepts a complete downward sequence', () {
      final frames = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(
          wristY: index < 6 ? 0.40 : 0.40 + (index - 5) * 0.012,
          index: index,
        ),
      );
      expect(strongestMovingDownTravel(frames), greaterThan(0.035));
      expect(isValidMovingDownCapture(frames), true);
    });

    test('rejects too few frames and insufficient movement', () {
      final tooFew = List<Map<String, dynamic>>.generate(
        11,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      );
      final tooStill = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.001, index: index),
      );
      expect(isValidMovingDownCapture(tooFew), false);
      expect(isValidMovingDownCapture(tooStill), false);
    });

    test('keeps a valid move when the hand rises slightly at the end', () {
      final frames = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      );
      frames.last = _frame(wristY: 0.43, index: 11);
      expect(isValidMovingDownCapture(frames), true);
    });

    test('keeps raw no-hand records without counting them as hand frames', () {
      final frames = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      )..insert(4, _undetectedFrame(index: 4));
      expect(isValidMovingDownCapture(frames), true);

      final onlyElevenDetected = frames.sublist(0, 12);
      expect(isValidMovingDownCapture(onlyElevenDetected), false);
    });

    test('prepares 27 literal JSONL lines indexed from zero', () {
      final captured = List<Map<String, dynamic>>.generate(
        27,
        (index) => _frame(wristY: 0.40 + index * 0.004, index: 100 + index),
      );
      final review = prepareMovingDownJsonlReview(
        capturedFrames: captured,
        userId: 'user1000',
        sampleId: 'user1000_direction_down_test',
      );
      final lines =
          const LineSplitter()
              .convert(review.contents)
              .where((line) => line.isNotEmpty)
              .toList();

      expect(review.validHandFrames, 27);
      expect(review.excludedFrames, 0);
      expect(review.canGenerate, true);
      expect(review.contents.startsWith('['), false);
      expect(lines.length, 27);
      for (var index = 0; index < lines.length; index++) {
        final record = jsonDecode(lines[index]) as Map<String, dynamic>;
        expect(record['sample_frame_idx'], index);
        expect(record['user_id'], 'user1000');
        expect(record['sample_id'], 'user1000_direction_down_test');
        expect(record['schema_version'], 2);
        expect(record['landmark_fps'], closeTo(18.1818, 0.001));
        expect(
          record['device_recorded_timestamp_ms'],
          record['pc_received_timestamp_ms'],
        );
      }
    });

    test('excludes no-hand and malformed records then reindexes', () {
      final valid = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      );
      final malformed = _frame(wristY: 0.5, index: 98)
        ..['landmarks_world_xyz_m'] = <Object>[];
      final review = prepareMovingDownJsonlReview(
        capturedFrames: <Map<String, dynamic>>[
          _undetectedFrame(index: 97),
          ...valid,
          malformed,
        ],
        userId: 'user1001',
        sampleId: 'user1001_direction_down_test',
        capturedFrameImages: <int, Uint8List>{
          for (final frame in valid)
            frame['frame_seq'] as int: Uint8List.fromList(<int>[
              frame['frame_seq'] as int,
            ]),
          97: Uint8List.fromList(const <int>[97]),
          98: Uint8List.fromList(const <int>[98]),
        },
      );

      expect(review.totalCapturedFrames, 14);
      expect(review.validHandFrames, 12);
      expect(review.excludedFrames, 2);
      expect(
        review.records.map((record) => record['sample_frame_idx']),
        orderedEquals(List<int>.generate(12, (index) => index)),
      );
      expect(review.frameImages.length, 12);
      expect(
        review.frameImages.map((image) => image!.single),
        orderedEquals(List<int>.generate(12, (index) => index)),
      );
    });

    test('derives final landmark FPS from valid timestamps with gaps', () {
      final frames = List<Map<String, dynamic>>.generate(
        4,
        (index) => _frame(wristY: 0.40 + index * 0.02, index: index),
      );
      frames[0]['timestamp_ms'] = 100;
      frames[1]['timestamp_ms'] = 150;
      frames[2]['timestamp_ms'] = 260;
      frames[3]['timestamp_ms'] = 400;
      final review = prepareMovingDownJsonlReview(
        capturedFrames: frames,
        userId: 'user1002',
        sampleId: 'user1002_direction_down_test',
        minimumFrames: 4,
      );

      expect(movingDownLandmarkFps(frames), 10);
      expect(
        review.records.map((record) => record['landmark_fps']),
        everyElement(10),
      );
    });

    test('boundary contact rejects review and identifies unsafe frame', () {
      final frames = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      );
      (frames.last['landmarks_normalized_xyz'] as List)[20][1] = 1.0;
      final review = prepareMovingDownJsonlReview(
        capturedFrames: frames,
        userId: 'user1003',
        sampleId: 'user1003_direction_down_test',
      );

      expect(isMovingDownFrameInsideSafeArea(frames.last), false);
      expect(review.unsafeFrameIndexes, <int>[11]);
      expect(review.canGenerate, false);
      expect(review.failureReason, contains('safety box'));
    });

    test('mixed physical handedness rejects the sample', () {
      final frames = List<Map<String, dynamic>>.generate(
        12,
        (index) => _frame(wristY: 0.40 + index * 0.006, index: index),
      );
      frames.last['is_right'] = false;
      final review = prepareMovingDownJsonlReview(
        capturedFrames: frames,
        userId: 'user1004',
        sampleId: 'user1004_direction_down_test',
      );

      expect(review.handednessConsistent, false);
      expect(review.detectedIsRight, isNull);
      expect(review.canGenerate, false);
      expect(review.failureReason, contains('Handedness changed'));
    });
  });

  group('camera metadata', () {
    test('maps every applied rotation to degrees', () {
      expect(movingDownInputOrientationDegrees(null), 0);
      expect(movingDownInputOrientationDegrees(CameraFrameRotation.cw90), 90);
      expect(movingDownInputOrientationDegrees(CameraFrameRotation.cw180), 180);
      expect(movingDownInputOrientationDegrees(CameraFrameRotation.cw270), 270);
    });

    test('maps all lens directions to portable metadata', () {
      expect(movingDownCameraFacing(CameraLensDirection.front), 'front');
      expect(movingDownCameraFacing(CameraLensDirection.back), 'back');
      expect(movingDownCameraFacing(CameraLensDirection.external), 'external');
    });

    test('upright rotation swaps dimensions before landmark export', () {
      expect(
        detectionSize(
          width: 1280,
          height: 720,
          rotation: CameraFrameRotation.cw90,
          maxDim: 640,
        ),
        const Size(360, 640),
      );
    });

    test('front preview mirroring does not invert physical handedness', () {
      expect(movingDownPhysicalIsRight(Handedness.right), true);
      expect(movingDownPhysicalIsRight(Handedness.left), false);
      expect(movingDownPhysicalIsRight(null), isNull);
    });
  });
}
