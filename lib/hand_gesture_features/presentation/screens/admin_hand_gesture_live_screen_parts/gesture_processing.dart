part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
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
      );
    } catch (e, st) {
      debugPrint('Hand gesture detection error: $e\n$st');
    } finally {
      _isProcessing = false;
    }
  }

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

  Future<void> _updateGestureState(
    List<Hand> hands,
    Size detectionImageSize, {
    required CameraImage image,
    required CameraFrameRotation? rotation,
  }) async {
    final now = DateTime.now();
    final trackedFollowTarget = await _refreshLockedFollowTarget(
      image: image,
      rotation: rotation,
      now: now,
    );
    if (!mounted) return;

    if (hands.isEmpty) {
      final followObjectRelease =
          await _releaseFollowObjectFromLastVisiblePoint(
            image: image,
            rotation: rotation,
            detectionImageSize: detectionImageSize,
            now: now,
          );
      if (!mounted) return;

      if (followObjectRelease != null) {
        final selectedTarget = followObjectRelease.target;
        _zoomGestureDetector.markPoseInvalid(now);
        _directionGestureDetector.clearState();
        _moveDirectionDisplayHold.clear();
        _clearRecordingGestureHold();
        _clearFaceDetectGestureHold();

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

      _zoomGestureDetector.markPoseInvalid(now);
      _directionGestureDetector.clearState();
      _moveDirectionDisplayHold.clear();
      _followObjectSequenceDetector.clear();
      _clearFollowObjectTargetCandidates();
      _clearRecordingGestureHold();
      _clearFaceDetectGestureHold();

      _setScreenState(() {
        _gestureText =
            trackedFollowTarget == null
                ? 'No hand detected'
                : _followTargetText(trackedFollowTarget);
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

    final reliableHands = hands
        .where((hand) => hand.score >= HandGestureThresholds.minHandScore)
        .toList(growable: false);

    if (reliableHands.isEmpty) {
      final followObjectRelease =
          await _releaseFollowObjectFromLastVisiblePoint(
            image: image,
            rotation: rotation,
            detectionImageSize: detectionImageSize,
            now: now,
          );
      if (!mounted) return;

      if (followObjectRelease != null) {
        final selectedTarget = followObjectRelease.target;
        _zoomGestureDetector.markPoseInvalid(now);
        _directionGestureDetector.clearState();
        _moveDirectionDisplayHold.clear();
        _clearRecordingGestureHold();
        _clearFaceDetectGestureHold();

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

      if (_isFollowingHand && trackedFollowTarget == null) {
        final trackedHand = _selectTrackedHand(hands);
        _updateFocusedHand(hand: trackedHand, imageSize: detectionImageSize);
        _directionGestureDetector.clearState();
        _moveDirectionDisplayHold.clear();

        _setScreenState(() {
          _hands = hands;
          _detectionImageSize = detectionImageSize;
          _detectedHandsCount = hands.length;
          _handText = trackedHand.handedness.displayLabel;
          _gestureText = 'Following hand';
          _gestureConfidence = 1;
        });
        return;
      }

      _zoomGestureDetector.markPoseInvalid(now);
      _directionGestureDetector.clearState();
      _moveDirectionDisplayHold.clear();
      _followObjectSequenceDetector.clear();
      _clearFollowObjectTargetCandidates();
      _clearRecordingGestureHold();
      _clearFaceDetectGestureHold();

      _setScreenState(() {
        _hands = hands;
        _detectionImageSize = detectionImageSize;
        _detectedHandsCount = hands.length;
        _handText = '';
        _gestureText =
            trackedFollowTarget == null
                ? 'Move hand closer'
                : _followTargetText(trackedFollowTarget);
        _gestureConfidence = trackedFollowTarget == null ? 0 : 1;
        _isFollowingHand = false;
        _focusedHandBox = null;
        _focusImageSize = null;
        _lockedFollowTarget = trackedFollowTarget;
      });
      return;
    }

    final bestHand =
        _isFollowingHand && trackedFollowTarget == null
            ? _selectTrackedHand(hands)
            : reliableHands.reduce(
              (currentBest, next) =>
                  next.score > currentBest.score ? next : currentBest,
            );

    final mirrorDirectionalGestureCoordinates =
        _shouldMirrorDirectionalGestureCoordinates(_controller);
    final mirrorPalmGestureCoordinates = _shouldMirrorPalmGestureCoordinates(
      _controller,
    );
    final allowBackCameraPalmFallback = _shouldAllowBackCameraPalmFallback(
      _controller,
    );
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

    if (rawCustomGestureResult.isOnlyCallMe && trackedFollowTarget == null) {
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
        _lockedFollowTarget = faceTarget;
        _lockedFollowTargetLostAt = null;
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
    var releaseHadNoTarget = false;
    final releasePoint = followObjectSequence.releasePoint;
    if (releasePoint != null) {
      final releaseDisplayPoint = _handPointToDisplayPoint(
        releasePoint,
        detectionImageSize,
      );
      lockedFollowTarget = await _selectFollowTargetAtReleasePoint(
        releaseDisplayPoint,
        image: image,
        rotation: rotation,
        now: now,
      );
      if (!mounted) return;

      if (lockedFollowTarget == null) {
        releaseHadNoTarget = true;
        _clearLockedFollowTarget();
        _clearFollowObjectTargetCandidates();
      } else {
        _lockedFollowTarget = lockedFollowTarget;
        _lockedFollowTargetLostAt = null;
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
      );
      if (!mounted) return;
    } else {
      _clearFollowObjectTargetCandidates();
    }

    final followObjectSequenceActive = followObjectSequence.isActive;
    final followObjectDetected =
        followObjectSequence.isDetected && lockedFollowTarget == null;
    final followTargetActive = lockedFollowTarget != null;
    final followTrackingActive =
        followTargetActive || _isFollowingHand || followObjectSequenceActive;

    final gesture = bestHand.gesture;
    final hasKnownGesture =
        !followTrackingActive &&
        gesture != null &&
        gesture.type != GestureType.unknown &&
        gesture.type != GestureType.openPalm &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;

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
        gesture != null &&
        gesture.type == GestureType.victory &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;

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
        hasKnownGesture && gesture.type != GestureType.pointingUp;
    final packageGestureBlocksDirection =
        hasKnownGesture && gesture.type != GestureType.closedFist;

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
            : packageGestureBlocksDirection
            ? 'blocked: package ${gesture.type.name}'
            : null;

    if (directionBlockReason == null) {
      moveDirection = _directionGestureDetector.detect(
        hand: bestHand,
        imageSize: detectionImageSize,
        mirrorHorizontally: mirrorDirectionalGestureCoordinates,
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
      } else if (_isFollowingHand) {
        _gestureText = 'Following hand';
        _gestureConfidence = 1;
      } else if (followObjectSequenceActive) {
        _gestureText = followObjectSequenceMessage ?? 'Hand detected';
        _gestureConfidence = followObjectSequenceMessage == null ? 0 : 1;
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
      } else if (moveDirection == HandMoveDirection.up) {
        _gestureText = 'Moving up';
        _gestureConfidence = 1;
      } else if (hasKnownGesture) {
        if (gesture.type == GestureType.thumbUp) {
          _gestureText = 'Stop & Continue Action';
        } else if (gesture.type == GestureType.victory) {
          _gestureText = _isVideoRecording ? 'End record video' : 'Victory';
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

  Future<FollowTarget?> _selectFollowTargetAtReleasePoint(
    Offset releasePoint, {
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
  }) async {
    final detections = await _refreshFollowObjectTargetCandidates(
      image: image,
      rotation: rotation,
      now: now,
    );

    return _followTargetSelector.selectNearest(
      releasePoint: releasePoint,
      faces: detections.faces,
      objects: detections.objects,
    );
  }

  Future<_FollowTargetDetections> _refreshFollowObjectTargetCandidates({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
  }) async {
    final detections = await _detectFollowTargets(
      image: image,
      rotation: rotation,
      now: now,
      includeFaces: true,
      includeObjects: true,
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

  void _clearFollowObjectTargetCandidates() {
    _followObjectCandidateFaces = const [];
    _followObjectCandidateObjects = const [];
  }

  Future<_FollowObjectReleaseSelection?>
  _releaseFollowObjectFromLastVisiblePoint({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required Size detectionImageSize,
    required DateTime now,
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
    );

    if (target == null) {
      _clearLockedFollowTarget();
      _clearFollowObjectTargetCandidates();
      return const _FollowObjectReleaseSelection(target: null);
    }

    _lockedFollowTarget = target;
    _lockedFollowTargetLostAt = null;
    _isFollowingHand = false;
    _focusedHandBox = null;
    _focusImageSize = null;
    _clearFollowObjectTargetCandidates();
    unawaited(_updateCameraFocusPointForTarget(target));

    return _FollowObjectReleaseSelection(target: target);
  }

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

  Future<FollowTarget?> _refreshLockedFollowTarget({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
  }) async {
    final previous = _lockedFollowTarget;
    if (previous == null) return null;

    final detections = await _detectFollowTargets(
      image: image,
      rotation: rotation,
      now: now,
      includeFaces: previous.type == FollowTargetType.face,
      includeObjects: previous.type == FollowTargetType.object,
    );
    if (detections == null) return _keepOrClearLostFollowTarget(now);

    final candidates =
        previous.type == FollowTargetType.face
            ? detections.faces
            : detections.objects;
    final updated = _followTargetSelector.track(
      previous: previous,
      candidates: candidates,
    );

    if (updated == null) return _keepOrClearLostFollowTarget(now);

    _lockedFollowTarget = updated;
    _lockedFollowTargetLostAt = null;
    unawaited(_updateCameraFocusPointForTarget(updated));
    return updated;
  }

  Future<_FollowTargetDetections?> _detectFollowTargets({
    required CameraImage image,
    required CameraFrameRotation? rotation,
    required DateTime now,
    required bool includeFaces,
    required bool includeObjects,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    final inputImage = _inputImageFromCameraImage(image, rotation);
    if (inputImage == null) return null;

    final inputRotation = _inputImageRotationFromCameraFrameRotation(rotation);
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    var faces = const <FollowTarget>[];
    var objects = const <FollowTarget>[];

    if (includeFaces) {
      final faceDetector = _faceDetector;
      if (faceDetector != null) {
        try {
          final detectedFaces = await faceDetector.processImage(inputImage);
          faces = [
            for (final face in detectedFaces)
              FollowTarget(
                type: FollowTargetType.face,
                boundingBox: face.boundingBox,
                displayBox: _mlKitRectToDisplayBox(
                  face.boundingBox,
                  imageSize: imageSize,
                  rotation: inputRotation,
                ),
                detectedAt: now,
                trackingId: face.trackingId,
                label: 'Face',
              ),
          ];
        } catch (e, st) {
          debugPrint('Face detection ignored: $e\n$st');
        }
      }
    }

    if (includeObjects) {
      final objectDetector = _objectDetector;
      if (objectDetector != null) {
        try {
          final detectedObjects = await objectDetector.processImage(inputImage);
          objects = [
            for (final object in detectedObjects)
              FollowTarget(
                type: FollowTargetType.object,
                boundingBox: object.boundingBox,
                displayBox: _mlKitRectToDisplayBox(
                  object.boundingBox,
                  imageSize: imageSize,
                  rotation: inputRotation,
                ),
                detectedAt: now,
                trackingId: object.trackingId,
                label: _objectLabel(object),
              ),
          ];
        } catch (e, st) {
          debugPrint('Object detection ignored: $e\n$st');
        }
      }
    }

    return _FollowTargetDetections(faces: faces, objects: objects);
  }

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

  String _objectLabel(ml_object.DetectedObject object) {
    if (object.labels.isEmpty) return 'Object';

    final bestLabel = object.labels.reduce(
      (currentBest, next) =>
          next.confidence > currentBest.confidence ? next : currentBest,
    );
    return bestLabel.text.isEmpty ? 'Object' : bestLabel.text;
  }

  String _followTargetText(FollowTarget target) {
    return 'Following ${target.displayLabel.toLowerCase()}';
  }

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

  void _clearLockedFollowTarget() {
    _lockedFollowTarget = null;
    _lockedFollowTargetLostAt = null;
  }

  void _clearFaceDetectGestureHold() {
    _faceDetectGestureStartedAt = null;
  }

  void _showVictoryToast(DateTime now) {
    final lastShownAt = _lastVictoryToastShownAt;
    if (lastShownAt != null && now.difference(lastShownAt).inSeconds < 3) {
      return;
    }

    _lastVictoryToastShownAt = now;
    // _showSnackBar("It's victory");
  }

  void _showPunchOnScreen(DateTime now) {
    _lastPunchScreenShownAt = now;
  }

  void _clearAllActiveGestureTasks({required bool resetCameraZoom}) {
    _zoomGestureDetector.clearState();
    _directionGestureDetector.clearState();
    _moveDirectionDisplayHold.clear();
    _followObjectSequenceDetector.clear();
    _clearFollowObjectTargetCandidates();
    _clearLockedFollowTarget();
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
      unawaited(_updateCameraFocusAtNormalizedPoint(const Offset(0.5, 0.5)));

      if (_isCameraZoomSupported) {
        unawaited(_setCameraZoomLevel(_minZoomLevel, revealZoomControl: false));
      }
    }
  }

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

  Future<void> _updateCameraFocusPointForTarget(FollowTarget target) async {
    await _updateCameraFocusAtNormalizedPoint(target.displayBox.center);
  }

  Future<void> _updateCameraFocusAtNormalizedPoint(Offset focusPoint) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
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

    final boundedFocusPoint = Offset(
      focusPoint.dx.clamp(0.0, 1.0),
      focusPoint.dy.clamp(0.0, 1.0),
    );

    try {
      await controller.setFocusPoint(boundedFocusPoint);
      await controller.setExposurePoint(boundedFocusPoint);
    } catch (e) {
      debugPrint('Camera focus point update ignored: $e');
    }
  }
}

class _FollowTargetDetections {
  const _FollowTargetDetections({required this.faces, required this.objects});

  final List<FollowTarget> faces;
  final List<FollowTarget> objects;
}

class _FollowObjectReleaseSelection {
  const _FollowObjectReleaseSelection({required this.target});

  final FollowTarget? target;
}
