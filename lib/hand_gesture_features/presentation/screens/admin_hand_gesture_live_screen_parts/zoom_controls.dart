part of '../admin_hand_gesture_live_screen.dart';

extension on _AdminHandGestureLiveScreenState {
  /// True when the active camera reports a real zoom range.
  bool get _isCameraZoomSupported => _maxZoomLevel > _minZoomLevel;

  /// Allows partial zoom-out detection only when there is zoom to reduce.
  bool get _shouldAllowPartialZoomOutRecovery {
    return _isCameraZoomSupported && _currentZoomLevel > _minZoomLevel;
  }

  /// Blocks gesture zoom while the user is manually controlling zoom.
  bool get _shouldIgnoreGestureZoomForManualControl {
    if (_isTouchZoomGuideEnabled && _isTouchZoomInteractionActive) return true;
    if (_isManualZoomInteractionActive) return true;

    final suppressedUntil = _gestureZoomSuppressedUntil;
    if (suppressedUntil == null) return false;

    return DateTime.now().isBefore(suppressedUntil);
  }

  /// True when the floating manual zoom control should be visible.
  bool get _shouldShowZoomControlOverlay {
    return _isZoomControlVisible &&
        _isCameraZoomSupported &&
        !_isStartingVideoRecording &&
        !_isStoppingVideoRecording;
  }

  /// True when the two-circle touch zoom guide should be visible.
  bool get _shouldShowTouchZoomGuideOverlay {
    return _isTouchZoomGuideEnabled &&
        _isTouchZoomGuideVisible &&
        _isCameraZoomSupported &&
        _currentZoomLevel > _minZoomLevel + 0.001 &&
        !_isStartingVideoRecording &&
        !_isStoppingVideoRecording;
  }

  /// Reads min/max zoom from the controller and resets to minimum zoom.
  Future<void> _initializeZoomLevels(CameraController controller) async {
    _resetCameraZoomState();

    try {
      final rawMinZoomLevel = await controller.getMinZoomLevel();
      final rawMaxZoomLevel = await controller.getMaxZoomLevel();

      final minZoomLevel = rawMinZoomLevel <= rawMaxZoomLevel
          ? rawMinZoomLevel
          : rawMaxZoomLevel;
      final maxZoomLevel = rawMaxZoomLevel >= rawMinZoomLevel
          ? rawMaxZoomLevel
          : rawMinZoomLevel;

      _minZoomLevel = minZoomLevel;
      _maxZoomLevel = maxZoomLevel;
      _currentZoomLevel = minZoomLevel;

      if (_isCameraZoomSupported && controller.value.isInitialized) {
        await controller.setZoomLevel(_currentZoomLevel);
      }
    } catch (error) {
      debugPrint('Camera zoom initialization ignored: $error');
      _resetCameraZoomState();
    }
  }

  /// Clears all zoom-related UI, pending updates, and detector output state.
  void _resetCameraZoomState() {
    _minZoomLevel = 1;
    _maxZoomLevel = 1;
    _currentZoomLevel = 1;
    _pendingZoomLevel = null;
    _gestureZoomSuppressedUntil = null;
    _lastGestureZoomAppliedAt = null;
    _isManualZoomInteractionActive = false;
    _isTouchZoomGuideVisible = false;
    _isTouchZoomInteractionActive = false;
    _isApplyingZoom = false;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _isZoomControlVisible = false;
    _zoomControlAutoHideTimer?.cancel();
  }

  /// Applies a zoom gesture result at a throttled repeat interval.
  void _handleZoomDirection(ZoomDirection direction) {
    if (direction == ZoomDirection.none) {
      _lastAppliedZoomDirection = ZoomDirection.none;
      _lastGestureZoomAppliedAt = null;
      return;
    }

    if (_shouldIgnoreGestureZoomForManualControl) {
      _lastAppliedZoomDirection = ZoomDirection.none;
      _lastGestureZoomAppliedAt = null;
      return;
    }

    if (!_isCameraZoomSupported) return;

    if (direction == ZoomDirection.zoomIn) {
      _showTouchZoomGuideOverlay();
    }

    _showZoomControlOverlay();
    final now = DateTime.now();
    final lastAppliedAt = _lastGestureZoomAppliedAt;
    final canApplyZoom =
        direction != _lastAppliedZoomDirection ||
        lastAppliedAt == null ||
        now.difference(lastAppliedAt) >=
            HandGestureThresholds.gestureZoomRepeatInterval;

    _lastAppliedZoomDirection = direction;

    if (!canApplyZoom) return;

    _lastGestureZoomAppliedAt = now;
    unawaited(
      _applyCameraZoom(direction, step: HandGestureThresholds.gestureZoomStep),
    );
  }

  /// Moves the camera zoom up or down by [step].
  Future<void> _applyCameraZoom(
    ZoomDirection direction, {
    double step = HandGestureThresholds.zoomStep,
  }) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        direction == ZoomDirection.none ||
        !_isCameraZoomSupported) {
      return;
    }

    final zoomDelta = direction == ZoomDirection.zoomIn ? step : -step;
    final nextZoomLevel = (_currentZoomLevel + zoomDelta)
        .clamp(_minZoomLevel, _maxZoomLevel)
        .toDouble();

    if (nextZoomLevel == _currentZoomLevel) {
      _showZoomControlOverlay();
      return;
    }

    await _setCameraZoomLevel(nextZoomLevel, revealZoomControl: true);
  }

  /// Serializes camera zoom writes and keeps only the latest pending level.
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

    final targetZoomLevel = zoomLevel
        .clamp(_minZoomLevel, _maxZoomLevel)
        .toDouble();

    _pendingZoomLevel = targetZoomLevel;

    if (revealZoomControl) {
      _showZoomControlOverlay();
    }

    if (_isApplyingZoom) {
      if (mounted) {
        _setScreenState(() {
          _currentZoomLevel = targetZoomLevel;
          _updateTouchZoomGuideForZoomLevelState(targetZoomLevel);
        });
      } else {
        _currentZoomLevel = targetZoomLevel;
        _updateTouchZoomGuideForZoomLevelState(targetZoomLevel);
      }
      return;
    }

    _isApplyingZoom = true;

    try {
      // Camera zoom calls can arrive faster than the controller can apply them.
      // This loop drains only the newest pending value for smoother interaction.
      while (_pendingZoomLevel != null && _controller == controller) {
        final nextZoomLevel = _pendingZoomLevel!
            .clamp(_minZoomLevel, _maxZoomLevel)
            .toDouble();
        _pendingZoomLevel = null;

        await controller.setZoomLevel(nextZoomLevel);

        if (_controller != controller) return;

        if (mounted) {
          _setScreenState(() {
            _currentZoomLevel = nextZoomLevel;
            _updateTouchZoomGuideForZoomLevelState(nextZoomLevel);
          });
        } else {
          _currentZoomLevel = nextZoomLevel;
          _updateTouchZoomGuideForZoomLevelState(nextZoomLevel);
        }
      }
    } catch (error) {
      debugPrint('Camera zoom update ignored: $error');
    } finally {
      if (_controller == controller) {
        _isApplyingZoom = false;
      }
    }
  }

  /// Reveals the floating zoom control and optionally schedules auto-hide.
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

  /// Reveals the touch guide after a zoom-in gesture if the feature is enabled.
  void _showTouchZoomGuideOverlay() {
    if (!_isTouchZoomGuideEnabled || !_isCameraZoomSupported) return;

    if (mounted) {
      _setScreenState(() {
        _isTouchZoomGuideVisible = true;
      });
    } else {
      _isTouchZoomGuideVisible = true;
    }
  }

  /// Hides the touch guide once zoom returns to minimum.
  void _updateTouchZoomGuideForZoomLevelState(double zoomLevel) {
    if (zoomLevel > _minZoomLevel + 0.001) return;

    _isTouchZoomGuideVisible = false;
    _isTouchZoomInteractionActive = false;
  }

  /// Hides the floating zoom control after a short idle delay.
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

  /// Immediately hides the floating zoom control.
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

  /// Marks manual slider/button interaction as active.
  void _beginManualZoomInteraction() {
    _zoomControlAutoHideTimer?.cancel();
    _isManualZoomInteractionActive = true;
    _gestureZoomSuppressedUntil = null;
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
  }

  /// Ends manual interaction and briefly suppresses gesture zoom.
  void _endManualZoomInteraction() {
    _isManualZoomInteractionActive = false;
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _scheduleZoomControlAutoHide();
  }

  /// Applies a zoom level from the manual slider.
  void _handleManualZoomChanged(double zoomLevel) {
    _showZoomControlOverlay(autoHide: false);
    unawaited(_setCameraZoomLevel(zoomLevel, revealZoomControl: false));
  }

  /// Marks the two-circle touch guide as the active zoom input.
  void _beginTouchZoomInteraction() {
    if (!_isTouchZoomGuideEnabled) return;

    _zoomControlAutoHideTimer?.cancel();
    _isTouchZoomInteractionActive = true;
    _gestureZoomSuppressedUntil = null;
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
  }

  /// Ends touch zoom and briefly suppresses gesture zoom.
  void _endTouchZoomInteraction() {
    _isTouchZoomInteractionActive = false;
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
  }

  /// Applies a zoom level from the touch zoom guide.
  void _handleTouchZoomChanged(double zoomLevel) {
    if (!_isTouchZoomGuideEnabled) return;

    unawaited(_setCameraZoomLevel(zoomLevel, revealZoomControl: false));
  }

  /// Increases zoom from the manual plus button.
  void _handleManualZoomIncrease() {
    _applyManualZoomDelta(HandGestureThresholds.zoomStep);
  }

  /// Decreases zoom from the manual minus button.
  void _handleManualZoomDecrease() {
    _applyManualZoomDelta(-HandGestureThresholds.zoomStep);
  }

  /// Applies a fixed manual zoom delta and suppresses gesture zoom briefly.
  void _applyManualZoomDelta(double delta) {
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _showZoomControlOverlay();

    final nextZoomLevel = (_currentZoomLevel + delta)
        .clamp(_minZoomLevel, _maxZoomLevel)
        .toDouble();

    unawaited(_setCameraZoomLevel(nextZoomLevel, revealZoomControl: true));
  }

  /// Returns camera zoom to minimum and clears touch-guide state.
  void _resetManualZoom() {
    _gestureZoomSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    _lastGestureZoomAppliedAt = null;
    _lastAppliedZoomDirection = ZoomDirection.none;
    _isTouchZoomGuideVisible = false;
    _isTouchZoomInteractionActive = false;
    _showZoomControlOverlay();
    unawaited(_setCameraZoomLevel(_minZoomLevel, revealZoomControl: true));
  }
}
