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
      final frameId = ++_cameraFrameId;
      final needsObjectTrackingFrame =
          _followObjectSequenceDetector.isTargetSelectionActive ||
          _followTargetProgress.phase == FollowTargetTrackingPhase.selecting ||
          _lockedFollowTarget?.type == FollowTargetType.object ||
          _followTargetIdentity?.type == FollowTargetType.object;
      final ObjectTrackingFrame? objectTrackingFrame =
          needsObjectTrackingFrame
              ? _objectTrackingFrameFactory.create(
                image: image,
                frameId: frameId,
                capturedAt: now,
                rotation: rotation,
                mirrorHorizontally: _shouldMirrorPreviewCoordinates(controller),
                isBgra: Platform.isIOS || Platform.isMacOS,
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
    } catch (e, st) {
      debugPrint('Hand gesture detection error: $e\n$st');
    } finally {
      _isProcessing = false;
    }
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
      deviceOrientation: controller.value.deviceOrientation,
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

  /// Applies gesture priority and updates all live-screen gesture UI state.
  Future<void> _updateGestureState(
    List<Hand> hands,
    Size detectionImageSize, {
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    final now = DateTime.now();
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
    // 5. zoom gestures
    // 6. movement directions and package labels.
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
        final selectedTarget = followObjectRelease.target;
        _clearFrameInterruptedGestureState(
          now: now,
          keepFollowObjectSequence: true,
        );

        _setScreenState(() {
          _gestureText =
              selectedTarget == null
                  ? 'No face or object selected'
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

      _clearFrameInterruptedGestureState(now: now);
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
      if (_followObjectSequenceDetector.isTargetSelectionActive) {
        final followObjectSequence = _followObjectSequenceDetector.update(
          hands.first,
          now,
          mirrorHorizontally: mirrorPalmGestureCoordinates,
          allowOppositePalmSide: allowBackCameraPalmFallback,
        );

        if (followObjectSequence.isTargetSelectionActive) {
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

        _clearFrameInterruptedGestureState(
          now: now,
          keepFollowObjectSequence: true,
        );

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
        final selectedTarget = followObjectRelease.target;
        _clearFrameInterruptedGestureState(
          now: now,
          keepFollowObjectSequence: true,
        );

        _setScreenState(() {
          _hands = hands;
          _detectionImageSize = detectionImageSize;
          _detectedHandsCount = hands.length;
          _handText = '';
          _gestureText =
              selectedTarget == null
                  ? 'No face or object selected'
                  : _followTargetText(selectedTarget);
          _gestureConfidence = selectedTarget == null ? 0 : 1;
          _isFollowingHand = false;
          _focusedHandBox = null;
          _focusImageSize = null;
          _lockedFollowTarget = selectedTarget;
        });
        return;
      }

      _clearFrameInterruptedGestureState(now: now);
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

    final bestHand =
        _handGeometry.bestReliableHand(
          reliableHands,
          focusedHandBox:
              _isFollowingHand &&
                      trackedFollowTarget == null &&
                      _followTargetIdentity == null
                  ? _focusedHandBox
                  : null,
        )!;
    final rawCustomGestureResult = _customGestureDetector.detect(
      hand: bestHand,
      imageSize: detectionImageSize,
      mirrorHorizontally: mirrorDirectionalGestureCoordinates,
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
        _moveDirectionDisplayHold.clear();
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
        _setLockedFollowTarget(faceTarget, captureIdentity: false);
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
        _gestureText =
            faceTarget == null
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

    var lockedFollowTarget = trackedFollowTarget;
    if (followObjectSequence.isTargetSelectionActive) {
      if (_followTargetProgress.phase != FollowTargetTrackingPhase.selecting) {
        _clearLockedFollowTarget(clearIdentity: true);
        _followTargetProgress.markSelecting();
      }
      lockedFollowTarget = null;
    }
    var releaseHadNoTarget = false;
    final releasePoint = followObjectSequence.releasePoint;
    if (releasePoint != null) {
      // Release points come from hand-detection image space; convert to the
      // normalized display space used by face/object candidates.
      final releaseDisplayPoint = _handPointToDisplayPoint(
        releasePoint,
        detectionImageSize,
      );
      lockedFollowTarget = await _selectFollowTargetAtReleasePoint(
        releaseDisplayPoint,
        image: image,
        rotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
      if (!mounted) return;

      if (lockedFollowTarget == null) {
        releaseHadNoTarget = true;
        _clearLockedFollowTarget(clearIdentity: true);
        _clearFollowObjectTargetCandidates();
      } else {
        _setLockedFollowTarget(lockedFollowTarget, captureIdentity: true);
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _clearFollowObjectTargetCandidates();
        unawaited(_updateCameraFocusPointForTarget(lockedFollowTarget));
      }
    } else if (followObjectSequence.isTargetSelectionActive) {
      await _refreshFollowObjectTargetCandidates(
        image: image,
        rotation: rotation,
        now: now,
        objectTrackingFrame: objectTrackingFrame,
      );
      if (!mounted) return;
      final handBox = bestHand.boundingBox;
      final predictedReleasePoint = _handPointToDisplayPoint(
        Offset(
          (handBox.left + handBox.right) / 2,
          (handBox.top + handBox.bottom) / 2,
        ),
        detectionImageSize,
      );
      _predictedFollowTarget = _followTargetSelector.selectNearest(
        releasePoint: predictedReleasePoint,
        faces: _freshFollowTargets(_followObjectCandidateFaces, now),
        objects: _freshFollowTargets(_followObjectCandidateObjects, now),
        detectedAfter: now.subtract(
          HandGestureThresholds.followTargetDetectionFreshness,
        ),
      );
    } else {
      _clearFollowObjectTargetCandidates();
    }

    final followObjectSequenceActive = followObjectSequence.isActive;
    final followObjectDetected =
        followObjectSequence.isDetected && lockedFollowTarget == null;
    final followTargetActive = lockedFollowTarget != null;
    final rememberedFollowTargetActive = _followTargetIdentity != null;
    final followTrackingActive =
        followTargetActive ||
        rememberedFollowTargetActive ||
        _isFollowingHand ||
        followObjectSequenceActive;

    final gesture = bestHand.gesture;
    final reliablePackageGesture =
        _handGeometry.isReliablePackageGesture(gesture) ? gesture : null;
    final knownPackageGesture =
        !followTrackingActive &&
                reliablePackageGesture != null &&
                reliablePackageGesture.type != GestureType.unknown &&
                reliablePackageGesture.type != GestureType.openPalm
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
        knownPackageGesture != null &&
        knownPackageGesture.type != GestureType.pointingUp;
    final packageGestureDirectionBlockReason =
        knownPackageGesture != null &&
                knownPackageGesture.type != GestureType.closedFist
            ? 'blocked: package ${knownPackageGesture.type.name}'
            : null;

    final canDetectZoom =
        !followTrackingActive &&
        customGestureLabels.isEmpty &&
        !hasOverlappingCustomGestures &&
        !recordingGestureActive &&
        !packageGestureBlocksZoom;

    var zoomDirection = ZoomDirection.none;
    if (canDetectZoom) {
      zoomDirection = _zoomGestureDetector.detect(
        hand: bestHand,
        imageSize: detectionImageSize,
        allowPartialZoomOut: _shouldAllowPartialZoomOutRecovery,
      );
    } else {
      _zoomGestureDetector.clearState();
    }

    var moveDirection = HandMoveDirection.none;
    final directionBlockReason =
        followTrackingActive
            ? 'blocked: follow active'
            : customGestureLabels.isNotEmpty
            ? 'blocked: custom ${customGestureLabels.join(', ')}'
            : hasOverlappingCustomGestures
            ? 'blocked: overlapping custom'
            : recordingGestureActive
            ? 'blocked: recording gesture'
            : packageGestureDirectionBlockReason;

    if (directionBlockReason == null) {
      moveDirection = _directionGestureDetector.detect(
        hand: bestHand,
        imageSize: detectionImageSize,
        mirrorHorizontally: mirrorDirectionalGestureCoordinates,
        now: now,
      );
    } else {
      _directionGestureDetector.clearState(reason: directionBlockReason);
    }

    final hasDirectionGesture = moveDirection != HandMoveDirection.none;

    if (moveDirection == HandMoveDirection.down) {
      zoomDirection = ZoomDirection.none;
      _zoomGestureDetector.clearState();
    } else if (hasDirectionGesture && zoomDirection == ZoomDirection.none) {
      _zoomGestureDetector.clearState();
    }

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
        hasOverlappingCustomGestures;

    final HandMoveDirection displayMoveDirection;
    if (directionDisplayBlockedByPriority) {
      _moveDirectionDisplayHold.clear();
      displayMoveDirection = HandMoveDirection.none;
    } else {
      displayMoveDirection = _moveDirectionDisplayHold.resolve(
        detectedDirection: moveDirection,
        now: now,
      );
    }

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
      } else if (releaseHadNoTarget) {
        _gestureText = 'No face or object selected';
        _gestureConfidence = 0;
      } else if (followObjectDetected) {
        _gestureText = 'Release on a face or object';
        _gestureConfidence = 1;
      } else if (rememberedFollowTargetActive && lockedFollowTarget == null) {
        _gestureText = 'Target unavailable — select it again';
        _gestureConfidence = 0;
      } else if (_isFollowingHand) {
        _gestureText = 'Following hand';
        _gestureConfidence = 1;
      } else if (followObjectSequenceActive) {
        _gestureText = followObjectSequenceMessage ?? 'Hand detected';
        _gestureConfidence =
            followObjectSequenceMessage == null
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
      } else if (displayMoveDirection == HandMoveDirection.down) {
        _gestureText = 'Moving down';
        _gestureConfidence = 1;
      } else if (zoomDirection == ZoomDirection.zoomIn) {
        _gestureText = _isCameraZoomSupported ? 'Zoom in' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
      } else if (zoomDirection == ZoomDirection.zoomOut) {
        _gestureText = _isCameraZoomSupported ? 'Zoom out' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
      } else if (moveDirection == HandMoveDirection.left) {
        _gestureText = 'Moving left';
        _gestureConfidence = 1;
      } else if (moveDirection == HandMoveDirection.right) {
        _gestureText = 'Moving right';
        _gestureConfidence = 1;
      } else if (displayMoveDirection == HandMoveDirection.up) {
        _gestureText = 'Moving up';
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

  /// Refreshes targets and selects the nearest target to a release point.
  Future<FollowTarget?> _selectFollowTargetAtReleasePoint(
    Offset releasePoint, {
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    var detections = await _refreshFollowObjectTargetCandidates(
      image: image,
      rotation: rotation,
      now: now,
      objectTrackingFrame: objectTrackingFrame,
    );

    var freshFaces = _freshFollowTargets(detections.faces, now);
    var freshObjects = _freshFollowTargets(detections.objects, now);
    if (freshFaces.isEmpty && freshObjects.isEmpty) {
      final pendingRequest = _objectDetectionRequests.pendingRequest;
      if (pendingRequest != null) {
        try {
          await pendingRequest.timeout(
            HandGestureThresholds.followTargetFreshDetectionWait,
          );
        } on TimeoutException {
          // A slow detector must not make release selection use stale boxes.
        } catch (error, stackTrace) {
          debugPrint('Fresh follow-target wait ignored: $error\n$stackTrace');
        }
        detections = await _refreshFollowObjectTargetCandidates(
          image: image,
          rotation: rotation,
          now: DateTime.now(),
          objectTrackingFrame: objectTrackingFrame,
        );
        final refreshedAt = DateTime.now();
        freshFaces = _freshFollowTargets(detections.faces, refreshedAt);
        freshObjects = _freshFollowTargets(detections.objects, refreshedAt);
      }
    }

    final selectionAt = DateTime.now();
    return _followTargetSelector.selectNearest(
      releasePoint: releasePoint,
      faces: freshFaces,
      objects: freshObjects,
      detectedAfter: selectionAt.subtract(
        HandGestureThresholds.followTargetDetectionFreshness,
      ),
    );
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
      _followObjectCandidateObjects = detections.objects;
    }

    return _FollowTargetDetections(
      faces: _followObjectCandidateFaces,
      objects: _followObjectCandidateObjects,
    );
  }

  /// Clears cached follow-object candidates from the debug/selection overlay.
  void _clearFollowObjectTargetCandidates() {
    _followObjectCandidateFaces = const [];
    _followObjectCandidateObjects = const [];
    _predictedFollowTarget = null;
  }

  /// Completes follow-object selection when the hand leaves the frame.
  Future<_FollowObjectReleaseSelection?>
  _releaseFollowObjectFromLastVisiblePoint({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required Size detectionImageSize,
    required DateTime now,
    required ObjectTrackingFrame? objectTrackingFrame,
  }) async {
    if (!_followObjectSequenceDetector.isTargetSelectionActive) {
      return null;
    }

    final releaseResult = _followObjectSequenceDetector
        .releaseFromLastVisiblePoint(now);
    final releasePoint = releaseResult.releasePoint;

    if (releasePoint == null) {
      _clearFollowObjectTargetCandidates();
      return null;
    }

    final releaseDisplayPoint = _handPointToDisplayPoint(
      releasePoint,
      detectionImageSize,
    );
    final target = await _selectFollowTargetAtReleasePoint(
      releaseDisplayPoint,
      image: image,
      rotation: rotation,
      now: now,
      objectTrackingFrame: objectTrackingFrame,
    );

    if (target == null) {
      _clearLockedFollowTarget(clearIdentity: true);
      _clearFollowObjectTargetCandidates();
      return const _FollowObjectReleaseSelection(target: null);
    }

    _setLockedFollowTarget(target, captureIdentity: true);
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    _clearFollowObjectTargetCandidates();
    unawaited(_updateCameraFocusPointForTarget(target));

    return _FollowObjectReleaseSelection(target: target);
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

    var visiblePrevious = previous;
    if (targetType == FollowTargetType.object &&
        previous != null &&
        objectTrackingFrame != null) {
      final opticalResult =
          _objectOpticalFlowTracker.isActive
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
      return identity == null
          ? _keepOrClearLostFollowTarget(now)
          : visiblePrevious;
    }

    final candidates =
        targetType == FollowTargetType.face
            ? detections.faces
            : detections.objects;
    final detectionCycleAt =
        targetType == FollowTargetType.face
            ? detections.facesDetectedAt
            : detections.objectsDetectedAt;

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
        final historicalBox =
            sourceFrameId == null
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

      if (!_followTargetProgress.recordVisibleMiss()) {
        return visiblePrevious;
      }
      _dropFollowTargetAfterMiss();
      return null;
    }
    return null;
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

    final inputRotation = _inputImageRotationFromCameraFrameRotation(rotation);
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    var faces = const <FollowTarget>[];
    var objects = const <FollowTarget>[];
    DateTime? facesDetectedAt;

    if (includeFaces) {
      final faceDetector = _faceDetector;
      if (faceDetector != null) {
        try {
          final inputImage = _inputImageFromCameraImage(image, rotation);
          final detectedFaces =
              inputImage == null
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
        } catch (e, st) {
          debugPrint('Face detection ignored: $e\n$st');
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
      objectsDetectedAt:
          includeObjects ? _cachedObjectDetectionBatch?.completedAt : null,
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
        detect: () => objectDetector.detect(image, rotation: frameRotation),
      );
    } catch (e, st) {
      debugPrint('Object detection ignored: $e\n$st');
    }

    if (request != null) {
      unawaited(
        request
            .then((detectedObjects) {
              if (generation != _objectDetectionGeneration) return;

              final completedAt = DateTime.now();
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
                detectedAt: batch.sourceCapturedAt,
                sourceFrameId: batch.sourceFrameId,
              );
              _cachedObjectTargets = objects;

              if (_followObjectSequenceDetector.isTargetSelectionActive ||
                  _lockedFollowTarget?.type == FollowTargetType.object) {
                _followObjectCandidateObjects = objects;
              }

              if (!mounted) return;
              _setScreenState(() {});
            })
            .catchError((Object e, StackTrace st) {
              if (generation != _objectDetectionGeneration) return;
              debugPrint('Object detection ignored: $e\n$st');
            }),
      );
    }

    return _cachedObjectTargets;
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
    final displayBox = _mlKitRectToDisplayBox(
      face.boundingBox,
      imageSize: imageSize,
      rotation: inputRotation,
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
    final displayBox =
        object.source == AppObjectDetectionSource.googleMlKit
            ? _mlKitRectToDisplayBox(
              object.boundingBox,
              imageSize: object.imageSize,
              rotation: _inputImageRotationFromCameraFrameRotation(
                frameRotation,
              ),
            )
            : imageRectToDisplayBox(
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
    if (_objectDetectionService != null ||
        _objectDetectionServiceStartup != null) {
      return;
    }

    final generation = _objectDetectionGeneration;
    final startup = ObjectDetectionService.start();
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
            debugPrint('Object detector startup ignored: $e\n$st');
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
    _cachedObjectTargets = const [];
    _cachedObjectDetectionBatch = null;
  }

  /// Stops the object detector and rejects stale async object results.
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
              debugPrint('Object detector close ignored: $e\n$st');
            }),
      );
    }
  }

  /// Converts a camera frame into the ML Kit input format for the platform.
  ml_face.InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraFrameRotation? rotation,
  ) {
    if (Platform.isAndroid) {
      final bytes = _androidNv21Bytes(image);
      if (bytes == null) return null;

      return ml_face.InputImage.fromBytes(
        bytes: bytes,
        metadata: ml_face.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _inputImageRotationFromCameraFrameRotation(rotation),
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
          rotation: _inputImageRotationFromCameraFrameRotation(rotation),
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  /// Converts Android YUV planes into NV21 bytes for ML Kit.
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

    // Copy the full-resolution luma plane first, then interleave V and U for
    // the chroma plane expected by NV21.
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

  /// Safely reads a pixel value from a camera image plane.
  int _planeValue(Plane plane, int row, int col) {
    final pixelStride = plane.bytesPerPixel ?? 1;
    final index = row * plane.bytesPerRow + col * pixelStride;
    if (index < 0 || index >= plane.bytes.length) return 128;
    return plane.bytes[index];
  }

  /// Maps hand-detector frame rotation to ML Kit input-image rotation.
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

  /// Converts an ML Kit bounding box into normalized preview display space.
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

  /// Converts one ML Kit point into normalized preview display space.
  Offset _mlKitPointToDisplayPoint(
    Offset point, {
    required Size imageSize,
    required ml_face.InputImageRotation rotation,
  }) {
    final mirrorHorizontally = _shouldMirrorPreviewCoordinates(_controller);
    final x = _translateMlKitX(
      point.dx,
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    );
    final y = _translateMlKitY(
      point.dy,
      imageSize: imageSize,
      rotation: rotation,
    );

    return Offset(x.clamp(0, 1), y.clamp(0, 1));
  }

  /// Normalizes the x-coordinate for the active ML Kit rotation.
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

  /// Normalizes the y-coordinate for the active ML Kit rotation.
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
    final rotatedPoint =
        controller == null
            ? normalizedPoint
            : _rotateNormalizedPoint(
              normalizedPoint,
              _previewQuarterTurnsForOverlays(controller),
            );
    final displayPoint =
        _shouldMirrorPreviewCoordinates(controller)
            ? Offset(1.0 - rotatedPoint.dx, rotatedPoint.dy)
            : rotatedPoint;

    return Offset(
      displayPoint.dx.clamp(0.0, 1.0),
      displayPoint.dy.clamp(0.0, 1.0),
    );
  }

  /// Rotates a normalized point by quarter turns.
  Offset _rotateNormalizedPoint(Offset point, int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return Offset(1 - point.dy, point.dx);
      case 2:
        return Offset(1 - point.dx, 1 - point.dy);
      case 3:
        return Offset(point.dy, 1 - point.dx);
      default:
        return point;
    }
  }

  /// Status text for a locked follow target.
  String _followTargetText(FollowTarget target) {
    final identity = _followTargetIdentity;
    if (identity != null) return 'Target locked: ${identity.displayLabel}';
    return 'Following ${target.displayLabel.toLowerCase()}';
  }

  String _followTargetStatusText({
    required FollowTarget? visibleTarget,
    required String fallbackText,
  }) {
    if (visibleTarget != null) return _followTargetText(visibleTarget);

    if (_followTargetIdentity != null) {
      return 'Target unavailable — select it again';
    }

    return fallbackText;
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
    }
    _setVisibleFollowTarget(target);
  }

  void _setVisibleFollowTarget(FollowTarget target) {
    _lockedFollowTarget = target;
    _lockedFollowTargetLostAt = null;
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

  void _resetFollowTargetTrackingState() {
    _followTargetIdentity = null;
    _followTargetProgress.reset();
    _lastEvaluatedFollowDetectionAt = null;
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
      _gestureText =
          promptReselect
              ? 'Show open palm to select a new target'
              : 'Follow target cancelled';
      _gestureConfidence = 0;
    });
  }

  /// Clears the "call me" face-detection hold timer.
  void _clearFaceDetectGestureHold() {
    _faceDetectGestureStartedAt = null;
  }

  /// Clears detector history after a missing or unreliable frame boundary.
  void _clearFrameInterruptedGestureState({
    required DateTime now,
    bool keepFollowObjectSequence = false,
  }) {
    _customGestureDetector.clearState();
    _zoomGestureDetector.markPoseInvalid(now);
    _directionGestureDetector.clearState();
    _moveDirectionDisplayHold.clear();
    if (!keepFollowObjectSequence) {
      _followObjectSequenceDetector.clear();
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
    _moveDirectionDisplayHold.clear();
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
    } catch (e) {
      debugPrint('Camera focus point update ignored: $e');
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
  const _FollowObjectReleaseSelection({required this.target});

  final FollowTarget? target;
}
