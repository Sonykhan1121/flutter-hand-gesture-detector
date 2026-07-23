part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
  /// Receives camera frames, throttles them, and starts gesture processing.
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
        now.difference(lastFrameProcessedAt) <
            HandGestureThresholds.minFrameProcessInterval) {
      return;
    }

    _lastFrameProcessedAt = now;
    _isProcessing = true;

    try {
      final rotation = _cameraFrameRotation(image);
      _observeCameraFrameRotation(rotation);
      final frameId = ++_cameraFrameId;
      final needsObjectTrackingFrame =
          _followObjectSequenceDetector.isTargetSelectionActive ||
          _followTargetProgress.phase == FollowTargetTrackingPhase.selecting ||
          _lockedFollowTarget?.type == FollowTargetType.object ||
          _followTargetIdentity?.type == FollowTargetType.object;
      final ObjectTrackingFrame? objectTrackingFrame = needsObjectTrackingFrame
          ? _objectTrackingFrameFactory.create(
              image: image,
              frameId: frameId,
              capturedAt: now,
              rotation: rotation,
              mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
              isBgra: Platform.isIOS || Platform.isMacOS,
              maxDimension: Platform.isIOS
                  ? HandGestureThresholds.iosObjectTrackingMaxDimension
                  : HandGestureThresholds.objectTrackingMaxDimension,
              useFastBgraLuma: Platform.isIOS,
            )
          : null;

      final detectionImageSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );

      final hands = await _detectHandsFromCameraImage(
        detector: detector,
        image: image,
        rotation: rotation,
      );

      if (!mounted) return;

      await _updateGestureState(
        hands,
        detectionImageSize,
        image: image,
        rotation: rotation,
        objectTrackingFrame: objectTrackingFrame,
      );
      _publishAppPointer(hands, detectionImageSize);
    } catch (error, stackTrace) {
      debugPrint('Hand gesture detection error: $error\n$stackTrace');
      widget.appPointerController?.clearExternalPointer(_appPointerOwner);
    } finally {
      _isProcessing = false;
    }
  }

  /// Publishes index fingertip point 8 to the app-wide dwell cursor.
  void _publishAppPointer(List<Hand> hands, Size detectionImageSize) {
    final appPointerController = widget.appPointerController;
    final cameraController = _controller;
    if (appPointerController == null || cameraController == null) return;

    final hand = _handGeometry.bestReliableHand(hands);
    final tip = _isGestureDebugMenuOpen || hand == null
        ? null
        : _handGeometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    appPointerController.updateExternalPointer(
      owner: _appPointerOwner,
      indexTip: tip == null ? null : Offset(tip.x, tip.y),
      detectionImageSize: detectionImageSize,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(cameraController),
      previewQuarterTurns: _previewQuarterTurnsForOverlays(cameraController),
      showCursor: _gestureDebugMode != GestureDebugMode.off,
    );
  }

  /// Runs the hand detector with the platform-specific camera frame format.
  Future<List<Hand>> _detectHandsFromCameraImage({
    required HandDetector detector,
    required CameraImage image,
    required CameraFrameRotation? rotation,
  }) {
    if (Platform.isIOS && image.planes.length == 1) {
      final plane = image.planes.first;
      final strideCols = plane.bytesPerRow ~/ 4;
      if (strideCols <= 0) return Future.value(const <Hand>[]);

      return detector.detectFromCameraFrame(
        CameraFrame(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          strideCols: strideCols,
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

  /// Calculates the rotation that makes detector coordinates match the preview.
  CameraFrameRotation? _cameraFrameRotation(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;

    if (!(Platform.isAndroid || Platform.isIOS)) return null;

    final rotation = rotationForFrame(
      width: image.width,
      height: image.height,
      sensorOrientation: controller.description.sensorOrientation,
      isFrontCamera:
          controller.description.lensDirection == CameraLensDirection.front,
      deviceOrientation:
          controller.value.recordingOrientation ??
          controller.value.lockedCaptureOrientation ??
          controller.value.deviceOrientation,
    );

    if (controller.value.isRecordingVideo) {
      final now = DateTime.now();
      final lastPrintedAt = _lastOrientationDebugPrintedAt;

      if (lastPrintedAt == null ||
          now.difference(lastPrintedAt) >= const Duration(seconds: 1)) {
        _lastOrientationDebugPrintedAt = now;
        _debugCameraOrientation(
          'recording-frame',
          controller: controller,
          image: image,
          frameRotation: rotation,
        );
      }
    }

    return rotation;
  }

  /// Drops old-orientation boxes when the user physically rotates the device.
  void _observeCameraFrameRotation(CameraFrameRotation? rotation) {
    if (_hasCameraFrameRotation && _lastCameraFrameRotation != rotation) {
      _resetForCameraOrientationChange();
    }
    _lastCameraFrameRotation = rotation;
    _hasCameraFrameRotation = true;
  }

  /// Applies gesture priority and updates all live-screen gesture UI state.
  Future<void> _updateGestureState(
    List<Hand> hands,
    Size detectionImageSize, {
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    final now = DateTime.now();
    if (_isGestureDebugMenuOpen) {
      _updateOpenGestureDebugMenuFrame(
        hands: hands,
        detectionImageSize: detectionImageSize,
      );
      return;
    }

    final trackedFollowTarget = await _refreshLockedFollowTarget(
      image: image,
      rotation: rotation,
      now: now,
      objectTrackingFrame: objectTrackingFrame,
    );
    if (!mounted) return;

    // Gesture priority from here down:
    // 1. release/clear follow target when no reliable hand exists
    // 2. return-to-main and face-detect holds
    // 3. follow-object target selection
    // 4. recording gestures
    // 5. one-index movement directions
    // 6. zoom gestures and remaining package labels.
    if (hands.isEmpty) {
      final followObjectRelease =
          await _releaseFollowObjectFromLastVisiblePoint(
            image: image,
            rotation: rotation,
            detectionImageSize: detectionImageSize,
            now: now,
            objectTrackingFrame: objectTrackingFrame,
          );
      if (!mounted) return;

      if (followObjectRelease != null) {
        if (followObjectRelease.isWaitingForHandReturn) {
          _clearFrameInterruptedGestureState(keepFollowObjectSequence: true);
          _setScreenState(() {
            _gestureText = _handReturnGraceText(
              followObjectRelease.handReturnProgress,
            );
            _handText = '';
            _gestureConfidence = 1 - followObjectRelease.handReturnProgress;
            _detectedHandsCount = 0;
            _hands = const [];
            _detectionImageSize = detectionImageSize;
            _isFollowingHand = false;
            _focusedHandBox = null;
            _focusImageSize = null;
            _lockedFollowTarget = null;
          });
          return;
        }
        final selectedTarget = followObjectRelease.target;
        _clearFrameInterruptedGestureState(keepFollowObjectSequence: true);

        _setScreenState(() {
          _gestureText = selectedTarget == null
              ? followObjectRelease.cancellationReason ??
                    'Follow target selection cancelled'
              : _followTargetText(selectedTarget);
          _handText = '';
          _gestureConfidence = selectedTarget == null ? 0 : 1;
          _detectedHandsCount = 0;
          _hands = const [];
          _detectionImageSize = detectionImageSize;
          _isFollowingHand = false;
          _focusedHandBox = null;
          _focusImageSize = null;
          _lockedFollowTarget = selectedTarget;
        });
        return;
      }

      _clearFrameInterruptedGestureState();
      _clearFollowObjectTargetCandidates();

      _setScreenState(() {
        _gestureText = _followTargetStatusText(
          visibleTarget: trackedFollowTarget,
          fallbackText: 'No hand detected',
        );
        _handText = '';
        _gestureConfidence = trackedFollowTarget == null ? 0 : 1;
        _detectedHandsCount = 0;
        _hands = const [];
        _detectionImageSize = detectionImageSize;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = trackedFollowTarget;
      });
      return;
    }

    final reliableHands = _handGeometry.reliableHands(hands);
    final mirrorDirectionalGestureCoordinates =
        _shouldMirrorDirectionalGestureCoordinates(_controller);
    final mirrorPalmGestureCoordinates = _shouldMirrorPalmGestureCoordinates(
      _controller,
    );
    final allowBackCameraPalmFallback = _shouldAllowBackCameraPalmFallback(
      _controller,
    );

    if (reliableHands.isEmpty) {
      final followObjectRelease =
          await _releaseFollowObjectFromLastVisiblePoint(
            image: image,
            rotation: rotation,
            detectionImageSize: detectionImageSize,
            now: now,
            objectTrackingFrame: objectTrackingFrame,
          );
      if (!mounted) return;

      if (followObjectRelease != null) {
        if (followObjectRelease.isWaitingForHandReturn) {
          _clearFrameInterruptedGestureState(keepFollowObjectSequence: true);
          _setScreenState(() {
            _hands = hands;
            _detectionImageSize = detectionImageSize;
            _detectedHandsCount = hands.length;
            _handText = '';
            _gestureText = _handReturnGraceText(
              followObjectRelease.handReturnProgress,
            );
            _gestureConfidence = 1 - followObjectRelease.handReturnProgress;
            _isFollowingHand = false;
            _focusedHandBox = null;
            _focusImageSize = null;
            _lockedFollowTarget = null;
          });
          return;
        }
        final selectedTarget = followObjectRelease.target;
        _clearFrameInterruptedGestureState(keepFollowObjectSequence: true);

        _setScreenState(() {
          _hands = hands;
          _detectionImageSize = detectionImageSize;
          _detectedHandsCount = hands.length;
          _handText = '';
          _gestureText = selectedTarget == null
              ? followObjectRelease.cancellationReason ??
                    'Follow target selection cancelled'
              : _followTargetText(selectedTarget);
          _gestureConfidence = selectedTarget == null ? 0 : 1;
          _isFollowingHand = false;
          _focusedHandBox = null;
          _focusImageSize = null;
          _lockedFollowTarget = selectedTarget;
        });
        return;
      }

      _clearFrameInterruptedGestureState();
      _clearFollowObjectTargetCandidates();

      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _detectedHandsCount = hands.length;
        _handText = '';
        _gestureText = _followTargetStatusText(
          visibleTarget: trackedFollowTarget,
          fallbackText: 'Move hand closer',
        );
        _gestureConfidence = trackedFollowTarget == null ? 0 : 1;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = trackedFollowTarget;
      });
      return;
    }

    final bestHand = _handGeometry.bestReliableHand(
      reliableHands,
      focusedHandBox:
          _isFollowingHand &&
              trackedFollowTarget == null &&
              _followTargetIdentity == null
          ? _focusedHandBox
          : null,
    )!;
    final gesture = bestHand.gesture;
    final reliablePackageGesture =
        _handGeometry.isReliablePackageGesture(gesture) ? gesture : null;
    _updateGestureDebugMenuTrigger(
      isLoveYou: reliablePackageGesture?.type == GestureType.iLoveYou,
    );
    if (_isGestureDebugMenuOpen) {
      _updateOpenGestureDebugMenuFrame(
        hands: hands,
        detectionImageSize: detectionImageSize,
      );
      return;
    }

    final rawCustomGestureResult = _customGestureDetector.detect(
      hand: bestHand,
      imageSize: detectionImageSize,
      mirrorHorizontally: mirrorDirectionalGestureCoordinates,
      requirePunchConfirmation: !_isVideoRecording,
    );
    final punchCircleCandidate = _handGeometry.matchesPunchMiddleFingerCircle(
      bestHand,
    );

    if (rawCustomGestureResult.isOnlyCancelEverything) {
      _clearAllActiveGestureTasks(resetCameraZoom: true);

      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = null;
        _detectedHandsCount = hands.length;
        _handText = bestHand.handedness.displayLabel;
        _gestureText = 'Return to main position';
        _gestureConfidence = 1;
      });
      return;
    }

    if (rawCustomGestureResult.isOnlyCallMe &&
        trackedFollowTarget == null &&
        _followTargetIdentity == null) {
      final startedAt = _faceDetectGestureStartedAt ?? now;
      _faceDetectGestureStartedAt = startedAt;

      final holdProgress =
          (now.difference(startedAt).inMilliseconds /
                  HandGestureThresholds.faceDetectHoldDuration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();

      if (holdProgress < 1) {
        _zoomGestureDetector.clearState();
        _directionGestureDetector.clearState();
        _followObjectSequenceDetector.clear();
        _clearFollowObjectTargetCandidates();
        _clearRecordingGestureHold();

        _setScreenState(() {
          _hands = hands;
          _detectionImageSize = detectionImageSize;
          _isFollowingHand = false;
          _focusedHandBox = null;
          _focusImageSize = null;
          _lockedFollowTarget = trackedFollowTarget;
          _detectedHandsCount = hands.length;
          _handText = bestHand.handedness.displayLabel;
          _gestureText = 'Hold call to detect face';
          _gestureConfidence = holdProgress;
        });
        return;
      }

      final faceTarget = await _selectBestFaceTarget(
        image: image,
        rotation: rotation,
        now: now,
      );
      if (!mounted) return;

      _clearAllActiveGestureTasks(resetCameraZoom: false);

      if (faceTarget != null) {
        _setLockedFollowTarget(faceTarget, captureIdentity: true);
        _detectMyFaceReacquisition.start();
        unawaited(_updateCameraFocusPointForTarget(faceTarget));
      }

      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = faceTarget;
        _detectedHandsCount = hands.length;
        _handText = bestHand.handedness.displayLabel;
        _gestureText = faceTarget == null
            ? 'No face detected'
            : _followTargetText(faceTarget);
        _gestureConfidence = faceTarget == null ? 0 : 1;
      });
      return;
    }

    _clearFaceDetectGestureHold();

    final followObjectSequence = _followObjectSequenceDetector.update(
      bestHand,
      now,
      mirrorHorizontally: mirrorPalmGestureCoordinates,
      allowOppositePalmSide: allowBackCameraPalmFallback,
    );

    if (followObjectSequence.wasCancelled) {
      _resetFollowPointingSelection(
        FollowTargetPointingResetReason.confirmationExpired,
      );
      _clearFollowObjectTargetCandidates();
      _followTargetProgress.reset();
      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _detectedHandsCount = hands.length;
        _handText = bestHand.handedness.displayLabel;
        _gestureText =
            followObjectSequence.cancellationReason ??
            'Follow target selection cancelled';
        _gestureConfidence = 0;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = null;
      });
      return;
    }

    if (followObjectSequence.isWaitingForHandReturn) {
      if (!_followTargetPointingDwell.isFrozen) {
        _resetFollowPointingSelection(FollowTargetPointingResetReason.poseLost);
      }
      _clearFrameInterruptedGestureState(keepFollowObjectSequence: true);
      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _detectedHandsCount = hands.length;
        _handText = bestHand.handedness.displayLabel;
        _gestureText = _handReturnGraceText(
          followObjectSequence.handReturnProgress,
        );
        _gestureConfidence = 1 - followObjectSequence.handReturnProgress;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = null;
      });
      return;
    }

    var lockedFollowTarget = trackedFollowTarget;
    if (followObjectSequence.isTargetSelectionActive) {
      if (_followTargetProgress.phase != FollowTargetTrackingPhase.selecting) {
        _clearLockedFollowTarget(clearIdentity: true);
        _clearFollowObjectTargetCandidates();
        _followTargetSelectionFailureUntil = null;
        _followTargetProgress.markSelecting();
      }
      lockedFollowTarget = null;
    }
    var releaseHadNoTarget = false;
    if (followObjectSequence.isFinalPalmConfirmation) {
      final detections = await _refreshFollowObjectTargetCandidates(
        image: image,
        rotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
      if (!mounted) return;
      final confirmedTarget = _resolveFrozenPointingTarget(
        detections: detections,
        now: now,
      );
      if (confirmedTarget == null) {
        lockedFollowTarget = null;
        releaseHadNoTarget = true;
        _followPointingStatus = 'Target is no longer uniquely available';
        _clearLockedFollowTarget(clearIdentity: true);
        _resetFollowPointingSelection(
          FollowTargetPointingResetReason.targetUnavailable,
        );
        _clearFollowObjectTargetCandidates();
      } else {
        lockedFollowTarget = _applyFollowTargetReleaseSelection(
          _FollowTargetReleaseSelection(
            target: confirmedTarget,
            requiresPostReleaseConfirmation: false,
            evaluatedDetectionCycleAt: confirmedTarget.detectedAt,
          ),
          now: now,
        );
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _resetFollowPointingSelection(FollowTargetPointingResetReason.none);
        _clearFollowObjectTargetCandidates();
      }
    } else if (followObjectSequence.isTargetSelectionActive) {
      final handBox = bestHand.boundingBox;
      final handDisplayBox = _handBoxToDisplayBox(handBox, detectionImageSize);
      _followSelectionHandDisplayBox = handDisplayBox;
      final detections = await _refreshFollowObjectTargetCandidates(
        image: image,
        rotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
      if (!mounted) return;

      if (followObjectSequence.isWaitingForFinalPalm) {
        final refreshedFrozen = _resolveFrozenPointingTarget(
          detections: detections,
          now: now,
        );
        if (refreshedFrozen != null) {
          _followTargetPointingDwell.updateFrozenTarget(refreshedFrozen);
          _predictedFollowTarget = refreshedFrozen;
          _followTargetSelectionCandidateHidden = false;
        } else {
          _predictedFollowTarget = _followTargetPointingDwell.frozenTarget;
          _followTargetSelectionCandidateHidden = true;
        }
        _followPointingCursor = null;
        _projectedPointingCursor.reset();
        final remaining = _followTargetPointingDwell.finalPalmRemaining(now);
        _followPointingStatus =
            'Open palm to confirm (${(remaining.inMilliseconds / 1000).clamp(0, 2).toStringAsFixed(1)}s)';
      } else if (followObjectSequence.isIndexOnlyPointing &&
          followObjectSequence.indexPip != null &&
          followObjectSequence.indexTip != null) {
        final indexPipDisplayPoint = _handPointToDisplayPoint(
          followObjectSequence.indexPip!,
          detectionImageSize,
        );
        final indexDisplayPoint = _handPointToDisplayPoint(
          followObjectSequence.indexTip!,
          detectionImageSize,
        );
        final projectedCursor = _projectedPointingCursor.observe(
          indexPip: indexPipDisplayPoint,
          indexTip: indexDisplayPoint,
        );
        _updatePointingTargetDwell(
          cursor: projectedCursor,
          now: now,
          detections: detections,
        );
      } else {
        _resetFollowPointingSelection(FollowTargetPointingResetReason.poseLost);
        _followObjectSequenceDetector.markPointHoldReset();
        _followPointingStatus =
            _followObjectSequenceDetector.debugPhase ==
                FollowObjectSequencePhase.waitingForPoint
            ? 'Move fist near a target, then open only the index finger'
            : null;
      }
    } else if (followObjectSequence.isActive) {
      // Warm face/object detection during the first open-palm hold so the
      // nearest target is already available when the fist closes.
      await _refreshFollowObjectTargetCandidates(
        image: image,
        rotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
      if (!mounted) return;
    } else {
      _clearFollowObjectTargetCandidates();
    }

    final followObjectSequenceActive = followObjectSequence.isActive;
    final followObjectDetected =
        followObjectSequence.isDetected && lockedFollowTarget == null;
    final followTargetActive = lockedFollowTarget != null;
    final rememberedFollowTargetActive = _followTargetIdentity != null;
    final selectionConfirmationFailed = _isFollowTargetSelectionFailureActive(
      now,
    );
    final followTrackingActive =
        followTargetActive ||
        rememberedFollowTargetActive ||
        _isFollowingHand ||
        followObjectSequenceActive;

    final knownPackageGesture =
        !followTrackingActive &&
            reliablePackageGesture != null &&
            reliablePackageGesture.type != GestureType.unknown &&
            reliablePackageGesture.type != GestureType.openPalm &&
            !punchCircleCandidate
        ? reliablePackageGesture
        : null;
    final rawCustomGestureHasOverlap = rawCustomGestureResult.hasOverlap;
    final customGestureResult =
        followTrackingActive || rawCustomGestureHasOverlap
        ? CustomGestureDetectionResult.empty
        : rawCustomGestureResult;

    final customGestureLabels = customGestureResult.labels;
    final hasSingleCustomGesture = customGestureResult.hasSingle;
    final hasOverlappingCustomGestures =
        !followTrackingActive && rawCustomGestureHasOverlap;
    final hasPunchGesture =
        !followTrackingActive &&
        hasSingleCustomGesture &&
        customGestureResult.isPunch;
    final hasVictoryGesture =
        !followTrackingActive &&
        customGestureLabels.isEmpty &&
        _handGeometry.isReliablePackageGesture(
          gesture,
          type: GestureType.victory,
        );

    if (hasVictoryGesture && !_isVideoRecording) {
      _showVictoryToast(now);
    }

    if (hasPunchGesture && !_isVideoRecording) {
      _showPunchOnScreen(now);
    }

    final shouldShowPunchOnScreen =
        !_isVideoRecording &&
        _lastPunchScreenShownAt != null &&
        (customGestureLabels.isEmpty || customGestureResult.isPunch) &&
        now.difference(_lastPunchScreenShownAt!) <= const Duration(seconds: 1);

    final recordingGestureFeedback = _updateRecordingGestureHold(
      action: _recordingGestureAction(
        followTrackingActive: followTrackingActive,
        customGestureResult: customGestureResult,
        hasSingleCustomGesture: hasSingleCustomGesture,
        hasVictoryGesture: hasVictoryGesture,
      ),
      now: now,
    );
    final recordingGestureActive = recordingGestureFeedback != null;

    final packageGestureBlocksZoom =
        punchCircleCandidate ||
        (knownPackageGesture != null &&
            knownPackageGesture.type != GestureType.pointingUp);
    final zoomOpeningTransitionReserved =
        _zoomGestureDetector.reservesZoomInOpeningTransition;

    var moveDirection = HandMoveDirection.none;
    final directionBlockReason = followTrackingActive
        ? 'blocked: follow active'
        : hasVictoryGesture
        ? 'blocked: victory gesture'
        : customGestureLabels.isNotEmpty
        ? 'blocked: custom ${customGestureLabels.join(', ')}'
        : hasOverlappingCustomGestures
        ? 'blocked: overlapping custom'
        : recordingGestureActive
        ? 'blocked: recording gesture'
        : punchCircleCandidate
        ? 'blocked: punch circle candidate'
        : zoomOpeningTransitionReserved
        ? 'blocked: zoom opening transition'
        : null;

    if (directionBlockReason == null) {
      // Landmark geometry is authoritative for directions. Package labels can
      // be wrong for a sideways or downward pointing index.
      moveDirection = _directionGestureDetector.detect(
        hand: bestHand,
        imageSize: detectionImageSize,
        mirrorHorizontally: mirrorDirectionalGestureCoordinates,
        mirrorPalmHorizontally: mirrorPalmGestureCoordinates,
      );
    } else {
      _directionGestureDetector.clearState(reason: directionBlockReason);
    }

    final canDetectZoom =
        !followTrackingActive &&
        customGestureLabels.isEmpty &&
        !hasOverlappingCustomGestures &&
        !recordingGestureActive &&
        moveDirection == HandMoveDirection.none &&
        !packageGestureBlocksZoom &&
        !_shouldIgnoreGestureZoomForManualControl;

    var zoomDirection = ZoomDirection.none;
    if (canDetectZoom) {
      zoomDirection = _zoomGestureDetector.detect(
        hand: bestHand,
        imageSize: detectionImageSize,
        mirrorHorizontally: mirrorPalmGestureCoordinates,
        mirrorScreenHorizontally: mirrorDirectionalGestureCoordinates,
      );
    } else {
      _zoomGestureDetector.clearState();
    }

    final zoomHoldDirection = _zoomGestureDetector.pendingDirection;
    final zoomHoldActive = _zoomGestureDetector.isGestureActive;
    final openingZoomInCandidate =
        _zoomGestureDetector.isOpeningZoomInCandidate;

    _handleZoomDirection(zoomDirection);

    final followObjectSequenceMessage =
        followObjectSequence.packageGestureType?.displayLabel;

    final shouldFocusOnHand =
        !followTargetActive &&
        !rememberedFollowTargetActive &&
        (_isFollowingHand ||
            (followObjectSequenceActive &&
                followObjectSequence.packageGestureType ==
                    GestureType.closedFist));

    if (shouldFocusOnHand) {
      _updateFocusedHand(hand: bestHand, imageSize: detectionImageSize);
    }

    final directionDisplayBlockedByPriority =
        followTargetActive ||
        releaseHadNoTarget ||
        followObjectDetected ||
        _isFollowingHand ||
        followObjectSequenceActive ||
        recordingGestureFeedback != null ||
        shouldShowPunchOnScreen ||
        hasSingleCustomGesture ||
        hasOverlappingCustomGestures ||
        zoomHoldActive;

    final displayMoveDirection = directionDisplayBlockedByPriority
        ? HandMoveDirection.none
        : moveDirection;

    _setScreenState(() {
      _hands = hands;
      _detectionImageSize = detectionImageSize;
      _isFollowingHand = shouldFocusOnHand;
      _lockedFollowTarget = lockedFollowTarget;
      if (!shouldFocusOnHand) {
        _focusedHandBox = null;
        _focusImageSize = null;
      }
      _detectedHandsCount = hands.length;
      _handText = bestHand.handedness.displayLabel;

      if (followTargetActive) {
        _gestureText = _followTargetText(lockedFollowTarget!);
        _gestureConfidence = 1;
      } else if (selectionConfirmationFailed) {
        _gestureText = 'Target not found — select again';
        _gestureConfidence = 0;
      } else if (releaseHadNoTarget) {
        _gestureText = _followPointingStatus ?? 'No face or object selected';
        _gestureConfidence = 0;
      } else if (followObjectDetected) {
        _gestureText = 'Follow target confirmed';
        _gestureConfidence = 1;
      } else if (rememberedFollowTargetActive && lockedFollowTarget == null) {
        _gestureText = 'Target unavailable — select it again';
        _gestureConfidence = 0;
      } else if (_isFollowingHand) {
        _gestureText = 'Following hand';
        _gestureConfidence = 1;
      } else if (followObjectSequenceActive) {
        _gestureText =
            _followPointingStatus ??
            followObjectSequenceMessage ??
            'Hand detected';
        _gestureConfidence = _followObjectSequenceDetector.isWaitingForPoint
            ? _followPointingHoldProgress
            : followObjectSequenceMessage == null
            ? 0
            : followObjectSequence.gestureConfidence;
      } else if (recordingGestureFeedback != null) {
        _gestureText = recordingGestureFeedback.text;
        _gestureConfidence = recordingGestureFeedback.confidence;
      } else if (shouldShowPunchOnScreen) {
        _gestureText = 'Punch';
        _gestureConfidence = 1;
      } else if (hasSingleCustomGesture) {
        _gestureText = customGestureLabels.first;
        _gestureConfidence = 1;
      } else if (hasOverlappingCustomGestures) {
        _gestureText = 'Hand detected';
        _gestureConfidence = 0;
      } else if (zoomDirection == ZoomDirection.zoomIn) {
        _gestureText = _isCameraZoomSupported ? 'Zoom in' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
      } else if (zoomDirection == ZoomDirection.zoomOut) {
        _gestureText = _isCameraZoomSupported ? 'Zoom out' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
      } else if (openingZoomInCandidate) {
        _gestureText = 'Open fingers to zoom in';
        _gestureConfidence = 0;
      } else if (zoomHoldDirection == ZoomDirection.zoomIn) {
        _gestureText = 'Hold to zoom in';
        _gestureConfidence = 0;
      } else if (zoomHoldDirection == ZoomDirection.zoomOut) {
        _gestureText = 'Hold to zoom out';
        _gestureConfidence = 0;
      } else if (displayMoveDirection == HandMoveDirection.left) {
        _gestureText = 'Moving left';
        _gestureConfidence = 1;
      } else if (displayMoveDirection == HandMoveDirection.right) {
        _gestureText = 'Moving right';
        _gestureConfidence = 1;
      } else if (displayMoveDirection == HandMoveDirection.up) {
        _gestureText = 'Moving up';
        _gestureConfidence = 1;
      } else if (displayMoveDirection == HandMoveDirection.down) {
        _gestureText = 'Moving down';
        _gestureConfidence = 1;
      } else if (knownPackageGesture != null) {
        if (knownPackageGesture.type == GestureType.thumbUp) {
          _gestureText = 'Stop & Continue Action';
        } else if (knownPackageGesture.type == GestureType.victory) {
          _gestureText = _isVideoRecording ? 'End record video' : 'Victory';
        } else {
          _gestureText = knownPackageGesture.type.displayLabel;
        }

        _gestureConfidence = knownPackageGesture.confidence;
      } else {
        _gestureText = 'Hand detected';
        _gestureConfidence = 0;
      }
    });
  }

  /// Saves the focused hand box and updates camera focus/exposure.
  void _updateFocusedHand({required Hand hand, required Size imageSize}) {
    final box = hand.boundingBox;

    _focusedHandBox = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    _focusImageSize = imageSize;

    unawaited(_updateCameraFocusPoint(hand: hand, imageSize: imageSize));
  }

  /// Advances dwell only when the projected Point 8 is on one fresh target.
  void _updatePointingTargetDwell({
    required ProjectedPointingCursorObservation? cursor,
    required DateTime now,
    required _FollowTargetDetections detections,
  }) {
    if (cursor == null) {
      _resetFollowPointingSelection(FollowTargetPointingResetReason.poseLost);
      _followObjectSequenceDetector.markPointHoldReset();
      _followPointingStatus = 'Pointing direction is unreliable — try again';
      return;
    }

    _followPointingCursor = cursor;
    if (!cursor.isInFrame) {
      _resetFollowPointingSelection(
        FollowTargetPointingResetReason.fingertipOutside,
        keepCursor: true,
        resetProjection: false,
      );
      _followObjectSequenceDetector.markPointHoldReset();
      _followPointingStatus = 'Aim pointer inside the camera view';
      return;
    }

    final selectionPoint = cursor.projectedPoint;
    final detectedAfter = now.subtract(
      HandGestureThresholds.followTargetDetectionFreshness,
    );
    final freshFaces = _freshFollowTargets(detections.faces, now);
    final freshObjects = _freshFollowTargets(detections.objects, now);
    final selection = _followTargetSelector.selectAtPoint(
      selectionPoint: selectionPoint,
      faces: freshFaces,
      objects: freshObjects,
      detectedAfter: detectedAfter,
      activeCandidate: _followTargetPointingDwell.candidate,
      activeCandidateHysteresis:
          HandGestureThresholds.followObjectProjectedPointDwellHysteresis,
    );

    if (selection.isAmbiguous) {
      _resetFollowPointingSelection(
        FollowTargetPointingResetReason.ambiguous,
        keepCursor: true,
        resetProjection: false,
      );
      _followObjectSequenceDetector.markPointHoldReset();
      _followPointingStatus = 'Overlapping targets are ambiguous — move point';
      return;
    }

    final selected = selection.target;
    if (selected == null) {
      final staleSelection = _followTargetSelector.selectAtPoint(
        selectionPoint: selectionPoint,
        faces: detections.faces,
        objects: detections.objects,
        activeCandidate: _followTargetPointingDwell.candidate,
        activeCandidateHysteresis:
            HandGestureThresholds.followObjectProjectedPointDwellHysteresis,
      );
      final reason = staleSelection.target != null || staleSelection.isAmbiguous
          ? FollowTargetPointingResetReason.staleDetection
          : FollowTargetPointingResetReason.fingertipOutside;
      _resetFollowPointingSelection(
        reason,
        keepCursor: true,
        resetProjection: false,
      );
      _followObjectSequenceDetector.markPointHoldReset();
      _followPointingStatus =
          reason == FollowTargetPointingResetReason.staleDetection
          ? 'Target detection is stale — keep pointing'
          : 'Aim the projected point inside a face or object';
      return;
    }

    final detectionCycleAt =
        (selected.type == FollowTargetType.face
            ? detections.facesDetectedAt
            : detections.objectsDetectedAt) ??
        selected.detectedAt;
    final observation = _followTargetPointingDwell.observe(
      candidate: selected,
      detectionCycleAt: detectionCycleAt,
      now: now,
    );
    _followObjectSequenceDetector.markPointHoldStarted();
    _predictedFollowTarget = observation.candidate;
    _followTargetSelectionCandidateHidden = false;
    _followPointingHoldProgress = observation.progress;
    final percent = (observation.progress * 100).round();
    _followPointingStatus =
        'Hold target $percent% '
        '(${observation.freshDetectionCycles}/'
        '${HandGestureThresholds.followObjectPointingMinFreshDetectionCycles} fresh)';

    if (!observation.isComplete) return;
    final deadline = _followTargetPointingDwell.confirmationDeadline;
    if (deadline == null) return;
    _followObjectSequenceDetector.markPointHoldComplete(
      confirmationDeadline: deadline,
    );
    _predictedFollowTarget = _followTargetPointingDwell.frozenTarget;
    _followPointingCursor = null;
    _projectedPointingCursor.reset();
    _followPointingHoldProgress = 1;
    _followPointingStatus = 'Open palm to confirm (2.0s)';
  }

  /// Refreshes the frozen identity without ever substituting another target.
  FollowTarget? _resolveFrozenPointingTarget({
    required _FollowTargetDetections detections,
    required DateTime now,
  }) {
    final frozen = _followTargetPointingDwell.frozenTarget;
    if (frozen == null) return null;
    final candidates = frozen.type == FollowTargetType.face
        ? _freshFollowTargets(detections.faces, now)
        : _freshFollowTargets(detections.objects, now);
    return _followTargetSelector.resolveFrozenPointingTarget(
      frozen: frozen,
      candidates: candidates,
    );
  }

  void _resetFollowPointingSelection(
    FollowTargetPointingResetReason reason, {
    bool keepCursor = false,
    bool resetProjection = true,
  }) {
    _followTargetPointingDwell.reset(reason);
    _predictedFollowTarget = null;
    _followTargetSelectionCandidateHidden = false;
    if (resetProjection) _projectedPointingCursor.reset();
    if (!keepCursor) _followPointingCursor = null;
    _followPointingHoldProgress = 0;
    if (reason == FollowTargetPointingResetReason.none) {
      _followPointingStatus = null;
    }
  }

  List<FollowTarget> _freshFollowTargets(
    List<FollowTarget> targets,
    DateTime now,
  ) {
    return targets
        .where((target) => _isFreshFollowTarget(target, now))
        .toList(growable: false);
  }

  bool _isFreshFollowTarget(FollowTarget target, DateTime now) {
    final age = now.difference(target.detectedAt);
    return !age.isNegative &&
        age <= HandGestureThresholds.followTargetDetectionFreshness;
  }

  /// Updates cached face/object candidates for follow-object selection.
  Future<_FollowTargetDetections> _refreshFollowObjectTargetCandidates({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    final detections = await _detectFollowTargets(
      image: image,
      rotation: rotation,
      now: now,
      includeFaces: true,
      includeObjects: true,
      objectTrackingFrame: objectTrackingFrame,
    );

    if (detections != null) {
      _followObjectCandidateFaces = detections.faces;
      _followObjectCandidateObjects = _selectableObjectTargets(
        _visualObjectTargets.isNotEmpty
            ? _visualObjectTargets
            : detections.objects,
        handDisplayBox: _followSelectionHandDisplayBox,
      );
    }

    return _FollowTargetDetections(
      faces: _followObjectCandidateFaces,
      objects: _followObjectCandidateObjects,
      facesDetectedAt: detections?.facesDetectedAt,
      objectsDetectedAt: detections?.objectsDetectedAt,
    );
  }

  /// Clears cached follow-object candidates from the debug/selection overlay.
  void _clearFollowObjectTargetCandidates() {
    _followObjectCandidateFaces = const [];
    _followObjectCandidateObjects = const [];
    _predictedFollowTarget = null;
    _followTargetSelectionCandidateHidden = false;
    _followSelectionHandDisplayBox = null;
    _resetFollowPointingSelection(FollowTargetPointingResetReason.none);
  }

  /// Preserves the hand-return grace but never auto-selects a missing hand.
  Future<_FollowObjectReleaseSelection?>
  _releaseFollowObjectFromLastVisiblePoint({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required Size detectionImageSize,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    final result = _followObjectSequenceDetector.handleHandMissing(now);
    if (result.isWaitingForHandReturn) {
      if (_followTargetPointingDwell.isFrozen) {
        final detections = await _refreshFollowObjectTargetCandidates(
          image: image,
          rotation: rotation,
          now: now,
          objectTrackingFrame: objectTrackingFrame,
        );
        if (!mounted) return null;
        final refreshed = _resolveFrozenPointingTarget(
          detections: detections,
          now: now,
        );
        if (refreshed != null) {
          _followTargetPointingDwell.updateFrozenTarget(refreshed);
          _predictedFollowTarget = refreshed;
          _followTargetSelectionCandidateHidden = false;
        } else {
          _followTargetSelectionCandidateHidden = true;
        }
      } else {
        _resetFollowPointingSelection(
          FollowTargetPointingResetReason.handMissing,
        );
      }
      return _FollowObjectReleaseSelection.waitingForHandReturn(
        progress: result.handReturnProgress,
      );
    }
    if (result.wasCancelled) {
      final reason =
          result.cancellationReason ?? 'Follow target selection cancelled';
      _resetFollowPointingSelection(
        FollowTargetPointingResetReason.confirmationExpired,
      );
      _followTargetProgress.reset();
      _clearFollowObjectTargetCandidates();
      return _FollowObjectReleaseSelection.cancelled(reason: reason);
    }
    return null;
  }

  /// Detects faces and picks the largest one for "detect my face".
  Future<FollowTarget?> _selectBestFaceTarget({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
  }) async {
    final detections = await _detectFollowTargets(
      image: image,
      rotation: rotation,
      now: now,
      includeFaces: true,
      includeObjects: false,
    );
    if (detections == null || detections.faces.isEmpty) return null;

    return detections.faces.reduce((currentBest, next) {
      final currentArea =
          currentBest.displayBox.width * currentBest.displayBox.height;
      final nextArea = next.displayBox.width * next.displayBox.height;
      return nextArea > currentArea ? next : currentBest;
    });
  }

  /// Refreshes the locked target and keeps it briefly if detection flickers.
  Future<FollowTarget?> _refreshLockedFollowTarget({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    final previous = _lockedFollowTarget;
    final identity = _followTargetIdentity;
    final targetType = previous?.type ?? identity?.type;
    if (targetType == null) return null;
    final isConfirmingSelection =
        _followTargetProgress.phase ==
        FollowTargetTrackingPhase.confirmingSelection;
    final isTemporarilyLost =
        _followTargetProgress.phase ==
        FollowTargetTrackingPhase.temporarilyLost;

    var visiblePrevious = previous;
    if (!isConfirmingSelection &&
        targetType == FollowTargetType.object &&
        previous != null &&
        objectTrackingFrame != null) {
      final opticalResult = _objectOpticalFlowTracker.isActive
          ? _objectOpticalFlowTracker.update(objectTrackingFrame)
          : _objectOpticalFlowTracker.seed(
              objectTrackingFrame,
              previous.displayBox,
            );
      _objectOpticalFlowResult = opticalResult;
      if (opticalResult.isUsable) {
        visiblePrevious = _copyFollowTargetWithDisplayBox(
          previous,
          opticalResult.displayBox,
        );
        _setVisibleFollowTarget(visiblePrevious);
        unawaited(_updateCameraFocusPointForTarget(visiblePrevious));
      }
    }

    final detections = await _detectFollowTargets(
      image: image,
      rotation: rotation,
      now: now,
      includeFaces: targetType == FollowTargetType.face,
      includeObjects: targetType == FollowTargetType.object,
      objectTrackingFrame: objectTrackingFrame,
    );
    if (detections == null) {
      if (isConfirmingSelection) {
        return _keepConfirmingSelectionOrFail(DateTime.now(), visiblePrevious);
      }
      if (isTemporarilyLost) {
        _expireDetectMyFaceReacquisitionIfNeeded(DateTime.now());
        return null;
      }
      return identity == null
          ? _keepOrClearLostFollowTarget(now)
          : visiblePrevious;
    }

    final candidates = targetType == FollowTargetType.face
        ? detections.faces
        : detections.objects;
    final detectionCycleAt = targetType == FollowTargetType.face
        ? detections.facesDetectedAt
        : detections.objectsDetectedAt;

    if (isConfirmingSelection) {
      final confirmationNow = DateTime.now();
      if (detectionCycleAt == null ||
          detectionCycleAt == _lastEvaluatedFollowDetectionAt) {
        return _keepConfirmingSelectionOrFail(confirmationNow, visiblePrevious);
      }
      _lastEvaluatedFollowDetectionAt = detectionCycleAt;
      final freshCandidates = candidates
          .where(
            (candidate) => _isFreshFollowTarget(candidate, confirmationNow),
          )
          .toList(growable: false);
      final confirmed = visiblePrevious == null
          ? null
          : _followTargetSelector.uniqueSelectionConfirmation(
              remembered: visiblePrevious,
              candidates: freshCandidates,
            );
      if (confirmed == null) {
        return _keepConfirmingSelectionOrFail(confirmationNow, visiblePrevious);
      }

      _followTargetConfirmationDeadline = null;
      _followTargetSelectionFailureUntil = null;
      _followTargetProgress.markVisible();
      _setVisibleFollowTarget(confirmed);
      unawaited(_updateCameraFocusPointForTarget(confirmed));
      return confirmed;
    }

    if (isTemporarilyLost) {
      final reacquisitionNow = DateTime.now();
      if (_expireDetectMyFaceReacquisitionIfNeeded(reacquisitionNow)) {
        return null;
      }
      if (identity == null ||
          detectionCycleAt == null ||
          detectionCycleAt == _lastEvaluatedFollowDetectionAt) {
        return null;
      }
      _lastEvaluatedFollowDetectionAt = detectionCycleAt;

      final freshCandidates = candidates
          .where(
            (candidate) => _isFreshFollowTarget(candidate, reacquisitionNow),
          )
          .toList(growable: false);
      return _reacquireDetectMyFaceTarget(
        identity: identity,
        candidates: freshCandidates,
      );
    }

    if (identity == null) {
      if (visiblePrevious == null) return null;
      final updated = _followTargetSelector.track(
        previous: visiblePrevious,
        candidates: candidates,
      );
      if (updated == null) return _keepOrClearLostFollowTarget(now);
      _setVisibleFollowTarget(updated);
      unawaited(_updateCameraFocusPointForTarget(updated));
      return updated;
    }

    if (detectionCycleAt == null ||
        detectionCycleAt == _lastEvaluatedFollowDetectionAt) {
      return visiblePrevious;
    }
    _lastEvaluatedFollowDetectionAt = detectionCycleAt;

    final freshCandidates = candidates
        .where((candidate) => _isFreshFollowTarget(candidate, now))
        .toList(growable: false);

    if (visiblePrevious != null) {
      var detectorPrevious = visiblePrevious;
      if (targetType == FollowTargetType.object && freshCandidates.isNotEmpty) {
        final sourceFrameId = freshCandidates.first.sourceFrameId;
        final historicalBox = sourceFrameId == null
            ? null
            : _objectOpticalFlowTracker.displayBoxForFrame(sourceFrameId);
        if (historicalBox != null) {
          detectorPrevious = _copyFollowTargetWithDisplayBox(
            visiblePrevious,
            historicalBox,
          );
        }
      }
      final updated = _followTargetSelector.track(
        previous: detectorPrevious,
        candidates: freshCandidates,
        identity: identity,
      );
      if (updated != null) {
        _followTargetProgress.markVisible();
        var corrected = updated;
        final sourceFrameId = updated.sourceFrameId;
        if (targetType == FollowTargetType.object &&
            objectTrackingFrame != null &&
            sourceFrameId != null) {
          final correction = _objectOpticalFlowTracker.correctFromDetection(
            currentFrame: objectTrackingFrame,
            detectedFrameId: sourceFrameId,
            detectedDisplayBox: updated.displayBox,
          );
          if (correction != null && correction.isUsable) {
            _objectOpticalFlowResult = correction;
            corrected = _copyFollowTargetWithDisplayBox(
              updated,
              correction.displayBox,
            );
          }
        }
        _setVisibleFollowTarget(corrected);
        unawaited(_updateCameraFocusPointForTarget(corrected));
        return corrected;
      }

      if (targetType == FollowTargetType.face &&
          _detectMyFaceReacquisition.isActive) {
        final missNow = DateTime.now();
        final missResult = _detectMyFaceReacquisition.observeFreshMiss(missNow);
        switch (missResult) {
          case DetectMyFaceMissResult.keepVisible:
            return visiblePrevious;
          case DetectMyFaceMissResult.temporarilyLost:
            final reacquired = _reacquireDetectMyFaceTarget(
              identity: identity,
              candidates: freshCandidates,
            );
            if (reacquired != null) return reacquired;
            _followTargetProgress.markTemporarilyLost();
            _lockedFollowTarget = null;
            _lockedFollowTargetLostAt = null;
            return null;
          case DetectMyFaceMissResult.expired:
            _expireDetectMyFaceReacquisition(missNow);
            return null;
        }
      }

      if (!_followTargetProgress.recordVisibleMiss()) {
        return visiblePrevious;
      }
      _dropFollowTargetAfterMiss();
      return null;
    }
    return null;
  }

  FollowTarget? _reacquireDetectMyFaceTarget({
    required FollowTargetIdentity identity,
    required List<FollowTarget> candidates,
  }) {
    final reacquired = _followTargetSelector.reacquireFace(
      identity: identity,
      candidates: candidates,
    );
    if (reacquired == null) return null;

    _followTargetIdentity = FollowTargetIdentity.fromTarget(reacquired);
    _followTargetProgress.markVisible();
    _setVisibleFollowTarget(reacquired);
    unawaited(_updateCameraFocusPointForTarget(reacquired));
    return reacquired;
  }

  FollowTarget _copyFollowTargetWithDisplayBox(
    FollowTarget target,
    Rect displayBox,
  ) {
    return FollowTarget(
      type: target.type,
      boundingBox: target.boundingBox,
      displayBox: displayBox,
      detectedAt: target.detectedAt,
      trackingId: target.trackingId,
      label: target.label,
      classIndex: target.classIndex,
      appearanceSignature: target.appearanceSignature,
      sourceFrameId: target.sourceFrameId,
    );
  }

  /// Runs face and object detection, then maps results to display boxes.
  Future<_FollowTargetDetections?> _detectFollowTargets({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
    required bool includeFaces,
    required bool includeObjects,
    ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    final inputRotation = mlKitInputRotation(rotation);
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    var faces = const <FollowTarget>[];
    var objects = const <FollowTarget>[];
    DateTime? facesDetectedAt;

    if (includeFaces) {
      final faceDetector = _faceDetector;
      if (faceDetector != null) {
        try {
          final inputImage = mlKitFaceInputImage(
            image,
            rotation: rotation,
            isAndroid: Platform.isAndroid,
            isIOS: Platform.isIOS,
          );
          final detectedFaces = inputImage == null
              ? const <ml_face.Face>[]
              : await faceDetector.processImage(inputImage);
          faces = [
            for (final face in detectedFaces)
              _faceFollowTarget(
                face: face,
                image: image,
                imageSize: imageSize,
                inputRotation: inputRotation,
                frameRotation: rotation,
                detectedAt: now,
              ),
          ];
          facesDetectedAt = now;
        } catch (error, stackTrace) {
          debugPrint('Face detection ignored: $error\n$stackTrace');
        }
      }
    }

    if (includeObjects) {
      objects = await _detectOrReuseObjectTargets(
        image: image,
        frameRotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
    }

    return _FollowTargetDetections(
      faces: faces,
      objects: objects,
      facesDetectedAt: facesDetectedAt,
      objectsDetectedAt: includeObjects
          ? _cachedObjectDetectionBatch?.completedAt
          : null,
    );
  }

  /// Runs object detection at a lower cadence and reuses the latest result.
  Future<List<FollowTarget>> _detectOrReuseObjectTargets({
    required CameraImage image,
    required CameraFrameRotation? frameRotation,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    _ensureObjectDetectionServiceStarted();

    final objectDetector = _objectDetectionService;
    if (objectDetector == null) {
      return _cachedObjectTargets;
    }

    final generation = _objectDetectionGeneration;
    final sourceFrameId = objectTrackingFrame?.frameId ?? _cameraFrameId;
    final sourceCapturedAt = objectTrackingFrame?.capturedAt ?? now;
    Future<List<AppObjectDetection>>? request;

    try {
      request = _objectDetectionRequests.submit(
        now: now,
        detectorBusy: objectDetector.isBusy,
        minIntervalOverride:
            _followObjectSequenceDetector.isTargetSelectionActive
            ? _followObjectSelectionDetectionInterval()
            : null,
        detect: () => objectDetector.detect(
          image,
          rotation: frameRotation,
          lensDirection: _currentLensDirection,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Object detection ignored: $error\n$stackTrace');
    }

    if (request != null) {
      unawaited(
        request
            .then((detectedObjects) {
              if (generation != _objectDetectionGeneration) return;

              final completedAt = DateTime.now();
              if (!_objectDetectionResultStabilizer.shouldReplace(
                hasDetections: detectedObjects.isNotEmpty,
                completedAt: completedAt,
              )) {
                return;
              }
              final batch = ObjectDetectionBatch(
                detections: detectedObjects,
                sourceFrameId: sourceFrameId,
                sourceCapturedAt: sourceCapturedAt,
                completedAt: completedAt,
              );
              _cachedObjectDetectionBatch = batch;
              final objects = _objectTargetsFromDetections(
                batch.detections,
                image: image,
                frameRotation: frameRotation,
                // iOS inference completes asynchronously in the package
                // detector. Use completion time only for cache freshness so a
                // valid result is not discarded immediately on slower devices;
                // sourceFrameId still preserves optical-flow alignment.
                detectedAt: Platform.isIOS
                    ? batch.completedAt
                    : batch.sourceCapturedAt,
                sourceFrameId: batch.sourceFrameId,
              );
              _cachedObjectTargets = objects;
              if (objects.isEmpty) {
                _objectDetectionTargetSmoother.clear();
                _visualObjectTargets = const [];
              } else {
                _visualObjectTargets = _objectDetectionTargetSmoother.update(
                  objects,
                  completedAt: completedAt,
                );
              }

              if (_followObjectSequenceDetector.isTargetSelectionActive ||
                  _lockedFollowTarget?.type == FollowTargetType.object) {
                _followObjectCandidateObjects = _selectableObjectTargets(
                  _visualObjectTargets,
                  handDisplayBox: _followSelectionHandDisplayBox,
                );
              }

              if (!mounted) return;
              _setScreenState(() {});
            })
            .catchError((Object error, StackTrace stackTrace) {
              if (generation != _objectDetectionGeneration) return;
              debugPrint('Object detection ignored: $error\n$stackTrace');
            }),
      );
    }

    return _cachedObjectTargets;
  }

  Duration _followObjectSelectionDetectionInterval() {
    final cap = Platform.isIOS
        ? HandGestureThresholds.iosFollowObjectSelectionDetectionMinInterval
        : HandGestureThresholds.followObjectSelectionDetectionMinInterval;
    return _objectDetectionRequests.minInterval <= cap
        ? _objectDetectionRequests.minInterval
        : cap;
  }

  /// Maps package detections to follow-target boxes for the current preview.
  List<FollowTarget> _objectTargetsFromDetections(
    List<AppObjectDetection> detectedObjects, {
    required CameraImage image,
    required CameraFrameRotation? frameRotation,
    required DateTime detectedAt,
    required int sourceFrameId,
  }) {
    return [
      for (final object in detectedObjects)
        _objectFollowTarget(
          object: object,
          image: image,
          frameRotation: frameRotation,
          detectedAt: detectedAt,
          sourceFrameId: sourceFrameId,
        ),
    ];
  }

  FollowTarget _faceFollowTarget({
    required ml_face.Face face,
    required CameraImage image,
    required Size imageSize,
    required ml_face.InputImageRotation inputRotation,
    required CameraFrameRotation? frameRotation,
    required DateTime detectedAt,
  }) {
    final displayBox = mlKitDisplayRect(
      face.boundingBox,
      imageSize: imageSize,
      rotation: inputRotation,
      isIOS: Platform.isIOS,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(_controller),
    );
    return FollowTarget(
      type: FollowTargetType.face,
      boundingBox: face.boundingBox,
      displayBox: displayBox,
      detectedAt: detectedAt,
      trackingId: face.trackingId,
      label: 'Face',
      appearanceSignature: _appearanceSignatureForTarget(
        image: image,
        displayBox: displayBox,
        frameRotation: frameRotation,
      ),
    );
  }

  FollowTarget _objectFollowTarget({
    required AppObjectDetection object,
    required CameraImage image,
    required CameraFrameRotation? frameRotation,
    required DateTime detectedAt,
    required int sourceFrameId,
  }) {
    final displayBox = imageRectToDisplayBox(
      rect: object.boundingBox,
      imageSize: object.imageSize,
      mirrorHorizontally: _shouldMirrorPreviewCoordinates(_controller),
    );
    return FollowTarget(
      type: FollowTargetType.object,
      boundingBox: object.boundingBox,
      displayBox: displayBox,
      detectedAt: detectedAt,
      label: object.label,
      classIndex: object.classIndex,
      trackingId: object.trackingId,
      sourceFrameId: sourceFrameId,
      appearanceSignature: _appearanceSignatureForTarget(
        image: image,
        displayBox: displayBox,
        frameRotation: frameRotation,
      ),
    );
  }

  AppearanceSignature? _appearanceSignatureForTarget({
    required CameraImage image,
    required Rect displayBox,
    required CameraFrameRotation? frameRotation,
  }) {
    try {
      return _appearanceSignatureExtractor.extract(
        frame: CameraPixelFrameData.fromCameraImage(
          image,
          isBgra: Platform.isIOS || Platform.isMacOS,
        ),
        displayBox: displayBox,
        rotation: frameRotation,
        mirrorHorizontally: _shouldMirrorPreviewCoordinates(_controller),
      );
    } catch (error, stackTrace) {
      debugPrint('Appearance signature ignored: $error\n$stackTrace');
      return null;
    }
  }

  /// Starts the object detector without blocking the live camera frame.
  void _ensureObjectDetectionServiceStarted() {
    final failedAt = _objectDetectionServiceStartupFailedAt;
    if (_objectDetectionServiceStartupFailed && failedAt != null) {
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
      _objectDetectionServiceStartupFailed = false;
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
            _objectDetectionServiceStartupFailed = true;
            _objectDetectionServiceStartupFailedAt = DateTime.now();
            debugPrint('Object detector startup ignored: $error\n$stackTrace');
          })
          .whenComplete(() {
            if (identical(_objectDetectionServiceStartup, startup)) {
              _objectDetectionServiceStartup = null;
            }
          }),
    );
  }

  /// Clears cached object detections while keeping any warm detector alive.
  void _clearObjectDetectionCache() {
    _objectDetectionGeneration++;
    _objectDetectionRequests.clear();
    _objectDetectionResultStabilizer.clear();
    _objectDetectionTargetSmoother.clear();
    _cachedObjectTargets = const [];
    _visualObjectTargets = const [];
    _cachedObjectDetectionBatch = null;
  }

  /// Stops the object detector and rejects stale async object results.
  void _closeObjectDetectionService() {
    _clearObjectDetectionCache();

    final objectDetector = _objectDetectionService;
    final startup = _objectDetectionServiceStartup;
    _objectDetectionService = null;
    _objectDetectionServiceStartup = null;
    _objectDetectionServiceStartupFailed = false;
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
              debugPrint('Object detector close ignored: $error\n$stackTrace');
            }),
      );
    }
  }

  /// Converts a hand-detector image point into normalized preview space.
  Offset _handPointToDisplayPoint(Offset point, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Offset.zero;
    }

    final normalizedPoint = Offset(
      (point.dx / imageSize.width).clamp(0.0, 1.0),
      (point.dy / imageSize.height).clamp(0.0, 1.0),
    );
    final controller = _controller;
    final displayPoint = _shouldMirrorPreviewCoordinates(controller)
        ? Offset(1.0 - normalizedPoint.dx, normalizedPoint.dy)
        : normalizedPoint;

    return Offset(
      displayPoint.dx.clamp(0.0, 1.0),
      displayPoint.dy.clamp(0.0, 1.0),
    );
  }

  Rect _handBoxToDisplayBox(BoundingBox box, Size imageSize) {
    final first = _handPointToDisplayPoint(
      Offset(box.left, box.top),
      imageSize,
    );
    final second = _handPointToDisplayPoint(
      Offset(box.right, box.bottom),
      imageSize,
    );
    return Rect.fromLTRB(
      math.min(first.dx, second.dx),
      math.min(first.dy, second.dy),
      math.max(first.dx, second.dx),
      math.max(first.dy, second.dy),
    );
  }

  List<FollowTarget> _selectableObjectTargets(
    List<FollowTarget> targets, {
    required Rect? handDisplayBox,
  }) {
    if (widget.objectDetectionBackend != ObjectDetectionBackend.googleMlKit ||
        handDisplayBox == null) {
      return targets;
    }
    return _followTargetSelector.withoutLikelyHandFalsePositives(
      objects: targets,
      handDisplayBox: handDisplayBox,
    );
  }

  /// Status text for a locked follow target.
  String _followTargetText(FollowTarget target) {
    final identity = _followTargetIdentity;
    if (identity != null &&
        _followTargetProgress.phase ==
            FollowTargetTrackingPhase.confirmingSelection) {
      return 'Move hand away — confirming ${identity.displayLabel}';
    }
    if (identity != null) return 'Target locked: ${identity.displayLabel}';
    return 'Following ${target.displayLabel.toLowerCase()}';
  }

  String _followTargetStatusText({
    required FollowTarget? visibleTarget,
    required String fallbackText,
  }) {
    if (visibleTarget != null) return _followTargetText(visibleTarget);

    final now = DateTime.now();
    if (_followTargetProgress.phase ==
        FollowTargetTrackingPhase.temporarilyLost) {
      return _detectMyFaceReacquisitionWaitingText(now);
    }
    if (_detectMyFaceReacquisition.shouldShowExpiredNotice(now)) {
      return 'Face lost - use Detect My Face again';
    }

    if (_isFollowTargetSelectionFailureActive(now)) {
      return 'Target not found — select again';
    }

    if (_followTargetIdentity != null) {
      return 'Target unavailable — select it again';
    }

    return fallbackText;
  }

  String _handReturnGraceText(double progress) {
    final remainingMilliseconds =
        HandGestureThresholds
            .followObjectHandReturnGraceDuration
            .inMilliseconds *
        (1 - progress.clamp(0.0, 1.0));
    final remainingSeconds = remainingMilliseconds / 1000;
    final returnPose = _followTargetPointingDwell.isFrozen
        ? 'open palm'
        : 'closed fist or index';
    return 'Hand left — return $returnPose '
        '(${remainingSeconds.toStringAsFixed(1)}s)';
  }

  FollowTarget _applyFollowTargetReleaseSelection(
    _FollowTargetReleaseSelection selection, {
    required DateTime now,
  }) {
    if (selection.requiresPostReleaseConfirmation) {
      _setConfirmingFollowTarget(
        selection.target,
        now: now,
        evaluatedDetectionCycleAt: selection.evaluatedDetectionCycleAt,
      );
      _lastCameraFocusPointSetAt = null;
      _lastCameraFocusPoint = null;
    } else {
      _setLockedFollowTarget(selection.target, captureIdentity: true);
    }
    unawaited(_updateCameraFocusPointForTarget(selection.target));
    return selection.target;
  }

  void _setConfirmingFollowTarget(
    FollowTarget target, {
    required DateTime now,
    DateTime? evaluatedDetectionCycleAt,
  }) {
    _followTargetIdentity = FollowTargetIdentity.fromTarget(target);
    _followTargetProgress.markConfirmingSelection();
    _followTargetConfirmationDeadline = now.add(
      HandGestureThresholds.followTargetPostReleaseConfirmationDuration,
    );
    _followTargetSelectionFailureUntil = null;
    _lastEvaluatedFollowDetectionAt = evaluatedDetectionCycleAt;
    _objectOpticalFlowTracker.reset();
    _objectOpticalFlowResult = null;
    _setVisibleFollowTarget(target);
  }

  FollowTarget? _keepConfirmingSelectionOrFail(
    DateTime now,
    FollowTarget? previous,
  ) {
    final deadline = _followTargetConfirmationDeadline;
    if (deadline != null && !now.isAfter(deadline)) return previous;

    _clearLockedFollowTarget(clearIdentity: true);
    _followTargetSelectionFailureUntil = now.add(
      HandGestureThresholds.followObjectMessageHoldDuration,
    );
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    return null;
  }

  bool _isFollowTargetSelectionFailureActive(DateTime now) {
    final until = _followTargetSelectionFailureUntil;
    if (until == null) return false;
    if (!now.isAfter(until)) return true;
    _followTargetSelectionFailureUntil = null;
    return false;
  }

  /// Stores a visible target and captures identity only for a new selection.
  void _setLockedFollowTarget(
    FollowTarget target, {
    required bool captureIdentity,
  }) {
    if (captureIdentity) {
      _followTargetIdentity = FollowTargetIdentity.fromTarget(target);
      _followTargetProgress.markVisible();
      _lastEvaluatedFollowDetectionAt = target.detectedAt;
      _followTargetConfirmationDeadline = null;
      _followTargetSelectionFailureUntil = null;
    }
    _setVisibleFollowTarget(target);
  }

  void _setVisibleFollowTarget(FollowTarget target) {
    _lockedFollowTarget = target;
    _lockedFollowTargetLostAt = null;
    _detectMyFaceReacquisition.observeVisible();
  }

  /// Keeps a lost target briefly before clearing it.
  FollowTarget? _keepOrClearLostFollowTarget(DateTime now) {
    final previous = _lockedFollowTarget;
    if (previous == null) return null;

    final lostAt = _lockedFollowTargetLostAt;
    if (lostAt == null) {
      _lockedFollowTargetLostAt = now;
      return previous;
    }

    if (now.difference(lostAt) <=
        HandGestureThresholds.followTargetLostHoldDuration) {
      return previous;
    }

    _clearLockedFollowTarget();
    return null;
  }

  /// Clears the visible face/object follow target.
  void _clearLockedFollowTarget({bool clearIdentity = false}) {
    _lockedFollowTarget = null;
    _lockedFollowTargetLostAt = null;
    if (clearIdentity) {
      _resetFollowTargetTrackingState();
    }
  }

  void _dropFollowTargetAfterMiss() {
    _clearLockedFollowTarget(clearIdentity: true);
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    _lastCameraFocusPointSetAt = null;
    _lastCameraFocusPoint = null;
    unawaited(_updateCameraFocusAtNormalizedPoint(const Offset(0.5, 0.5)));
  }

  bool _expireDetectMyFaceReacquisitionIfNeeded(DateTime now) {
    if (!_detectMyFaceReacquisition.hasExpired(now)) return false;
    _expireDetectMyFaceReacquisition(now);
    return true;
  }

  void _expireDetectMyFaceReacquisition(DateTime now) {
    _dropFollowTargetAfterMiss();
    _detectMyFaceReacquisition.markExpired(now);
  }

  String _detectMyFaceReacquisitionWaitingText(DateTime now) {
    final remaining = _detectMyFaceReacquisition.remaining(now);
    final remainingSeconds = remaining.inMilliseconds / 1000;
    return 'Face lost - waiting (${remainingSeconds.toStringAsFixed(1)}s)';
  }

  void _resetFollowTargetTrackingState() {
    _followTargetIdentity = null;
    _followTargetProgress.reset();
    _detectMyFaceReacquisition.clear();
    _lastEvaluatedFollowDetectionAt = null;
    _followTargetConfirmationDeadline = null;
    _followTargetSelectionFailureUntil = null;
    _objectOpticalFlowTracker.reset();
    _objectOpticalFlowResult = null;
  }

  void _cancelFollowTarget({required bool promptReselect}) {
    _followObjectSequenceDetector.clear();
    _clearFollowObjectTargetCandidates();
    _clearLockedFollowTarget(clearIdentity: true);
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    _lastCameraFocusPointSetAt = null;
    _lastCameraFocusPoint = null;
    unawaited(_updateCameraFocusAtNormalizedPoint(const Offset(0.5, 0.5)));

    _setScreenState(() {
      _gestureText = promptReselect
          ? 'Show open palm to select a new target'
          : 'Follow target cancelled';
      _gestureConfidence = 0;
    });
  }

  /// Clears the "call me" face-detection hold timer.
  void _clearFaceDetectGestureHold() {
    _faceDetectGestureStartedAt = null;
  }

  /// Opens the debug selector once per confirmed I-Love-You pose.
  void _updateGestureDebugMenuTrigger({required bool isLoveYou}) {
    final shouldOpen = _gestureDebugMenuTrigger.update(isLoveYou: isLoveYou);
    if (!shouldOpen || _isGestureDebugMenuOpen) return;
    _isGestureDebugMenuOpen = true;
    _clearGestureActionsForDebugMenu();
  }

  /// While choosing, updates only the hand cursor and Love-You release latch.
  void _updateOpenGestureDebugMenuFrame({
    required List<Hand> hands,
    required Size detectionImageSize,
  }) {
    final reliableHands = _handGeometry.reliableHands(hands);
    final bestHand = _handGeometry.bestReliableHand(reliableHands);
    final gesture = bestHand?.gesture;
    _updateGestureDebugMenuTrigger(
      isLoveYou: _handGeometry.isReliablePackageGesture(
        gesture,
        type: GestureType.iLoveYou,
      ),
    );

    _setScreenState(() {
      _hands = hands;
      _detectionImageSize = detectionImageSize;
      _detectedHandsCount = hands.length;
      _handText = bestHand?.handedness.displayLabel ?? '';
      _gestureText = bestHand == null
          ? 'Show point 8 to choose debug drawing'
          : 'Point at one debug box for 2 seconds';
      _gestureConfidence = 0;
    });
  }

  void _selectGestureDebugMode(GestureDebugMode mode) {
    _clearGestureActionsForDebugMenu();
    _setScreenState(() {
      _gestureDebugMode = mode;
      _isGestureDebugMenuOpen = false;
      _gestureText = mode == GestureDebugMode.off
          ? 'Debug drawing off'
          : '${_gestureDebugModeLabel(mode)} debug selected';
      _gestureConfidence = 0;
    });
  }

  void _cancelGestureDebugMenu() {
    _clearGestureActionsForDebugMenu();
    _setScreenState(() {
      _isGestureDebugMenuOpen = false;
      _gestureText = _gestureDebugMode == GestureDebugMode.off
          ? 'Debug drawing off'
          : '${_gestureDebugModeLabel(_gestureDebugMode)} debug selected';
      _gestureConfidence = 0;
    });
  }

  void _clearGestureActionsForDebugMenu() {
    _customGestureDetector.clearState();
    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState(reason: 'debug selector open');
    _followObjectSequenceDetector.clear();
    _clearRecordingGestureHold();
    _clearFaceDetectGestureHold();
    _clearFollowObjectTargetCandidates();
  }

  String _gestureDebugModeLabel(GestureDebugMode mode) {
    switch (mode) {
      case GestureDebugMode.off:
        return 'Off';
      case GestureDebugMode.direction:
        return 'Direction';
      case GestureDebugMode.punch:
        return 'Punch';
      case GestureDebugMode.zoomIn:
        return 'Zoom In';
      case GestureDebugMode.zoomOut:
        return 'Zoom Out';
      case GestureDebugMode.returnMain:
        return 'Return Main';
      case GestureDebugMode.recording:
        return 'Recording';
      case GestureDebugMode.callMe:
        return 'Call Me';
      case GestureDebugMode.followObject:
        return 'Follow Object';
    }
  }

  /// Clears detector history after a missing or unreliable frame boundary.
  void _clearFrameInterruptedGestureState({
    bool keepFollowObjectSequence = false,
  }) {
    _updateGestureDebugMenuTrigger(isLoveYou: false);
    _customGestureDetector.clearState();
    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState();
    if (!keepFollowObjectSequence) {
      _followObjectSequenceDetector.clear();
      _resetFollowPointingSelection(FollowTargetPointingResetReason.none);
    }
    _clearRecordingGestureHold();
    _clearFaceDetectGestureHold();
  }

  /// Rate-limits the optional victory feedback hook.
  void _showVictoryToast(DateTime now) {
    final lastShownAt = _lastVictoryToastShownAt;
    if (lastShownAt != null && now.difference(lastShownAt).inSeconds < 3) {
      return;
    }

    _lastVictoryToastShownAt = now;
    // _showSnackBar("It's victory");
  }

  /// Records when punch should be displayed briefly outside recording mode.
  void _showPunchOnScreen(DateTime now) {
    _lastPunchScreenShownAt = now;
  }

  /// Clears every active gesture task and optionally resets camera zoom/focus.
  void _clearAllActiveGestureTasks({required bool resetCameraZoom}) {
    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState();
    _followObjectSequenceDetector.clear();
    _clearFollowObjectTargetCandidates();
    _clearLockedFollowTarget(clearIdentity: true);
    _clearRecordingGestureHold();
    _clearFaceDetectGestureHold();
    _lastPunchScreenShownAt = null;
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _lastGestureZoomAppliedAt = null;
    _pendingZoomLevel = null;
    _gestureZoomSuppressedUntil = null;
    _isManualZoomInteractionActive = false;
    _isTouchZoomGuideVisible = false;
    _isTouchZoomInteractionActive = false;
    _isZoomControlVisible = false;
    _zoomControlAutoHideTimer?.cancel();

    if (resetCameraZoom) {
      _lastCameraFocusPointSetAt = null;
      _lastCameraFocusPoint = null;
      unawaited(_updateCameraFocusAtNormalizedPoint(const Offset(0.5, 0.5)));

      if (_isCameraZoomSupported) {
        unawaited(_setCameraZoomLevel(_minZoomLevel, revealZoomControl: false));
      }
    }
  }

  /// Focuses the camera on the center of a detected hand box.
  Future<void> _updateCameraFocusPoint({
    required Hand hand,
    required Size imageSize,
  }) async {
    final box = hand.boundingBox;
    await _updateCameraFocusAtNormalizedPoint(
      Offset(
        (((box.left + box.right) / 2) / imageSize.width).clamp(0.0, 1.0),
        (((box.top + box.bottom) / 2) / imageSize.height).clamp(0.0, 1.0),
      ),
    );
  }

  /// Focuses the camera on the center of a selected follow target.
  Future<void> _updateCameraFocusPointForTarget(FollowTarget target) async {
    await _updateCameraFocusAtNormalizedPoint(target.displayBox.center);
  }

  /// Applies camera focus/exposure with throttling and bounds checking.
  Future<void> _updateCameraFocusAtNormalizedPoint(Offset focusPoint) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final now = DateTime.now();
    final lastCameraFocusPointSetAt = _lastCameraFocusPointSetAt;

    if (lastCameraFocusPointSetAt != null &&
        now.difference(lastCameraFocusPointSetAt) <
            HandGestureThresholds.followTargetFocusMinInterval) {
      return;
    }

    final boundedFocusPoint = Offset(
      focusPoint.dx.clamp(0.0, 1.0),
      focusPoint.dy.clamp(0.0, 1.0),
    );
    final lastFocusPoint = _lastCameraFocusPoint;
    if (lastFocusPoint != null &&
        (boundedFocusPoint - lastFocusPoint).distance <
            HandGestureThresholds.followTargetFocusMovementDeadband) {
      return;
    }

    _lastCameraFocusPointSetAt = now;
    _lastCameraFocusPoint = boundedFocusPoint;

    try {
      await controller.setFocusPoint(boundedFocusPoint);
      await controller.setExposurePoint(boundedFocusPoint);
    } catch (error) {
      debugPrint('Camera focus point update ignored: $error');
    }
  }
}

/// Cached face and object detections from the current frame.
class _FollowTargetDetections {
  const _FollowTargetDetections({
    required this.faces,
    required this.objects,
    this.facesDetectedAt,
    this.objectsDetectedAt,
  });

  final List<FollowTarget> faces;
  final List<FollowTarget> objects;
  final DateTime? facesDetectedAt;
  final DateTime? objectsDetectedAt;
}

/// Result of releasing follow-object selection when the hand is gone.
class _FollowObjectReleaseSelection {
  const _FollowObjectReleaseSelection({required this.target})
    : isWaitingForHandReturn = false,
      handReturnProgress = 0,
      cancellationReason = null;

  const _FollowObjectReleaseSelection.waitingForHandReturn({
    required double progress,
  }) : target = null,
       isWaitingForHandReturn = true,
       handReturnProgress = progress,
       cancellationReason = null;

  const _FollowObjectReleaseSelection.cancelled({required String reason})
    : target = null,
      isWaitingForHandReturn = false,
      handReturnProgress = 0,
      cancellationReason = reason;

  final FollowTarget? target;
  final bool isWaitingForHandReturn;
  final double handReturnProgress;
  final String? cancellationReason;
}

/// Exact remembered selection plus whether it still needs post-release proof.
class _FollowTargetReleaseSelection {
  const _FollowTargetReleaseSelection({
    required this.target,
    required this.requiresPostReleaseConfirmation,
    this.evaluatedDetectionCycleAt,
  });

  final FollowTarget target;
  final bool requiresPostReleaseConfirmation;
  final DateTime? evaluatedDetectionCycleAt;
}
