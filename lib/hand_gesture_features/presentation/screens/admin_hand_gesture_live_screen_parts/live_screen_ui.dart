part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
  /// Rotates and resizes only the camera pixels inside the fixed upright UI.
  Widget _buildCameraPreview(
    CameraController controller, {
    required Size cardSize,
    required double rotationProgress,
  }) {
    final recordingCorrectionTurns = _recordingPreviewQuarterTurns(controller);

    // CameraPreview applies Android's landscape recording rotation itself, but
    // its portrait recording path leaves this device's raw texture clockwise.
    // Use the proven raw-texture correction only for portrait recording.
    if (recordingCorrectionTurns != 0 && !_cameraPreviewMode.isLandscape) {
      final previewSize = orientedCameraPreviewSize(
        rawPreviewSize: controller.value.previewSize,
        isLandscape: false,
      );
      final correctedPreview = RotatedBox(
        quarterTurns: recordingCorrectionTurns,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: controller.buildPreview(),
        ),
      );

      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child:
              controller.description.lensDirection == CameraLensDirection.front
              ? Transform.flip(flipX: true, child: correctedPreview)
              : correctedPreview,
        ),
      );
    }

    final rotatedSize = Size(cardSize.height, cardSize.width);
    final cameraSize = Size.lerp(
      cardSize,
      rotatedSize,
      rotationProgress.clamp(0.0, 1.0),
    )!;

    return ClipRect(
      child: Center(
        child: Transform.rotate(
          angle: math.pi * 0.5 * rotationProgress,
          child: SizedBox(
            width: cameraSize.width,
            height: cameraSize.height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
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
    // Directions describe what the user sees on screen. Apply only the same
    // horizontal correction used to align detector coordinates to the preview.
    return _shouldMirrorPreviewCoordinates(controller);
  }

  /// True when palm-facing chirality must be normalized for the detector.
  ///
  /// Do not reuse preview mirroring here. iOS mirrors its front preview
  /// natively, so the overlay needs no flip, while the landmark/handedness
  /// convention still requires the same front-camera palm-side flip as Android.
  bool _shouldMirrorPalmGestureCoordinates(CameraController? controller) {
    return shouldMirrorPalmOrientationCoordinates(
      controller?.description.lensDirection,
    );
  }

  /// Lets back-camera palm detection retry with the opposite side convention.
  bool _shouldAllowBackCameraPalmFallback(CameraController? controller) {
    return controller?.description.lensDirection == CameraLensDirection.back;
  }

  /// Native landscape recording is already rotated by CameraPreview itself.
  double _cameraVisualRotationProgress(CameraController controller) {
    if (controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive) {
      return 0;
    }
    return _cameraPreviewRotationController.value;
  }

  /// Returns the recording-only camera/overlay correction for this platform.
  int _recordingPreviewQuarterTurns(CameraController controller) {
    return recordingCameraPreviewQuarterTurns(
      isAndroid: Platform.isAndroid,
      isRecordingPreview:
          controller.value.isRecordingVideo ||
          _isRecordingPreviewCorrectionActive,
    );
  }

  /// Rotates only painter output; detector-space coordinates remain unchanged.
  int _previewQuarterTurnsForOverlays(CameraController controller) {
    final recordingTurns = _recordingPreviewQuarterTurns(controller);
    if (recordingTurns != 0) return recordingTurns;
    return cameraPreviewQuarterTurns(_cameraVisualRotationProgress(controller));
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
    final showClosedFistTargetCandidate =
        _followTargetProgress.phase == FollowTargetTrackingPhase.selecting;
    final nearestClosedFistTarget = showClosedFistTargetCandidate
        ? _predictedFollowTarget
        : null;
    final otherClosedFistFaceTargets = showClosedFistTargetCandidate
        ? _followObjectCandidateFaces
              .where((target) => !identical(target, nearestClosedFistTarget))
              .toList(growable: false)
        : const <FollowTarget>[];
    final otherClosedFistObjectTargets = showClosedFistTargetCandidate
        ? _followObjectCandidateObjects
              .where((target) => !identical(target, nearestClosedFistTarget))
              .toList(growable: false)
        : const <FollowTarget>[];
    final closedFistTargetCandidates = nearestClosedFistTarget != null
        ? <FollowTarget>[nearestClosedFistTarget]
        : const <FollowTarget>[];
    final closedFistFaceCandidates = closedFistTargetCandidates
        .where((target) => target.type == FollowTargetType.face)
        .toList(growable: false);
    final closedFistObjectCandidates = closedFistTargetCandidates
        .where((target) => target.type == FollowTargetType.object)
        .toList(growable: false);
    final selectionCandidateColor = _followTargetPointingDwell.isFrozen
        ? followTargetSelectionGreen
        : const Color(0xFFFFB020);
    final selectionCandidateLabelPrefix = _followTargetSelectionCandidateHidden
        ? 'Last seen: '
        : _followTargetPointingDwell.isFrozen
        ? 'Open palm → '
        : 'Hold ${(_followPointingHoldProgress * 100).round()}% → ';
    final showFollowTargetDebugOverlay =
        _showFollowTargetDebugOverlay &&
        !showClosedFistTargetCandidate &&
        _lockedFollowTarget == null &&
        _followTargetIdentity == null;
    final followTargetDebugFaceTargets = showFollowTargetDebugOverlay
        ? _followObjectCandidateFaces
        : const <FollowTarget>[];
    final followTargetDebugObjectTargets = showFollowTargetDebugOverlay
        ? _visualObjectTargets
        : const <FollowTarget>[];
    final showSelectedDebugPainter = !_isGestureDebugMenuOpen;
    final showFollowObjectCenters =
        showSelectedDebugPainter &&
        _gestureDebugMode == GestureDebugMode.followObject;
    final punchCircleDebugHand =
        showSelectedDebugPainter && _gestureDebugMode == GestureDebugMode.punch
        ? _reliableHandWithPoint10ForCircleDebug()
        : null;
    final faceReacquisitionNow = DateTime.now();
    final showFaceReacquisitionCountdown =
        _followTargetProgress.phase ==
        FollowTargetTrackingPhase.temporarilyLost;
    final showFaceReacquisitionExpiredNotice = _detectMyFaceReacquisition
        .shouldShowExpiredNotice(faceReacquisitionNow);

    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _isCameraInitialized &&
              controller != null &&
              controller.value.isInitialized
          ? Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _cameraPreviewRotationController,
                    builder: (context, _) {
                      final animationProgress =
                          _cameraPreviewRotationController.value;
                      final visualRotationProgress =
                          _cameraVisualRotationProgress(controller);
                      final overlayQuarterTurns =
                          _previewQuarterTurnsForOverlays(controller);
                      final overlayOpacity = cameraOverlayOpacity(
                        animationProgress,
                      );

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final viewportSize = constraints.biggest;
                          final cardSize = interpolatedCameraPreviewSize(
                            viewportSize: viewportSize,
                            rawPreviewSize: controller.value.previewSize,
                            progress: animationProgress,
                          );

                          return Center(
                            child: SizedBox(
                              key: const Key('cameraPreviewCard'),
                              width: cardSize.width,
                              height: cardSize.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildCameraPreview(
                                        controller,
                                        cardSize: cardSize,
                                        rotationProgress:
                                            visualRotationProgress,
                                      ),
                                      Opacity(
                                        opacity: overlayOpacity,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (!_isGestureDebugMenuOpen &&
                                                _detectionImageSize != null)
                                              CustomPaint(
                                                key: const Key(
                                                  'handLandmarkOverlay',
                                                ),
                                                painter:
                                                    _handLandmarkPainterForCurrentMode(
                                                      controller,
                                                    ),
                                              ),
                                            if (_followPointingCursor != null)
                                              CustomPaint(
                                                key: const Key(
                                                  'followPointingCursor',
                                                ),
                                                painter:
                                                    FollowPointingCursorPainter(
                                                      realIndexTip:
                                                          _followPointingCursor!
                                                              .realIndexTip,
                                                      projectedPoint:
                                                          _followPointingCursor!
                                                              .visiblePoint,
                                                      progress:
                                                          _followPointingHoldProgress,
                                                      isInFrame:
                                                          _followPointingCursor!
                                                              .isInFrame,
                                                      previewQuarterTurns:
                                                          overlayQuarterTurns,
                                                    ),
                                              ),
                                            if (showSelectedDebugPainter &&
                                                _gestureDebugMode ==
                                                    GestureDebugMode
                                                        .direction &&
                                                _detectionImageSize != null)
                                              CustomPaint(
                                                painter:
                                                    _directionDebugPainterForCurrentMode(
                                                      controller,
                                                    ),
                                              ),
                                            if (punchCircleDebugHand != null &&
                                                _detectionImageSize != null)
                                              CustomPaint(
                                                painter:
                                                    _punchCircleDebugPainterForCurrentMode(
                                                      controller,
                                                      punchCircleDebugHand,
                                                    ),
                                              ),
                                            if (showSelectedDebugPainter &&
                                                _gestureDebugMode ==
                                                    GestureDebugMode.zoomIn &&
                                                _detectionImageSize != null)
                                              CustomPaint(
                                                painter:
                                                    _zoomInDebugPainterForCurrentMode(
                                                      controller,
                                                    ),
                                              ),
                                            if (showSelectedDebugPainter &&
                                                _usesFamilyDebugPainter(
                                                  _gestureDebugMode,
                                                ) &&
                                                _detectionImageSize != null)
                                              CustomPaint(
                                                painter:
                                                    _gestureFamilyDebugPainterForCurrentMode(
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
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (_lockedFollowTarget != null)
                                              CustomPaint(
                                                painter: FollowTargetOverlayPainter(
                                                  target: _lockedFollowTarget!,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                  colorOverride:
                                                      _followTargetIdentity !=
                                                          null
                                                      ? followTargetSelectionGreen
                                                      : null,
                                                  showCenter:
                                                      showFollowObjectCenters,
                                                ),
                                              ),
                                            if (_showObjectOpticalFlowDebugOverlay &&
                                                _objectOpticalFlowResult !=
                                                    null)
                                              CustomPaint(
                                                painter:
                                                    ObjectOpticalFlowDebugPainter(
                                                      result:
                                                          _objectOpticalFlowResult!,
                                                      previewQuarterTurns:
                                                          overlayQuarterTurns,
                                                    ),
                                              ),
                                            if (otherClosedFistFaceTargets
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainter(
                                                  targets:
                                                      otherClosedFistFaceTargets,
                                                  showLabels: true,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (otherClosedFistObjectTargets
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainterFactory.create(
                                                  backend: widget
                                                      .objectDetectionBackend,
                                                  targets:
                                                      otherClosedFistObjectTargets,
                                                  showLabels: true,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (closedFistFaceCandidates
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainter(
                                                  targets:
                                                      closedFistFaceCandidates,
                                                  showLabels: true,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  color:
                                                      selectionCandidateColor,
                                                  labelPrefix:
                                                      selectionCandidateLabelPrefix,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (closedFistObjectCandidates
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainterFactory.create(
                                                  backend: widget
                                                      .objectDetectionBackend,
                                                  targets:
                                                      closedFistObjectCandidates,
                                                  showLabels: true,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  color:
                                                      selectionCandidateColor,
                                                  labelPrefix:
                                                      selectionCandidateLabelPrefix,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (followTargetDebugFaceTargets
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainter(
                                                  targets:
                                                      followTargetDebugFaceTargets,
                                                  showLabels: false,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                            if (followTargetDebugObjectTargets
                                                .isNotEmpty)
                                              CustomPaint(
                                                painter: ObjectDetectionDebugPainterFactory.create(
                                                  backend: widget
                                                      .objectDetectionBackend,
                                                  targets:
                                                      followTargetDebugObjectTargets,
                                                  showLabels: false,
                                                  showCenters:
                                                      showFollowObjectCenters,
                                                  previewQuarterTurns:
                                                      overlayQuarterTurns,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (_isGestureDebugMenuOpen &&
                                          _detectionImageSize != null)
                                        GestureDebugSelectorOverlay(
                                          selectedMode: _gestureDebugMode,
                                          indexTip: _gestureDebugMenuIndexTip(),
                                          detectionImageSize:
                                              _detectionImageSize!,
                                          mirrorHorizontally:
                                              _shouldMirrorPreviewCoordinates(
                                                controller,
                                              ),
                                          previewQuarterTurns:
                                              overlayQuarterTurns,
                                          useRecordingPreviewMapping:
                                              controller
                                                  .value
                                                  .isRecordingVideo ||
                                              _isRecordingPreviewCorrectionActive,
                                          onModeSelected:
                                              _selectGestureDebugMode,
                                          onCancel: _cancelGestureDebugMenu,
                                          onExitDetection: () =>
                                              Navigator.pop(context),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_shouldShowTouchZoomGuideOverlay)
                  Positioned.fill(
                    child: TouchZoomGuideOverlay(
                      currentZoomLevel: _currentZoomLevel,
                      minZoomLevel: _minZoomLevel,
                      maxZoomLevel: _maxZoomLevel,
                      onZoomChanged: _handleTouchZoomChanged,
                      onInteractionStart: _beginTouchZoomInteraction,
                      onInteractionEnd: _endTouchZoomInteraction,
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RoundIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Back',
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Show Your Hand',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          RoundIconButton(
                            key: const Key('rotateCameraPreviewButton'),
                            icon: Icons.screen_rotation,
                            tooltip: _cameraPreviewMode.isLandscape
                                ? 'Use portrait 9:16'
                                : 'Use landscape 16:9',
                            onPressed: _canRotateCameraPreview
                                ? _toggleCameraPreviewOrientation
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _availableCameras.length > 1
                              ? RoundIconButton(
                                  icon: Icons.flip_camera_ios,
                                  tooltip: 'Switch camera',
                                  onPressed: _canSwitchCamera
                                      ? () => unawaited(
                                          _switchCamera(
                                            restartRecordingAfterSwitch:
                                                controller
                                                    .value
                                                    .isRecordingVideo,
                                          ),
                                        )
                                      : null,
                                )
                              : const SizedBox(width: 40),
                        ],
                      ),
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
                if (showFaceReacquisitionCountdown ||
                    showFaceReacquisitionExpiredNotice)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 128),
                        child: showFaceReacquisitionCountdown
                            ? FaceReacquisitionStatusOverlay.waiting(
                                remaining: _detectMyFaceReacquisition.remaining(
                                  faceReacquisitionNow,
                                ),
                              )
                            : const FaceReacquisitionStatusOverlay.timedOut(),
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
                if (!_isGestureDebugMenuOpen)
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

  /// Chooses the normal or recording-aware always-on 21-point hand painter.
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

  /// Maps the direction guides and index axis onto the current preview mode.
  CustomPainter _directionDebugPainterForCurrentMode(
    CameraController controller,
  ) {
    final isRecordingPreview =
        controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive;

    return DirectionDebugOverlayPainter(
      hand: _handGeometry.bestReliableHand(_hands),
      imageSize: _detectionImageSize!,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
      candidateDirection: _directionGestureDetector.debugCandidateDirection,
      acceptedDirection: _directionGestureDetector.debugAcceptedDirection,
      debugSummary: _directionGestureDetector.debugSummary,
      showPalmCircle: true,
      previewQuarterTurns: _previewQuarterTurnsForOverlays(controller),
      useRecordingPreviewMapping: isRecordingPreview,
    );
  }

  Hand? _reliableHandWithPoint10ForCircleDebug() {
    final hand = _handGeometry.bestReliableHand(_hands);
    if (hand == null ||
        _handGeometry.visibleLandmark(hand, HandLandmarkType.middleFingerPIP) ==
            null) {
      return null;
    }
    return hand;
  }

  Offset? _gestureDebugMenuIndexTip() {
    final hand = _handGeometry.bestReliableHand(_hands);
    final tip = hand == null
        ? null
        : _handGeometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    return tip == null ? null : Offset(tip.x, tip.y);
  }

  /// Draws only the temporary point-10 circle while full debug paint is off.
  CustomPainter _punchCircleDebugPainterForCurrentMode(
    CameraController controller,
    Hand hand,
  ) {
    final isRecordingPreview =
        controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive;

    return DirectionDebugOverlayPainter(
      hand: hand,
      imageSize: _detectionImageSize!,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
      candidateDirection: HandMoveDirection.none,
      acceptedDirection: HandMoveDirection.none,
      debugSummary: '',
      showPalmCircle: false,
      showPunchCircle: true,
      showDirectionDrawing: false,
      punchConfirmationEnabled: !_isVideoRecording,
      punchConfirmationFrameCount: _customGestureDetector.punchSteadyFrameCount,
      previewQuarterTurns: _previewQuarterTurnsForOverlays(controller),
      useRecordingPreviewMapping: isRecordingPreview,
    );
  }

  /// Maps the Zoom In-only debug rays onto the current preview mode.
  CustomPainter _zoomInDebugPainterForCurrentMode(CameraController controller) {
    final isRecordingPreview =
        controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive;

    return ZoomInDebugOverlayPainter(
      hand: _handGeometry.bestReliableHand(_hands),
      imageSize: _detectionImageSize!,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
      previewQuarterTurns: _previewQuarterTurnsForOverlays(controller),
      useRecordingPreviewMapping: isRecordingPreview,
    );
  }

  bool _usesFamilyDebugPainter(GestureDebugMode mode) {
    return mode == GestureDebugMode.zoomIn ||
        mode == GestureDebugMode.zoomOut ||
        mode == GestureDebugMode.returnMain ||
        mode == GestureDebugMode.recording ||
        mode == GestureDebugMode.callMe ||
        mode == GestureDebugMode.followObject;
  }

  CustomPainter _gestureFamilyDebugPainterForCurrentMode(
    CameraController controller,
  ) {
    final now = DateTime.now();
    final isRecordingPreview =
        controller.value.isRecordingVideo ||
        _isRecordingPreviewCorrectionActive;
    final hand = _handGeometry.bestReliableHand(_hands);
    final evaluation = _gestureDebugEvaluator.evaluate(
      mode: _gestureDebugMode,
      hand: hand,
      imageSize: _detectionImageSize!,
      mirrorPalmHorizontally: _shouldMirrorPalmGestureCoordinates(controller),
      mirrorScreenHorizontally: _shouldMirrorDirectionalGestureCoordinates(
        controller,
      ),
      customResult: _customGestureDetector.debugLastResult,
      returnMainHoldProgress: _customGestureDetector.returnToMainHoldProgress(
        now,
      ),
      pendingZoomDirection: _zoomGestureDetector.pendingDirection,
      zoomHoldProgress: _zoomGestureDetector.debugHoldProgress(now),
      zoomPalmStable: _zoomGestureDetector.debugPalmStable,
      zoomStableFingers: _zoomGestureDetector.debugStableFingers,
      isRecording: _isVideoRecording,
      isRecordingPaused: _isVideoRecordingPaused,
      recordingActionLabel: _recordingDebugActionLabel(),
      recordingHoldProgress: _recordingDebugHoldProgress(now),
      callMeHoldProgress: _callMeDebugHoldProgress(now),
      followPhase: _followObjectSequenceDetector.debugPhase,
      followOpenPalm: _followObjectSequenceDetector.debugOpenPalm,
      followClosedFist: _followObjectSequenceDetector.debugClosedFist,
      followRelaxedReleaseFrames:
          _followObjectSequenceDetector.debugRelaxedReleaseFrames,
      followFirstOpenHoldProgress: _followObjectSequenceDetector
          .debugFirstOpenHoldProgress(now),
      followHandReturnProgress: _followObjectSequenceDetector
          .debugHandReturnProgress(now),
      followIndexOnly: _followObjectSequenceDetector.debugIndexOnly,
      followPointHoldProgress: _followPointingHoldProgress,
      followFinalPalmProgress: _followObjectSequenceDetector
          .debugFinalPalmProgress(now),
    );

    return GestureFamilyDebugOverlayPainter(
      mode: _gestureDebugMode,
      hand: hand,
      imageSize: _detectionImageSize!,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
      evaluation: evaluation,
      previewQuarterTurns: _previewQuarterTurnsForOverlays(controller),
      useRecordingPreviewMapping: isRecordingPreview,
    );
  }

  String _recordingDebugActionLabel() {
    final action = _activeRecordingGestureAction;
    if (action == null) return '';
    return switch (action) {
      _RecordingGestureAction.start => 'Start recording action pending',
      _RecordingGestureAction.togglePause =>
        _isVideoRecordingPaused
            ? 'Resume recording action pending'
            : 'Pause recording action pending',
      _RecordingGestureAction.stop => 'Stop recording action pending',
    };
  }

  double _recordingDebugHoldProgress(DateTime now) {
    final action = _activeRecordingGestureAction;
    final startedAt = _recordingGestureStartedAt;
    if (action == null || startedAt == null || now.isBefore(startedAt)) {
      return 0;
    }
    return (now.difference(startedAt).inMilliseconds /
            _recordingHoldDuration(action).inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _callMeDebugHoldProgress(DateTime now) {
    final startedAt = _faceDetectGestureStartedAt;
    if (startedAt == null || now.isBefore(startedAt)) return 0;
    return (now.difference(startedAt).inMilliseconds /
            HandGestureThresholds.faceDetectHoldDuration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
