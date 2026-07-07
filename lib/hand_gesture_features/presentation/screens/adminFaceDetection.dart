// import 'dart:async';
// import 'dart:io';
// import 'dart:math' as math;
//
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:permission_handler/permission_handler.dart';
//
// class AdminFaceDetection extends StatefulWidget {
//   const AdminFaceDetection({
//     super.key,
//     this.fontorback = 1,
//   });
//
//   /// 0 = back camera
//   /// 1 = front camera
//   final int fontorback;
//
//   @override
//   State<AdminFaceDetection> createState() => _AdminFaceDetectionState();
// }
//
// class _AdminFaceDetectionState extends State<AdminFaceDetection> {
//   CameraController? _cameraController;
//   FaceDetector? _faceDetector;
//
//   bool _isCameraInitialized = false;
//   bool _isProcessing = false;
//   bool _hasReturnedResult = false;
//   bool _faceInsideFrame = false;
//   bool _isHoldingFace = false;
//
//   Timer? _stableFaceTimer;
//
//   List<CameraDescription> _cameras = [];
//   late CameraLensDirection _lensDirection;
//
//   static const double _requiredInsideRatio = 0.70;
//   static const Duration _requiredStableDuration = Duration(seconds: 2);
//
//   static const Map<DeviceOrientation, int> _deviceOrientations = {
//     DeviceOrientation.portraitUp: 0,
//     DeviceOrientation.landscapeLeft: 90,
//     DeviceOrientation.portraitDown: 180,
//     DeviceOrientation.landscapeRight: 270,
//   };
//
//   @override
//   void initState() {
//     super.initState();
//
//     _lensDirection = widget.fontorback == 0
//         ? CameraLensDirection.back
//         : CameraLensDirection.front;
//
//     _initializePage();
//   }
//
//   Future<void> _initializePage() async {
//     final hasPermission = await _requestCameraPermission();
//
//     if (!hasPermission || !mounted) return;
//
//     _faceDetector = FaceDetector(
//       options: FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.fast,
//         enableClassification: false,
//         enableContours: false,
//         enableLandmarks: false,
//         enableTracking: false,
//         minFaceSize: 0.15,
//       ),
//     );
//
//     await _initializeCamera();
//   }
//
//   Future<bool> _requestCameraPermission() async {
//     PermissionStatus status = await Permission.camera.status;
//
//     if (status.isDenied) {
//       status = await Permission.camera.request();
//     }
//
//     if (status.isGranted) {
//       return true;
//     }
//
//     if (status.isPermanentlyDenied) {
//       _showSnackBar('Camera permission is permanently denied.');
//       await openAppSettings();
//       return false;
//     }
//
//     _showSnackBar('Camera permission denied.');
//     return false;
//   }
//
//   Future<void> _initializeCamera() async {
//     try {
//       _cameras = await availableCameras();
//
//       if (_cameras.isEmpty) {
//         _showSnackBar('No camera found.');
//         return;
//       }
//
//       final selectedCamera = _cameras.firstWhere(
//             (camera) => camera.lensDirection == _lensDirection,
//         orElse: () => _cameras.first,
//       );
//
//       final controller = CameraController(
//         selectedCamera,
//         ResolutionPreset.medium,
//         enableAudio: false,
//         imageFormatGroup: Platform.isAndroid
//             ? ImageFormatGroup.nv21
//             : ImageFormatGroup.bgra8888,
//       );
//
//       _cameraController = controller;
//
//       await controller.initialize();
//
//       if (!mounted) return;
//
//       setState(() {
//         _isCameraInitialized = true;
//       });
//
//       await controller.startImageStream(_processCameraImage);
//     } catch (e) {
//       debugPrint('Camera initialization error: $e');
//       _showSnackBar('Camera initialization failed.');
//     }
//   }
//
//   Future<void> _processCameraImage(CameraImage image) async {
//     if (_isProcessing || _hasReturnedResult) return;
//
//     final controller = _cameraController;
//     final faceDetector = _faceDetector;
//
//     if (controller == null ||
//         faceDetector == null ||
//         !controller.value.isInitialized) {
//       return;
//     }
//
//     _isProcessing = true;
//
//     try {
//       final inputImage = _convertCameraImageToInputImage(image);
//
//       if (inputImage == null) return;
//
//       final faces = await faceDetector.processImage(inputImage);
//
//       if (!mounted || _hasReturnedResult) return;
//
//       if (faces.isEmpty) {
//         _resetStableFaceTimer();
//         _updateFaceState(
//           faceInsideFrame: false,
//           isHoldingFace: false,
//         );
//         return;
//       }
//
//       final face = faces.first;
//
//       final isFaceEnoughInsideFrame = _isFaceAtLeast70PercentInsideFrame(
//         face: face,
//         image: image,
//         controller: controller,
//       );
//
//       if (isFaceEnoughInsideFrame) {
//         _updateFaceState(
//           faceInsideFrame: true,
//           isHoldingFace: true,
//         );
//
//         _startStableFaceTimerIfNeeded();
//       } else {
//         _resetStableFaceTimer();
//
//         _updateFaceState(
//           faceInsideFrame: false,
//           isHoldingFace: false,
//         );
//       }
//     } catch (e) {
//       debugPrint('Face detection error: $e');
//       _resetStableFaceTimer();
//     } finally {
//       _isProcessing = false;
//     }
//   }
//
//   bool _isFaceAtLeast70PercentInsideFrame({
//     required Face face,
//     required CameraImage image,
//     required CameraController controller,
//   }) {
//     final imageSize = _getMlKitImageSize(
//       image: image,
//       controller: controller,
//     );
//
//     final frameRect = _buildCenterFaceFrameRect(imageSize);
//
//     final faceRect = face.boundingBox;
//
//     if (faceRect.width <= 0 || faceRect.height <= 0) {
//       return false;
//     }
//
//     final intersection = faceRect.intersect(frameRect);
//
//     if (intersection.isEmpty) {
//       return false;
//     }
//
//     final faceArea = faceRect.width * faceRect.height;
//     final insideArea = intersection.width * intersection.height;
//
//     if (faceArea <= 0) return false;
//
//     final insideRatio = insideArea / faceArea;
//
//     debugPrint(
//       'Face inside ratio: ${(insideRatio * 100).toStringAsFixed(1)}%',
//     );
//
//     return insideRatio >= _requiredInsideRatio;
//   }
//
//   Size _getMlKitImageSize({
//     required CameraImage image,
//     required CameraController controller,
//   }) {
//     final sensorOrientation = controller.description.sensorOrientation;
//
//     final isRotated = sensorOrientation == 90 || sensorOrientation == 270;
//
//     if (isRotated) {
//       return Size(
//         image.height.toDouble(),
//         image.width.toDouble(),
//       );
//     }
//
//     return Size(
//       image.width.toDouble(),
//       image.height.toDouble(),
//     );
//   }
//
//   Rect _buildCenterFaceFrameRect(Size imageSize) {
//     final frameWidth = imageSize.width * 0.78;
//     final frameHeight = math.min(
//       frameWidth * 1.30,
//       imageSize.height * 0.85,
//     );
//
//     return Rect.fromCenter(
//       center: Offset(
//         imageSize.width / 2,
//         imageSize.height / 2,
//       ),
//       width: frameWidth,
//       height: frameHeight,
//     );
//   }
//
//   void _startStableFaceTimerIfNeeded() {
//     if (_stableFaceTimer != null || _hasReturnedResult) return;
//
//     _stableFaceTimer = Timer(_requiredStableDuration, () async {
//       if (!mounted || _hasReturnedResult || !_faceInsideFrame) return;
//
//       await _returnTrueAfterFaceDetected();
//     });
//   }
//
//   void _resetStableFaceTimer() {
//     _stableFaceTimer?.cancel();
//     _stableFaceTimer = null;
//   }
//
//   void _updateFaceState({
//     required bool faceInsideFrame,
//     required bool isHoldingFace,
//   }) {
//     if (!mounted) return;
//
//     if (_faceInsideFrame == faceInsideFrame &&
//         _isHoldingFace == isHoldingFace) {
//       return;
//     }
//
//     setState(() {
//       _faceInsideFrame = faceInsideFrame;
//       _isHoldingFace = isHoldingFace;
//     });
//   }
//
//   Future<void> _returnTrueAfterFaceDetected() async {
//     if (_hasReturnedResult) return;
//
//     _hasReturnedResult = true;
//     _resetStableFaceTimer();
//
//     if (mounted) {
//       setState(() {
//         _faceInsideFrame = true;
//         _isHoldingFace = false;
//       });
//     }
//
//     await _stopImageStreamOnly();
//
//     if (!mounted) return;
//
//     Navigator.pop(context, true);
//   }
//
//   InputImage? _convertCameraImageToInputImage(CameraImage image) {
//     final controller = _cameraController;
//
//     if (controller == null) return null;
//
//     final camera = controller.description;
//     final sensorOrientation = camera.sensorOrientation;
//
//     InputImageRotation? rotation;
//
//     if (Platform.isIOS) {
//       rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
//     } else if (Platform.isAndroid) {
//       final deviceOrientation = controller.value.deviceOrientation;
//       final rotationCompensation = _deviceOrientations[deviceOrientation];
//
//       if (rotationCompensation == null) return null;
//
//       int rotationDegrees;
//
//       if (camera.lensDirection == CameraLensDirection.front) {
//         rotationDegrees = (sensorOrientation + rotationCompensation) % 360;
//       } else {
//         rotationDegrees =
//             (sensorOrientation - rotationCompensation + 360) % 360;
//       }
//
//       rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
//     }
//
//     if (rotation == null) return null;
//
//     final format = InputImageFormatValue.fromRawValue(image.format.raw);
//
//     if (format == null) return null;
//
//     if (Platform.isAndroid && format != InputImageFormat.nv21) {
//       debugPrint('Unsupported Android image format: $format');
//       return null;
//     }
//
//     if (Platform.isIOS && format != InputImageFormat.bgra8888) {
//       debugPrint('Unsupported iOS image format: $format');
//       return null;
//     }
//
//     if (image.planes.length != 1) {
//       debugPrint('Invalid plane count: ${image.planes.length}');
//       return null;
//     }
//
//     final plane = image.planes.first;
//
//     return InputImage.fromBytes(
//       bytes: plane.bytes,
//       metadata: InputImageMetadata(
//         size: Size(
//           image.width.toDouble(),
//           image.height.toDouble(),
//         ),
//         rotation: rotation,
//         format: format,
//         bytesPerRow: plane.bytesPerRow,
//       ),
//     );
//   }
//
//   Future<void> _stopImageStreamOnly() async {
//     final controller = _cameraController;
//
//     if (controller == null) return;
//
//     try {
//       if (controller.value.isInitialized && controller.value.isStreamingImages) {
//         await controller.stopImageStream();
//       }
//     } catch (e) {
//       debugPrint('Stop image stream error: $e');
//     }
//   }
//
//   Future<void> _disposeCamera() async {
//     final controller = _cameraController;
//
//     if (controller == null) return;
//
//     try {
//       if (controller.value.isInitialized && controller.value.isStreamingImages) {
//         await controller.stopImageStream();
//       }
//     } catch (e) {
//       debugPrint('Dispose stop stream error: $e');
//     }
//
//     try {
//       await controller.dispose();
//     } catch (e) {
//       debugPrint('Camera dispose error: $e');
//     }
//
//     _cameraController = null;
//   }
//
//   void _showSnackBar(String message) {
//     if (!mounted) return;
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final messenger = ScaffoldMessenger.maybeOf(context);
//
//       messenger?.showSnackBar(
//         SnackBar(
//           content: Text(message),
//           behavior: SnackBarBehavior.floating,
//           duration: const Duration(seconds: 2),
//         ),
//       );
//     });
//   }
//
//   @override
//   void dispose() {
//     _resetStableFaceTimer();
//     unawaited(_disposeCamera());
//     unawaited(_faceDetector?.close());
//
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final controller = _cameraController;
//
//     final showCamera = _isCameraInitialized &&
//         controller != null &&
//         controller.value.isInitialized &&
//         !_hasReturnedResult;
//
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: SafeArea(
//         child: showCamera
//             ? Stack(
//           children: [
//             Positioned.fill(
//               child: CameraPreview(controller),
//             ),
//             Positioned.fill(
//               child: CustomPaint(
//                 painter: FaceOvalPainter(),
//               ),
//             ),
//             Positioned(
//               left: 16,
//               right: 16,
//               bottom: 40,
//               child: _FaceDetectionInstruction(
//                 faceInsideFrame: _faceInsideFrame,
//                 isHoldingFace: _isHoldingFace,
//               ),
//             ),
//           ],
//         )
//             : Center(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const CircularProgressIndicator(
//                 color: Color(0xFF00FB46),
//               ),
//               const SizedBox(height: 16),
//               Text(
//                 _hasReturnedResult
//                     ? 'Face detected...'
//                     : 'Initializing camera...',
//                 style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 16,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// class _FaceDetectionInstruction extends StatelessWidget {
//   const _FaceDetectionInstruction({
//     required this.faceInsideFrame,
//     required this.isHoldingFace,
//   });
//
//   final bool faceInsideFrame;
//   final bool isHoldingFace;
//
//   @override
//   Widget build(BuildContext context) {
//     final color = faceInsideFrame ? const Color(0xFF00FB46) : Colors.white;
//
//     final text = faceInsideFrame && isHoldingFace
//         ? 'Hold still for 2 seconds...'
//         : 'Center at least 70% of your face in the frame';
//
//     return Container(
//       padding: const EdgeInsets.symmetric(
//         horizontal: 20,
//         vertical: 14,
//       ),
//       decoration: BoxDecoration(
//         color: Colors.black54,
//         borderRadius: BorderRadius.circular(30),
//         border: Border.all(
//           color: faceInsideFrame ? const Color(0xFF00FB46) : Colors.white24,
//         ),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(
//             faceInsideFrame ? Icons.check_circle : Icons.face,
//             color: color,
//             size: 24,
//           ),
//           const SizedBox(width: 12),
//           Flexible(
//             child: Text(
//               text,
//               style: TextStyle(
//                 color: color,
//                 fontSize: 16,
//                 fontWeight: FontWeight.w500,
//               ),
//               textAlign: TextAlign.center,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class FaceOvalPainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final center = Offset(size.width / 2, size.height / 2);
//
//     final ovalWidth = size.width * 0.78;
//     final ovalHeight = ovalWidth * 1.3;
//
//     final ovalRect = Rect.fromCenter(
//       center: center,
//       width: ovalWidth,
//       height: ovalHeight,
//     );
//
//     final backgroundPath = Path()
//       ..addRect(
//         Rect.fromLTWH(0, 0, size.width, size.height),
//       );
//
//     final ovalPath = Path()..addOval(ovalRect);
//
//     final outsidePath = Path.combine(
//       PathOperation.difference,
//       backgroundPath,
//       ovalPath,
//     );
//
//     final outsidePaint = Paint()
//       ..color = Colors.black.withOpacity(0.55)
//       ..style = PaintingStyle.fill;
//
//     final borderPaint = Paint()
//       ..color = Colors.white
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2;
//
//     canvas.drawPath(outsidePath, outsidePaint);
//     canvas.drawPath(ovalPath, borderPaint);
//   }
//
//   @override
//   bool shouldRepaint(covariant FaceOvalPainter oldDelegate) {
//     return false;
//   }
// }
