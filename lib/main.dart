import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gesture_detector/utils/app_snack_bar.dart';

import 'hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'hand_gesture_features/domain/enums/stand_control_mode.dart';
import 'hand_gesture_features/domain/services/object_detection_backend_preference_service.dart';
import 'hand_gesture_features/domain/services/ultralytics_yolo_model_preloader.dart';
import 'hand_gesture_features/presentation/screens/admin_hand_gesture_live_screen.dart';
import 'hand_gesture_features/presentation/screens/face_object_debug_camera_screen.dart';
import 'hand_gesture_features/presentation/screens/moving_down_capture_screen.dart';
import 'hand_gesture_features/stand_control_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App feature handlers: change only these two values when needed.
  const showFloatingCameraDetectionButton = true;
  const showMovingDownTrainingListItem = false;
  final supportsNativeMethodChannel = Platform.isAndroid;
  final supportsOpenCvSdk = Platform.isAndroid;
  final supportsUltralyticsYolo = Platform.isAndroid || Platform.isIOS;
  final supportsGoogleMlKit = Platform.isAndroid || Platform.isIOS;
  const preferenceService = ObjectDetectionBackendPreferenceService();
  final objectDetectionBackend = await preferenceService.load(
    supportsNativeMethodChannel: supportsNativeMethodChannel,
    supportsOpenCvSdk: supportsOpenCvSdk,
    supportsUltralyticsYolo: supportsUltralyticsYolo,
    supportsGoogleMlKit: supportsGoogleMlKit,
  );

  runApp(
    GestureDetectorApp(
      showFloatingCameraDetectionButton: showFloatingCameraDetectionButton,
      showMovingDownTrainingListItem: showMovingDownTrainingListItem,
      initialObjectDetectionBackend: objectDetectionBackend,
      supportsNativeMethodChannel: supportsNativeMethodChannel,
      supportsOpenCvSdk: supportsOpenCvSdk,
      supportsUltralyticsYolo: supportsUltralyticsYolo,
      supportsGoogleMlKit: supportsGoogleMlKit,
      objectDetectionBackendPreferenceService: preferenceService,
    ),
  );

  // Resolve/download the official YOLO model after the app starts. This is
  // intentionally not awaited, so startup and the first rendered frame never
  // wait for network or model metadata inspection.
  if (Platform.isAndroid || Platform.isIOS) {
    unawaited(ultralyticsYoloModelPreloader.prefetch());
  }
}

/// Root widget that configures app theme and opens the stand-control flow.
class GestureDetectorApp extends StatefulWidget {
  final bool showFloatingCameraDetectionButton;
  final bool showMovingDownTrainingListItem;
  final ObjectDetectionBackend initialObjectDetectionBackend;
  final bool supportsNativeMethodChannel;
  final bool supportsOpenCvSdk;
  final bool supportsUltralyticsYolo;
  final bool supportsGoogleMlKit;
  final ObjectDetectionBackendPreferenceService
  objectDetectionBackendPreferenceService;

  const GestureDetectorApp({
    super.key,
    this.showFloatingCameraDetectionButton = true,
    this.showMovingDownTrainingListItem = true,
    this.initialObjectDetectionBackend = ObjectDetectionBackend.ultralyticsYolo,
    this.supportsNativeMethodChannel = false,
    this.supportsOpenCvSdk = false,
    this.supportsUltralyticsYolo = true,
    this.supportsGoogleMlKit = true,
    this.objectDetectionBackendPreferenceService =
        const ObjectDetectionBackendPreferenceService(),
  });

  @override
  State<GestureDetectorApp> createState() => _GestureDetectorAppState();
}

class _GestureDetectorAppState extends State<GestureDetectorApp> {
  late ObjectDetectionBackend _selectedObjectDetectionBackend;

  @override
  void initState() {
    super.initState();
    _selectedObjectDetectionBackend = _supportedInitialBackend();
  }

  ObjectDetectionBackend _supportedInitialBackend() {
    if (widget.initialObjectDetectionBackend.isSupported(
      supportsNativeMethodChannel: widget.supportsNativeMethodChannel,
      supportsOpenCvSdk: widget.supportsOpenCvSdk,
      supportsUltralyticsYolo: widget.supportsUltralyticsYolo,
      supportsGoogleMlKit: widget.supportsGoogleMlKit,
    )) {
      return widget.initialObjectDetectionBackend;
    }

    return ObjectDetectionBackendPreferenceService.platformDefault(
      supportsNativeMethodChannel: widget.supportsNativeMethodChannel,
      supportsOpenCvSdk: widget.supportsOpenCvSdk,
      supportsUltralyticsYolo: widget.supportsUltralyticsYolo,
      supportsGoogleMlKit: widget.supportsGoogleMlKit,
    );
  }

  Future<void> _selectObjectDetectionBackend(
    BuildContext context,
    ObjectDetectionBackend backend,
  ) async {
    if (!backend.isSupported(
      supportsNativeMethodChannel: widget.supportsNativeMethodChannel,
      supportsOpenCvSdk: widget.supportsOpenCvSdk,
      supportsUltralyticsYolo: widget.supportsUltralyticsYolo,
      supportsGoogleMlKit: widget.supportsGoogleMlKit,
    )) {
      return;
    }

    setState(() {
      _selectedObjectDetectionBackend = backend;
    });

    final saved = await widget.objectDetectionBackendPreferenceService.save(
      backend,
      supportsNativeMethodChannel: widget.supportsNativeMethodChannel,
      supportsOpenCvSdk: widget.supportsOpenCvSdk,
      supportsUltralyticsYolo: widget.supportsUltralyticsYolo,
      supportsGoogleMlKit: widget.supportsGoogleMlKit,
    );
    if (!saved && mounted && context.mounted) {
      AppSnackBar.show(
        context: context,
        message:
            'Detector changed for this session, but it could not be saved.',
        isError: true,
      );
    }
  }

  @override
  /// Builds the Material app and wires home-screen actions to navigation.
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Stand Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E90FA)),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          return StandControlHomePage(
            initialMode: StandControlMode.handGesture,
            showDebugCameraButton: widget.showFloatingCameraDetectionButton,
            showMovingDownTraining: widget.showMovingDownTrainingListItem,
            selectedObjectDetectionBackend: _selectedObjectDetectionBackend,
            supportsNativeMethodChannel: widget.supportsNativeMethodChannel,
            supportsOpenCvSdk: widget.supportsOpenCvSdk,
            supportsUltralyticsYolo: widget.supportsUltralyticsYolo,
            supportsGoogleMlKit: widget.supportsGoogleMlKit,
            onObjectDetectionBackendChanged: (backend) {
              unawaited(_selectObjectDetectionBackend(context, backend));
            },
            onModeChanged: (mode) {
              debugPrint('New mode : $mode');
            },
            onDebugCameraTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FaceObjectDebugCameraScreen(
                    objectDetectionBackend: _selectedObjectDetectionBackend,
                  ),
                ),
              );
            },
            onAutomaticDetectTap: () {
              AppSnackBar.show(
                context: context,
                message: 'Automatic Detect is coming soon.',
              );
            },
            onHandGestureTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminHandGestureLiveScreen(
                    initialLensDirection: CameraLensDirection.front,
                    objectDetectionBackend: _selectedObjectDetectionBackend,
                  ),
                ),
              );
            },
            onMovingDownTrainingTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MovingDownCaptureScreen(),
                ),
              );
            },
            onVoiceCommandTap: () {
              AppSnackBar.show(
                context: context,
                message: 'Voice Command is coming soon.',
              );
            },
          );
        },
      ),
    );
  }
}
