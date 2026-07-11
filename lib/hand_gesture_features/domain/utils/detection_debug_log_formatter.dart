import 'dart:ui';

/// Formats face/object detector timing and area for debug logs.
String formatDetectionDebugLog({
  required String label,
  required Rect boundingBox,
  required Duration elapsed,
}) {
  final width = _positiveFinite(boundingBox.width);
  final height = _positiveFinite(boundingBox.height);
  final areaPx = (width * height).round();

  return '$label : area=$areaPx, time=${elapsed.inMilliseconds}ms';
}

double _positiveFinite(double value) {
  if (!value.isFinite || value <= 0) return 0;
  return value;
}
