/// Confirms one Love-You pose and latches until the pose is released.
class GestureDebugMenuTrigger {
  GestureDebugMenuTrigger({this.confirmationFrames = 3})
    : assert(confirmationFrames > 0);

  final int confirmationFrames;

  int _matchFrames = 0;
  int _releaseFrames = 0;
  bool _latched = false;

  bool get isLatched => _latched;

  /// Returns true exactly once when the pose reaches its frame requirement.
  bool update({required bool isLoveYou}) {
    if (isLoveYou) {
      _releaseFrames = 0;
      if (_latched) return false;
      _matchFrames += 1;
      if (_matchFrames < confirmationFrames) return false;
      _matchFrames = 0;
      _latched = true;
      return true;
    }

    _matchFrames = 0;
    if (!_latched) {
      _releaseFrames = 0;
      return false;
    }
    _releaseFrames += 1;
    if (_releaseFrames >= confirmationFrames) {
      _releaseFrames = 0;
      _latched = false;
    }
    return false;
  }

  void clear() {
    _matchFrames = 0;
    _releaseFrames = 0;
    _latched = false;
  }
}
