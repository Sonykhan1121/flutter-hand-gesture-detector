part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
  /// Returns the portrait-oriented preview size used by AspectRatio.
  Size _previewDisplaySize(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Size(9, 16);
    }

    final previewSize = controller.value.previewSize;
    if (previewSize == null ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return const Size(9, 16);
    }

    final rawWidth = previewSize.width;
    final rawHeight = previewSize.height;
    return rawWidth > rawHeight
        ? Size(rawHeight, rawWidth)
        : Size(rawWidth, rawHeight);
  }

  /// Aspect ratio for the visible camera preview container.
  double _previewAspectRatio() {
    final controller = _controller;
    final previewDisplaySize = _previewDisplaySize(controller);
    return previewDisplaySize.width / previewDisplaySize.height;
  }

  /// Builds the camera preview, applying Android recording correction if needed.
  Widget _buildCameraPreview(CameraController controller) {
    if (!Platform.isAndroid) {
      return CameraPreview(controller);
    }

    final previewDisplaySize = _previewDisplaySize(controller);
    final applyRecordingCorrection = _shouldApplyRecordingPreviewCorrection(
      controller,
    );
    final mirrorRecordingPreview =
        applyRecordingCorrection &&
        controller.description.lensDirection == CameraLensDirection.front;
    final preview = controller.buildPreview();

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: _mirrorPreviewIfNeeded(
          mirrorHorizontally: mirrorRecordingPreview,
          child: applyRecordingCorrection
              ? RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: previewDisplaySize.height,
                    height: previewDisplaySize.width,
                    child: preview,
                  ),
                )
              : SizedBox(
                  width: previewDisplaySize.width,
                  height: previewDisplaySize.height,
                  child: preview,
                ),
        ),
      ),
    );
  }

  /// Mirrors a preview widget for front-camera recording correction.
  Widget _mirrorPreviewIfNeeded({
    required bool mirrorHorizontally,
    required Widget child,
  }) {
    if (!mirrorHorizontally) return child;

    return Transform.flip(flipX: true, child: child);
  }

  /// True when overlay coordinates must mirror to match the preview.
  bool _shouldMirrorPreviewCoordinates(CameraController? controller) {
    return controller?.description.lensDirection == CameraLensDirection.front &&
        !Platform.isIOS;
  }

  /// True when movement gestures should use mirrored horizontal coordinates.
  bool _shouldMirrorDirectionalGestureCoordinates(
    CameraController? controller,
  ) {
    // Rear-camera users face the camera, so horizontal commands are reversed
    // compared with the raw image coordinate system.
    if (controller?.description.lensDirection == CameraLensDirection.back) {
      return true;
    }

    return _shouldMirrorPreviewCoordinates(controller);
  }

  /// True when open-palm orientation checks should use mirrored coordinates.
  bool _shouldMirrorPalmGestureCoordinates(CameraController? controller) {
    return _shouldMirrorPreviewCoordinates(controller);
  }

  /// Lets back-camera palm detection retry with the opposite side convention.
  bool _shouldAllowBackCameraPalmFallback(CameraController? controller) {
    return controller?.description.lensDirection == CameraLensDirection.back;
  }

  /// Android recording preview needs correction while recording starts/stops.
  bool _shouldApplyRecordingPreviewCorrection(CameraController controller) {
    return Platform.isAndroid &&
        (_isRecordingPreviewCorrectionActive ||
            controller.value.isRecordingVideo);
  }

  /// Quarter-turns used by overlay painters for the current preview mode.
  int _previewQuarterTurnsForOverlays(CameraController controller) {
    return _shouldApplyRecordingPreviewCorrection(controller) ? 3 : 0;
  }

  /// Full-screen scrim shown while recording mode transitions settle.
  Widget _buildRecordingTransitionScrim({required String message}) {
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FB46)),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the live camera screen, overlays, status panel, and loading state.
  Widget _buildLiveScreen(BuildContext context) {
    final controller = _controller;
    final showFollowTargetDebugOverlay =
        _showFollowTargetDebugOverlay &&
        _lockedFollowTarget == null &&
        _followTargetIdentity == null;
    final followTargetDebugOverlayTargets = showFollowTargetDebugOverlay
        ? <FollowTarget>[
            ..._followObjectCandidateFaces,
            ..._followObjectCandidateObjects,
          ]
        : const <FollowTarget>[];

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
                            _buildCameraPreview(controller),
                            if (_detectionImageSize != null)
                              CustomPaint(
                                painter: _handLandmarkPainterForCurrentMode(
                                  controller,
                                ),
                              ),
                            if (_focusedHandBox != null &&
                                _focusImageSize != null)
                              CustomPaint(
                                painter: HandFocusOverlayPainter(
                                  handBox: _focusedHandBox!,
                                  imageSize: _focusImageSize!,
                                  mirrorHorizontally:
                                      _shouldMirrorPreviewCoordinates(
                                        controller,
                                      ),
                                  previewQuarterTurns:
                                      _previewQuarterTurnsForOverlays(
                                        controller,
                                      ),
                                ),
                              ),
                            if (_lockedFollowTarget != null)
                              CustomPaint(
                                painter: FollowTargetOverlayPainter(
                                  target: _lockedFollowTarget!,
                                ),
                              ),
                            if (followTargetDebugOverlayTargets.isNotEmpty)
                              CustomPaint(
                                painter: FollowTargetDebugOverlayPainter(
                                  targets: followTargetDebugOverlayTargets,
                                  showLabels: false,
                                ),
                              ),
                            if (_shouldShowTouchZoomGuideOverlay)
                              Positioned.fill(
                                child: TouchZoomGuideOverlay(
                                  currentZoomLevel: _currentZoomLevel,
                                  minZoomLevel: _minZoomLevel,
                                  maxZoomLevel: _maxZoomLevel,
                                  onZoomChanged: _handleTouchZoomChanged,
                                  onInteractionStart:
                                      _beginTouchZoomInteraction,
                                  onInteractionEnd: _endTouchZoomInteraction,
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
                                onPressed: _canSwitchCamera
                                    ? () => unawaited(
                                        _switchCamera(
                                          restartRecordingAfterSwitch:
                                              controller.value.isRecordingVideo,
                                        ),
                                      )
                                    : null,
                              )
                            : const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
                if (_followTargetIdentity != null)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 76),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _cancelFollowTarget(promptReselect: false),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Cancel'),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.black54,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _cancelFollowTarget(promptReselect: true),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Reselect'),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.black54,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (controller.value.isRecordingVideo)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 72, 16, 0),
                        child: _buildRecordingControls(controller),
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
                if (_shouldShowZoomControlOverlay)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: ZoomControlOverlay(
                          currentZoomLevel: _currentZoomLevel,
                          minZoomLevel: _minZoomLevel,
                          maxZoomLevel: _maxZoomLevel,
                          onZoomChanged: _handleManualZoomChanged,
                          onZoomIncrease: _handleManualZoomIncrease,
                          onZoomDecrease: _handleManualZoomDecrease,
                          onZoomReset: _resetManualZoom,
                          onInteractionStart: _beginManualZoomInteraction,
                          onInteractionEnd: _endManualZoomInteraction,
                          onClose: _hideZoomControlOverlay,
                        ),
                      ),
                    ),
                  ),
                if (_isStartingVideoRecording || _isStoppingVideoRecording)
                  Positioned.fill(
                    child: _buildRecordingTransitionScrim(
                      message: _isStoppingVideoRecording
                          ? 'Stopping video recording...'
                          : 'Starting video recording...',
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

  /// Chooses the normal or recording-aware landmark painter.
  CustomPainter _handLandmarkPainterForCurrentMode(
    CameraController controller,
  ) {
    final isRecordingPreview =
        controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive;

    if (isRecordingPreview) {
      return RecordingHandLandmarkOverlayPainter(
        hands: _hands,
        imageSize: _detectionImageSize!,
        mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
        recordingQuarterTurns: _previewQuarterTurnsForOverlays(controller),
        showLandmarkIndices: false,
      );
    }

    return HandLandmarkOverlayPainter(
      hands: _hands,
      imageSize: _detectionImageSize!,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
      previewQuarterTurns: _previewQuarterTurnsForOverlays(controller),
    );
  }
}
