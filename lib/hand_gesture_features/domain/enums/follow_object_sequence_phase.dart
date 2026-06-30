enum FollowObjectSequencePhase {
  idle,

  /// First open palm is already detected.
  /// The hand must remain on screen while waiting for closed fist.
  waitingForClosed,

  /// Closed fist is already detected.
  /// The hand must remain on screen while waiting for the final open palm.
  waitingForFinalOpen,
}
