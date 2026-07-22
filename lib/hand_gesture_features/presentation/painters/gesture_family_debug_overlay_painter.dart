import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../../domain/enums/gesture_debug_mode.dart';
import '../../domain/models/gesture_debug_evaluation.dart';
import '../../domain/services/hand_geometry_service.dart';
import '../../domain/utils/camera_preview_geometry.dart';

/// Draws the selected non-Direction/non-Punch gesture-family diagnostics.
class GestureFamilyDebugOverlayPainter extends CustomPainter {
  const GestureFamilyDebugOverlayPainter({
    required this.mode,
    required this.hand,
    required this.imageSize,
    required this.mirrorHorizontally,
    required this.evaluation,
    this.previewQuarterTurns = 0,
    this.useRecordingPreviewMapping = false,
    this.geometry = const HandGeometryService(),
  });

  final GestureDebugMode mode;
  final Hand? hand;
  final Size imageSize;
  final bool mirrorHorizontally;
  final GestureDebugEvaluation evaluation;
  final int previewQuarterTurns;
  final bool useRecordingPreviewMapping;
  final HandGeometryService geometry;

  static const _green = Color(0xFF69F0AE);
  static const _red = Color(0xFFFF5252);
  static const _cyan = Color(0xFF00E5FF);
  static const _yellow = Color(0xFFFFD740);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final currentHand = hand;
    if (currentHand != null && imageSize.width > 0 && imageSize.height > 0) {
      _drawRequiredLandmarks(canvas, size, currentHand);
      _drawEmphasisGeometry(canvas, size, currentHand);
    }
    _drawEvaluationPanel(canvas, size);
    canvas.restore();
  }

  void _drawRequiredLandmarks(Canvas canvas, Size size, Hand hand) {
    final types = evaluation.landmarkTypes;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _cyan;

    for (final connection in handLandmarkConnections) {
      final startType = connection[0];
      final endType = connection[1];
      if (!types.contains(startType) || !types.contains(endType)) continue;
      final start = geometry.visibleLandmark(hand, startType);
      final end = geometry.visibleLandmark(hand, endType);
      if (start == null || end == null) continue;
      final mappedStart = _mapPoint(size, Offset(start.x, start.y));
      final mappedEnd = _mapPoint(size, Offset(end.x, end.y));
      if (mappedStart == null || mappedEnd == null) continue;
      canvas.drawLine(mappedStart, mappedEnd, linePaint);
    }

    for (final type in types) {
      final landmark = geometry.visibleLandmark(hand, type);
      if (landmark == null) continue;
      final point = _mapPoint(size, Offset(landmark.x, landmark.y));
      if (point == null) continue;
      canvas.drawCircle(point, 6, Paint()..color = _yellow);
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black,
      );
      _drawPointLabel(canvas, point, '${type.index}');
    }
  }

  void _drawEmphasisGeometry(Canvas canvas, Size size, Hand hand) {
    final pairs = <(HandLandmarkType, HandLandmarkType)>[];
    switch (mode) {
      case GestureDebugMode.zoomIn:
      case GestureDebugMode.zoomOut:
        pairs.addAll(const [
          (HandLandmarkType.thumbIP, HandLandmarkType.thumbTip),
          (HandLandmarkType.indexFingerDIP, HandLandmarkType.indexFingerTip),
          (HandLandmarkType.thumbTip, HandLandmarkType.indexFingerTip),
        ]);
        break;
      case GestureDebugMode.callMe:
        pairs.add(const (HandLandmarkType.thumbTip, HandLandmarkType.pinkyTip));
        break;
      case GestureDebugMode.recording:
        pairs.add(const (
          HandLandmarkType.thumbTip,
          HandLandmarkType.indexFingerTip,
        ));
        break;
      case GestureDebugMode.returnMain:
      case GestureDebugMode.followObject:
      case GestureDebugMode.off:
      case GestureDebugMode.direction:
      case GestureDebugMode.punch:
        break;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = evaluation.matches ? _green : _red;
    for (final pair in pairs) {
      final first = geometry.visibleLandmark(hand, pair.$1);
      final second = geometry.visibleLandmark(hand, pair.$2);
      if (first == null || second == null) continue;
      final mappedFirst = _mapPoint(size, Offset(first.x, first.y));
      final mappedSecond = _mapPoint(size, Offset(second.x, second.y));
      if (mappedFirst == null || mappedSecond == null) continue;
      canvas.drawLine(mappedFirst, mappedSecond, paint);
    }
  }

  void _drawEvaluationPanel(Canvas canvas, Size size) {
    final statusColor = evaluation.matches ? _green : _red;
    final spans = <InlineSpan>[
      TextSpan(
        text: evaluation.matches
            ? '✓ ${evaluation.title}'
            : '✕ ${evaluation.title}',
        style: TextStyle(
          color: statusColor,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    ];
    for (final requirement in evaluation.requirements) {
      spans.add(
        TextSpan(
          text: '\n${requirement.matches ? '✓' : '✕'} ${requirement.text}',
          style: TextStyle(
            color: requirement.matches ? _green : _red,
            fontSize: 10,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    const padding = 9.0;
    final textPainter = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(80, math.min(330, size.width - 24)));
    final panelWidth = textPainter.width + padding * 2;
    final panelHeight = textPainter.height + padding * 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 8, panelWidth, panelHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.black.withValues(alpha: 0.84),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = statusColor,
    );
    textPainter.paint(canvas, const Offset(8 + padding, 8 + padding));
  }

  Offset? _mapPoint(Size canvasSize, Offset sourcePoint) {
    return detectionPointToPreviewCanvas(
      sourcePoint: sourcePoint,
      detectionImageSize: imageSize,
      canvasSize: canvasSize,
      mirrorHorizontally: mirrorHorizontally,
      previewQuarterTurns: previewQuarterTurns,
      useRecordingPreviewMapping: useRecordingPreviewMapping,
    );
  }

  void _drawPointLabel(Canvas canvas, Offset point, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, point + const Offset(7, -13));
  }

  @override
  bool shouldRepaint(covariant GestureFamilyDebugOverlayPainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.hand != hand ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.evaluation != evaluation ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns ||
        oldDelegate.useRecordingPreviewMapping != useRecordingPreviewMapping;
  }
}
