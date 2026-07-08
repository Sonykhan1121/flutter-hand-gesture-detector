part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
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
    _handDetector ??= await HandDetectorFactory.create();
    _faceDetector ??= ml_face.FaceDetector(
      options: ml_face.FaceDetectorOptions(
        enableTracking: true,
        performanceMode: ml_face.FaceDetectorMode.fast,
      ),
    );
    _objectDetector ??= ml_object.ObjectDetector(
      options: ml_object.ObjectDetectorOptions(
        mode: ml_object.DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
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
        imageFormatGroup:
            Platform.isIOS
                ? ImageFormatGroup.bgra8888
                : Platform.isAndroid
                ? ImageFormatGroup.yuv420
                : ImageFormatGroup.bgra8888,
      );

      _controller = controller;
      await controller.initialize();
      await _initializeZoomLevels(controller);
      _directionGestureDetector.clearState();
      _moveDirectionDisplayHold.clear();

      if (Platform.isIOS) {
        await _turnFlashOff();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _setScreenState(() {
        _hasCameraFailure = false;
        _shouldOpenSettingsOnRetry = false;
        _cameraStatusTitle = 'Initializing camera...';
        _cameraStatusMessage = 'Preparing hand gesture detection.';
        _cameraActionLabel = 'Try Again';
        _isCameraInitialized = true;
        _gestureText = 'Show your hand';
        _handText = '';
        _gestureConfidence = 0;
        _lastAppliedZoomDirection = ZoomDirection.none;
        _lastGestureZoomAppliedAt = null;
        _detectedHandsCount = 0;
        _hands = const [];
        _detectionImageSize = null;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = null;
        _followObjectCandidateFaces = const [];
        _followObjectCandidateObjects = const [];
        _lockedFollowTargetLostAt = null;
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
      if (controller.value.isInitialized && controller.value.isRecordingVideo) {
        final file = await controller.stopVideoRecording();
        final savedFile = await _copyRecordingToDownloads(file);
        await _unlockRecordingOrientation(controller);
        _resetRecordingTimer();
        _isStartingVideoRecording = false;
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = false;
        debugPrint(
          'Recording stopped before camera disposal: ${savedFile.path}',
        );
        _isStreaming = false;
      } else if (_isStreaming && controller.value.isInitialized) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping old camera activity: $e');
    }

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Error disposing old controller: $e');
    }

    _controller = null;
    _isStreaming = false;
  }

  Future<void> _disposeControllerFromWidgetDispose(
    CameraController controller,
  ) async {
    try {
      if (controller.value.isInitialized && controller.value.isRecordingVideo) {
        final file = await controller.stopVideoRecording();
        final savedFile = await _copyRecordingToDownloads(file);
        await _unlockRecordingOrientation(controller);
        _resetRecordingTimer();
        _isStartingVideoRecording = false;
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = false;
        debugPrint('Recording stopped in dispose: ${savedFile.path}');
      } else if (_isStreaming && controller.value.isInitialized) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping camera activity in dispose: $e');
    }

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Error disposing controller in dispose: $e');
    }
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
        controller.value.isRecordingVideo ||
        _isStreaming) {
      return;
    }

    try {
      await controller.startImageStream(_processCameraImage);
      if (!mounted) return;

      _setScreenState(() {
        _isStreaming = true;
      });

      debugPrint('Camera stream started');
    } catch (e, st) {
      debugPrint('Error starting camera stream: $e\n$st');
      if (!mounted) return;

      _setScreenState(() {
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

    if (controller.value.isRecordingVideo) {
      return;
    }

    try {
      await controller.stopImageStream();
      debugPrint('Camera stream stopped');
    } catch (e, st) {
      debugPrint('Error stopping camera stream: $e\n$st');
    } finally {
      _directionGestureDetector.clearState();
      _moveDirectionDisplayHold.clear();
      if (mounted) {
        _setScreenState(() {
          _isStreaming = false;
        });
      } else {
        _isStreaming = false;
      }
    }
  }

  bool get _canSwitchCamera {
    return cameras.length > 1 &&
        !_isSwitchingCamera &&
        !_isRecordingActionInProgress &&
        !_isStartingVideoRecording &&
        !_isStoppingVideoRecording;
  }

  Future<void> _switchCamera({bool restartRecordingAfterSwitch = false}) async {
    if (cameras.length < 2 || _isSwitchingCamera) return;

    final activeController = _controller;
    final shouldRestartRecording =
        restartRecordingAfterSwitch &&
        activeController != null &&
        activeController.value.isInitialized &&
        activeController.value.isRecordingVideo;

    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState();
    _moveDirectionDisplayHold.clear();
    _followObjectSequenceDetector.clear();
    _clearFollowObjectTargetCandidates();
    _clearLockedFollowTarget();
    _clearRecordingGestureHold();
    _clearFaceDetectGestureHold();
    _zoomControlAutoHideTimer?.cancel();
    _gestureZoomSuppressedUntil = null;
    _lastGestureZoomAppliedAt = null;

    _setScreenState(() {
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
      _lastAppliedZoomDirection = ZoomDirection.none;
      _lastGestureZoomAppliedAt = null;
      _detectedHandsCount = 0;
      _hands = const [];
      _detectionImageSize = null;
      _isFollowingHand = false;
      _focusedHandBox = null;
      _focusImageSize = null;
      _lockedFollowTarget = null;
      _lockedFollowTargetLostAt = null;
      _isZoomControlVisible = false;
      _isManualZoomInteractionActive = false;
      _pendingZoomLevel = null;
    });

    _currentLensDirection =
        _currentLensDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front;

    await _initializeCamera();

    final nextController = _controller;
    if (shouldRestartRecording &&
        mounted &&
        nextController != null &&
        nextController.value.isInitialized) {
      await _startGestureVideoRecording(nextController);
    }

    if (!mounted) return;
    _setScreenState(() {
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
    _resetCameraZoomState();
    _resetRecordingTimer();
    _isStartingVideoRecording = false;
    _isStoppingVideoRecording = false;
    _isRecordingPreviewCorrectionActive = false;
    _isRecordingActionInProgress = false;
    _isZoomControlVisible = false;
    _pendingZoomLevel = null;
    _gestureZoomSuppressedUntil = null;
    _lastGestureZoomAppliedAt = null;
    _isManualZoomInteractionActive = false;
    _zoomControlAutoHideTimer?.cancel();

    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState();
    _moveDirectionDisplayHold.clear();
    _followObjectSequenceDetector.clear();
    _clearFollowObjectTargetCandidates();
    _clearLockedFollowTarget();
    _clearRecordingGestureHold();
    _clearFaceDetectGestureHold();

    if (!mounted) return;

    _setScreenState(() {
      _isStreaming = false;
      _isCameraInitialized = false;
      _isProcessing = false;
      _lastFrameProcessedAt = null;
      _gestureText = 'Show your hand';
      _handText = '';
      _gestureConfidence = 0;
      _lastAppliedZoomDirection = ZoomDirection.none;
      _lastGestureZoomAppliedAt = null;
      _detectedHandsCount = 0;
      _hands = const [];
      _detectionImageSize = null;
      _isFollowingHand = false;
      _focusedHandBox = null;
      _focusImageSize = null;
      _lockedFollowTarget = null;
      _lockedFollowTargetLostAt = null;
      _isZoomControlVisible = false;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    AppSnackBar.show(context: context, message: message);
  }

  void _setCameraLoading({required String title, required String message}) {
    if (!mounted) return;

    _setScreenState(() {
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

    _setScreenState(() {
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
}
