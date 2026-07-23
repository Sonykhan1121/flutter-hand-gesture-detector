import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as ml_face;
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../utils/app_snack_bar.dart';
import '../../data/factories/hand_detector_factory.dart';
import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/enums/camera_preview_mode.dart';
import '../../domain/enums/follow_object_release_reason.dart';
import '../../domain/enums/follow_target_type.dart';
import '../../domain/enums/follow_target_tracking_phase.dart';
import '../../domain/enums/gesture_debug_mode.dart';
import '../../domain/enums/hand_move_direction.dart';
import '../../domain/enums/object_detection_backend.dart';
import '../../domain/enums/zoom_direction.dart';
import '../../domain/models/app_object_detection.dart';
import '../../domain/models/appearance_signature.dart';
import '../../domain/models/custom_gesture_detection_result.dart';
import '../../domain/models/follow_target.dart';
import '../../domain/models/follow_target_identity.dart';
import '../../domain/models/follow_target_selection_memory.dart';
import '../../domain/models/object_detection_batch.dart';
import '../../domain/models/object_optical_flow_track_result.dart';
import '../../domain/models/object_tracking_frame.dart';
import '../../domain/services/custom_gesture_detector.dart';
import '../../domain/services/appearance_signature_extractor.dart';
import '../../domain/services/detect_my_face_reacquisition_controller.dart';
import '../../domain/services/direction_gesture_detector.dart';
import '../../domain/services/follow_object_sequence_detector.dart';
import '../../domain/services/follow_target_selector.dart';
import '../../domain/services/follow_target_tracking_progress.dart';
import '../../domain/services/gesture_debug_evaluator.dart';
import '../../domain/services/gesture_debug_menu_trigger.dart';
import '../../domain/services/hand_geometry_service.dart';
import '../../domain/services/object_detection_request_controller.dart';
import '../../domain/services/object_detection_result_stabilizer.dart';
import '../../domain/services/object_detection_target_smoother.dart';
import '../../domain/services/object_detection_service.dart';
import '../../domain/services/object_detection_service_factory.dart';
import '../../domain/services/object_optical_flow_tracker.dart';
import '../../domain/services/zoom_gesture_detector.dart';
import '../../domain/utils/camera_frame_box_mapper.dart';
import '../../domain/utils/camera_preview_geometry.dart';
import '../painters/object_detection_debug_painter.dart';
import '../painters/direction_debug_overlay_painter.dart';
import '../painters/follow_target_overlay_painter.dart';
import '../painters/gesture_family_debug_overlay_painter.dart';
import '../painters/hand_focus_overlay_painter.dart';
import '../painters/hand_landmark_overlay_painter.dart';
import '../painters/object_detection_debug_painter_factory.dart';
import '../painters/object_optical_flow_debug_painter.dart';
import '../painters/recording_hand_landmark_overlay_painter.dart';
import '../painters/zoom_in_debug_overlay_painter.dart';
import '../utils/hand_gesture_label_mapper.dart';
import '../utils/camera_orientation_preferences.dart';
import '../utils/palm_orientation_coordinate_policy.dart';
import '../utils/ml_kit_preview_mapper.dart';
import '../widgets/gesture_status_panel.dart';
import '../widgets/gesture_debug_selector_overlay.dart';
import '../widgets/face_reacquisition_status_overlay.dart';
import '../widgets/hand_camera_loading_view.dart';
import '../widgets/home_hand_pointer_layer.dart';
import '../widgets/round_icon_button.dart';
import '../widgets/touch_zoom_guide_overlay.dart';
import '../widgets/zoom_control_overlay.dart';

part 'admin_hand_gesture_live_screen_parts/camera_lifecycle.dart';
part 'admin_hand_gesture_live_screen_parts/zoom_controls.dart';
part 'admin_hand_gesture_live_screen_parts/recording_controls.dart';
part 'admin_hand_gesture_live_screen_parts/gesture_processing.dart';
part 'admin_hand_gesture_live_screen_parts/live_screen_ui.dart';

/// Live camera page that detects hand gestures and controls the stand/camera.
class AdminHandGestureLiveScreen extends StatefulWidget {
  const AdminHandGestureLiveScreen({
    super.key,
    this.initialLensDirection = CameraLensDirection.front,
    this.objectDetectionBackend = ObjectDetectionBackend.ultralyticsYolo,
    this.appPointerController,
  });

  final CameraLensDirection initialLensDirection;
  final ObjectDetectionBackend objectDetectionBackend;
  final HomeHandPointerController? appPointerController;

  /// Creates the state object that owns camera, detectors, and live UI state.
  @override
  State<AdminHandGestureLiveScreen> createState() =>
      _AdminHandGestureLiveScreenState();
}

/// Coordinates camera streaming, gesture detection, zoom, recording, and UI.
class _AdminHandGestureLiveScreenState extends State<AdminHandGestureLiveScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  HandDetector? _handDetector;
  ml_face.FaceDetector? _faceDetector;
  ObjectDetectionService? _objectDetectionService;
  Future<ObjectDetectionService>? _objectDetectionServiceStartup;
  bool _objectDetectionServiceStartupFailed = false;
  DateTime? _objectDetectionServiceStartupFailedAt;

  final _customGestureDetector = CustomGestureDetector();
  final _directionGestureDetector = DirectionGestureDetector();
  final _zoomGestureDetector = ZoomGestureDetector();
  final _followTargetSelector = const FollowTargetSelector();
  final _followTargetProgress = FollowTargetTrackingProgress();
  final _detectMyFaceReacquisition = DetectMyFaceReacquisitionController();
  final _gestureDebugEvaluator = const GestureDebugEvaluator();
  final _gestureDebugMenuTrigger = GestureDebugMenuTrigger();
  final _appearanceSignatureExtractor = const AppearanceSignatureExtractor();
  final _handGeometry = const HandGeometryService();
  final _objectTrackingFrameFactory = const ObjectTrackingFrameFactory();
  final _objectOpticalFlowTracker = ObjectOpticalFlowTracker();
  final Object _appPointerOwner = Object();
  late final ObjectDetectionRequestController _objectDetectionRequests;
  late final ObjectDetectionResultStabilizer _objectDetectionResultStabilizer;
  late final ObjectDetectionTargetSmoother _objectDetectionTargetSmoother;

  late final FollowObjectSequenceDetector _followObjectSequenceDetector;

  List<CameraDescription> _availableCameras = const [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  bool _isChangingPreviewOrientation = false;
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
  // Set false to disable the two-circle touch zoom guide.
  // ignore: prefer_final_fields
  bool _isTouchZoomGuideEnabled = false;
  bool _isTouchZoomGuideVisible = false;
  bool _isTouchZoomInteractionActive = false;
  // Set true to show red face/object detection boxes for follow-object debug.
  final bool _showFollowTargetDebugOverlay = false;
  // Set true to inspect optical-flow points, raw boxes, and confidence.
  final bool _showObjectOpticalFlowDebugOverlay = false;
  // Exactly one diagnostic gesture-family painter may be active. The normal
  // 21-point hand overlay remains visible except while its selector is open.
  GestureDebugMode _gestureDebugMode = GestureDebugMode.off;
  bool _isGestureDebugMenuOpen = false;

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
  DateTime? _lastGestureZoomAppliedAt;
  int _detectedHandsCount = 0;

  List<Hand> _hands = const [];
  List<FollowTarget> _followObjectCandidateFaces = const [];
  List<FollowTarget> _followObjectCandidateObjects = const [];
  FollowTarget? _predictedFollowTarget;
  FollowTargetSelectionMemory? _followTargetSelectionMemory;
  bool _followTargetSelectionCandidateHidden = false;
  Offset? _handReturnGraceReleasePoint;
  FollowTarget? _handReturnGraceFrozenTarget;
  List<FollowTarget> _cachedObjectTargets = const [];
  List<FollowTarget> _visualObjectTargets = const [];
  Rect? _followSelectionHandDisplayBox;
  Size? _detectionImageSize;
  Rect? _focusedHandBox;
  Size? _focusImageSize;
  FollowTarget? _lockedFollowTarget;
  FollowTargetIdentity? _followTargetIdentity;
  DateTime? _lastEvaluatedFollowDetectionAt;
  DateTime? _followTargetConfirmationDeadline;
  DateTime? _followTargetSelectionFailureUntil;
  ObjectDetectionBatch? _cachedObjectDetectionBatch;
  DateTime? _lockedFollowTargetLostAt;
  DateTime? _lastFrameProcessedAt;
  DateTime? _lastCameraFocusPointSetAt;
  Offset? _lastCameraFocusPoint;
  DateTime? _lastOrientationDebugPrintedAt;
  CameraFrameRotation? _lastCameraFrameRotation;
  bool _hasCameraFrameRotation = false;
  CameraPreviewMode _cameraPreviewMode = CameraPreviewMode.portrait;
  late final AnimationController _cameraPreviewRotationController;
  bool _didLockLiveCameraUiOrientation = false;
  int _objectDetectionGeneration = 0;
  int _cameraFrameId = 0;
  ObjectOpticalFlowTrackResult? _objectOpticalFlowResult;
  DateTime? _faceDetectGestureStartedAt;
  DateTime? _lastVictoryToastShownAt;
  DateTime? _lastPunchScreenShownAt;
  Timer? _recordingTimer;
  Timer? _zoomControlAutoHideTimer;
  DateTime? _recordingSegmentStartedAt;
  Duration _recordingElapsedBeforePause = Duration.zero;
  Duration _recordingElapsed = Duration.zero;
  ZoomDirection _lastAppliedZoomDirection = ZoomDirection.none;
  _RecordingGestureAction? _activeRecordingGestureAction;
  DateTime? _recordingGestureStartedAt;
  bool _recordingGestureTriggered = false;

  /// Initializes detector state, picks the starting lens, and requests camera.
  @override
  void initState() {
    super.initState();
    _objectDetectionRequests = ObjectDetectionRequestController(
      minInterval: ObjectDetectionServiceFactory.requestMinIntervalFor(
        backend: widget.objectDetectionBackend,
        isIOS: Platform.isIOS,
      ),
    );
    _objectDetectionResultStabilizer =
        ObjectDetectionResultStabilizer.forBackend(
          widget.objectDetectionBackend,
        );
    _objectDetectionTargetSmoother = ObjectDetectionTargetSmoother.forBackend(
      widget.objectDetectionBackend,
    );
    WidgetsBinding.instance.addObserver(this);
    _cameraPreviewRotationController = AnimationController(
      vsync: this,
      duration: cameraPreviewRotationDuration,
    )..addStatusListener(_handleCameraPreviewAnimationStatus);
    unawaited(_lockLiveCameraUiOrientation());

    _followObjectSequenceDetector = FollowObjectSequenceDetector(
      onDebug: debugPrint,
    );

    _currentLensDirection = widget.initialLensDirection;

    _requestCameraPermission();
  }

  /// Releases timers, camera controller, and ML detectors.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appPointerController?.clearExternalPointer(_appPointerOwner);
    _detectMyFaceReacquisition.clear();
    _resetRecordingTimer();
    _zoomControlAutoHideTimer?.cancel();
    final controller = _controller;

    if (controller != null) {
      unawaited(_disposeControllerFromWidgetDispose(controller));
    }

    unawaited(_handDetector?.dispose() ?? Future<void>.value());
    unawaited(_faceDetector?.close() ?? Future<void>.value());
    _closeObjectDetectionService();
    _objectOpticalFlowTracker.dispose();
    _cameraPreviewRotationController
      ..removeStatusListener(_handleCameraPreviewAnimationStatus)
      ..dispose();
    unawaited(_restoreSupportedCameraOrientations());
    super.dispose();
  }

  /// Restarts or pauses streaming as the app moves foreground/background.
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

  /// Runs a state update only through setState while the widget is mounted.
  void _setScreenState(VoidCallback update) {
    if (mounted) {
      setState(update);
    } else {
      update();
    }
  }

  /// Delegates rendering to the live-screen UI part file.
  @override
  Widget build(BuildContext context) => _buildLiveScreen(context);
}
