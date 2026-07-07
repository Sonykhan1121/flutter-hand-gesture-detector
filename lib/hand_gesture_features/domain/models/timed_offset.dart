import 'package:flutter/material.dart';

class TimedOffset {
  const TimedOffset({required this.point, required this.time, this.depth = 0});

  final Offset point;
  final DateTime time;
  final double depth;
}
