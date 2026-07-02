part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
  bool get _isCameraZoomSupported => _maxZoomLevel > _minZoomLevel;

  bool get _shouldAllowPartialZoomOutRecovery {
    return _isCameraZoomSupported && _currentZoomLevel > _minZoomLevel;
  }

  bool get _shouldIgnoreGestureZoomForManualControl {
    if (_isManualZoomInteractionActive) return true;

    final suppressedUntil = _gestureZoomSuppressedUntil;
    if (suppressedUntil == null) return false;

    return DateTime.now().isBefore(suppressedUntil);
  }

  bool get _shouldShowZoomControlOverlay {
    return _isZoomControlVisible &&
        _isCameraZoomSupported &&
        !_isStartingVideoRecording &&
        !_isStoppingVideoRecording;
  }

  Future<void> _initializeZoomLevels(CameraController controller) async {
    _resetCameraZoomState();

    try {
      final rawMinZoomLevel = await controller.getMinZoomLevel();
      final rawMaxZoomLevel = await controller.getMaxZoomLevel();

      final minZoomLevel =
          rawMinZoomLevel <= rawMaxZoomLevel
              ? rawMinZoomLevel
              : rawMaxZoomLevel;
      final maxZoomLevel =
          rawMaxZoomLevel >= rawMinZoomLevel
              ? rawMaxZoomLevel
              : rawMinZoomLevel;

      _minZoomLevel = minZoomLevel;
      _maxZoomLevel = maxZoomLevel;
      _currentZoomLevel = minZoomLevel;

      if (_isCameraZoomSupported && controller.value.isInitialized) {
        await controller.setZoomLevel(_currentZoomLevel);
      }
    } catch (e) {
      debugPrint('Camera zoom initialization ignored: $e');
      _resetCameraZoomState();
    }
  }

  void _resetCameraZoomState() {
    _minZoomLevel = 1;
    _maxZoomLevel = 1;
    _currentZoomLevel = 1;
    _pendingZoomLevel = null;
    _gestureZoomSuppressedUntil = null;
    _isManualZoomInteractionActive = false;
    _isApplyingZoom = false;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _isZoomControlVisible = false;
    _zoomControlAutoHideTimer?.cancel();
  }

  void _handleZoomDirection(ZoomDirection direction) {
    if (direction == ZoomDirection.none) {
      _lastAppliedZoomDirection = ZoomDirection.none;
      return;
    }

    if (_shouldIgnoreGestureZoomForManualControl) {
      _lastAppliedZoomDirection = ZoomDirection.none;
      return;
    }

    if (direction == _lastAppliedZoomDirection) {
      _showZoomControlOverlay();
      return;
    }

    _lastAppliedZoomDirection = direction;

    if (!_isCameraZoomSupported) return;

    _showZoomControlOverlay();
    unawaited(_applyCameraZoom(direction));
  }

  Future<void> _applyCameraZoom(ZoomDirection direction) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        direction == ZoomDirection.none ||
        !_isCameraZoomSupported) {
      return;
    }

    final zoomDelta =
        direction == ZoomDirection.zoomIn
            ? HandGestureThresholds.zoomStep
            : -HandGestureThresholds.zoomStep;
    final nextZoomLevel =
        (_currentZoomLevel + zoomDelta)
            .clamp(_minZoomLevel, _maxZoomLevel)
            .toDouble();

    if (nextZoomLevel == _currentZoomLevel) {
      _showZoomControlOverlay();
      return;
    }

    await _setCameraZoomLevel(nextZoomLevel, revealZoomControl: true);
  }

  Future<void> _setCameraZoomLevel(
    double zoomLevel, {
    bool revealZoomControl = true,
  }) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        !_isCameraZoomSupported) {
      return;
    }

    final targetZoomLevel =
        zoomLevel.clamp(_minZoomLevel, _maxZoomLevel).toDouble();

    _pendingZoomLevel = targetZoomLevel;

    if (revealZoomControl) {
      _showZoomControlOverlay();
    }

    if (_isApplyingZoom) {
      if (mounted) {
        _setScreenState(() {
          _currentZoomLevel = targetZoomLevel;
        });
      } else {
        _currentZoomLevel = targetZoomLevel;
      }
      return;
    }

    _isApplyingZoom = true;

    try {
      while (_pendingZoomLevel != null && _controller == controller) {
        final nextZoomLevel =
            _pendingZoomLevel!.clamp(_minZoomLevel, _maxZoomLevel).toDouble();
        _pendingZoomLevel = null;

        await controller.setZoomLevel(nextZoomLevel);

        if (_controller != controller) return;

        if (mounted) {
          _setScreenState(() {
            _currentZoomLevel = nextZoomLevel;
          });
        } else {
          _currentZoomLevel = nextZoomLevel;
        }
      }
    } catch (e) {
      debugPrint('Camera zoom update ignored: $e');
    } finally {
      if (_controller == controller) {
        _isApplyingZoom = false;
      }
    }
  }

  void _showZoomControlOverlay({bool autoHide = true}) {
    if (!_isCameraZoomSupported) return;

    _zoomControlAutoHideTimer?.cancel();

    if (mounted) {
      _setScreenState(() {
        _isZoomControlVisible = true;
      });
    } else {
      _isZoomControlVisible = true;
    }

    if (autoHide) {
      _scheduleZoomControlAutoHide();
    }
  }

  void _scheduleZoomControlAutoHide() {
    _zoomControlAutoHideTimer?.cancel();
    _zoomControlAutoHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _setScreenState(() {
          _isZoomControlVisible = false;
        });
      } else {
        _isZoomControlVisible = false;
      }
    });
  }

  void _hideZoomControlOverlay() {
    _zoomControlAutoHideTimer?.cancel();

    if (mounted) {
      _setScreenState(() {
        _isZoomControlVisible = false;
      });
    } else {
      _isZoomControlVisible = false;
    }
  }

  void _beginManualZoomInteraction() {
    _zoomControlAutoHideTimer?.cancel();
    _isManualZoomInteractionActive = true;
    _gestureZoomSuppressedUntil = null;
  }

  void _endManualZoomInteraction() {
    _isManualZoomInteractionActive = false;
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _scheduleZoomControlAutoHide();
  }

  void _handleManualZoomChanged(double zoomLevel) {
    _showZoomControlOverlay(autoHide: false);
    unawaited(_setCameraZoomLevel(zoomLevel, revealZoomControl: false));
  }

  void _handleManualZoomIncrease() {
    _applyManualZoomDelta(HandGestureThresholds.zoomStep);
  }

  void _handleManualZoomDecrease() {
    _applyManualZoomDelta(-HandGestureThresholds.zoomStep);
  }

  void _applyManualZoomDelta(double delta) {
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _showZoomControlOverlay();

    final nextZoomLevel =
        (_currentZoomLevel + delta)
            .clamp(_minZoomLevel, _maxZoomLevel)
            .toDouble();

    unawaited(_setCameraZoomLevel(nextZoomLevel, revealZoomControl: true));
  }

  void _resetManualZoom() {
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _showZoomControlOverlay();
    unawaited(_setCameraZoomLevel(_minZoomLevel, revealZoomControl: true));
  }
}
