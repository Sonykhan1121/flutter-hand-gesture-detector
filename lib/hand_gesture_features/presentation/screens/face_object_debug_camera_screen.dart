import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as ml_face;
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/enums/follow_target_type.dart';
import '../../domain/enums/object_detection_backend.dart';
import '../../domain/models/app_object_detection.dart';
import '../../domain/models/follow_target.dart';
import '../../domain/services/object_detection_request_controller.dart';
import '../../domain/services/object_detection_service.dart';
import '../../domain/services/object_detection_service_factory.dart';
import '../../domain/utils/camera_frame_box_mapper.dart';
import '../../domain/utils/camera_preview_geometry.dart';
import '../../domain/utils/detection_debug_log_formatter.dart';
import '../painters/follow_target_debug_overlay_painter.dart';
import '../painters/object_detection_debug_painter_factory.dart';
import '../widgets/hand_camera_loading_view.dart';
import '../widgets/round_icon_button.dart';

/// Debug-only camera view that shows raw face/object detector output.
class FaceObjectDebugCameraScreen extends StatefulWidget {
  const FaceObjectDebugCameraScreen({
    super.key,
    this.autoStartCamera = true,
    this.objectDetectionBackend = ObjectDetectionBackend.ultralyticsYolo,
  });

  /// Disabled in widget tests so no real camera/plugin calls are made.
  final bool autoStartCamera;
  final ObjectDetectionBackend objectDetectionBackend;

  @override
  State<FaceObjectDebugCameraScreen> createState() =>
      _FaceObjectDebugCameraScreenState();
}

class _FaceObjectDebugCameraScreenState
    extends State<FaceObjectDebugCameraScreen> {
  CameraController? _controller;
  ml_face.FaceDetector? _faceDetector;
  ObjectDetectionService? _objectDetectionService;
  Future<ObjectDetectionService>? _objectDetectionServiceStartup;

  late final ObjectDetectionRequestController _objectDetectionRequests;

  List<CameraDescription> _cameras = const [];
  List<FollowTarget> _faceTargets = const [];
  List<FollowTarget> _objectTargets = const [];

  bool _isCameraInitialized = false;
  bool _isCameraSetupInProgress = false;
  bool _isStreaming = false;
  bool _isProcessingFrame = false;
  String _statusTitle = 'Initializing camera...';
  String _statusMessage = 'Preparing face and object debug detection.';
  String _actionLabel = 'Try Again';
  DateTime? _lastFrameProcessedAt;
  int _objectDetectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _objectDetectionRequests = ObjectDetectionRequestController(
      minInterval: ObjectDetectionServiceFactory.requestMinIntervalFor(
        backend: widget.objectDetectionBackend,
        isIOS: Platform.isIOS,
      ),
    );
    _faceDetector = ml_face.FaceDetector(
      options: ml_face.FaceDetectorOptions(
        enableTracking: true,
        performanceMode: ml_face.FaceDetectorMode.fast,
      ),
    );

    if (widget.autoStartCamera) {
      unawaited(_requestCameraPermission());
    } else {
      _statusTitle = 'Face/Object Debug';
      _statusMessage = 'Camera startup is disabled for this test run.';
      _actionLabel = 'Start Camera';
    }
  }

  @override
  void dispose() {
    unawaited(_cleanupCamera());
    unawaited(_faceDetector?.close() ?? Future<void>.value());
    _closeObjectDetectionService();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    if (_isCameraSetupInProgress) return;
    _isCameraSetupInProgress = true;

    _setCameraLoading(
      title: 'Initializing camera...',
      message: 'Preparing face and object debug detection.',
    );

    try {
      var status = await Permission.camera.status;
      if (status.isDenied) {
        status = await Permission.camera.request();
      }

      if (status.isGranted) {
        await _loadBackCamera();
        return;
      }

      _setCameraFailure(
        title: status.isPermanentlyDenied
            ? 'Camera access needed'
            : 'Camera permission denied',
        message: status.isPermanentlyDenied
            ? 'Enable camera permission in settings to test detectors.'
            : 'Allow camera access to test face and object detection.',
        actionLabel: status.isPermanentlyDenied ? 'Open Settings' : 'Try Again',
      );
    } catch (e, st) {
      debugPrint('Face/object debug camera permission error: $e\n$st');
      _setCameraFailure(
        title: 'Camera unavailable',
        message: 'Could not prepare the debug camera.',
      );
    } finally {
      _isCameraSetupInProgress = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadBackCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _setCameraFailure(
          title: 'No camera found',
          message: 'This device does not report an available camera.',
        );
        return;
      }

      final camera = _cameras.firstWhere(
        (description) => description.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      await _initializeCamera(camera);
    } catch (e, st) {
      debugPrint('Face/object debug camera load error: $e\n$st');
      _setCameraFailure(
        title: 'Camera unavailable',
        message: 'Could not open the back camera.',
      );
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    await _cleanupCamera();

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    try {
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _clearObjectDetectionCache();
      setState(() {
        _isCameraInitialized = true;
        _statusTitle = 'Face/Object Debug';
        _statusMessage = 'Detecting faces and objects.';
        _actionLabel = 'Try Again';
        _faceTargets = const [];
        _objectTargets = const [];
        _lastFrameProcessedAt = null;
      });

      await _startCameraStream();
    } catch (e, st) {
      debugPrint('Face/object debug camera init error: $e\n$st');
      await controller.dispose();
      if (_controller == controller) _controller = null;
      _setCameraFailure(
        title: 'Camera initialization failed',
        message: 'Check camera access and try again.',
      );
    }
  }

  Future<void> _startCameraStream() async {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !controller.value.isInitialized ||
        _isStreaming) {
      return;
    }

    try {
      await controller.startImageStream(_processCameraImage);
      if (!mounted) return;
      setState(() {
        _isStreaming = true;
      });
    } catch (e, st) {
      debugPrint('Face/object debug stream start error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isStreaming = false;
      });
    }
  }

  Future<void> _stopCameraStream() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isStreaming) {
      return;
    }

    try {
      await controller.stopImageStream();
    } catch (e, st) {
      debugPrint('Face/object debug stream stop error: $e\n$st');
    } finally {
      _isStreaming = false;
    }
  }

  Future<void> _cleanupCamera() async {
    await _stopCameraStream();

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Face/object debug controller dispose error: $e');
      }
    }

    _clearObjectDetectionCache();
    if (!mounted) return;
    setState(() {
      _isCameraInitialized = false;
      _isProcessingFrame = false;
      _faceTargets = const [];
      _objectTargets = const [];
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final controller = _controller;
    final faceDetector = _faceDetector;
    if (_isProcessingFrame ||
        !mounted ||
        controller == null ||
        faceDetector == null ||
        !controller.value.isInitialized ||
        !_isCameraInitialized) {
      return;
    }

    final now = DateTime.now();
    final lastFrameProcessedAt = _lastFrameProcessedAt;
    if (lastFrameProcessedAt != null &&
        now.difference(lastFrameProcessedAt) <
            HandGestureThresholds.minFrameProcessInterval) {
      return;
    }

    _lastFrameProcessedAt = now;
    _isProcessingFrame = true;

    try {
      final frameRotation = _cameraFrameRotation(image);
      final inputRotation = _inputImageRotationFromCameraFrameRotation(
        frameRotation,
      );
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      await _detectFaces(
        image: image,
        imageSize: imageSize,
        inputRotation: inputRotation,
      );
      _submitObjectDetection(image: image, frameRotation: frameRotation);
    } catch (e, st) {
      debugPrint('Face/object debug frame error: $e\n$st');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _detectFaces({
    required CameraImage image,
    required Size imageSize,
    required ml_face.InputImageRotation inputRotation,
  }) async {
    final detector = _faceDetector;
    if (detector == null) return;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    final startedAt = DateTime.now();
    final faces = await detector.processImage(inputImage);
    final elapsed = DateTime.now().difference(startedAt);

    for (final face in faces) {
      debugPrint(
        formatDetectionDebugLog(
          label: 'Face',
          boundingBox: face.boundingBox,
          elapsed: elapsed,
        ),
      );
    }

    final targets = [
      for (final face in faces)
        FollowTarget(
          type: FollowTargetType.face,
          boundingBox: face.boundingBox,
          displayBox: _mlKitRectToDisplayBox(
            face.boundingBox,
            imageSize: imageSize,
            rotation: inputRotation,
          ),
          detectedAt: DateTime.now(),
          trackingId: face.trackingId,
          label: 'Face',
        ),
    ];

    if (!mounted) return;
    setState(() {
      _faceTargets = targets;
    });
  }

  void _submitObjectDetection({
    required CameraImage image,
    required CameraFrameRotation? frameRotation,
  }) {
    _ensureObjectDetectionServiceStarted();

    final objectDetector = _objectDetectionService;
    if (objectDetector == null) return;

    final generation = _objectDetectionGeneration;
    final startedAt = DateTime.now();
    Future<List<AppObjectDetection>>? request;

    try {
      request = _objectDetectionRequests.submit(
        now: startedAt,
        detectorBusy: objectDetector.isBusy,
        detect: () => objectDetector.detect(image, rotation: frameRotation),
      );
    } catch (e, st) {
      debugPrint('Face/object debug object detection ignored: $e\n$st');
    }

    if (request == null) return;

    unawaited(
      request
          .then((objects) {
            if (generation != _objectDetectionGeneration) return;

            final elapsed = DateTime.now().difference(startedAt);
            for (final object in objects) {
              debugPrint(
                formatDetectionDebugLog(
                  label: object.label,
                  boundingBox: object.boundingBox,
                  elapsed: elapsed,
                ),
              );
            }

            final targets = [
              for (final object in objects)
                FollowTarget(
                  type: FollowTargetType.object,
                  boundingBox: object.boundingBox,
                  displayBox: imageRectToDisplayBox(
                    rect: object.boundingBox,
                    imageSize: object.imageSize,
                    mirrorHorizontally: _shouldMirrorPreviewCoordinates,
                  ),
                  detectedAt: DateTime.now(),
                  label: object.label,
                  classIndex: object.classIndex,
                  trackingId: object.trackingId,
                ),
            ];

            if (!mounted) return;
            setState(() {
              _objectTargets = targets;
            });
          })
          .catchError((Object e, StackTrace st) {
            if (generation != _objectDetectionGeneration) return;
            debugPrint('Face/object debug object detection ignored: $e\n$st');
          }),
    );
  }

  void _ensureObjectDetectionServiceStarted() {
    if (_objectDetectionService != null ||
        _objectDetectionServiceStartup != null) {
      return;
    }

    final generation = _objectDetectionGeneration;
    final startup = ObjectDetectionServiceFactory.start(
      backend: widget.objectDetectionBackend,
    );
    _objectDetectionServiceStartup = startup;

    unawaited(
      startup
          .then((objectDetector) {
            if (generation != _objectDetectionGeneration) {
              unawaited(objectDetector.close());
              return;
            }

            _objectDetectionService = objectDetector;
          })
          .catchError((Object e, StackTrace st) {
            if (generation != _objectDetectionGeneration) return;
            debugPrint('Face/object debug detector startup ignored: $e\n$st');
          })
          .whenComplete(() {
            if (identical(_objectDetectionServiceStartup, startup)) {
              _objectDetectionServiceStartup = null;
            }
          }),
    );
  }

  void _clearObjectDetectionCache() {
    _objectDetectionGeneration++;
    _objectDetectionRequests.clear();
    _objectTargets = const [];
  }

  void _closeObjectDetectionService() {
    _clearObjectDetectionCache();

    final objectDetector = _objectDetectionService;
    final startup = _objectDetectionServiceStartup;
    _objectDetectionService = null;
    _objectDetectionServiceStartup = null;

    if (objectDetector != null) {
      unawaited(objectDetector.close());
    }

    if (startup != null) {
      unawaited(
        startup
            .then((startedDetector) {
              if (!identical(startedDetector, objectDetector)) {
                return startedDetector.close();
              }
            })
            .catchError((Object e, StackTrace st) {
              debugPrint('Face/object debug detector close ignored: $e\n$st');
            }),
      );
    }
  }

  ml_face.InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (Platform.isAndroid) {
      final bytes = _androidNv21Bytes(image);
      if (bytes == null) return null;

      return ml_face.InputImage.fromBytes(
        bytes: bytes,
        metadata: ml_face.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _inputImageRotationFromCameraFrameRotation(
            _cameraFrameRotation(image),
          ),
          format: ml_face.InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (Platform.isIOS) {
      final format = ml_face.InputImageFormatValue.fromRawValue(
        image.format.raw,
      );
      if (format != ml_face.InputImageFormat.bgra8888 ||
          image.planes.length != 1) {
        return null;
      }

      final plane = image.planes.first;
      return ml_face.InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: ml_face.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _inputImageRotationFromCameraFrameRotation(
            _cameraFrameRotation(image),
          ),
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  Uint8List? _androidNv21Bytes(CameraImage image) {
    final format = ml_face.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == ml_face.InputImageFormat.nv21 && image.planes.length == 1) {
      return image.planes.first.bytes;
    }

    if (image.planes.length < 3 || image.width.isOdd || image.height.isOdd) {
      return null;
    }

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final ySize = width * height;
    final out = Uint8List(ySize + width * height ~/ 2);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        out[row * width + col] = _planeValue(yPlane, row, col);
      }
    }

    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final outIndex = ySize + row * width + col * 2;
        out[outIndex] = _planeValue(vPlane, row, col);
        out[outIndex + 1] = _planeValue(uPlane, row, col);
      }
    }

    return out;
  }

  int _planeValue(Plane plane, int row, int col) {
    final pixelStride = plane.bytesPerPixel ?? 1;
    final index = row * plane.bytesPerRow + col * pixelStride;
    if (index < 0 || index >= plane.bytes.length) return 128;
    return plane.bytes[index];
  }

  CameraFrameRotation? _cameraFrameRotation(CameraImage image) {
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

  ml_face.InputImageRotation _inputImageRotationFromCameraFrameRotation(
    CameraFrameRotation? rotation,
  ) {
    switch (rotation) {
      case CameraFrameRotation.cw90:
        return ml_face.InputImageRotation.rotation90deg;
      case CameraFrameRotation.cw180:
        return ml_face.InputImageRotation.rotation180deg;
      case CameraFrameRotation.cw270:
        return ml_face.InputImageRotation.rotation270deg;
      case null:
        return ml_face.InputImageRotation.rotation0deg;
    }
  }

  Rect _mlKitRectToDisplayBox(
    Rect rect, {
    required Size imageSize,
    required ml_face.InputImageRotation rotation,
  }) {
    final topLeft = _mlKitPointToDisplayPoint(
      Offset(rect.left, rect.top),
      imageSize: imageSize,
      rotation: rotation,
    );
    final bottomRight = _mlKitPointToDisplayPoint(
      Offset(rect.right, rect.bottom),
      imageSize: imageSize,
      rotation: rotation,
    );

    return Rect.fromLTRB(
      (topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx).clamp(0, 1),
      (topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy).clamp(0, 1),
      (topLeft.dx > bottomRight.dx ? topLeft.dx : bottomRight.dx).clamp(0, 1),
      (topLeft.dy > bottomRight.dy ? topLeft.dy : bottomRight.dy).clamp(0, 1),
    );
  }

  Offset _mlKitPointToDisplayPoint(
    Offset point, {
    required Size imageSize,
    required ml_face.InputImageRotation rotation,
  }) {
    final x = _translateMlKitX(
      point.dx,
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates,
    );
    final y = _translateMlKitY(
      point.dy,
      imageSize: imageSize,
      rotation: rotation,
    );

    return Offset(x.clamp(0, 1), y.clamp(0, 1));
  }

  bool get _shouldMirrorPreviewCoordinates {
    return _controller?.description.lensDirection ==
            CameraLensDirection.front &&
        !Platform.isIOS;
  }

  double _translateMlKitX(
    double x, {
    required Size imageSize,
    required ml_face.InputImageRotation rotation,
    required bool mirrorHorizontally,
  }) {
    switch (rotation) {
      case ml_face.InputImageRotation.rotation90deg:
        return x / (Platform.isIOS ? imageSize.width : imageSize.height);
      case ml_face.InputImageRotation.rotation270deg:
        return 1 - x / (Platform.isIOS ? imageSize.width : imageSize.height);
      case ml_face.InputImageRotation.rotation0deg:
      case ml_face.InputImageRotation.rotation180deg:
        final normalizedX = x / imageSize.width;
        return mirrorHorizontally ? 1 - normalizedX : normalizedX;
    }
  }

  double _translateMlKitY(
    double y, {
    required Size imageSize,
    required ml_face.InputImageRotation rotation,
  }) {
    switch (rotation) {
      case ml_face.InputImageRotation.rotation90deg:
      case ml_face.InputImageRotation.rotation270deg:
        return y / (Platform.isIOS ? imageSize.height : imageSize.width);
      case ml_face.InputImageRotation.rotation0deg:
      case ml_face.InputImageRotation.rotation180deg:
        return y / imageSize.height;
    }
  }

  Size _previewDisplaySize({required bool isLandscape}) {
    final controller = _controller;
    return orientedCameraPreviewSize(
      rawPreviewSize: controller != null && controller.value.isInitialized
          ? controller.value.previewSize
          : null,
      isLandscape: isLandscape,
    );
  }

  double _previewAspectRatio({required bool isLandscape}) {
    final previewDisplaySize = _previewDisplaySize(isLandscape: isLandscape);
    return previewDisplaySize.width / previewDisplaySize.height;
  }

  Widget _buildCameraPreview(CameraController controller) {
    return CameraPreview(controller);
  }

  void _setCameraLoading({required String title, required String message}) {
    if (!mounted) return;
    setState(() {
      _statusTitle = title;
      _statusMessage = message;
      _actionLabel = 'Try Again';
    });
  }

  void _setCameraFailure({
    required String title,
    required String message,
    String actionLabel = 'Try Again',
  }) {
    if (!mounted) return;
    setState(() {
      _isCameraInitialized = false;
      _statusTitle = title;
      _statusMessage = message;
      _actionLabel = actionLabel;
    });
  }

  Future<void> _handleRetry() async {
    if (_actionLabel == 'Open Settings') {
      await openAppSettings();
      return;
    }

    await _requestCameraPermission();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _isCameraInitialized &&
              controller != null &&
              controller.value.isInitialized
          ? Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: _previewAspectRatio(
                          isLandscape: isLandscape,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildCameraPreview(controller),
                            if (_faceTargets.isNotEmpty)
                              CustomPaint(
                                painter: FollowTargetDebugOverlayPainter(
                                  targets: _faceTargets,
                                ),
                              ),
                            if (_objectTargets.isNotEmpty)
                              CustomPaint(
                                painter:
                                    ObjectDetectionDebugPainterFactory.create(
                                      backend: widget.objectDetectionBackend,
                                      targets: _objectTargets,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RoundIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Back',
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Text(
                            'Detector Debug',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 56, height: 56),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : HandCameraLoadingView(
              title: _statusTitle,
              message: _statusMessage,
              actionLabel: _actionLabel,
              isBusy: _isCameraSetupInProgress,
              onRetry: () => unawaited(_handleRetry()),
            ),
    );
  }
}
