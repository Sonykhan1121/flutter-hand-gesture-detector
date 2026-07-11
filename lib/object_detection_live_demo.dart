// import 'dart:io';
//
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:object_detection/object_detection.dart';
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Keep this first demo in portrait so camera rotation and overlay mapping
//   // are easy to verify. Remove this when you add full orientation support.
//   await SystemChrome.setPreferredOrientations(
//     const <DeviceOrientation>[DeviceOrientation.portraitUp],
//   );
//
//   runApp(const ObjectDetectionDemoApp());
// }
//
// class ObjectDetectionDemoApp extends StatelessWidget {
//   const ObjectDetectionDemoApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Object Detection Live Demo',
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
//         useMaterial3: true,
//       ),
//       home: const ObjectDetectionLivePage(),
//     );
//   }
// }
//
// class ObjectDetectionLivePage extends StatefulWidget {
//   const ObjectDetectionLivePage({super.key});
//
//   @override
//   State<ObjectDetectionLivePage> createState() =>
//       _ObjectDetectionLivePageState();
// }
//
// class _ObjectDetectionLivePageState extends State<ObjectDetectionLivePage> {
//   static const int _maxDetectionDimension = 640;
//
//   CameraController? _cameraController;
//   ObjectDetector? _objectDetector;
//
//   List<DetectedObject> _detections = const <DetectedObject>[];
//   Size? _detectionImageSize;
//
//   bool _isInitializing = true;
//   bool _isProcessingFrame = false;
//   bool _isFrontCamera = false;
//
//   double _scoreThreshold = 0.40;
//   int _detectionTimeMs = 0;
//   String? _errorMessage;
//
//   @override
//   void initState() {
//     super.initState();
//     _initialize();
//   }
//
//   Future<void> _initialize() async {
//     try {
//       final detector = await ObjectDetector.create(
//         model: ObjectDetectionModel.efficientDetLite0,
//       );
//
//       final cameras = await availableCameras();
//       if (cameras.isEmpty) {
//         throw StateError('No camera was found on this device.');
//       }
//
//       final selectedCamera = cameras.firstWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.back,
//         orElse: () => cameras.first,
//       );
//
//       final controller = CameraController(
//         selectedCamera,
//         ResolutionPreset.medium,
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.yuv420,
//       );
//
//       await controller.initialize();
//
//       if (!mounted) {
//         await controller.dispose();
//         await detector.dispose();
//         return;
//       }
//
//       _objectDetector = detector;
//       _cameraController = controller;
//       _isFrontCamera =
//           selectedCamera.lensDirection == CameraLensDirection.front;
//
//       setState(() => _isInitializing = false);
//
//       await controller.startImageStream(_processCameraFrame);
//     } catch (error, stackTrace) {
//       debugPrint('Object detection initialization failed: $error');
//       debugPrintStack(stackTrace: stackTrace);
//
//       if (!mounted) return;
//       setState(() {
//         _isInitializing = false;
//         _errorMessage = error.toString();
//       });
//     }
//   }
//
//   Future<void> _processCameraFrame(CameraImage image) async {
//     // The camera can provide frames faster than inference finishes. Dropping
//     // overlapping frames prevents a growing queue and keeps the UI responsive.
//     if (_isProcessingFrame) return;
//
//     final detector = _objectDetector;
//     final controller = _cameraController;
//
//     if (detector == null ||
//         controller == null ||
//         !detector.isReady ||
//         !controller.value.isInitialized) {
//       return;
//     }
//
//     _isProcessingFrame = true;
//     final stopwatch = Stopwatch()..start();
//
//     try {
//       final rotation = rotationForFrame(
//         width: image.width,
//         height: image.height,
//         sensorOrientation: controller.description.sensorOrientation,
//         isFrontCamera: _isFrontCamera,
//         deviceOrientation: controller.value.deviceOrientation,
//       );
//
//       final detectionImageSize = detectionSize(
//         width: image.width,
//         height: image.height,
//         rotation: rotation,
//         maxDim: _maxDetectionDimension,
//       );
//
//       final results = await detector.detectFromCameraImage(
//         image,
//         rotation: rotation,
//         maxDim: _maxDetectionDimension,
//         options: ObjectDetectorOptions(
//           scoreThreshold: _scoreThreshold,
//           maxResults: 10,
//         ),
//       );
//
//       stopwatch.stop();
//
//       if (!mounted) return;
//       setState(() {
//         _detections = results;
//         _detectionImageSize = detectionImageSize;
//         _detectionTimeMs = stopwatch.elapsedMilliseconds;
//       });
//     } catch (error, stackTrace) {
//       // A temporary bad camera frame should not stop the live stream.
//       debugPrint('Frame detection failed: $error');
//       debugPrintStack(stackTrace: stackTrace);
//     } finally {
//       _isProcessingFrame = false;
//     }
//   }
//
//   @override
//   void dispose() {
//     final controller = _cameraController;
//     _cameraController = null;
//
//     if (controller != null) {
//       if (controller.value.isStreamingImages) {
//         controller.stopImageStream().then((_) => controller.dispose());
//       } else {
//         controller.dispose();
//       }
//     }
//
//     _objectDetector?.dispose();
//     _objectDetector = null;
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (_isInitializing) {
//       return const Scaffold(
//         body: Center(child: CircularProgressIndicator()),
//       );
//     }
//
//     if (_errorMessage != null) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('Object Detection Demo')),
//         body: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Center(
//             child: Text(
//               'Could not start object detection.\n\n$_errorMessage',
//               textAlign: TextAlign.center,
//               style: const TextStyle(color: Colors.red),
//             ),
//           ),
//         ),
//       );
//     }
//
//     final controller = _cameraController!;
//     final orientation = controller.value.deviceOrientation;
//     final isPortrait = orientation == DeviceOrientation.portraitUp ||
//         orientation == DeviceOrientation.portraitDown;
//
//     final displayAspectRatio = isPortrait
//         ? 1 / controller.value.aspectRatio
//         : controller.value.aspectRatio;
//
//     // This follows the official example's Android front-camera overlay rule.
//     final mirrorOverlay = Platform.isAndroid && _isFrontCamera;
//
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         fit: StackFit.expand,
//         children: <Widget>[
//           ObjectDetectionCameraOverlay(
//             cameraPreview: CameraPreview(controller),
//             displayAspectRatio: displayAspectRatio,
//             mirrorHorizontally: mirrorOverlay,
//             detections: _detections,
//             imageSize: _detectionImageSize,
//             showLabels: true,
//           ),
//           SafeArea(
//             child: Align(
//               alignment: Alignment.topCenter,
//               child: _StatusPanel(
//                 detections: _detections,
//                 detectionTimeMs: _detectionTimeMs,
//               ),
//             ),
//           ),
//           SafeArea(
//             child: Align(
//               alignment: Alignment.bottomCenter,
//               child: _ThresholdPanel(
//                 threshold: _scoreThreshold,
//                 onChanged: (value) {
//                   setState(() => _scoreThreshold = value);
//                 },
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _StatusPanel extends StatelessWidget {
//   const _StatusPanel({
//     required this.detections,
//     required this.detectionTimeMs,
//   });
//
//   final List<DetectedObject> detections;
//   final int detectionTimeMs;
//
//   @override
//   Widget build(BuildContext context) {
//     final labels = detections
//         .take(4)
//         .map(
//           (object) =>
//               '${object.categoryName} ${(object.score * 100).toStringAsFixed(0)}%',
//         )
//         .join('  •  ');
//
//     return Container(
//       width: double.infinity,
//       margin: const EdgeInsets.all(12),
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//       decoration: BoxDecoration(
//         color: Colors.black.withValues(alpha: 0.72),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: <Widget>[
//           Text(
//             'EfficientDet-Lite0  •  ${detections.length} object(s)  •  '
//             '${detectionTimeMs}ms',
//             style: const TextStyle(
//               color: Colors.white,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             labels.isEmpty ? 'Point the camera at a person or common object.' : labels,
//             maxLines: 2,
//             overflow: TextOverflow.ellipsis,
//             style: const TextStyle(color: Colors.white70),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _ThresholdPanel extends StatelessWidget {
//   const _ThresholdPanel({
//     required this.threshold,
//     required this.onChanged,
//   });
//
//   final double threshold;
//   final ValueChanged<double> onChanged;
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.all(12),
//       padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
//       decoration: BoxDecoration(
//         color: Colors.black.withValues(alpha: 0.72),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: <Widget>[
//           Row(
//             children: <Widget>[
//               const Text(
//                 'Confidence',
//                 style: TextStyle(color: Colors.white),
//               ),
//               const Spacer(),
//               Text(
//                 threshold.toStringAsFixed(2),
//                 style: const TextStyle(color: Colors.white),
//               ),
//             ],
//           ),
//           Slider(
//             value: threshold,
//             min: 0.10,
//             max: 0.90,
//             divisions: 16,
//             label: threshold.toStringAsFixed(2),
//             onChanged: onChanged,
//           ),
//         ],
//       ),
//     );
//   }
// }
