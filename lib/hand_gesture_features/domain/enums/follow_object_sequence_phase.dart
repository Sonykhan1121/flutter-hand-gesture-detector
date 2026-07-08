/// Internal phases for the open-palm, closed-fist, open-palm target sequence.
enum FollowObjectSequencePhase {
  /// No follow-object sequence is in progress.
  idle,

  /// First open palm is detected and must stay visible long enough.
  holdingFirstOpen,

  /// First open palm is already detected.
  /// The hand must remain on screen while waiting for closed fist.
  waitingForClosed,

  /// Closed fist is already detected.
  /// The hand must remain on screen while waiting for the final open palm.
  waitingForFinalOpen,
}
