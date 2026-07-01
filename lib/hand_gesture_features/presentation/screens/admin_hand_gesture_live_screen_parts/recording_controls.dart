part of '../admin_hand_gesture_live_screen.dart';

enum _RecordingGestureAction { start, togglePause, stop }

class _RecordingGestureFeedback {
  const _RecordingGestureFeedback({
    required this.text,
    required this.confidence,
  });

  final String text;
  final double confidence;
}

extension on _AdminHandGestureLiveScreenState {
  bool get _isVideoRecording => _controller?.value.isRecordingVideo ?? false;

  bool get _isVideoRecordingPaused =>
      _controller?.value.isRecordingPaused ?? false;

  _RecordingGestureAction? _recordingGestureAction({
    required bool followTrackingActive,
    required CustomGestureDetectionResult customGestureResult,
    required bool hasSingleCustomGesture,
    required bool hasVictoryGesture,
  }) {
    if (followTrackingActive) return null;

    if (hasSingleCustomGesture && customGestureResult.isOk) {
      return _RecordingGestureAction.start;
    }

    if (hasSingleCustomGesture && customGestureResult.isPunch) {
      return _RecordingGestureAction.togglePause;
    }

    if (hasVictoryGesture) {
      return _RecordingGestureAction.stop;
    }

    return null;
  }

  _RecordingGestureFeedback? _updateRecordingGestureHold({
    required _RecordingGestureAction? action,
    required DateTime now,
  }) {
    if (action == null) {
      _clearRecordingGestureHold();
      return null;
    }

    if (_activeRecordingGestureAction != action) {
      _activeRecordingGestureAction = action;
      _recordingGestureStartedAt = now;
      _recordingGestureTriggered = false;
    }

    if (_recordingGestureTriggered) {
      return _RecordingGestureFeedback(
        text: _recordingTriggeredText(action),
        confidence: 1,
      );
    }

    if (!_canRunRecordingGestureAction(action)) {
      _clearRecordingGestureHold();
      return _RecordingGestureFeedback(
        text: _recordingUnavailableText(action),
        confidence: 0,
      );
    }

    final startedAt = _recordingGestureStartedAt ?? now;
    final holdDuration = _recordingHoldDuration(action);
    final holdProgress =
        (now.difference(startedAt).inMilliseconds / holdDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

    if (holdProgress >= 1) {
      _recordingGestureTriggered = true;
      unawaited(_runRecordingGestureAction(action));

      return _RecordingGestureFeedback(
        text: _recordingTriggeredText(action),
        confidence: 1,
      );
    }

    return _RecordingGestureFeedback(
      text: _recordingHoldText(action),
      confidence: holdProgress,
    );
  }

  Duration _recordingHoldDuration(_RecordingGestureAction action) {
    switch (action) {
      case _RecordingGestureAction.start:
        return HandGestureThresholds.recordStartHoldDuration;
      case _RecordingGestureAction.togglePause:
        return HandGestureThresholds.recordPauseHoldDuration;
      case _RecordingGestureAction.stop:
        return HandGestureThresholds.recordStopHoldDuration;
    }
  }

  bool _canRunRecordingGestureAction(_RecordingGestureAction action) {
    switch (action) {
      case _RecordingGestureAction.start:
        return !_isVideoRecording;
      case _RecordingGestureAction.togglePause:
      case _RecordingGestureAction.stop:
        return _isVideoRecording;
    }
  }

  String _recordingHoldText(_RecordingGestureAction action) {
    switch (action) {
      case _RecordingGestureAction.start:
        return 'Hold OK to record';
      case _RecordingGestureAction.togglePause:
        return _isVideoRecordingPaused
            ? 'Hold punch to resume'
            : 'Hold punch to pause';
      case _RecordingGestureAction.stop:
        return 'Hold victory to end';
    }
  }

  String _recordingTriggeredText(_RecordingGestureAction action) {
    switch (action) {
      case _RecordingGestureAction.start:
        return _isVideoRecording ? 'Recording' : 'Starting recording...';
      case _RecordingGestureAction.togglePause:
        if (_isRecordingActionInProgress) return 'Updating recording...';
        return _isVideoRecordingPaused ? 'Recording paused' : 'Recording';
      case _RecordingGestureAction.stop:
        return _isVideoRecording
            ? 'Stopping video recording...'
            : 'Recording saved';
    }
  }

  String _recordingUnavailableText(_RecordingGestureAction action) {
    switch (action) {
      case _RecordingGestureAction.start:
        return 'Already recording';
      case _RecordingGestureAction.togglePause:
      case _RecordingGestureAction.stop:
        return 'Start recording first';
    }
  }

  void _clearRecordingGestureHold() {
    _activeRecordingGestureAction = null;
    _recordingGestureStartedAt = null;
    _recordingGestureTriggered = false;
  }

  Future<void> _runRecordingGestureAction(
    _RecordingGestureAction action,
  ) async {
    final controller = _controller;

    if (_isRecordingActionInProgress ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (mounted) {
      _setScreenState(() {
        _isRecordingActionInProgress = true;
      });
    } else {
      _isRecordingActionInProgress = true;
    }

    try {
      switch (action) {
        case _RecordingGestureAction.start:
          await _startGestureVideoRecording(controller);
          break;
        case _RecordingGestureAction.togglePause:
          await _toggleGestureVideoPause(controller);
          break;
        case _RecordingGestureAction.stop:
          await _stopGestureVideoRecording(controller);
          break;
      }
    } finally {
      if (mounted) {
        _setScreenState(() {
          _isRecordingActionInProgress = false;
        });
      } else {
        _isRecordingActionInProgress = false;
      }
    }
  }

  Future<void> _startGestureVideoRecording(CameraController controller) async {
    if (controller.value.isRecordingVideo) return;

    try {
      _showRecordingStartingOverlay(controller);

      // Let Flutter paint the loading overlay before the camera switches from
      // image stream mode to video recording mode. This hides the preview jump.
      await _waitForRecordingStartingOverlayToPaint();

      if (!mounted ||
          _controller != controller ||
          !controller.value.isInitialized) {
        return;
      }

      _debugCameraOrientation('before-start-recording', controller: controller);
      await _lockRecordingOrientation(controller);

      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        _isStreaming = false;
      }

      await controller.startVideoRecording(onAvailable: _processCameraImage);
      _isStreaming = true;
      _startRecordingTimer();
      _debugCameraOrientation('after-start-recording', controller: controller);

      // Keep the loading screen for a very short moment after startVideoRecording
      // returns so the first recording preview frame is already stable.
      await _keepRecordingStartingOverlayVisible();

      if (!mounted || _controller != controller) return;

      _setScreenState(() {
        _isStartingVideoRecording = false;
        _gestureText = 'Recording';
        _gestureConfidence = 1;
      });
    } catch (e, st) {
      debugPrint('Video recording start failed: $e\n$st');
      _showSnackBar('Could not start recording.');
      unawaited(_unlockRecordingOrientation(controller));
      _resetRecordingTimer();

      if (mounted && _controller == controller) {
        _setScreenState(() {
          _isStartingVideoRecording = false;
          _isStoppingVideoRecording = false;
          _isRecordingPreviewCorrectionActive = false;
        });
      } else {
        _isStartingVideoRecording = false;
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = false;
      }

      if (mounted && _controller == controller && !_isStreaming) {
        unawaited(_startCameraStream());
      }
    }
  }

  void _showRecordingStartingOverlay(CameraController controller) {
    if (mounted && _controller == controller) {
      _setScreenState(() {
        _isStartingVideoRecording = true;
        _isRecordingPreviewCorrectionActive = true;
        _gestureText = 'Starting video recording...';
        _gestureConfidence = 1;
      });
      return;
    }

    _isStartingVideoRecording = true;
    _isRecordingPreviewCorrectionActive = true;
    _gestureText = 'Starting video recording...';
    _gestureConfidence = 1;
  }

  Future<void> _waitForRecordingStartingOverlayToPaint() async {
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _keepRecordingStartingOverlayVisible() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _showRecordingStoppingOverlay(CameraController controller) {
    if (mounted && _controller == controller) {
      _setScreenState(() {
        _isStoppingVideoRecording = true;
        _isRecordingPreviewCorrectionActive = true;
        _gestureText = 'Stopping video recording...';
        _gestureConfidence = 1;
      });
      return;
    }

    _isStoppingVideoRecording = true;
    _isRecordingPreviewCorrectionActive = true;
    _gestureText = 'Stopping video recording...';
    _gestureConfidence = 1;
  }

  Future<void> _waitForRecordingStoppingOverlayToPaint() async {
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _keepRecordingStoppingOverlayVisible() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _toggleGestureVideoPause(CameraController controller) async {
    if (!controller.value.isRecordingVideo) return;

    try {
      final wasPaused = controller.value.isRecordingPaused;

      if (wasPaused) {
        await controller.resumeVideoRecording();
        _resumeRecordingTimer();
      } else {
        await controller.pauseVideoRecording();
        _pauseRecordingTimer();
      }

      if (!mounted || _controller != controller) return;

      _setScreenState(() {
        _gestureText = wasPaused ? 'Recording resumed' : 'Recording paused';
        _gestureConfidence = 1;
      });

      _showSnackBar(wasPaused ? 'Recording resumed.' : 'Recording paused.');
    } catch (e, st) {
      debugPrint('Video recording pause toggle failed: $e\n$st');
      _showSnackBar('Could not update recording.');
    }
  }

  Future<void> _stopGestureVideoRecording(CameraController controller) async {
    if (!controller.value.isRecordingVideo) return;

    try {
      _showRecordingStoppingOverlay(controller);

      // Let Flutter paint the loading overlay before the camera switches from
      // video recording mode back to image stream gesture detection mode.
      await _waitForRecordingStoppingOverlayToPaint();

      if (!mounted ||
          _controller != controller ||
          !controller.value.isInitialized) {
        _isStoppingVideoRecording = false;
        return;
      }

      final file = await controller.stopVideoRecording();
      _debugCameraOrientation('after-stop-recording', controller: controller);
      await _copyRecordingToDownloads(file);
      await _unlockRecordingOrientation(controller);
      _isStreaming = false;
      _resetRecordingTimer();
      _isStartingVideoRecording = false;

      if (!mounted || _controller != controller) {
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = false;
        return;
      }

      _setScreenState(() {
        _gestureText = 'Recording saved';
        _gestureConfidence = 1;
      });

      _showSnackBar('Recording saved to Download folder');

      // Restart normal gesture detection while the loading layer is still
      // covering the preview, then hide it after the stream has settled.
      await _startCameraStream();
      await _keepRecordingStoppingOverlayVisible();

      if (!mounted || _controller != controller) return;

      _setScreenState(() {
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = false;
        if (_gestureText == 'Recording saved') {
          _gestureText = 'Show your hand';
          _gestureConfidence = 0;
        }
      });
    } catch (e, st) {
      debugPrint('Video recording stop failed: $e\n$st');
      _showSnackBar('Could not stop recording.');

      if (mounted && _controller == controller) {
        _setScreenState(() {
          _isStoppingVideoRecording = false;
          _isRecordingPreviewCorrectionActive =
              controller.value.isRecordingVideo;
        });
      } else {
        _isStoppingVideoRecording = false;
        _isRecordingPreviewCorrectionActive = controller.value.isRecordingVideo;
      }
    }
  }

  Future<void> _lockRecordingOrientation(CameraController controller) async {
    try {
      _debugCameraOrientation(
        'before-lock-orientation',
        controller: controller,
      );
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _debugCameraOrientation('after-lock-orientation', controller: controller);
    } catch (e) {
      debugPrint('Recording orientation lock ignored: $e');
    }
  }

  Future<void> _unlockRecordingOrientation(CameraController controller) async {
    try {
      if (controller.value.isInitialized) {
        _debugCameraOrientation(
          'before-unlock-orientation',
          controller: controller,
        );
        await controller.unlockCaptureOrientation();
        _debugCameraOrientation(
          'after-unlock-orientation',
          controller: controller,
        );
      }
    } catch (e) {
      debugPrint('Recording orientation unlock ignored: $e');
    }
  }

  void _debugCameraOrientation(
    String label, {
    CameraController? controller,
    CameraImage? image,
    CameraFrameRotation? frameRotation,
  }) {
    final activeController = controller ?? _controller;

    if (activeController == null) {
      debugPrint('[CameraOrientation][$label] no controller');
      return;
    }

    final value = activeController.value;
    final previewSize = value.previewSize;
    final previewText = previewSize == null
        ? ''
        : ', preview=${previewSize.width.toStringAsFixed(0)}x'
              '${previewSize.height.toStringAsFixed(0)}, '
              'aspect=${(previewSize.width / previewSize.height).toStringAsFixed(4)}';
    final imageText = image == null
        ? ''
        : ', image=${image.width}x${image.height}';
    final frameRotationText = frameRotation == null
        ? ''
        : ', frameRotation=$frameRotation';

    debugPrint(
      '[CameraOrientation][$label] '
      'device=${value.deviceOrientation}, '
      'locked=${value.lockedCaptureOrientation}, '
      'recording=${value.recordingOrientation}, '
      'isRecording=${value.isRecordingVideo}, '
      'isStreaming=${value.isStreamingImages}, '
      'lens=${activeController.description.lensDirection}, '
      'sensor=${activeController.description.sensorOrientation}'
      '$previewText'
      '$imageText'
      '$frameRotationText',
    );
  }

  Future<XFile> _copyRecordingToDownloads(XFile file) async {
    if (!Platform.isAndroid) return file;

    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final sourceFile = File(file.path);
      if (!await sourceFile.exists()) {
        debugPrint('Recording source file missing: ${file.path}');
        return file;
      }

      final destinationPath =
          '${downloadsDir.path}/smart_stand_recording_'
          '${_recordingFileTimestamp()}${_recordingFileExtension(file.path)}';
      final copiedFile = await sourceFile.copy(destinationPath);
      debugPrint('Recording copied to Downloads: ${copiedFile.path}');

      return XFile(copiedFile.path);
    } catch (e, st) {
      debugPrint('Recording copy to Downloads failed: $e\n$st');
      return file;
    }
  }

  String _recordingFileTimestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  String _recordingFileExtension(String path) {
    final lastSlashIndex = path.lastIndexOf(Platform.pathSeparator);
    final lastDotIndex = path.lastIndexOf('.');

    if (lastDotIndex > lastSlashIndex && lastDotIndex < path.length - 1) {
      return path.substring(lastDotIndex);
    }

    return '.mp4';
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingElapsedBeforePause = Duration.zero;
    _recordingElapsed = Duration.zero;
    _recordingSegmentStartedAt = DateTime.now();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRecordingElapsed();
    });
  }

  void _pauseRecordingTimer() {
    final segmentStartedAt = _recordingSegmentStartedAt;
    if (segmentStartedAt != null) {
      _recordingElapsedBeforePause += DateTime.now().difference(
        segmentStartedAt,
      );
      _recordingElapsed = _recordingElapsedBeforePause;
    }

    _recordingSegmentStartedAt = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _resumeRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingSegmentStartedAt = DateTime.now();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRecordingElapsed();
    });
  }

  void _resetRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingSegmentStartedAt = null;
    _recordingElapsedBeforePause = Duration.zero;
    _recordingElapsed = Duration.zero;
  }

  void _updateRecordingElapsed() {
    final segmentStartedAt = _recordingSegmentStartedAt;
    final elapsed =
        _recordingElapsedBeforePause +
        (segmentStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(segmentStartedAt));

    if (!mounted) {
      _recordingElapsed = elapsed;
      return;
    }

    _setScreenState(() {
      _recordingElapsed = elapsed;
    });
  }

  String get _recordingDurationText {
    final totalSeconds = _recordingElapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Widget _buildRecordingControls(CameraController controller) {
    final isPaused = controller.value.isRecordingPaused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isPaused ? Colors.amberAccent : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _recordingDurationText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          if (cameras.length > 1) ...[
            _recordingIconButton(
              icon: Icons.flip_camera_ios_rounded,
              tooltip: 'Switch camera',
              onPressed: _canSwitchCamera
                  ? () => unawaited(
                      _switchCamera(restartRecordingAfterSwitch: true),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          _recordingControlButton(
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: isPaused ? 'Resume' : 'Pause',
            onPressed: _isRecordingActionInProgress
                ? null
                : () => unawaited(
                    _runRecordingGestureAction(
                      _RecordingGestureAction.togglePause,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          _recordingControlButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            foregroundColor: Colors.white,
            backgroundColor: Colors.redAccent,
            onPressed: _isRecordingActionInProgress
                ? null
                : () => unawaited(
                    _runRecordingGestureAction(_RecordingGestureAction.stop),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _recordingIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color foregroundColor = Colors.white,
    Color backgroundColor = Colors.white12,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 38,
        height: 38,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor,
            disabledBackgroundColor: Colors.white10,
            foregroundColor: foregroundColor,
            disabledForegroundColor: Colors.white38,
            elevation: 0,
            shape: const CircleBorder(),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _recordingControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color foregroundColor = Colors.white,
    Color backgroundColor = Colors.white12,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: backgroundColor,
        disabledBackgroundColor: Colors.white10,
        foregroundColor: foregroundColor,
        disabledForegroundColor: Colors.white38,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
