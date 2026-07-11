import 'package:flutter/material.dart';

import '../../domain/models/object_optical_flow_track_result.dart';

/// Optional optical-flow diagnostics kept out of the normal camera UI.
class ObjectOpticalFlowDebugPainter extends CustomPainter {
  const ObjectOpticalFlowDebugPainter({required this.result});

  final ObjectOpticalFlowTrackResult result;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = _scale(result.rawDisplayBox, size);
    final smoothed = _scale(result.displayBox, size);
    canvas.drawRect(
      raw,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.orange,
    );
    canvas.drawRect(
      smoothed,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.cyanAccent,
    );
    final pointPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.yellowAccent;
    for (final point in result.featurePoints) {
      canvas.drawCircle(
        Offset(point.dx * size.width, point.dy * size.height),
        2,
        pointPaint,
      );
    }

    final label = TextPainter(
      text: TextSpan(
        text:
            'flow ${result.status.name} '
            'f=${result.frameId} p=${result.validPointCount} '
            'inliers=${result.inlierRatio.toStringAsFixed(2)} '
            'c=${result.confidence.toStringAsFixed(2)}'
            '${result.rejectionReason == null ? '' : ' ${result.rejectionReason}'}',
        style: const TextStyle(
          color: Colors.cyanAccent,
          backgroundColor: Colors.black87,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: size.width - 12);
    label.paint(canvas, const Offset(6, 6));
  }

  Rect _scale(Rect box, Size size) => Rect.fromLTRB(
    box.left * size.width,
    box.top * size.height,
    box.right * size.width,
    box.bottom * size.height,
  );

  @override
  bool shouldRepaint(covariant ObjectOpticalFlowDebugPainter oldDelegate) =>
      oldDelegate.result != result;
}
