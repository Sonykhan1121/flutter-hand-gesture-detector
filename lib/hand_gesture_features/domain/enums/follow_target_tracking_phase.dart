/// User-visible lifecycle for a remembered follow target.
enum FollowTargetTrackingPhase {
  idle,
  selecting,
  visible,
  lost,
  confirmingReacquisition,
}
