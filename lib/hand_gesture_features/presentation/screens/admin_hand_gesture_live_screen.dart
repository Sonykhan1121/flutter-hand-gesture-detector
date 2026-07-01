import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../utils/app_snack_bar.dart';
import '../../data/factories/hand_detector_factory.dart';
import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/enums/hand_move_direction.dart';
import '../../domain/enums/zoom_direction.dart';
import '../../domain/models/custom_gesture_detection_result.dart';
import '../../domain/services/custom_gesture_detector.dart';
import '../../domain/services/direction_gesture_detector.dart';
import '../../domain/services/follow_object_sequence_detector.dart';
import '../../domain/services/zoom_gesture_detector.dart';
import '../painters/hand_focus_overlay_painter.dart';
import '../painters/hand_landmark_overlay_painter.dart';
import '../painters/recording_hand_landmark_overlay_painter.dart';
import '../utils/hand_gesture_label_mapper.dart';
import '../widgets/gesture_status_panel.dart';
import '../widgets/hand_camera_loading_view.dart';
import '../widgets/round_icon_button.dart';
import '../widgets/zoom_control_overlay.dart';

part 'admin_hand_gesture_live_screen_parts/camera_lifecycle.dart';
part 'admin_hand_gesture_live_screen_parts/zoom_controls.dart';
part 'admin_hand_gesture_live_screen_parts/recording_controls.dart';
part 'admin_hand_gesture_live_screen_parts/gesture_processing.dart';
part 'admin_hand_gesture_live_screen_parts/live_screen_ui.dart';

class AdminHandGestureLiveScreen extends StatefulWidget {
  const AdminHandGestureLiveScreen({super.key, required this.fontorback});

  /// Same flow as your previous camera page:
  /// 0 = back camera, anything else = front camera.
  final int fontorback;

  @override
  State<AdminHandGestureLiveScreen> createState() =>
      _AdminHandGestureLiveScreenState();
}

class _AdminHandGestureLiveScreenState extends State<AdminHandGestureLiveScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  HandDetector? _handDetector;

  final _customGestureDetector = CustomGestureDetector();
  final _directionGestureDetector = const DirectionGestureDetector();
  final _zoomGestureDetector = ZoomGestureDetector();

  late final FollowObjectSequenceDetector _followObjectSequenceDetector;

  List<CameraDescription> cameras = const [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  bool _isCameraSetupInProgress = false;
  bool _isFollowingHand = false;
  bool _hasCameraFailure = false;
  bool _shouldOpenSettingsOnRetry = false;
  bool _isApplyingZoom = false;
  bool _isRecordingActionInProgress = false;
  bool _isStartingVideoRecording = false;
  bool _isStoppingVideoRecording = false;
  bool _isRecordingPreviewCorrectionActive = false;
  bool _isZoomControlVisible = false;
  bool _isManualZoomInteractionActive = false;

  String _gestureText = 'Show your hand';
  String _handText = '';
  String _cameraStatusTitle = 'Initializing camera...';
  String _cameraStatusMessage = 'Preparing hand gesture detection.';
  String _cameraActionLabel = 'Try Again';
  double _gestureConfidence = 0;
  double _minZoomLevel = 1;
  double _maxZoomLevel = 1;
  double _currentZoomLevel = 1;
  double? _pendingZoomLevel;
  DateTime? _gestureZoomSuppressedUntil;
  int _detectedHandsCount = 0;

  List<Hand> _hands = const [];
  Size? _detectionImageSize;
  Rect? _focusedHandBox;
  Size? _focusImageSize;
  DateTime? _lastFrameProcessedAt;
  DateTime? _lastCameraFocusPointSetAt;
  DateTime? _lastOrientationDebugPrintedAt;
  Timer? _recordingTimer;
  Timer? _zoomControlAutoHideTimer;
  DateTime? _recordingSegmentStartedAt;
  Duration _recordingElapsedBeforePause = Duration.zero;
  Duration _recordingElapsed = Duration.zero;
  ZoomDirection _lastAppliedZoomDirection = ZoomDirection.none;
  _RecordingGestureAction? _activeRecordingGestureAction;
  DateTime? _recordingGestureStartedAt;
  bool _recordingGestureTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _followObjectSequenceDetector = FollowObjectSequenceDetector(
      onDebug: debugPrint,
    );

    _currentLensDirection = widget.fontorback == 0
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    _requestCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetRecordingTimer();
    _zoomControlAutoHideTimer?.cancel();
    final controller = _controller;

    if (controller != null) {
      unawaited(_disposeControllerFromWidgetDispose(controller));
    }

    unawaited(_handDetector?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isCameraInitialized) {
        unawaited(_startCameraStream());
      } else if (!_hasCameraFailure && !_isCameraSetupInProgress) {
        unawaited(_requestCameraPermission());
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stopCameraStream());
    }
  }

  void _setScreenState(VoidCallback update) {
    if (mounted) {
      setState(update);
    } else {
      update();
    }
  }

  @override
  Widget build(BuildContext context) => _buildLiveScreen(context);
}
