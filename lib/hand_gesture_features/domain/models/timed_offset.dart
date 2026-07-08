import 'package:flutter/material.dart';

/// Stores a point, timestamp, and optional depth for motion history windows.
class TimedOffset {
  const TimedOffset({required this.point, required this.time, this.depth = 0});

  final Offset point;
  final DateTime time;
  final double depth;
}
