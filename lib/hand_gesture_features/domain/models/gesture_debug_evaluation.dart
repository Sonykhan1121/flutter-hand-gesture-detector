import 'package:hand_detection/hand_detection.dart';

/// One detector requirement displayed by a gesture-family debug painter.
class GestureDebugRequirement {
  const GestureDebugRequirement({required this.matches, required this.text});

  final bool matches;
  final String text;
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
