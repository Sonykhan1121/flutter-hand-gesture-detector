import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as ml_face;
import 'package:permission_handler/permission_handler.dart';

import '../hand_gesture_features/presentation/utils/ml_kit_preview_mapper.dart';

const faceVerificationDuration = Duration(seconds: 2);
const faceVerificationPreviewAspectRatio = 9 / 16;
const faceVerificationOvalWidthFraction = 0.8;
const faceVerificationOvalHeightToWidthRatio = 1.3;

bool shouldReleaseFaceVerificationCameraForLifecycle({
  required AppLifecycleState state,
  required bool requestingPermission,
}) {
  if (requestingPermission) return false;
  return state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

bool isNormalizedFaceCenterInsideVerificationOval({
  required Offset normalizedFaceCenter,
  required Size viewportSize,
}) {
  if (!normalizedFaceCenter.dx.isFinite ||
      !normalizedFaceCenter.dy.isFinite ||
      viewportSize.width <= 0 ||
      viewportSize.height <= 0) {
    return false;
  }

  final viewportAspectRatio = viewportSize.width / viewportSize.height;
  late final Size previewSize;
  if (viewportAspectRatio > faceVerificationPreviewAspectRatio) {
    previewSize = Size(
      viewportSize.height * faceVerificationPreviewAspectRatio,
      viewportSize.height,
    );
  } else {
    previewSize = Size(
      viewportSize.width,
      viewportSize.width / faceVerificationPreviewAspectRatio,
    );
  }
  final previewOrigin = Offset(
    (viewportSize.width - previewSize.width) / 2,
    (viewportSize.height - previewSize.height) / 2,
  );
  final displayedFaceCenter = Offset(
    previewOrigin.dx + normalizedFaceCenter.dx * previewSize.width,
    previewOrigin.dy + normalizedFaceCenter.dy * previewSize.height,
  );

  final ovalWidth = viewportSize.width * faceVerificationOvalWidthFraction;
  final ovalHeight = ovalWidth * faceVerificationOvalHeightToWidthRatio;
  final radiusX = ovalWidth / 2;
  final radiusY = ovalHeight / 2;
  if (radiusX <= 0 || radiusY <= 0) return false;

  final delta = displayedFaceCenter - viewportSize.center(Offset.zero);
  final ellipseDistance =
      (delta.dx * delta.dx) / (radiusX * radiusX) +
      (delta.dy * delta.dy) / (radiusY * radiusY);
  return ellipseDistance <= 1;
}

class FaceVerificationObservation {
  const FaceVerificationObservation({
    required this.isValid,
    required this.progress,
    required this.confirmed,
  });

  final bool isValid;
  final double progress;
  final bool confirmed;
}

/// Confirms only when exactly one face remains visible continuously.
class FaceVerificationHoldController {
  FaceVerificationHoldController({
    this.holdDuration = faceVerificationDuration,
  });

  final Duration holdDuration;

  DateTime? _validSince;
  bool _confirmed = false;

  FaceVerificationObservation observe({
    required DateTime now,
    required int faceCount,
    bool faceCentered = true,
  }) {
    if (faceCount != 1 || !faceCentered) {
      reset();
      return const FaceVerificationObservation(
        isValid: false,
        progress: 0,
        confirmed: false,
      );
    }

    _validSince ??= now;
    final elapsed = now.difference(_validSince!);
    final durationMicros = holdDuration.inMicroseconds;
    final progress = durationMicros == 0
        ? 1.0
        : (elapsed.inMicroseconds / durationMicros).clamp(0.0, 1.0);
    if (elapsed >= holdDuration) {
      _confirmed = true;
    }
    return FaceVerificationObservation(
      isValid: true,
      progress: _confirmed ? 1 : progress,
      confirmed: _confirmed,
    );
  }

  void reset() {
    _validSince = null;
    _confirmed = false;
  }
}

class FaceVerificationPage extends StatefulWidget {
  const FaceVerificationPage({
    super.key,
    this.autoStartCamera = true,
    this.clock,
  });

  /// Allows widget tests to render without invoking the camera plugin.
  final bool autoStartCamera;
  final DateTime Function()? clock;

  @override
  State<FaceVerificationPage> createState() => _FaceVerificationPageState();
}

class _FaceVerificationPageState extends State<FaceVerificationPage>
    with WidgetsBindingObserver {
  final FaceVerificationHoldController _holdController =
      FaceVerificationHoldController();

  CameraController? _cameraController;
  ml_face.FaceDetector? _faceDetector;
  Future<void>? _initializing;
  Future<void>? _releasing;
  Future<void>? _activeFrameProcessing;
  bool _isValidFace = false;
  bool _processingFrame = false;
  bool _completing = false;
  bool _requestingCameraPermission = false;
  int _initializationGeneration = 0;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStartCamera) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.autoStartCamera) return;
    if (shouldReleaseFaceVerificationCameraForLifecycle(
      state: state,
      requestingPermission: _requestingCameraPermission,
    )) {
      _initializationGeneration++;
      unawaited(_releaseCamera(updateUi: true));
      return;
    }
    if (state == AppLifecycleState.resumed && _cameraController == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() {
    final active = _initializing;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _performCameraInitialization().whenComplete(() {
      if (identical(_initializing, operation)) {
        _initializing = null;
        if (mounted) setState(() {});
      }
    });
    _initializing = operation;
    return operation;
  }

  Future<void> _performCameraInitialization() async {
    final pendingRelease = _releasing;
    if (pendingRelease != null) await pendingRelease;
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _isValidFace = false;
      });
    }

    CameraController? controller;
    ml_face.FaceDetector? detector;
    try {
      var permission = await Permission.camera.status;
      if (permission.isDenied) {
        _requestingCameraPermission = true;
        try {
          permission = await Permission.camera.request();
        } finally {
          _requestingCameraPermission = false;
        }
      }
      if (!permission.isGranted) {
        _showFailure();
        return;
      }

      final cameras = await availableCameras();
      final frontCameras = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.front)
          .toList(growable: false);
      if (frontCameras.isEmpty) {
        throw StateError('No front camera was found on this device.');
      }

      controller = CameraController(
        frontCameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some front cameras do not expose flash controls.
      }

      detector = ml_face.FaceDetector(
        options: ml_face.FaceDetectorOptions(
          performanceMode: ml_face.FaceDetectorMode.accurate,
          enableTracking: false,
          enableContours: false,
          enableClassification: false,
          enableLandmarks: false,
          minFaceSize: 0.15,
        ),
      );

      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        await detector.close();
        return;
      }

      _cameraController = controller;
      _faceDetector = detector;
      await controller.startImageStream(_onCameraImage);
      if (!mounted || generation != _initializationGeneration) return;
      setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Attendance camera failed: $error\n$stackTrace');
      if (identical(_cameraController, controller)) {
        await _releaseCamera(updateUi: false);
      } else {
        try {
          await controller?.dispose();
        } catch (_) {
          // The camera may have failed before initialization completed.
        }
        await detector?.close();
      }
      _showFailure();
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_processingFrame || _completing || _releasing != null || !mounted) {
      return;
    }
    _processingFrame = true;
    late final Future<void> operation;
    operation = _processCameraImage(image).whenComplete(() {
      _processingFrame = false;
      if (identical(_activeFrameProcessing, operation)) {
        _activeFrameProcessing = null;
      }
    });
    _activeFrameProcessing = operation;
    unawaited(operation);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final detector = _faceDetector;
    if (detector == null) return;

    try {
      final frame = _inputImageFromCamera(image);
      if (frame == null) {
        _resetObservation();
        return;
      }
      final faces = await detector.processImage(frame.inputImage);
      if (!mounted || _releasing != null || _completing) return;

      final faceCentered =
          faces.length == 1 &&
          _isFaceCenteredInsideOverlay(
            face: faces.single,
            image: image,
            rotation: frame.rotation,
          );
      final observation = _holdController.observe(
        now: _now,
        faceCount: faces.length,
        faceCentered: faceCentered,
      );
      setState(() {
        _isValidFace = observation.isValid;
      });
      if (observation.confirmed) {
        await _completeVerification();
      }
    } catch (error, stackTrace) {
      debugPrint('Attendance face detection failed: $error\n$stackTrace');
      _resetObservation();
    }
  }

  bool _isFaceCenteredInsideOverlay({
    required ml_face.Face face,
    required CameraImage image,
    required ml_face.InputImageRotation rotation,
  }) {
    final controller = _cameraController;
    if (controller == null || !mounted) return false;
    final displayRect = mlKitDisplayRect(
      face.boundingBox,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      isIOS: Platform.isIOS,
      mirrorHorizontally:
          controller.description.lensDirection == CameraLensDirection.front &&
          !Platform.isIOS,
    );
    return isNormalizedFaceCenterInsideVerificationOval(
      normalizedFaceCenter: displayRect.center,
      viewportSize: MediaQuery.sizeOf(context),
    );
  }

  ({ml_face.InputImage inputImage, ml_face.InputImageRotation rotation})?
  _inputImageFromCamera(CameraImage image) {
    final controller = _cameraController;
    if (controller == null ||
        image.planes.isEmpty ||
        !(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final rotation = ml_face.InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );
    if (rotation == null) return null;

    return (
      inputImage: ml_face.InputImage.fromBytes(
        bytes: bytes,
        metadata: ml_face.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: Platform.isAndroid
              ? ml_face.InputImageFormat.nv21
              : ml_face.InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ),
      rotation: rotation,
    );
  }

  void _resetObservation() {
    _holdController.reset();
    if (!mounted || _completing) return;
    setState(() {
      _isValidFace = false;
    });
  }

  Future<void> _completeVerification() async {
    if (_completing) return;
    _completing = true;
    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (error) {
        debugPrint('Could not stop attendance camera stream: $error');
      }
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _showFailure() {
    if (!mounted) return;
    setState(() {
      _isValidFace = false;
    });
  }

  Future<void> _releaseCamera({required bool updateUi}) {
    final active = _releasing;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _performCameraRelease(updateUi: updateUi).whenComplete(() {
      if (identical(_releasing, operation)) {
        _releasing = null;
      }
    });
    _releasing = operation;
    return operation;
  }

  Future<void> _performCameraRelease({required bool updateUi}) async {
    _holdController.reset();
    final controller = _cameraController;
    final detector = _faceDetector;
    _cameraController = null;
    _faceDetector = null;

    if (controller != null) {
      try {
        if (controller.value.isInitialized &&
            controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {
        // The platform may already have reclaimed the camera.
      }
    }

    final processing = _activeFrameProcessing;
    if (processing != null) {
      try {
        await processing;
      } catch (_) {
        // Frame errors are already handled by the processing callback.
      }
    }

    try {
      await controller?.dispose();
    } catch (_) {
      // A partially initialized controller may already be disposed.
    }
    await detector?.close();

    if (updateUi && mounted) {
      setState(() {
        _isValidFace = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationGeneration++;
    unawaited(_releaseCamera(updateUi: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final cameraReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: cameraReady
          ? Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24, width: 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      child: RotatedBox(
                        quarterTurns: 4,
                        child: AspectRatio(
                          aspectRatio: faceVerificationPreviewAspectRatio,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: CustomPaint(
                    key: const Key('faceOvalOverlay'),
                    size: Size(
                      MediaQuery.sizeOf(context).width,
                      MediaQuery.sizeOf(context).height,
                    ),
                    painter: FaceOvalPainter(
                      ovalWidth:
                          MediaQuery.sizeOf(context).width *
                          faceVerificationOvalWidthFraction,
                      ovalHeight:
                          MediaQuery.sizeOf(context).width *
                          faceVerificationOvalWidthFraction *
                          faceVerificationOvalHeightToWidthRatio,
                    ),
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 50,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.black38,
                          radius: 20,
                          child: IconButton(
                            key: const Key('cancelFaceVerificationButton'),
                            onPressed: () => Navigator.of(context).pop(false),
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Cancel',
                          ),
                        ),
                        const Text(
                          'Face Verification',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: _buildInstructions(),
                  ),
                ),
              ],
            )
          : _buildCameraLoading(),
    );
  }

  Widget _buildCameraLoading() {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        bottom: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 1),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF00FB46),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Initializing Camera...',
                      key: Key('faceCameraLoadingText'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    key: const Key('retryFaceCameraButton'),
                    onPressed: _initializing == null ? _initializeCamera : null,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Column(
      children: [
        AnimatedContainer(
          key: const Key('faceVerificationInstruction'),
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isValidFace
                ? const Color(0xFF00FB46).withValues(alpha: 0.2)
                : Colors.black38,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _isValidFace ? const Color(0xFF00FB46) : Colors.white24,
              width: 1,
            ),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isValidFace ? Icons.check_circle : Icons.face,
                color: _isValidFace ? const Color(0xFF00FB46) : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _isValidFace
                      ? 'Hold Still...'
                      : 'Make sure your face is centered and the background is white',
                  style: TextStyle(
                    color: _isValidFace
                        ? const Color(0xFF00FB46)
                        : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_isValidFace)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              key: Key('faceHoldProgress'),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FB46)),
              strokeWidth: 3,
            ),
          )
        else
          const Icon(Icons.arrow_upward, size: 36, color: Colors.white70),
      ],
    );
  }
}

class FaceOvalPainter extends CustomPainter {
  const FaceOvalPainter({required this.ovalWidth, required this.ovalHeight});

  final double ovalWidth;
  final double ovalHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalPath = Path()
      ..addOval(
        Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight),
      );
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final outsideOvalPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );
    final outsidePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(outsideOvalPath, outsidePaint);
    canvas.drawPath(ovalPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant FaceOvalPainter oldDelegate) {
    return oldDelegate.ovalWidth != ovalWidth ||
        oldDelegate.ovalHeight != ovalHeight;
  }
}
