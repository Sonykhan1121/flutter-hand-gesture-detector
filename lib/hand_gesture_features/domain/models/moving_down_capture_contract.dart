import 'dart:convert';
import 'dart:typed_data';

/// Raw sample duration used by the phone-side collector.
const movingDownRawCaptureDuration = Duration(seconds: 2);

const movingDownSafeAreaMinimum = 0.05;
const movingDownSafeAreaMaximum = 0.95;

/// Original field order retained at the beginning of every v2 record.
const movingDownLegacyJsonlFields = <String>[
  'schema_version',
  'frame_seq',
  'timestamp_ms',
  'frame_width',
  'frame_height',
  'fps',
  'processing_fps',
  'device_source',
  'media_source',
  'landmark_backend',
  'camera_flipped',
  'palm_count',
  'hand_detected',
  'palm_score',
  'palm_bbox',
  'palm_bbox_source',
  'roi_corners',
  'landmark_confidence',
  'landmark_confidence_source',
  'presence_score',
  'handedness_score',
  'is_right',
  'landmarks_normalized_xyz',
  'landmarks_frame_xyz_px',
  'landmarks_world_xyz_m',
  'landmarks_raw_roi_xyz',
  'user_id',
  'session_id',
  'sample_id',
  'gesture_target',
  'static_gesture_label',
  'static_loss_enabled',
  'temporal_action_label',
  'sample_frame_idx',
  'pc_received_timestamp_ms',
];

/// Additive v2 field order accepted by the Python-compatible phone exporter.
const movingDownJsonlFields = <String>[
  ...movingDownLegacyJsonlFields,
  'input_orientation_degrees',
  'landmark_coordinate_space',
  'display_orientation',
  'camera_facing',
  'landmark_fps',
  'device_recorded_timestamp_ms',
];

bool _isLandmarkArray(Object? value) {
  if (value is! List || value.length != 21) return false;
  return value.every(
    (point) =>
        point is List &&
        point.length == 3 &&
        point.every((coordinate) => coordinate is num),
  );
}

/// True only when one record satisfies the complete additive v2 contract.
bool isCompleteMovingDownJsonlFrame(Map<String, dynamic> frame) {
  if (frame.length != movingDownJsonlFields.length ||
      !movingDownJsonlFields.every(frame.containsKey)) {
    return false;
  }
  final orientation = frame['input_orientation_degrees'];
  final landmarkFps = frame['landmark_fps'];
  if (frame['schema_version'] != 2 ||
      frame['processing_fps'] is! num ||
      frame['hand_detected'] is! bool ||
      orientation is! int ||
      !const <int>{0, 90, 180, 270}.contains(orientation) ||
      frame['landmark_coordinate_space'] != 'display_upright' ||
      frame['display_orientation'] != 'portrait' ||
      !const <String>{
        'front',
        'back',
        'external',
      }.contains(frame['camera_facing']) ||
      landmarkFps is! num ||
      !landmarkFps.toDouble().isFinite ||
      landmarkFps < 0 ||
      frame['device_recorded_timestamp_ms'] is! int ||
      frame['pc_received_timestamp_ms'] !=
          frame['device_recorded_timestamp_ms']) {
    return false;
  }
  if (frame['hand_detected'] == false) {
    return frame['palm_count'] == 0 &&
        frame['palm_bbox'] is List &&
        (frame['palm_bbox'] as List).isEmpty &&
        frame['handedness_score'] == null &&
        frame['is_right'] == null &&
        frame['landmarks_normalized_xyz'] is List &&
        (frame['landmarks_normalized_xyz'] as List).isEmpty &&
        frame['landmarks_frame_xyz_px'] is List &&
        (frame['landmarks_frame_xyz_px'] as List).isEmpty &&
        frame['landmarks_world_xyz_m'] is List &&
        (frame['landmarks_world_xyz_m'] as List).isEmpty;
  }
  return frame['palm_count'] == 1 &&
      _isLandmarkArray(frame['landmarks_normalized_xyz']) &&
      _isLandmarkArray(frame['landmarks_frame_xyz_px']) &&
      _isLandmarkArray(frame['landmarks_world_xyz_m']) &&
      frame['palm_bbox'] is List &&
      (frame['palm_bbox'] as List).length == 4 &&
      frame['handedness_score'] is num &&
      frame['is_right'] is bool;
}

/// Whether all normalized X/Y landmarks remain inside the capture safe area.
bool isMovingDownFrameInsideSafeArea(
  Map<String, dynamic> frame, {
  double minimum = movingDownSafeAreaMinimum,
  double maximum = movingDownSafeAreaMaximum,
}) {
  if (frame['hand_detected'] != true || minimum >= maximum) return false;
  final landmarks = frame['landmarks_normalized_xyz'];
  if (!_isLandmarkArray(landmarks)) return false;
  return (landmarks as List).every((point) {
    final coordinates = point as List;
    final x = (coordinates[0] as num).toDouble();
    final y = (coordinates[1] as num).toDouble();
    return x.isFinite &&
        y.isFinite &&
        x >= minimum &&
        x <= maximum &&
        y >= minimum &&
        y <= maximum;
  });
}

/// Timestamp-derived rate of the valid landmark records that will be saved.
double movingDownLandmarkFps(Iterable<Map<String, dynamic>> frames) {
  final records = frames.toList(growable: false);
  if (records.length < 2) return 0;
  final first = records.first['timestamp_ms'];
  final last = records.last['timestamp_ms'];
  if (first is! num || last is! num) return 0;
  final spanMs = last.toDouble() - first.toDouble();
  if (!spanMs.isFinite || spanMs <= 0) return 0;
  return (records.length - 1) * 1000 / spanMs;
}

/// Largest later increase in the five-landmark palm-center Y coordinate.
double strongestMovingDownTravel(Iterable<Map<String, dynamic>> frames) {
  var highestEarlierPosition = double.infinity;
  var strongestTravel = 0.0;
  for (final frame in frames) {
    final landmarks = frame['landmarks_normalized_xyz'];
    if (landmarks is! List || landmarks.isEmpty) continue;
    const palmIndices = <int>[0, 5, 9, 13, 17];
    var palmY = 0.0;
    var validPalm = true;
    for (final index in palmIndices) {
      if (index >= landmarks.length ||
          landmarks[index] is! List ||
          (landmarks[index] as List).length < 2 ||
          (landmarks[index] as List)[1] is! num) {
        validPalm = false;
        break;
      }
      palmY += ((landmarks[index] as List)[1] as num).toDouble();
    }
    if (!validPalm) continue;
    palmY /= palmIndices.length;
    if (!palmY.isFinite) continue;
    if (highestEarlierPosition.isFinite) {
      final travel = palmY - highestEarlierPosition;
      if (travel > strongestTravel) strongestTravel = travel;
    }
    if (palmY < highestEarlierPosition) highestEarlierPosition = palmY;
  }
  return strongestTravel;
}

bool isValidMovingDownCapture(
  List<Map<String, dynamic>> frames, {
  int minimumFrames = 12,
  double minimumTravel = 0.035,
}) {
  final detectedFrames = frames
      .where((frame) => frame['hand_detected'] == true)
      .toList(growable: false);
  final handednessValues = detectedFrames
      .map((frame) => frame['is_right'])
      .whereType<bool>()
      .toSet();
  return detectedFrames.length >= minimumFrames &&
      frames.every(isCompleteMovingDownJsonlFrame) &&
      detectedFrames.every(isMovingDownFrameInsideSafeArea) &&
      handednessValues.length == 1 &&
      strongestMovingDownTravel(frames) >= minimumTravel;
}

/// Immutable preview of the exact valid-frame JSONL proposed for saving.
class MovingDownJsonlReview {
  const MovingDownJsonlReview({
    required this.records,
    required this.contents,
    required this.sampleId,
    required this.totalCapturedFrames,
    required this.excludedFrames,
    required this.downwardTravel,
    required this.canGenerate,
    required this.failureReason,
    this.frameImages = const <Uint8List?>[],
    this.unsafeFrameIndexes = const <int>[],
    this.detectedIsRight,
    this.handednessConsistent = true,
  });

  final List<Map<String, dynamic>> records;
  final String contents;
  final String sampleId;
  final int totalCapturedFrames;
  final int excludedFrames;
  final double downwardTravel;
  final bool canGenerate;
  final String? failureReason;

  /// Camera thumbnails aligned one-to-one with [records].
  ///
  /// Images are review-only and are never added to the 35-field JSONL.
  final List<Uint8List?> frameImages;
  final List<int> unsafeFrameIndexes;
  final bool? detectedIsRight;
  final bool handednessConsistent;

  int get validHandFrames => records.length;
  int get unsafeFrames => unsafeFrameIndexes.length;
  double get landmarkFps {
    if (records.isEmpty) return 0;
    final fpsValue = records.first['landmark_fps'];
    return fpsValue is num ? fpsValue.toDouble() : 0;
  }

  String get fileName => '$sampleId.jsonl';
}

/// Filters, labels, reindexes, and encodes the exact JSONL shown before save.
MovingDownJsonlReview prepareMovingDownJsonlReview({
  required List<Map<String, dynamic>> capturedFrames,
  required String userId,
  required String sampleId,
  Map<int, Uint8List> capturedFrameImages = const <int, Uint8List>{},
  int minimumFrames = 12,
  double minimumTravel = 0.035,
}) {
  final records = capturedFrames
      .where(
        (frame) =>
            frame['hand_detected'] == true &&
            isCompleteMovingDownJsonlFrame(frame),
      )
      .map(Map<String, dynamic>.from)
      .toList(growable: false);

  for (var index = 0; index < records.length; index++) {
    records[index]
      ..['user_id'] = userId
      ..['sample_id'] = sampleId
      ..['sample_frame_idx'] = index;
  }

  final landmarkFps = movingDownLandmarkFps(records);
  for (final record in records) {
    record['landmark_fps'] = landmarkFps;
  }

  final downwardTravel = strongestMovingDownTravel(records);
  final enoughFrames = records.length >= minimumFrames;
  final enoughMovement = downwardTravel >= minimumTravel;
  final unsafeFrameIndexes = <int>[
    for (var index = 0; index < records.length; index++)
      if (!isMovingDownFrameInsideSafeArea(records[index])) index,
  ];
  final handednessValues = records
      .map((record) => record['is_right'])
      .whereType<bool>()
      .toSet();
  final handednessConsistent =
      records.isNotEmpty && handednessValues.length == 1;
  final detectedIsRight = handednessConsistent ? handednessValues.single : null;
  final canGenerate =
      enoughFrames &&
      enoughMovement &&
      unsafeFrameIndexes.isEmpty &&
      handednessConsistent;
  final failureReason = !enoughFrames
      ? 'At least $minimumFrames valid hand frames are required.'
      : unsafeFrameIndexes.isNotEmpty
      ? 'The complete hand must stay inside the safety box. '
            'Retake the sample without touching a camera edge.'
      : !handednessConsistent
      ? 'Handedness changed during capture. Use one consistent hand.'
      : !enoughMovement
      ? 'Downward palm movement must be at least '
            '${(minimumTravel * 100).toStringAsFixed(1)}%.'
      : null;
  final contents = records.isEmpty
      ? ''
      : '${records.map(jsonEncode).join('\n')}\n';
  final frameImages = records
      .map((record) => capturedFrameImages[record['frame_seq']])
      .toList(growable: false);

  return MovingDownJsonlReview(
    records: List<Map<String, dynamic>>.unmodifiable(records),
    contents: contents,
    sampleId: sampleId,
    totalCapturedFrames: capturedFrames.length,
    excludedFrames: capturedFrames.length - records.length,
    downwardTravel: downwardTravel,
    canGenerate: canGenerate,
    failureReason: failureReason,
    frameImages: List<Uint8List?>.unmodifiable(frameImages),
    unsafeFrameIndexes: List<int>.unmodifiable(unsafeFrameIndexes),
    detectedIsRight: detectedIsRight,
    handednessConsistent: handednessConsistent,
  );
}
