import 'package:hand_detection/hand_detection.dart';

/// Stable identifiers for detector results that painters use as geometry gates.
enum GestureDebugRequirementId { zoomTipGap }

/// One detector requirement displayed by a gesture-family debug painter.
class GestureDebugRequirement {
  const GestureDebugRequirement({
    required this.matches,
    required this.text,
    this.id,
  });

  final bool matches;
  final String text;
  final GestureDebugRequirementId? id;
}

/// Immutable diagnostic result derived from shared gesture geometry.
class GestureDebugEvaluation {
  GestureDebugEvaluation({
    required this.title,
    required this.matches,
    required List<GestureDebugRequirement> requirements,
    required Set<HandLandmarkType> landmarkTypes,
  }) : requirements = List.unmodifiable(requirements),
       landmarkTypes = Set.unmodifiable(landmarkTypes);

  final String title;
  final bool matches;
  final List<GestureDebugRequirement> requirements;
  final Set<HandLandmarkType> landmarkTypes;
}
