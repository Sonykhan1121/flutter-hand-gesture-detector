import 'package:flutter/material.dart';

class MobileStandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final phoneWidth = size.width * 0.38;
    final phoneHeight = size.height * 0.70;
    final phoneLeft = size.width * 0.34;
    final phoneTop = size.height * 0.08;

    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneLeft, phoneTop, phoneWidth, phoneHeight),
      Radius.circular(phoneWidth * 0.14),
    );

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawRRect(phoneRect.shift(const Offset(0, 12)), shadowPaint);

    final phonePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEFF6FF), Color(0xFFBFD7FF)],
      ).createShader(phoneRect.outerRect);

    canvas.drawRRect(phoneRect, phonePaint);

    final screenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        phoneLeft + phoneWidth * 0.09,
        phoneTop + phoneHeight * 0.08,
        phoneWidth * 0.82,
        phoneHeight * 0.76,
      ),
      Radius.circular(phoneWidth * 0.09),
    );

    final screenPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF163B70), Color(0xFF0B1220)],
      ).createShader(screenRect.outerRect);

    canvas.drawRRect(screenRect, screenPaint);

    final cameraPaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawCircle(
      Offset(phoneLeft + phoneWidth * 0.50, phoneTop + phoneHeight * 0.04),
      phoneWidth * 0.025,
      cameraPaint,
    );

    final armPaint = Paint()
      ..color = const Color(0xFFE6F1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    final armPath = Path()
      ..moveTo(size.width * 0.51, phoneTop + phoneHeight * 0.82)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.84,
        size.width * 0.50,
        size.height * 0.90,
      );

    canvas.drawPath(armPath, armPaint);

    final basePaint = Paint()
      ..shader =
          const LinearGradient(
            colors: [Color(0xFFEFF6FF), Color(0xFFBBD3F7)],
          ).createShader(
            Rect.fromLTWH(
              size.width * 0.22,
              size.height * 0.88,
              size.width * 0.58,
              size.height * 0.10,
            ),
          );

    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.22,
        size.height * 0.86,
        size.width * 0.58,
        size.height * 0.10,
      ),
      Radius.circular(size.height * 0.05),
    );

    canvas.drawRRect(baseRect, shadowPaint);
    canvas.drawRRect(baseRect, basePaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF00FB46).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.53, size.height * 0.46),
        radius: size.width * 0.36,
      ),
      -1.1,
      2.2,
      false,
      glowPaint,
    );

    final dotPaint = Paint()..color = const Color(0xFF00FB46);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.32),
      4,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.58),
      3,
      dotPaint..color = const Color(0xFF53B1FD),
    );
  }

  @override
  bool shouldRepaint(covariant MobileStandPainter oldDelegate) => false;
}
