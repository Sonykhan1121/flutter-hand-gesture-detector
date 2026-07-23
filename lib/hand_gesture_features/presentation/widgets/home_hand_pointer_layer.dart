import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/factories/hand_detector_factory.dart';
import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/services/hand_geometry_service.dart';
import '../../domain/utils/camera_preview_geometry.dart';

/// Coordinates the app-wide point-8 cursor and its active camera source.
class HomeHandPointerController {
  _HomeHandPointerLayerState? _state;

  /// Releases the home camera before another camera page is opened.
  Future<void> suspend() => _state?.suspend() ?? Future<void>.value();

  /// Restarts transparent hand pointing after returning to the home page.
  Future<void> resume() => _state?.resume() ?? Future<void>.value();

  /// Uses point 8 from a camera page while the hidden home camera is stopped.
  void updateExternalPointer({
    required Object owner,
    required Offset? indexTip,
    required Size detectionImageSize,
    required bool mirrorHorizontally,
    int previewQuarterTurns = 0,
    bool showCursor = true,
  }) {
    _state?._updateExternalPointer(
      owner: owner,
      indexTip: indexTip,
      detectionImageSize: detectionImageSize,
      mirrorHorizontally: mirrorHorizontally,
      previewQuarterTurns: previewQuarterTurns,
      showCursor: showCursor,
    );
  }

  /// Stops accepting point 8 from the camera page identified by [owner].
  void clearExternalPointer(Object owner) {
    _state?._clearExternalPointer(owner);
  }

  void _attach(_HomeHandPointerLayerState state) => _state = state;

  void _detach(_HomeHandPointerLayerState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// Uses a hidden home camera or a camera page's landmarks for one root cursor.
class HomeHandPointerLayer extends StatefulWidget {
  const HomeHandPointerLayer({
    super.key,
    required this.controller,
    this.enabled = true,
    this.selectionHoldDuration = const Duration(seconds: 2),
    @visibleForTesting this.cameraStartOverride,
  });

  final HomeHandPointerController controller;
  final bool enabled;
  final Duration selectionHoldDuration;
  final Future<void> Function()? cameraStartOverride;

  @override
  State<HomeHandPointerLayer> createState() => _HomeHandPointerLayerState();
}

class _HomeHandPointerLayerState extends State<HomeHandPointerLayer>
    with WidgetsBindingObserver {
  static const _geometry = HandGeometryService();
  static const _cameraRestartDelays = <Duration>[
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];
  static const _cameraWatchdogInterval = Duration(seconds: 2);
  static const _cameraFrameStallTimeout = Duration(seconds: 5);
  final _dwellOverlayKey = GlobalKey<_HomeGestureDwellOverlayState>();

  CameraController? _cameraController;
  HandDetector? _handDetector;
  List<CameraDescription>? _cameras;
  Future<void> _cameraWork = Future<void>.value();
  bool _streaming = false;
  bool _processing = false;
  bool _explicitlySuspended = false;
  bool _appAllowsCamera = true;
  bool _permissionRequested = false;
  Timer? _cameraRestartTimer;
  Timer? _cameraWatchdogTimer;
  int _cameraStartGeneration = 0;
  DateTime? _lastProcessedAt;
  DateTime? _lastCameraFrameAt;
  Offset? _indexTip;
  Size? _detectionImageSize;
  bool _mirrorHorizontally = false;
  _ExternalHandPointer? _externalPointer;

  bool get _isSupportedPlatform =>
      widget.cameraStartOverride != null ||
      Platform.isAndroid ||
      Platform.isIOS;

  bool get _shouldRun =>
      widget.enabled &&
      _isSupportedPlatform &&
      !_explicitlySuspended &&
      _appAllowsCamera;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(resume());
    });
  }

  @override
  void didUpdateWidget(covariant HomeHandPointerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        unawaited(resume());
      } else {
        unawaited(suspend());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appAllowsCamera = true;
        if (!_explicitlySuspended) unawaited(_requestCameraStart());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _appAllowsCamera = false;
        _cancelCameraRestart();
        _clearCursor();
        unawaited(_enqueue(_stopCamera));
        break;
    }
  }

  /// Stops and disposes the home camera before camera-based navigation.
  Future<void> suspend() {
    _explicitlySuspended = true;
    _cancelCameraRestart();
    _clearCursor();
    return _enqueue(_stopCamera);
  }

  /// Allows the transparent home camera to start again.
  Future<void> resume() {
    _explicitlySuspended = false;
    _clearAnyExternalPointer();
    return _requestCameraStart();
  }

  /// Reopens the transparent home detector after another page releases camera.
  Future<void> _requestCameraStart() {
    _cameraRestartTimer?.cancel();
    _cameraRestartTimer = null;
    final generation = ++_cameraStartGeneration;
    return _enqueue(() => _attemptCameraStart(generation, 0));
  }

  Future<void> _attemptCameraStart(int generation, int retryIndex) async {
    if (generation != _cameraStartGeneration || !_shouldRun) return;

    try {
      await _startCamera();
    } catch (error) {
      debugPrint(
        'Home hand pointer camera start attempt ${retryIndex + 1} failed: '
        '$error',
      );
      _scheduleCameraRestart(generation, retryIndex);
    }
  }

  void _scheduleCameraRestart(int generation, int retryIndex) {
    if (generation != _cameraStartGeneration ||
        !_shouldRun ||
        _cameraRestartDelays.isEmpty) {
      return;
    }

    final boundedIndex = retryIndex < _cameraRestartDelays.length
        ? retryIndex
        : _cameraRestartDelays.length - 1;
    final nextIndex = boundedIndex < _cameraRestartDelays.length - 1
        ? boundedIndex + 1
        : boundedIndex;
    _cameraRestartTimer?.cancel();
    _cameraRestartTimer = Timer(_cameraRestartDelays[boundedIndex], () {
      _cameraRestartTimer = null;
      if (!mounted || generation != _cameraStartGeneration || !_shouldRun) {
        return;
      }
      unawaited(_enqueue(() => _attemptCameraStart(generation, nextIndex)));
    });
  }

  void _cancelCameraRestart() {
    _cameraStartGeneration += 1;
    _cameraRestartTimer?.cancel();
    _cameraRestartTimer = null;
  }

  void _armCameraWatchdog() {
    _cameraWatchdogTimer?.cancel();
    if (!_shouldRun ||
        widget.cameraStartOverride != null ||
        _cameraController == null) {
      _cameraWatchdogTimer = null;
      return;
    }

    _cameraWatchdogTimer = Timer.periodic(_cameraWatchdogInterval, (_) {
      if (!mounted || !_shouldRun) {
        _cancelCameraWatchdog();
        return;
      }

      final lastFrameAt = _lastCameraFrameAt;
      final streamStalled =
          !_streaming ||
          lastFrameAt == null ||
          DateTime.now().difference(lastFrameAt) > _cameraFrameStallTimeout;
      if (!streamStalled) return;

      _cancelCameraWatchdog();
      final generation = ++_cameraStartGeneration;
      unawaited(
        _enqueue(() async {
          if (generation != _cameraStartGeneration || !_shouldRun) return;
          await _stopCamera();
          await _attemptCameraStart(generation, 0);
        }),
      );
    });
  }

  void _cancelCameraWatchdog() {
    _cameraWatchdogTimer?.cancel();
    _cameraWatchdogTimer = null;
    _lastCameraFrameAt = null;
  }

  void _updateExternalPointer({
    required Object owner,
    required Offset? indexTip,
    required Size detectionImageSize,
    required bool mirrorHorizontally,
    required int previewQuarterTurns,
    required bool showCursor,
  }) {
    if (!mounted) return;
    if (indexTip == null) _dwellOverlayKey.currentState?._cancelHoldNow();
    final next = _ExternalHandPointer(
      owner: owner,
      indexTip: indexTip,
      detectionImageSize: detectionImageSize,
      mirrorHorizontally: mirrorHorizontally,
      previewQuarterTurns: previewQuarterTurns,
      showCursor: showCursor,
    );
    if (next == _externalPointer) return;
    setState(() => _externalPointer = next);
  }

  void _clearExternalPointer(Object owner) {
    if (!mounted || !identical(_externalPointer?.owner, owner)) return;
    _dwellOverlayKey.currentState?._cancelHoldNow();
    setState(() => _externalPointer = null);
  }

  void _clearAnyExternalPointer() {
    if (!mounted || _externalPointer == null) return;
    _dwellOverlayKey.currentState?._cancelHoldNow();
    setState(() => _externalPointer = null);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _cameraWork.then((_) => action());
    _cameraWork = result.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Home hand pointer camera error: $error\n$stackTrace');
    });
    return _cameraWork;
  }

  Future<void> _startCamera() async {
    if (!_shouldRun || _cameraController != null) return;

    final cameraStartOverride = widget.cameraStartOverride;
    if (cameraStartOverride != null) {
      await cameraStartOverride();
      return;
    }

    var permission = await Permission.camera.status;
    if (permission.isDenied && !_permissionRequested) {
      _permissionRequested = true;
      permission = await Permission.camera.request();
    }
    if (!permission.isGranted || !_shouldRun) return;

    _cameras ??= await availableCameras();
    final cameras = _cameras!;
    if (cameras.isEmpty || !_shouldRun) return;

    _handDetector ??= await HandDetectorFactory.create();
    if (!_shouldRun) return;

    final selectedCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      if (!_shouldRun) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      _mirrorHorizontally =
          selectedCamera.lensDirection == CameraLensDirection.front &&
          !Platform.isIOS;
      await controller.startImageStream(_processFrame);
      _streaming = true;
      _lastCameraFrameAt = DateTime.now();
      _armCameraWatchdog();
    } catch (_) {
      if (identical(_cameraController, controller)) {
        _cameraController = null;
      }
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _stopCamera() async {
    _cancelCameraWatchdog();
    final controller = _cameraController;
    _cameraController = null;
    _streaming = false;
    _lastProcessedAt = null;
    _clearCursor();
    if (controller == null) return;

    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (error) {
      debugPrint('Home hand pointer stream stop ignored: $error');
    }
    try {
      await controller.dispose();
    } catch (error) {
      debugPrint('Home hand pointer camera dispose ignored: $error');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    _lastCameraFrameAt = DateTime.now();
    final controller = _cameraController;
    final detector = _handDetector;
    if (!_shouldRun ||
        _processing ||
        !_streaming ||
        controller == null ||
        detector == null) {
      return;
    }

    final now = DateTime.now();
    final lastProcessedAt = _lastProcessedAt;
    if (lastProcessedAt != null &&
        now.difference(lastProcessedAt) <
            HandGestureThresholds.minFrameProcessInterval) {
      return;
    }
    _lastProcessedAt = now;
    _processing = true;

    try {
      final rotation = rotationForFrame(
        width: image.width,
        height: image.height,
        sensorOrientation: controller.description.sensorOrientation,
        isFrontCamera:
            controller.description.lensDirection == CameraLensDirection.front,
        deviceOrientation:
            controller.value.lockedCaptureOrientation ??
            controller.value.deviceOrientation,
      );
      final imageSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: HandGestureThresholds.maxDetectionDimension,
      );
      final hands = await _detectHands(
        detector: detector,
        image: image,
        rotation: rotation,
      );
      if (!mounted || !_shouldRun) return;

      final hand = _geometry.bestReliableHand(hands);
      final tip = hand == null
          ? null
          : _geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
      setState(() {
        _indexTip = tip == null ? null : Offset(tip.x, tip.y);
        _detectionImageSize = imageSize;
      });
      if (tip == null) _dwellOverlayKey.currentState?._cancelHoldNow();
    } catch (error, stackTrace) {
      debugPrint('Home hand pointer detection ignored: $error\n$stackTrace');
      _clearCursor();
    } finally {
      _processing = false;
    }
  }

  Future<List<Hand>> _detectHands({
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
      maxDim: HandGestureThresholds.maxDetectionDimension,
    );
  }

  void _clearCursor() {
    if (!mounted || (_indexTip == null && _detectionImageSize == null)) return;
    setState(() {
      _indexTip = null;
      _detectionImageSize = null;
    });
    _dwellOverlayKey.currentState?._cancelHoldNow();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        final external = _externalPointer;
        final sourceSize = external != null
            ? external.detectionImageSize
            : _detectionImageSize;
        final sourceTip = external != null ? external.indexTip : _indexTip;
        final cursor = sourceSize == null || sourceTip == null
            ? null
            : detectionPointToPreviewCanvas(
                sourcePoint: sourceTip,
                detectionImageSize: sourceSize,
                canvasSize: canvasSize,
                mirrorHorizontally:
                    external?.mirrorHorizontally ?? _mirrorHorizontally,
                previewQuarterTurns: external?.previewQuarterTurns ?? 0,
                useRecordingPreviewMapping: false,
              );
        return HomeGestureDwellOverlay(
          key: _dwellOverlayKey,
          cursor: cursor,
          showCursor: external?.showCursor ?? true,
          selectionHoldDuration: widget.selectionHoldDuration,
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller._detach(this);
    _explicitlySuspended = true;
    _appAllowsCamera = false;
    _cancelCameraRestart();
    _cancelCameraWatchdog();
    final detector = _handDetector;
    _handDetector = null;
    unawaited(
      _cameraWork
          .then((_) async {
            await _stopCamera();
            await detector?.dispose();
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('Home hand pointer shutdown error: $error\n$stackTrace');
          }),
    );
    super.dispose();
  }
}

class _ExternalHandPointer {
  const _ExternalHandPointer({
    required this.owner,
    required this.indexTip,
    required this.detectionImageSize,
    required this.mirrorHorizontally,
    required this.previewQuarterTurns,
    required this.showCursor,
  });

  final Object owner;
  final Offset? indexTip;
  final Size detectionImageSize;
  final bool mirrorHorizontally;
  final int previewQuarterTurns;
  final bool showCursor;

  @override
  bool operator ==(Object other) {
    return other is _ExternalHandPointer &&
        identical(other.owner, owner) &&
        other.indexTip == indexTip &&
        other.detectionImageSize == detectionImageSize &&
        other.mirrorHorizontally == mirrorHorizontally &&
        other.previewQuarterTurns == previewQuarterTurns &&
        other.showCursor == showCursor;
  }

  @override
  int get hashCode => Object.hash(
    identityHashCode(owner),
    indexTip,
    detectionImageSize,
    mirrorHorizontally,
    previewQuarterTurns,
    showCursor,
  );
}

/// Holds point 8 over the nearest enabled semantic tap target and activates it.
class HomeGestureDwellOverlay extends StatefulWidget {
  const HomeGestureDwellOverlay({
    super.key,
    required this.cursor,
    this.showCursor = true,
    this.selectionHoldDuration = const Duration(seconds: 2),
  });

  final Offset? cursor;
  final bool showCursor;
  final Duration selectionHoldDuration;

  @override
  State<HomeGestureDwellOverlay> createState() =>
      _HomeGestureDwellOverlayState();
}

class _HomeGestureDwellOverlayState extends State<HomeGestureDwellOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;
  Timer? _selectionTimer;
  RenderObject? _hoveredTarget;
  bool _activationCommitted = false;
  bool _targetUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: widget.selectionHoldDuration,
    );
  }

  @override
  void didUpdateWidget(covariant HomeGestureDwellOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cursor == null && oldWidget.cursor != null) {
      _cancelHoldNow();
    }
    if (oldWidget.selectionHoldDuration != widget.selectionHoldDuration) {
      _holdController.duration = widget.selectionHoldDuration;
      final target = _hoveredTarget;
      if (target != null && !_activationCommitted) _restartHold(target);
    }
  }

  void _commitTarget(RenderObject target) {
    final onTap = _tapCallbackFor(target);
    if (!mounted ||
        _activationCommitted ||
        !identical(target, _hoveredTarget) ||
        !target.attached ||
        onTap == null) {
      return;
    }

    _activationCommitted = true;
    _selectionTimer?.cancel();
    try {
      onTap.call();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'home hand pointer',
          context: ErrorDescription('while activating a held home control'),
        ),
      );
    }
  }

  void _scheduleTargetUpdate() {
    if (_targetUpdateScheduled) return;
    _targetUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _targetUpdateScheduled = false;
      if (!mounted) return;
      final nextTarget = _tapTargetAt(widget.cursor);
      if (identical(nextTarget, _hoveredTarget)) return;
      setState(() {
        _hoveredTarget = nextTarget;
        _activationCommitted = false;
        _selectionTimer?.cancel();
        _holdController
          ..stop()
          ..value = 0;
        if (nextTarget != null) _restartHold(nextTarget);
      });
    });
  }

  void _restartHold(RenderObject target) {
    _selectionTimer?.cancel();
    _holdController
      ..stop()
      ..value = 0
      ..forward();
    _selectionTimer = Timer(
      widget.selectionHoldDuration,
      () => _commitTarget(target),
    );
  }

  void _cancelHoldNow() {
    _selectionTimer?.cancel();
    _hoveredTarget = null;
    _activationCommitted = false;
    _holdController
      ..stop()
      ..value = 0;
  }

  RenderObject? _tapTargetAt(Offset? cursor) {
    if (cursor == null || !cursor.dx.isFinite || !cursor.dy.isFinite) {
      return null;
    }
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      cursor,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderObject && _tapCallbackFor(target) != null) {
        return target;
      }
    }
    return null;
  }

  VoidCallback? _tapCallbackFor(RenderObject target) {
    if (target is RenderSemanticsGestureHandler) return target.onTap;
    if (target is RenderSemanticsAnnotations) return target.properties.onTap;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleTargetUpdate();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) => CustomPaint(
          key: const Key('homeGesturePointerOverlay'),
          painter: _HomeGesturePointerPainter(
            cursor: widget.showCursor ? widget.cursor : null,
            progress: _hoveredTarget == null ? 0 : _holdController.value,
            overAction: _hoveredTarget != null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _holdController.dispose();
    super.dispose();
  }
}

class _HomeGesturePointerPainter extends CustomPainter {
  const _HomeGesturePointerPainter({
    required this.cursor,
    required this.progress,
    required this.overAction,
  });

  final Offset? cursor;
  final double progress;
  final bool overAction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = cursor;
    if (center == null || !center.dx.isFinite || !center.dy.isFinite) return;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFD740);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = overAction ? Colors.white54 : Colors.white30;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF00C853);

    canvas.drawCircle(center, 11, fill);
    canvas.drawCircle(center, 11, border);
    canvas.drawCircle(center, 19, track);
    if (overAction && progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 19),
        -1.5707963267948966,
        6.283185307179586 * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }

    final label = TextPainter(
      text: const TextSpan(
        text: '8',
        style: TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HomeGesturePointerPainter oldDelegate) {
    return oldDelegate.cursor != cursor ||
        oldDelegate.progress != progress ||
        oldDelegate.overAction != overAction;
  }
}
