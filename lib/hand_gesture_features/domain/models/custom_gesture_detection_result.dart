/// Boolean result set for custom gestures recognized outside the package enum.
class CustomGestureDetectionResult {
  const CustomGestureDetectionResult({
    required this.isCancelEverything,
    required this.isOk,
    required this.isCallMe,
    required this.isPunch,
  });

  final bool isCancelEverything;
  final bool isOk;
  final bool isCallMe;
  final bool isPunch;

  static const empty = CustomGestureDetectionResult(
    isCancelEverything: false,
    isOk: false,
    isCallMe: false,
    isPunch: false,
  );

  /// True when at least one custom gesture is active.
  bool get hasAny => labels.isNotEmpty;
  /// True when exactly one custom gesture is active.
  bool get hasSingle => labels.length == 1;
  /// True when multiple custom gestures overlap in the same frame.
  bool get hasOverlap => labels.length > 1;

  /// True when return-to-main is the only custom gesture.
  bool get isOnlyCancelEverything => isCancelEverything && hasSingle;
  /// True when call-me is the only custom gesture.
  bool get isOnlyCallMe => isCallMe && hasSingle;

  /// User-facing labels for every active custom gesture in this frame.
  List<String> get labels => [
    if (isCancelEverything) 'Return to main position',
    if (isOk) 'Start record video',
    if (isCallMe) 'Detect my face',
    if (isPunch) 'Pause video',
  ];
}
