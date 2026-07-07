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

  bool get hasAny => labels.isNotEmpty;
  bool get hasSingle => labels.length == 1;
  bool get hasOverlap => labels.length > 1;

  bool get isOnlyCancelEverything => isCancelEverything && hasSingle;
  bool get isOnlyCallMe => isCallMe && hasSingle;

  List<String> get labels => [
    if (isCancelEverything) 'Return to main position',
    if (isOk) 'Start record video',
    if (isCallMe) 'Detect my face',
    if (isPunch) 'Pause video',
  ];
}
