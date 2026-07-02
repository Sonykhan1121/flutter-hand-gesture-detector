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

      debugPrint(
        'image send to detectFromCameraImage : $image ${Platform.isIOS}',
      );
      final hands = await detector.detectFromCameraImage(
        image,
        rotation: rotation,
        isBgra: Platform.isMacOS,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );
      debugPrint('hands : ${hands.length}');

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

  void _updateGestureState(List<Hand> hands, Size detectionImageSize) {
    if (hands.isEmpty) {
      _zoomGestureDetector.markPoseInvalid(DateTime.now());
      _followObjectSequenceDetector.clear();
      _clearRecordingGestureHold();

      _setScreenState(() {
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

      _zoomGestureDetector.markPoseInvalid(DateTime.now());
      _followObjectSequenceDetector.clear();
      _clearRecordingGestureHold();

      _setScreenState(() {
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

    final bestHand =
        _isFollowingHand
            ? _selectTrackedHand(hands)
            : reliableHands.reduce(
              (currentBest, next) =>
                  next.score > currentBest.score ? next : currentBest,
            );

    final now = DateTime.now();
    final mirrorDirectionalGestureCoordinates =
        _shouldMirrorDirectionalGestureCoordinates(_controller);
    final mirrorPalmGestureCoordinates = _shouldMirrorPalmGestureCoordinates(
      _controller,
    );
    final allowBackCameraPalmFallback = _shouldAllowBackCameraPalmFallback(
      _controller,
    );

    final followObjectSequence = _followObjectSequenceDetector.update(
      bestHand,
      now,
      mirrorHorizontally: mirrorPalmGestureCoordinates,
      allowOppositePalmSide: allowBackCameraPalmFallback,
    );

    final followObjectSequenceActive = followObjectSequence.isActive;
    final followObjectDetected = followObjectSequence.isDetected;
    final followTrackingActive = _isFollowingHand || followObjectSequenceActive;

    final gesture = bestHand.gesture;
    final hasKnownGesture =
        !followTrackingActive &&
        gesture != null &&
        gesture.type != GestureType.unknown &&
        gesture.type != GestureType.openPalm &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;

    final customGestureResult =
        followTrackingActive
            ? CustomGestureDetectionResult.empty
            : _customGestureDetector.detect(
              hand: bestHand,
              imageSize: detectionImageSize,
              mirrorHorizontally: mirrorDirectionalGestureCoordinates,
            );

    final customGestureLabels = customGestureResult.labels;
    final hasSingleCustomGesture = customGestureLabels.length == 1;
    final hasOverlappingCustomGestures = customGestureLabels.length > 1;
    final hasVictoryGesture =
        !followTrackingActive &&
        customGestureLabels.isEmpty &&
        gesture != null &&
        gesture.type == GestureType.victory &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;
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

    final moveDirection =
        !followTrackingActive &&
                customGestureLabels.isEmpty &&
                !recordingGestureActive
            ? _directionGestureDetector.detect(
              hand: bestHand,
              imageSize: detectionImageSize,
              mirrorHorizontally: mirrorDirectionalGestureCoordinates,
            )
            : HandMoveDirection.none;

    final hasDirectionGesture = moveDirection != HandMoveDirection.none;

    if (hasDirectionGesture) {
      _zoomGestureDetector.clearState();
    }

    final zoomDirection =
        !followTrackingActive &&
                customGestureLabels.isEmpty &&
                !recordingGestureActive &&
                !hasDirectionGesture
            ? _zoomGestureDetector.detect(
              hand: bestHand,
              imageSize: detectionImageSize,
              allowPartialZoomOut: _shouldAllowPartialZoomOutRecovery,
            )
            : ZoomDirection.none;

    _handleZoomDirection(zoomDirection);

    final followObjectSequenceMessage =
        followObjectSequence.packageGestureType?.displayLabel;

    final shouldFocusOnHand =
        _isFollowingHand ||
        (followObjectSequenceActive &&
            followObjectSequence.packageGestureType == GestureType.closedFist);

    if (shouldFocusOnHand) {
      _updateFocusedHand(hand: bestHand, imageSize: detectionImageSize);
    }

    _setScreenState(() {
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
      } else if (recordingGestureFeedback != null) {
        _gestureText = recordingGestureFeedback.text;
        _gestureConfidence = recordingGestureFeedback.confidence;
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
        _gestureText = _isCameraZoomSupported ? 'Zoom in' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
      } else if (zoomDirection == ZoomDirection.zoomOut) {
        _gestureText = _isCameraZoomSupported ? 'Zoom out' : 'Zoom unavailable';
        _gestureConfidence = _isCameraZoomSupported ? 1 : 0;
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
}
