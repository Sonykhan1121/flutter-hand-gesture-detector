import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/factories/hand_detector_factory.dart';
import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/models/moving_down_capture_contract.dart';
import '../../domain/services/appearance_signature_extractor.dart';
import '../../domain/services/yolo_camera_frame_encoder.dart';
import '../../domain/utils/camera_preview_geometry.dart';
import '../../domain/utils/moving_down_capture_metadata.dart';
import '../painters/hand_landmark_overlay_painter.dart';
import '../utils/camera_orientation_preferences.dart';
import '../widgets/moving_down_jsonl_review_dialog.dart';
import '../widgets/moving_down_safe_area_overlay.dart';

/// Captures one raw, two-second MOVE_DOWN training sequence.
class MovingDownCaptureScreen extends StatefulWidget {
  const MovingDownCaptureScreen({super.key});

  @override
  State<MovingDownCaptureScreen> createState() =>
      _MovingDownCaptureScreenState();
}

class _MovingDownCaptureScreenState extends State<MovingDownCaptureScreen> {
  static const _downloadsChannel = MethodChannel('smart_stand/downloads');
  static const _minimumCapturedFrames = 12;
  static const _minimumDownwardTravel = 0.035;
  static const _reviewFrameEncoder = YoloCameraFrameEncoder(
    maxDimension: 360,
    jpegQuality: 72,
  );

  CameraController? _controller;
  HandDetector? _detector;
  List<Hand> _hands = const [];
  Size _detectorImageSize = Size.zero;
  Timer? _captureTimer;
  DateTime? _cameraStreamStartedAt;
  final List<Map<String, dynamic>> _frames = [];
  final Map<int, Uint8List> _frameImages = {};

  bool _loading = true;
  bool _processing = false;
  bool _capturing = false;
  bool _saving = false;
  bool _reviewing = false;
  int _cameraFrameSequence = 0;
  double _processingFps = 0;
  DateTime? _lastDetectionCompletedAt;
  String _message = 'Preparing the front camera…';
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      var permission = await Permission.camera.status;
      if (!permission.isGranted) {
        permission = await Permission.camera.request();
      }
      if (!permission.isGranted) {
        _setStatus('Camera permission is required.', loading: false);
        return;
      }

      final deviceCameras = await availableCameras();
      if (deviceCameras.isEmpty) throw StateError('No camera found');
      final selectedCamera = deviceCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => deviceCameras.first,
      );
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      final detector = await HandDetectorFactory.create();
      if (!mounted) {
        await controller.dispose();
        await detector.dispose();
        return;
      }

      _controller = controller;
      _detector = detector;
      _cameraStreamStartedAt = DateTime.now();
      await controller.startImageStream(_processFrame);
      _setStatus(
        'Tap Start to collect two seconds of raw camera landmark records.',
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Moving-down capture setup failed: $error\n$stackTrace');
      _setStatus(
        'Could not start the hand camera. Please try again.',
        loading: false,
      );
    }
  }

  void _setStatus(String message, {bool? loading}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      if (loading != null) {
        _loading = loading;
      }
    });
  }

  CameraFrameRotation? _frameRotation(CameraImage image) {
    final controller = _controller;
    if (controller == null || !(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }
    return rotationForFrame(
      width: image.width,
      height: image.height,
      sensorOrientation: controller.description.sensorOrientation,
      isFrontCamera:
          controller.description.lensDirection == CameraLensDirection.front,
      deviceOrientation: controller.value.deviceOrientation,
    );
  }

  Future<List<Hand>> _detect(CameraImage image) {
    final detector = _detector!;
    final rotation = _frameRotation(image);
    if (Platform.isIOS && image.planes.length == 1) {
      final plane = image.planes.first;
      return detector.detectFromCameraFrame(
        CameraFrame(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          strideCols: plane.bytesPerRow ~/ 4,
          conversion: CameraFrameConversion.bgra2bgr,
          rotation: rotation,
        ),
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );
    }
    return detector.detectFromCameraImage(
      image,
      rotation: rotation,
      isBgra: Platform.isMacOS,
      maxDim: HandGestureThresholds.maxDetectionDimension,
    );
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing || _detector == null || !mounted) return;
    _processing = true;
    try {
      final rotation = _frameRotation(image);
      final detectorImageSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );
      final hands = await _detect(image);
      final frameSequence = _cameraFrameSequence++;
      final detectionCompletedAt = DateTime.now();
      final previousCompletion = _lastDetectionCompletedAt;
      if (previousCompletion != null) {
        final elapsedMicros = detectionCompletedAt
            .difference(previousCompletion)
            .inMicroseconds;
        if (elapsedMicros > 0) {
          final instantaneousFps = 1000000 / elapsedMicros;
          _processingFps = _processingFps == 0
              ? instantaneousFps
              : (_processingFps * 0.8) + (instantaneousFps * 0.2);
        }
      }
      _lastDetectionCompletedAt = detectionCompletedAt;
      if (!mounted) return;
      setState(() {
        _hands = hands;
        _detectorImageSize = detectorImageSize;
      });

      if (_capturing) {
        final hand = hands.isEmpty ? null : hands.first;
        final record = _jsonFrame(
          hand,
          frameSequence,
          fallbackImageSize: detectorImageSize,
          rotation: rotation,
        );
        Uint8List? reviewImage;
        if (hand != null) {
          reviewImage = _encodeReviewImage(image, rotation: rotation);
        }
        setState(() {
          _frames.add(record);
          if (reviewImage != null) {
            _frameImages[frameSequence] = reviewImage;
          }
        });
      }
    } catch (error) {
      debugPrint('Moving-down frame detection failed: $error');
    } finally {
      _processing = false;
    }
  }

  void _startCapture() {
    if (_capturing || _saving || _controller == null) return;
    _captureTimer?.cancel();
    setState(() {
      _frames.clear();
      _frameImages.clear();
      _savedPath = null;
      _capturing = true;
      _message = 'Recording raw hand-landmark frames…';
    });
    _captureTimer = Timer(
      movingDownRawCaptureDuration,
      () => unawaited(_finishCapture()),
    );
  }

  Future<void> _finishCapture() async {
    setState(() {
      _capturing = false;
      _reviewing = true;
      _message = 'Preparing JSONL review…';
    });

    try {
      final now = DateTime.now().toUtc();
      final userId = await _nextUserId();
      final stamp = now
          .toIso8601String()
          .replaceAll(RegExp(r'[-:.]'), '')
          .replaceFirst(RegExp(r'Z$'), '');
      final sampleId = '${userId}_direction_down_${stamp}Z';
      final review = prepareMovingDownJsonlReview(
        capturedFrames: _frames,
        capturedFrameImages: _frameImages,
        userId: userId,
        sampleId: sampleId,
        minimumFrames: _minimumCapturedFrames,
        minimumTravel: _minimumDownwardTravel,
      );
      if (!mounted) return;

      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => MovingDownJsonlReviewDialog(review: review),
      );
      if (!mounted) return;
      if (approved != true || !review.canGenerate) {
        setState(() {
          _reviewing = false;
          _frames.clear();
          _frameImages.clear();
          _message = review.canGenerate
              ? 'Capture discarded. Ready to record again.'
              : 'Capture rejected. Retake the moving-down sample.';
        });
        return;
      }

      setState(() {
        _reviewing = false;
        _saving = true;
        _message = 'Generating the approved JSONL file…';
      });
      final savedPath = await _saveFile(review.fileName, review.contents);
      if (!mounted) return;
      setState(() {
        _frames
          ..clear()
          ..addAll(review.records);
        _frameImages.clear();
        _saving = false;
        _savedPath = savedPath;
        _message = 'Success! Moving-down JSONL generated.';
      });
    } catch (error, stackTrace) {
      debugPrint('Moving-down JSONL save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _reviewing = false;
        _saving = false;
        _message = 'The JSONL review or save could not be completed.';
      });
    }
  }

  Uint8List? _encodeReviewImage(
    CameraImage image, {
    required CameraFrameRotation? rotation,
  }) {
    try {
      return _reviewFrameEncoder
          .encode(
            frame: CameraPixelFrameData.fromCameraImage(
              image,
              isBgra: Platform.isIOS,
            ),
            rotation: rotation,
          )
          ?.jpegBytes;
    } catch (error) {
      debugPrint('Moving-down review image encoding failed: $error');
      return null;
    }
  }

  Map<String, dynamic> _jsonFrame(
    Hand? hand,
    int frameSequence, {
    required Size fallbackImageSize,
    required CameraFrameRotation? rotation,
  }) {
    final streamStartedAt = _cameraStreamStartedAt ?? DateTime.now();
    final now = DateTime.now();
    final width = hand?.imageWidth.toDouble() ?? fallbackImageSize.width;
    final height = hand?.imageHeight.toDouble() ?? fallbackImageSize.height;
    final elapsed = now.difference(streamStartedAt).inMilliseconds;
    final mirrorCoordinates =
        _controller?.description.lensDirection == CameraLensDirection.front;
    final normalized = (hand?.landmarks ?? const <HandLandmark>[])
        .map((point) {
          final normalizedX = point.x / width;
          return <double>[
            mirrorCoordinates ? 1 - normalizedX : normalizedX,
            point.y / height,
            point.z / width,
          ];
        })
        .toList(growable: false);
    final pixels = (hand?.landmarks ?? const <HandLandmark>[])
        .map(
          (point) => <double>[
            mirrorCoordinates ? width - point.x : point.x,
            point.y,
            point.z,
          ],
        )
        .toList(growable: false);
    final world = (hand?.worldLandmarks ?? const <HandLandmark>[])
        .map(
          (point) => <double>[
            mirrorCoordinates ? -point.x : point.x,
            point.y,
            point.z,
          ],
        )
        .toList(growable: false);
    final palmBoundingBox = hand == null
        ? const <double>[]
        : _landmarkDerivedBoundingBox(pixels, width: width, height: height);
    final deviceRecordedTimestamp = now.millisecondsSinceEpoch;
    final cameraDirection =
        _controller?.description.lensDirection ?? CameraLensDirection.front;

    return <String, dynamic>{
      'schema_version': 2,
      'frame_seq': frameSequence,
      'timestamp_ms': elapsed,
      'frame_width': width.round(),
      'frame_height': height.round(),
      'fps': 30.0,
      'processing_fps': _processingFps,
      'device_source': 'phone_camera',
      'media_source': _controller?.description.name ?? 'front_camera',
      'landmark_backend': 'hand_detection_flutter_3.3.0',
      'camera_flipped': mirrorCoordinates,
      'palm_count': hand == null ? 0 : 1,
      'hand_detected': hand != null,
      'palm_score': null,
      'palm_bbox': palmBoundingBox,
      'palm_bbox_source': hand == null ? null : 'derived_from_landmarks',
      'roi_corners': const [],
      'landmark_confidence': null,
      'landmark_confidence_source': null,
      'presence_score': null,
      'handedness_score': hand?.handednessScore,
      'is_right': movingDownPhysicalIsRight(hand?.handedness),
      'landmarks_normalized_xyz': normalized,
      'landmarks_frame_xyz_px': pixels,
      'landmarks_world_xyz_m': world,
      'landmarks_raw_roi_xyz': const [],
      'user_id': '',
      'session_id': 'session_001',
      'sample_id': '',
      'gesture_target': 'MOVE_DOWN',
      'static_gesture_label': 'IGNORE_STATIC',
      'static_loss_enabled': false,
      'temporal_action_label': 'DIRECTION_DOWN',
      'sample_frame_idx': _frames.length,
      'pc_received_timestamp_ms': deviceRecordedTimestamp,
      'input_orientation_degrees': movingDownInputOrientationDegrees(rotation),
      'landmark_coordinate_space': 'display_upright',
      'display_orientation': 'portrait',
      'camera_facing': movingDownCameraFacing(cameraDirection),
      'landmark_fps': 0.0,
      'device_recorded_timestamp_ms': deviceRecordedTimestamp,
    };
  }

  bool _isHandInsideSafeArea(Hand hand) {
    final width = hand.imageWidth.toDouble();
    final height = hand.imageHeight.toDouble();
    if (width <= 0 || height <= 0 || hand.landmarks.length != 21) return false;
    return hand.landmarks.every((point) {
      final x = point.x / width;
      final y = point.y / height;
      return x >= movingDownSafeAreaMinimum &&
          x <= movingDownSafeAreaMaximum &&
          y >= movingDownSafeAreaMinimum &&
          y <= movingDownSafeAreaMaximum;
    });
  }

  String _detectedHandLabel(Hand hand) {
    return switch (hand.handedness) {
      Handedness.right => 'Right',
      Handedness.left => 'Left',
      null => 'Unknown',
    };
  }

  List<double> _landmarkDerivedBoundingBox(
    List<List<double>> landmarks, {
    required double width,
    required double height,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in landmarks) {
      if (point[0] < minX) minX = point[0];
      if (point[0] > maxX) maxX = point[0];
      if (point[1] < minY) minY = point[1];
      if (point[1] > maxY) maxY = point[1];
    }
    final span = (maxX - minX) > (maxY - minY) ? maxX - minX : maxY - minY;
    final padding = span * 0.08;
    return <double>[
      (minX - padding).clamp(0.0, width - 1),
      (minY - padding).clamp(0.0, height - 1),
      (maxX + padding).clamp(0.0, width - 1),
      (maxY + padding).clamp(0.0, height - 1),
    ];
  }

  Future<String> _saveFile(String fileName, String contents) async {
    if (Platform.isAndroid) {
      final path = await _downloadsChannel.invokeMethod<String>(
        'saveTextFile',
        {'fileName': fileName, 'contents': contents},
      );
      if (path == null) throw StateError('Android did not return a save path');
      return path;
    }

    final folder = Directory('${Directory.systemTemp.path}/moving down');
    await folder.create(recursive: true);
    final file = File('${folder.path}/$fileName');
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  Future<String> _nextUserId() async {
    if (!Platform.isAndroid) return 'user1000';
    final userId = await _downloadsChannel.invokeMethod<String>(
      'nextMovingDownUserId',
    );
    if (userId == null || !RegExp(r'^user\d+$').hasMatch(userId)) {
      throw StateError('Android did not return a valid user ID');
    }
    return userId;
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) controller.stopImageStream();
      controller.dispose();
    }
    _detector?.dispose();
    _detector = null;
    unawaited(
      SystemChrome.setPreferredOrientations(supportedCameraDeviceOrientations),
    );
    super.dispose();
  }

  bool _shouldMirrorPreviewCoordinates(CameraController controller) {
    return controller.description.lensDirection == CameraLensDirection.front &&
        !Platform.isIOS;
  }

  Widget _buildMatchedCameraCanvas(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize = interpolatedCameraPreviewSize(
          viewportSize: constraints.biggest,
          rawPreviewSize: controller.value.previewSize,
          progress: 0,
        );
        final hand = _hands.isEmpty ? null : _hands.first;
        final handInside = hand != null && _isHandInsideSafeArea(hand);
        return Center(
          child: SizedBox(
            key: const Key('movingDownCameraPreviewCard'),
            width: cardSize.width,
            height: cardSize.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: Center(
                      child: SizedBox(
                        width: cardSize.width,
                        height: cardSize.height,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                  if (_hands.isNotEmpty && _detectorImageSize != Size.zero)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: HandLandmarkOverlayPainter(
                          hands: _hands,
                          imageSize: _detectorImageSize,
                          mirrorHorizontally: _shouldMirrorPreviewCoordinates(
                            controller,
                          ),
                          previewQuarterTurns: 0,
                        ),
                      ),
                    ),
                  MovingDownSafeAreaOverlay(
                    canvasSize: cardSize,
                    detectedHandLabel: hand == null
                        ? null
                        : _detectedHandLabel(hand),
                    handInside: handInside,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Record Moving Down'),
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Positioned.fill(child: _buildMatchedCameraCanvas(controller))
            else
              const Center(child: CircularProgressIndicator()),
            Positioned(
              left: 20,
              right: 20,
              top: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    if (_capturing) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD92D20),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'RECORDING RAW FRAMES',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_frames.length} landmark frames captured',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _savedPath == null
                            ? Colors.white
                            : Colors.greenAccent,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_savedPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _savedPath!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: FilledButton.icon(
                key: const Key('startMovingDownCaptureButton'),
                onPressed: _loading || _capturing || _reviewing || _saving
                    ? null
                    : _startCapture,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.back_hand_rounded),
                label: Text(
                  _savedPath == null
                      ? 'Start 2-Second Raw Capture'
                      : 'Record Another',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
