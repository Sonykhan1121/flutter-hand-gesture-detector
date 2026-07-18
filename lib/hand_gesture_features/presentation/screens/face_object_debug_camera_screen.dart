import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../domain/services/object_detection_result_stabilizer.dart';
import '../../domain/services/object_detection_service.dart';
import '../../domain/services/object_detection_service_factory.dart';
import '../../domain/services/object_detection_target_smoother.dart';
import '../../domain/utils/camera_frame_box_mapper.dart';
import '../../domain/utils/camera_preview_geometry.dart';
import '../../domain/utils/detection_debug_log_formatter.dart';
import '../painters/object_detection_debug_painter.dart';
import '../painters/object_detection_debug_painter_factory.dart';
import '../utils/ml_kit_preview_mapper.dart';
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
  String? _objectDetectionServiceStartupError;
  DateTime? _objectDetectionServiceStartupFailedAt;

  late final ObjectDetectionRequestController _objectDetectionRequests;
  late final ObjectDetectionResultStabilizer _objectDetectionResultStabilizer;
  late final ObjectDetectionTargetSmoother _objectDetectionTargetSmoother;

  List<CameraDescription> _availableCameras = const [];
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
    _objectDetectionResultStabilizer =
        ObjectDetectionResultStabilizer.forBackend(
          widget.objectDetectionBackend,
        );
    _objectDetectionTargetSmoother = ObjectDetectionTargetSmoother.forBackend(
      widget.objectDetectionBackend,
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
    } catch (error, stackTrace) {
      debugPrint(
        'Face/object debug camera permission error: $error\n$stackTrace',
      );
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
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _setCameraFailure(
          title: 'No camera found',
          message: 'This device does not report an available camera.',
        );
        return;
      }

      final camera = _availableCameras.firstWhere(
        (description) => description.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      await _initializeCamera(camera);
    } catch (error, stackTrace) {
      debugPrint('Face/object debug camera load error: $error\n$stackTrace');
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
    } catch (error, stackTrace) {
      debugPrint('Face/object debug camera init error: $error\n$stackTrace');
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
    } catch (error, stackTrace) {
      debugPrint('Face/object debug stream start error: $error\n$stackTrace');
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
    } catch (error, stackTrace) {
      debugPrint('Face/object debug stream stop error: $error\n$stackTrace');
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
      } catch (error) {
        debugPrint('Face/object debug controller dispose error: $error');
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
      final inputRotation = mlKitInputRotation(frameRotation);
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      await _detectFaces(
        image: image,
        imageSize: imageSize,
        inputRotation: inputRotation,
      );
      _submitObjectDetection(image: image, frameRotation: frameRotation);
    } catch (error, stackTrace) {
      debugPrint('Face/object debug frame error: $error\n$stackTrace');
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

    final inputImage = mlKitFaceInputImage(
      image,
      rotation: _cameraFrameRotation(image),
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    );
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
          displayBox: mlKitDisplayRect(
            face.boundingBox,
            imageSize: imageSize,
            rotation: inputRotation,
            isIOS: Platform.isIOS,
            mirrorHorizontally: _shouldMirrorPreviewCoordinates,
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
        detect: () => objectDetector.detect(
          image,
          rotation: frameRotation,
          lensDirection: _controller?.description.lensDirection,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Face/object debug object detection ignored: $error\n$stackTrace',
      );
    }

    if (request == null) return;

    unawaited(
      request
          .then((objects) {
            if (generation != _objectDetectionGeneration) return;

            final elapsed = DateTime.now().difference(startedAt);
            final completedAt = DateTime.now();
            if (!_objectDetectionResultStabilizer.shouldReplace(
              hasDetections: objects.isNotEmpty,
              completedAt: completedAt,
            )) {
              return;
            }
            for (final object in objects) {
              debugPrint(
                formatDetectionDebugLog(
                  label: object.label,
                  boundingBox: object.boundingBox,
                  elapsed: elapsed,
                ),
              );
            }

            final rawTargets = [
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
            late final List<FollowTarget> targets;
            if (objects.isEmpty) {
              _objectDetectionTargetSmoother.clear();
              targets = const [];
            } else {
              targets = _objectDetectionTargetSmoother.update(
                rawTargets,
                completedAt: completedAt,
              );
            }

            if (!mounted) return;
            setState(() {
              _objectTargets = targets;
            });
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (generation != _objectDetectionGeneration) return;
            debugPrint(
              'Face/object debug object detection ignored: '
              '$error\n$stackTrace',
            );
          }),
    );
  }

  void _ensureObjectDetectionServiceStarted() {
    final failedAt = _objectDetectionServiceStartupFailedAt;
    if (_objectDetectionServiceStartupError != null && failedAt != null) {
      final retryDelay = switch (widget.objectDetectionBackend) {
        ObjectDetectionBackend.ultralyticsYolo =>
          HandGestureThresholds.ultralyticsYoloStartupRetryDelay,
        ObjectDetectionBackend.nativeMethodChannel =>
          HandGestureThresholds.nativeMethodChannelStartupRetryDelay,
        ObjectDetectionBackend.opencvSdk =>
          HandGestureThresholds.opencvSdkStartupRetryDelay,
        _ => Duration.zero,
      };
      if (DateTime.now().difference(failedAt) < retryDelay) return;
      _objectDetectionServiceStartupError = null;
      _objectDetectionServiceStartupFailedAt = null;
    }
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
          .catchError((Object error, StackTrace stackTrace) {
            if (generation != _objectDetectionGeneration) return;
            final message = error is PlatformException
                ? (error.message ?? error.code)
                : error.toString();
            if (mounted) {
              setState(() {
                _objectDetectionServiceStartupError = message;
                _objectDetectionServiceStartupFailedAt = DateTime.now();
              });
            }
            debugPrint(
              'Face/object debug detector startup ignored: '
              '$error\n$stackTrace',
            );
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
    _objectDetectionResultStabilizer.clear();
    _objectDetectionTargetSmoother.clear();
    _objectTargets = const [];
  }

  void _closeObjectDetectionService() {
    _clearObjectDetectionCache();

    final objectDetector = _objectDetectionService;
    final startup = _objectDetectionServiceStartup;
    _objectDetectionService = null;
    _objectDetectionServiceStartup = null;
    _objectDetectionServiceStartupError = null;
    _objectDetectionServiceStartupFailedAt = null;

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
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                'Face/object debug detector close ignored: '
                '$error\n$stackTrace',
              );
            }),
      );
    }
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

  bool get _shouldMirrorPreviewCoordinates {
    return _controller?.description.lensDirection ==
            CameraLensDirection.front &&
        !Platform.isIOS;
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
                                painter: ObjectDetectionDebugPainter(
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
                if (_objectDetectionServiceStartupError case final error?)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          error,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
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
