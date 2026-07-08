import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Two-circle touch guide that maps finger distance to camera zoom.
class TouchZoomGuideOverlay extends StatefulWidget {
  const TouchZoomGuideOverlay({
    super.key,
    required this.currentZoomLevel,
    required this.minZoomLevel,
    required this.maxZoomLevel,
    required this.onZoomChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final double currentZoomLevel;
  final double minZoomLevel;
  final double maxZoomLevel;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  static const firstCircleKey = ValueKey('touchZoomGuideFirstCircle');
  static const secondCircleKey = ValueKey('touchZoomGuideSecondCircle');

  @override
  /// Creates state that tracks the two active touch pointers.
  State<TouchZoomGuideOverlay> createState() => _TouchZoomGuideOverlayState();
}

/// Tracks touch circles and emits zoom changes while both are dragged.
class _TouchZoomGuideOverlayState extends State<TouchZoomGuideOverlay> {
  static const double _circleRadius = 25;
  static const double _touchRadius = 58;
  static const double _minCircleGap = 8;

  Offset? _firstCircleCenter;
  Offset? _secondCircleCenter;
  Size _lastSize = Size.zero;

  int? _firstPointer;
  int? _secondPointer;
  double? _lastSentZoomLevel;
  bool _isTracking = false;

  @override
  /// Stops touch tracking when zoom returns to the minimum level.
  void didUpdateWidget(covariant TouchZoomGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isAtMinimumZoom(widget.currentZoomLevel)) {
      _clearTracking(notifyEnd: _isTracking);
    }
  }

  @override
  /// Builds the guide line and two draggable circle targets.
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        _syncCircleCentersToZoom(size);

        final positions = _visibleCirclePositions(size);
        final firstCenter = positions.$1;
        final secondCenter = positions.$2;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _TouchZoomGuidePainter(
                  firstCenter: firstCenter,
                  secondCenter: secondCenter,
                ),
              ),
              _CircleTarget(
                key: TouchZoomGuideOverlay.firstCircleKey,
                center: firstCenter,
                radius: _circleRadius,
                isActive: _firstPointer != null,
              ),
              _CircleTarget(
                key: TouchZoomGuideOverlay.secondCircleKey,
                center: secondCenter,
                radius: _circleRadius,
                isActive: _secondPointer != null,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Assigns a pointer to the nearest inactive circle target.
  void _handlePointerDown(PointerDownEvent event) {
    if (_isTracking || _lastSize == Size.zero) return;

    final positions = _visibleCirclePositions(_lastSize);
    final firstCenter = positions.$1;
    final secondCenter = positions.$2;
    final position = event.localPosition;

    if (_firstPointer == null &&
        (position - firstCenter).distance <= _touchRadius) {
      setState(() {
        _firstPointer = event.pointer;
        _firstCircleCenter = _clampToBounds(position);
      });
    } else if (_secondPointer == null &&
        (position - secondCenter).distance <= _touchRadius) {
      setState(() {
        _secondPointer = event.pointer;
        _secondCircleCenter = _clampToBounds(position);
      });
    } else {
      return;
    }

    _tryStartTracking();
  }

  /// Moves whichever circle owns the pointer and emits a zoom update.
  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _firstPointer && event.pointer != _secondPointer) {
      return;
    }

    setState(() {
      if (event.pointer == _firstPointer) {
        _firstCircleCenter = _clampToBounds(event.localPosition);
      } else if (event.pointer == _secondPointer) {
        _secondCircleCenter = _clampToBounds(event.localPosition);
      }
    });

    if (_isTracking) {
      _emitZoomLevel();
    }
  }

  /// Ends the two-finger interaction when either pointer lifts.
  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == _firstPointer || event.pointer == _secondPointer) {
      _clearTracking(notifyEnd: _isTracking);
    }
  }

  /// Cancels tracking when the system cancels either active pointer.
  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _firstPointer || event.pointer == _secondPointer) {
      _clearTracking(notifyEnd: _isTracking);
    }
  }

  /// Starts zoom tracking once both circles have active pointers.
  void _tryStartTracking() {
    final firstCenter = _firstCircleCenter;
    final secondCenter = _secondCircleCenter;

    if (_firstPointer == null || _secondPointer == null) return;
    if (firstCenter == null || secondCenter == null) return;

    final distance = (secondCenter - firstCenter).distance;
    if (distance <= 0) return;

    _isTracking = true;
    _lastSentZoomLevel = widget.currentZoomLevel;
    widget.onInteractionStart();
    _emitZoomLevel();
  }

  /// Converts current circle distance into a zoom level callback.
  void _emitZoomLevel() {
    final firstCenter = _firstCircleCenter;
    final secondCenter = _secondCircleCenter;

    if (firstCenter == null || secondCenter == null) {
      return;
    }

    final distance = (secondCenter - firstCenter).distance;
    final nextZoomLevel = _zoomLevelForDistance(distance, _lastSize);

    final lastSent = _lastSentZoomLevel;
    if (lastSent != null && (nextZoomLevel - lastSent).abs() < 0.005) {
      return;
    }

    _lastSentZoomLevel = nextZoomLevel;
    widget.onZoomChanged(nextZoomLevel);
  }

  /// Clears pointer ownership and optionally notifies the parent.
  void _clearTracking({required bool notifyEnd}) {
    if (notifyEnd) {
      widget.onInteractionEnd();
    }

    setState(() {
      _firstPointer = null;
      _secondPointer = null;
      _lastSentZoomLevel = null;
      _isTracking = false;
    });
  }

  /// Returns either dragged positions or positions derived from current zoom.
  (Offset, Offset) _visibleCirclePositions(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return (Offset.zero, Offset.zero);
    }

    final firstCenter = _firstCircleCenter;
    final secondCenter = _secondCircleCenter;

    if (firstCenter != null && secondCenter != null) {
      return (firstCenter, secondCenter);
    }

    return _circlePositionsForZoom(size, widget.currentZoomLevel);
  }

  /// Repositions idle circles to match the latest zoom level.
  void _syncCircleCentersToZoom(Size size) {
    _lastSize = size;

    if (size.width <= 0 || size.height <= 0) return;
    if (_isTracking || _firstPointer != null || _secondPointer != null) return;

    final positions = _circlePositionsForZoom(size, widget.currentZoomLevel);
    _firstCircleCenter = positions.$1;
    _secondCircleCenter = positions.$2;
  }

  /// Calculates resting circle positions for a given zoom level.
  (Offset, Offset) _circlePositionsForZoom(Size size, double zoomLevel) {
    final center = Offset(size.width / 2, size.height * 0.44);
    final guideDistance = _distanceForZoomLevel(zoomLevel, size);
    final halfDistance = guideDistance / 2;
    final safeCenter = Offset(
      center.dx
          .clamp(
            _circleRadius + halfDistance,
            size.width - _circleRadius - halfDistance,
          )
          .toDouble(),
      center.dy.clamp(_circleRadius, size.height - _circleRadius).toDouble(),
    );
    final first = Offset(safeCenter.dx - halfDistance, safeCenter.dy);
    final second = Offset(safeCenter.dx + halfDistance, safeCenter.dy);

    return (first, second);
  }

  /// Keeps a dragged circle fully inside the overlay bounds.
  Offset _clampToBounds(Offset position) {
    final size = _lastSize;
    if (size.width <= 0 || size.height <= 0) return position;

    return Offset(
      position.dx.clamp(_circleRadius, size.width - _circleRadius).toDouble(),
      position.dy.clamp(_circleRadius, size.height - _circleRadius).toDouble(),
    );
  }

  /// Checks whether the camera is effectively at minimum zoom.
  bool _isAtMinimumZoom(double zoomLevel) {
    return zoomLevel <= widget.minZoomLevel + 0.001;
  }

  /// Converts zoom level to guide distance between the two circles.
  double _distanceForZoomLevel(double zoomLevel, Size size) {
    final minDistance = _minGuideDistance;
    final maxDistance = _maxGuideDistance(size);
    final zoomRange = widget.maxZoomLevel - widget.minZoomLevel;

    if (zoomRange <= 0 || maxDistance <= minDistance) {
      return minDistance;
    }

    final zoomRatio = ((zoomLevel - widget.minZoomLevel) / zoomRange).clamp(
      0.0,
      1.0,
    );

    return minDistance + (maxDistance - minDistance) * zoomRatio;
  }

  /// Converts guide distance back to a camera zoom level.
  double _zoomLevelForDistance(double distance, Size size) {
    final minDistance = _minGuideDistance;
    final maxDistance = _maxGuideDistance(size);
    final distanceRange = maxDistance - minDistance;

    if (distanceRange <= 0) return widget.minZoomLevel;

    final distanceRatio = ((distance - minDistance) / distanceRange).clamp(
      0.0,
      1.0,
    );

    return widget.minZoomLevel +
        (widget.maxZoomLevel - widget.minZoomLevel) * distanceRatio;
  }

  /// Minimum distance that keeps the two guide circles from overlapping.
  double get _minGuideDistance => _circleRadius * 2 + _minCircleGap;

  /// Maximum distance available within the current overlay size.
  double _maxGuideDistance(Size size) {
    final maxDistance = math.min(size.width, size.height) - _circleRadius * 2;
    return math.max(_minGuideDistance, maxDistance);
  }
}

/// Draggable visual target used by the touch zoom guide.
class _CircleTarget extends StatelessWidget {
  const _CircleTarget({
    super.key,
    required this.center,
    required this.radius,
    required this.isActive,
  });

  final Offset center;
  final double radius;
  final bool isActive;

  @override
  /// Builds the positioned circle with active/inactive styling.
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: isActive ? 0.48 : 0.32),
          border: Border.all(
            color: isActive ? const Color(0xFF00FB46) : Colors.white,
            width: isActive ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF00FB46) : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the line between the two zoom-guide circles.
class _TouchZoomGuidePainter extends CustomPainter {
  const _TouchZoomGuidePainter({
    required this.firstCenter,
    required this.secondCenter,
  });

  final Offset firstCenter;
  final Offset secondCenter;

  @override
  /// Draws a shadowed guide line between the two circles.
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(firstCenter, secondCenter, shadowPaint);
    canvas.drawLine(firstCenter, secondCenter, linePaint);
  }

  @override
  /// Repaints when either guide endpoint moves.
  bool shouldRepaint(covariant _TouchZoomGuidePainter oldDelegate) {
    return firstCenter != oldDelegate.firstCenter ||
        secondCenter != oldDelegate.secondCenter;
  }
}
