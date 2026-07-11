import 'dart:ui';

enum ObjectOpticalFlowTrackStatus { initialized, tracked, uncertain }

/// One optical-flow update for the currently selected object.
class ObjectOpticalFlowTrackResult {
  const ObjectOpticalFlowTrackResult({
    required this.status,
    required this.frameId,
    required this.displayBox,
    required this.rawDisplayBox,
    required this.confidence,
    required this.validPointCount,
    required this.inlierRatio,
    required this.featurePoints,
    this.rejectionReason,
  });

  final ObjectOpticalFlowTrackStatus status;
  final int frameId;
  final Rect displayBox;
  final Rect rawDisplayBox;
  final double confidence;
  final int validPointCount;
  final double inlierRatio;
  final List<Offset> featurePoints;
  final String? rejectionReason;

  bool get isUsable =>
      status == ObjectOpticalFlowTrackStatus.initialized ||
      status == ObjectOpticalFlowTrackStatus.tracked;
}
