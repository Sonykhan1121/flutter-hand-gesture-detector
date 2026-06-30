import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../utils/app_snack_bar.dart';
import '../../data/factories/hand_detector_factory.dart';
import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/enums/hand_move_direction.dart';
import '../../domain/enums/zoom_direction.dart';
import '../../domain/models/custom_gesture_detection_result.dart';
import '../../domain/services/custom_gesture_detector.dart';
import '../../domain/services/direction_gesture_detector.dart';
import '../../domain/services/follow_object_sequence_detector.dart';
import '../../domain/services/zoom_gesture_detector.dart';
import '../painters/hand_focus_overlay_painter.dart';
import '../painters/hand_landmark_overlay_painter.dart';
import '../utils/hand_gesture_label_mapper.dart';
import '../widgets/gesture_status_panel.dart';
import '../widgets/hand_camera_loading_view.dart';
import '../widgets/round_icon_button.dart';

class AdminHandGestureLiveScreen extends StatefulWidget {
  const AdminHandGestureLiveScreen({super.key, required this.fontorback});

  /// Same flow as your previous camera page:
  /// 0 = back camera, anything else = front camera.
  final int fontorback;

  @override
  State<AdminHandGestureLiveScreen> createState() =>
      _AdminHandGestureLiveScreenState();
}

class _AdminHandGestureLiveScreenState extends State<AdminHandGestureLiveScreen>
    with WidgetsBindingObserver {
  static const _minFrameProcessInterval = Duration(milliseconds: 100);

  CameraController? _controller;
  HandDetector? _handDetector;

  final _customGestureDetector = CustomGestureDetector();
  final _directionGestureDetector = const DirectionGestureDetector();
  final _zoomGestureDetector = ZoomGestureDetector();

  late final FollowObjectSequenceDetector _followObjectSequenceDetector;

  List<CameraDescription> cameras = const [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  bool _isCameraSetupInProgress = false;
  bool _isFollowingHand = false;
  bool _hasCameraFailure = false;
  bool _shouldOpenSettingsOnRetry = false;

  String _gestureText = 'Show your hand';
  String _handText = '';
  String _cameraStatusTitle = 'Initializing camera...';
  String _cameraStatusMessage = 'Preparing hand gesture detection.';
  String _cameraActionLabel = 'Try Again';
  double _gestureConfidence = 0;
  int _detectedHandsCount = 0;

  List<Hand> _hands = const [];
  Size? _detectionImageSize;
  Rect? _focusedHandBox;
  Size? _focusImageSize;
  DateTime? _lastFrameProcessedAt;
  DateTime? _lastCameraFocusPointSetAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _followObjectSequenceDetector = FollowObjectSequenceDetector(
      onDebug: debugPrint,
    );

    _currentLensDirection = widget.fontorback == 0
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    _requestCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;

    if (controller != null) {
      if (_isStreaming && controller.value.isInitialized) {
        unawaited(
          controller.stopImageStream().catchError((Object error) {
            debugPrint('Error stopping camera stream in dispose: $error');
          }),
        );
      }

      unawaited(controller.dispose());
    }

    unawaited(_handDetector?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isCameraInitialized) {
        unawaited(_startCameraStream());
      } else if (!_hasCameraFailure && !_isCameraSetupInProgress) {
        unawaited(_requestCameraPermission());
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stopCameraStream());
    }
  }

  Future<void> _requestCameraPermission() async {
    if (_isCameraSetupInProgress) return;

    _isCameraSetupInProgress = true;

    try {
      await _requestCameraPermissionInternal();
    } finally {
      _isCameraSetupInProgress = false;
    }
  }

  Future<void> _requestCameraPermissionInternal() async {
    _setCameraLoading(
      title: 'Initializing camera...',
      message: 'Preparing hand gesture detection.',
    );

    var status = await Permission.camera.status;
    final requestedPermission = status.isDenied;

    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      if (requestedPermission) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      await _loadCameras();
      return;
    }

    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      _setCameraFailure(
        title: 'Camera access needed',
        message: 'Enable camera permission in settings to use hand gestures.',
        actionLabel: 'Open Settings',
        shouldOpenSettings: true,
      );
      _showSnackBar('Camera permission permanently denied.');
    } else {
      _setCameraFailure(
        title: 'Camera permission denied',
        message: 'Allow camera access to detect your hand gestures.',
      );
      _showSnackBar('Camera permission denied.');
    }
  }

  Future<void> _loadCameras() async {
    try {
      cameras = await availableCameras();
      await _initializeCamera();
    } catch (e, st) {
      debugPrint('Error loading cameras: $e\n$st');
      _setCameraFailure(
        title: 'Camera unavailable',
        message: 'Could not load cameras on this device.',
      );
      _showSnackBar('Could not load cameras.');
    }
  }

  Future<void> _initializeDetector() async {
    if (_handDetector != null) return;
    _handDetector = await HandDetectorFactory.create();
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        _setCameraFailure(
          title: 'No camera found',
          message: 'This device does not report an available camera.',
        );
        _showSnackBar('No cameras available.');
        return;
      }

      await _disposeCurrentController();
      await _initializeDetector();

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == _currentLensDirection,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      _controller = controller;
      await controller.initialize();

      if (Platform.isIOS) {
        await _turnFlashOff();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _hasCameraFailure = false;
        _shouldOpenSettingsOnRetry = false;
        _cameraStatusTitle = 'Initializing camera...';
        _cameraStatusMessage = 'Preparing hand gesture detection.';
        _cameraActionLabel = 'Try Again';
        _isCameraInitialized = true;
        _gestureText = 'Show your hand';
        _handText = '';
        _gestureConfidence = 0;
        _detectedHandsCount = 0;
        _hands = const [];
        _detectionImageSize = null;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lastFrameProcessedAt = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startCameraStream();
      });

      debugPrint('Camera initialized successfully');
    } catch (e, st) {
      debugPrint('Error initializing camera: $e\n$st');
      await _cleanupCamera();
      _setCameraFailure(
        title: 'Camera initialization failed',
        message: 'Check camera access and try again.',
      );
      _showSnackBar('Camera initialization failed.');
    }
  }

  Future<void> _disposeCurrentController() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      if (_isStreaming && controller.value.isInitialized) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping old stream: $e');
    }

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Error disposing old controller: $e');
    }

    _controller = null;
    _isStreaming = false;
  }

  Future<void> _turnFlashOff() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (e) {
      debugPrint('Error setting flash mode: $e');
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

      debugPrint('Camera stream started');
    } catch (e, st) {
      debugPrint('Error starting camera stream: $e\n$st');
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
      debugPrint('Camera stream stopped');
    } catch (e, st) {
      debugPrint('Error stopping camera stream: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
        });
      } else {
        _isStreaming = false;
      }
    }
  }

  Future<void> _switchCamera() async {
    if (cameras.length < 2 || _isSwitchingCamera) return;

    _zoomGestureDetector.clearState();
    _followObjectSequenceDetector.clear();

    setState(() {
      _isSwitchingCamera = true;
      _isCameraInitialized = false;
      _hasCameraFailure = false;
      _shouldOpenSettingsOnRetry = false;
      _cameraStatusTitle = 'Switching camera...';
      _cameraStatusMessage = 'Preparing the other camera.';
      _cameraActionLabel = 'Try Again';
      _gestureText = 'Switching camera...';
      _handText = '';
      _gestureConfidence = 0;
      _detectedHandsCount = 0;
      _hands = const [];
      _detectionImageSize = null;
      _isFollowingHand = false;
      _focusedHandBox = null;
      _focusImageSize = null;
    });

    _currentLensDirection = _currentLensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    await _initializeCamera();

    if (!mounted) return;
    setState(() {
      _isSwitchingCamera = false;
    });
  }

  Future<void> _cleanupCamera() async {
    try {
      await _stopCameraStream();
    } catch (e) {
      debugPrint('Error stopping stream during cleanup: $e');
    }

    try {
      await _controller?.dispose();
    } catch (e) {
      debugPrint('Error disposing controller during cleanup: $e');
    }

    _controller = null;

    _zoomGestureDetector.clearState();
    _followObjectSequenceDetector.clear();

    if (!mounted) return;

    setState(() {
      _isStreaming = false;
      _isCameraInitialized = false;
      _isProcessing = false;
      _lastFrameProcessedAt = null;
      _gestureText = 'Show your hand';
      _handText = '';
      _gestureConfidence = 0;
      _detectedHandsCount = 0;
      _hands = const [];
      _detectionImageSize = null;
      _isFollowingHand = false;
      _focusedHandBox = null;
      _focusImageSize = null;
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final controller = _controller;
    final detector = _handDetector;

    if (_isProcessing ||
        !mounted ||
        controller == null ||
        detector == null ||
        !controller.value.isInitialized ||
        !_isCameraInitialized) {
      return;
    }

    final now = DateTime.now();
    final lastFrameProcessedAt = _lastFrameProcessedAt;
    if (lastFrameProcessedAt != null &&
        now.difference(lastFrameProcessedAt) < _minFrameProcessInterval) {
      return;
    }

    _lastFrameProcessedAt = now;
    _isProcessing = true;

    try {
      final rotation = _cameraFrameRotation(image);

      final detectionImageSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );

      final hands = await detector.detectFromCameraImage(
        image,
        rotation: rotation,
        isBgra: Platform.isIOS,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );

      if (!mounted) return;

      _updateGestureState(hands, detectionImageSize);
    } catch (e, st) {
      debugPrint('Hand gesture detection error: $e\n$st');
    } finally {
      _isProcessing = false;
    }
  }

  CameraFrameRotation? _cameraFrameRotation(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;

    if (!(Platform.isAndroid || Platform.isIOS)) return null;

    return rotationForFrame(
      width: image.width,
      height: image.height,
      sensorOrientation: controller.description.sensorOrientation,
      isFrontCamera:
          controller.description.lensDirection == CameraLensDirection.front,
      deviceOrientation: controller.value.deviceOrientation,
    );
  }

  void _updateGestureState(List<Hand> hands, Size detectionImageSize) {
    if (hands.isEmpty) {
      _zoomGestureDetector.markPoseInvalid(DateTime.now());
      _followObjectSequenceDetector.clear();

      setState(() {
        _gestureText = 'No hand detected';
        _handText = '';
        _gestureConfidence = 0;
        _detectedHandsCount = 0;
        _hands = const [];
        _detectionImageSize = detectionImageSize;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
      });
      return;
    }

    final reliableHands = hands
        .where((hand) => hand.score >= HandGestureThresholds.minHandScore)
        .toList(growable: false);

    if (reliableHands.isEmpty) {
      if (_isFollowingHand) {
        final trackedHand = _selectTrackedHand(hands);
        _updateFocusedHand(hand: trackedHand, imageSize: detectionImageSize);

        setState(() {
          _hands = hands;
          _detectionImageSize = detectionImageSize;
          _detectedHandsCount = hands.length;
          _handText = trackedHand.handedness.displayLabel;
          _gestureText = 'Following hand';
          _gestureConfidence = 1;
        });
        return;
      }

      _zoomGestureDetector.markPoseInvalid(DateTime.now());
      _followObjectSequenceDetector.clear();

      setState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _detectedHandsCount = hands.length;
        _handText = '';
        _gestureText = 'Move hand closer';
        _gestureConfidence = 0;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
      });
      return;
    }

    final bestHand = _isFollowingHand
        ? _selectTrackedHand(hands)
        : reliableHands.reduce(
            (currentBest, next) =>
                next.score > currentBest.score ? next : currentBest,
          );

    final now = DateTime.now();

    final followObjectSequence = _followObjectSequenceDetector.update(
      bestHand,
      now,
    );

    final followObjectSequenceActive = followObjectSequence.isActive;
    final followObjectDetected = followObjectSequence.isDetected;
    final followTrackingActive = _isFollowingHand || followObjectSequenceActive;

    final gesture = bestHand.gesture;
    final hasKnownGesture =
        !followTrackingActive &&
        gesture != null &&
        gesture.type != GestureType.unknown &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;

    final customGestureResult = followTrackingActive
        ? CustomGestureDetectionResult.empty
        : _customGestureDetector.detect(
            hand: bestHand,
            imageSize: detectionImageSize,
            isFrontCamera:
                _controller?.description.lensDirection ==
                CameraLensDirection.front,
          );

    final customGestureLabels = customGestureResult.labels;
    final hasSingleCustomGesture = customGestureLabels.length == 1;
    final hasOverlappingCustomGestures = customGestureLabels.length > 1;

    final moveDirection = !followTrackingActive && customGestureLabels.isEmpty
        ? _directionGestureDetector.detect(
            hand: bestHand,
            imageSize: detectionImageSize,
            isFrontCamera:
                _controller?.description.lensDirection ==
                CameraLensDirection.front,
          )
        : HandMoveDirection.none;

    final hasDirectionGesture = moveDirection != HandMoveDirection.none;

    if (hasDirectionGesture) {
      _zoomGestureDetector.clearState();
    }

    final zoomDirection =
        !followTrackingActive &&
            customGestureLabels.isEmpty &&
            !hasDirectionGesture
        ? _zoomGestureDetector.detect(
            hand: bestHand,
            imageSize: detectionImageSize,
          )
        : ZoomDirection.none;

    final followObjectSequenceMessage =
        followObjectSequence.packageGestureType?.displayLabel;

    final shouldFocusOnHand =
        _isFollowingHand ||
        (followObjectSequenceActive &&
            followObjectSequence.packageGestureType == GestureType.closedFist);

    if (shouldFocusOnHand) {
      _updateFocusedHand(hand: bestHand, imageSize: detectionImageSize);
    }

    setState(() {
      _hands = hands;
      _detectionImageSize = detectionImageSize;
      _isFollowingHand = shouldFocusOnHand;
      if (!shouldFocusOnHand) {
        _focusedHandBox = null;
        _focusImageSize = null;
      }
      _detectedHandsCount = hands.length;
      _handText = bestHand.handedness.displayLabel;

      if (followObjectDetected) {
        _gestureText = 'Follow the object';
        _gestureConfidence = 1;
      } else if (_isFollowingHand) {
        _gestureText = 'Following hand';
        _gestureConfidence = 1;
      } else if (followObjectSequenceActive) {
        _gestureText = followObjectSequenceMessage ?? 'Hand detected';
        _gestureConfidence = followObjectSequenceMessage == null ? 0 : 1;
      } else if (hasSingleCustomGesture) {
        _gestureText = customGestureLabels.first;
        _gestureConfidence = 1;
      } else if (hasOverlappingCustomGestures) {
        _gestureText = 'Hand detected';
        _gestureConfidence = 0;
      } else if (moveDirection == HandMoveDirection.left) {
        _gestureText = 'Moving left';
        _gestureConfidence = 1;
      } else if (moveDirection == HandMoveDirection.right) {
        _gestureText = 'Moving right';
        _gestureConfidence = 1;
      } else if (moveDirection == HandMoveDirection.up) {
        _gestureText = 'Moving up';
        _gestureConfidence = 1;
      } else if (moveDirection == HandMoveDirection.down) {
        _gestureText = 'Moving down';
        _gestureConfidence = 1;
      } else if (zoomDirection == ZoomDirection.zoomIn) {
        _gestureText = 'Zoom in';
        _gestureConfidence = 1;
      } else if (zoomDirection == ZoomDirection.zoomOut) {
        _gestureText = 'Zoom out';
        _gestureConfidence = 1;
      } else if (hasKnownGesture) {
        if (gesture.type == GestureType.thumbUp) {
          _gestureText = 'Stop & Continue Action';
        } else if (gesture.type == GestureType.victory) {
          _gestureText = 'End record video';
        } else {
          _gestureText = gesture.type.displayLabel;
        }

        _gestureConfidence = gesture.confidence;
      } else {
        _gestureText = 'Hand detected';
        _gestureConfidence = 0;
      }
    });
  }

  double _previewAspectRatio() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return 9 / 16;
    }

    return 1 / controller.value.aspectRatio;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    AppSnackBar.show(context: context, message: message);
  }

  Hand _selectTrackedHand(List<Hand> visibleHands) {
    final focusedHandBox = _focusedHandBox;

    if (focusedHandBox == null) {
      return visibleHands.reduce(
        (currentBest, next) =>
            next.score > currentBest.score ? next : currentBest,
      );
    }

    final focusedCenter = focusedHandBox.center;

    return visibleHands.reduce((currentBest, next) {
      final currentDistance = _distanceBetweenOffsets(
        _handBoxCenter(currentBest),
        focusedCenter,
      );
      final nextDistance = _distanceBetweenOffsets(
        _handBoxCenter(next),
        focusedCenter,
      );

      return nextDistance < currentDistance ? next : currentBest;
    });
  }

  void _updateFocusedHand({required Hand hand, required Size imageSize}) {
    final box = hand.boundingBox;

    _focusedHandBox = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    _focusImageSize = imageSize;

    unawaited(_updateCameraFocusPoint(hand: hand, imageSize: imageSize));
  }

  Offset _handBoxCenter(Hand hand) {
    final box = hand.boundingBox;
    return Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  }

  double _distanceBetweenOffsets(Offset first, Offset second) {
    final dx = first.dx - second.dx;
    final dy = first.dy - second.dy;
    return dx * dx + dy * dy;
  }

  Future<void> _updateCameraFocusPoint({
    required Hand hand,
    required Size imageSize,
  }) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return;
    }

    final now = DateTime.now();
    final lastCameraFocusPointSetAt = _lastCameraFocusPointSetAt;

    if (lastCameraFocusPointSetAt != null &&
        now.difference(lastCameraFocusPointSetAt) <
            const Duration(milliseconds: 700)) {
      return;
    }

    _lastCameraFocusPointSetAt = now;

    final box = hand.boundingBox;
    final focusPoint = Offset(
      (((box.left + box.right) / 2) / imageSize.width).clamp(0.0, 1.0),
      (((box.top + box.bottom) / 2) / imageSize.height).clamp(0.0, 1.0),
    );

    try {
      await controller.setFocusPoint(focusPoint);
      await controller.setExposurePoint(focusPoint);
    } catch (e) {
      debugPrint('Camera focus point update ignored: $e');
    }
  }

  void _setCameraLoading({required String title, required String message}) {
    if (!mounted) return;

    setState(() {
      _hasCameraFailure = false;
      _shouldOpenSettingsOnRetry = false;
      _cameraStatusTitle = title;
      _cameraStatusMessage = message;
      _cameraActionLabel = 'Try Again';
    });
  }

  void _setCameraFailure({
    required String title,
    required String message,
    String actionLabel = 'Try Again',
    bool shouldOpenSettings = false,
  }) {
    if (!mounted) return;

    setState(() {
      _hasCameraFailure = true;
      _shouldOpenSettingsOnRetry = shouldOpenSettings;
      _cameraStatusTitle = title;
      _cameraStatusMessage = message;
      _cameraActionLabel = actionLabel;
    });
  }

  Future<void> _handleCameraRetry() async {
    if (_shouldOpenSettingsOnRetry) {
      await openAppSettings();
      return;
    }

    await _requestCameraPermission();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

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
                        aspectRatio: _previewAspectRatio(),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(controller),
                            if (_detectionImageSize != null)
                              CustomPaint(
                                painter: HandLandmarkOverlayPainter(
                                  hands: _hands,
                                  imageSize: _detectionImageSize!,
                                  mirrorHorizontally:
                                      controller.description.lensDirection ==
                                      CameraLensDirection.front,
                                ),
                              ),
                            if (_focusedHandBox != null &&
                                _focusImageSize != null)
                              CustomPaint(
                                painter: HandFocusOverlayPainter(
                                  handBox: _focusedHandBox!,
                                  imageSize: _focusImageSize!,
                                  mirrorHorizontally:
                                      controller.description.lensDirection ==
                                      CameraLensDirection.front,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RoundIconButton(
                          icon: Icons.arrow_back,
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          'Show Your Hand',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        cameras.length > 1
                            ? RoundIconButton(
                                icon: Icons.flip_camera_ios,
                                tooltip: 'Switch camera',
                                onPressed: _isSwitchingCamera
                                    ? null
                                    : _switchCamera,
                              )
                            : const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: GestureStatusPanel(
                      gestureText: _gestureText,
                      handText: _handText,
                      gestureConfidence: _gestureConfidence,
                      detectedHandsCount: _detectedHandsCount,
                    ),
                  ),
                ),
              ],
            )
          : HandCameraLoadingView(
              title: _cameraStatusTitle,
              message: _cameraStatusMessage,
              actionLabel: _cameraActionLabel,
              isBusy: !_hasCameraFailure,
              onRetry: _handleCameraRetry,
            ),
    );
  }
}
