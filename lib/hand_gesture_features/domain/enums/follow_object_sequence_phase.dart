/// Internal phases for the palm, fist, index-point, final-palm sequence.
enum FollowObjectSequencePhase {
  /// No follow-object sequence is in progress.
  idle,

  /// First open palm is detected and must stay visible long enough.
  holdingFirstOpen,

  /// First open palm is already detected.
  /// The hand must remain on screen while waiting for closed fist.
  waitingForClosed,

  /// Closed fist is already detected; wait for an index-only pointing pose.
  waitingForPoint,

  /// The index fingertip is dwelling inside one target rectangle.
  holdingPoint,

  /// One target completed its dwell; wait for the explicit final open palm.
  waitingForFinalPalm,

  /// The selecting hand left the frame and may return before cancellation.
  waitingForHandReturn,
}
