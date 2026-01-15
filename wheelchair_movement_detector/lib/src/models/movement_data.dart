class MovementData {
  final bool isMoving;
  final String movementType;
  final double totalDistance;
  final double sessionDistance;
  final double velocity;
  final DateTime sessionStartTime;
  final Duration totalMovingTime;
  final DateTime? movingStartTime;
  final bool isCalibrating;

  MovementData({
    required this.isMoving,
    required this.movementType,
    required this.totalDistance,
    required this.sessionDistance,
    required this.velocity,
    required this.sessionStartTime,
    required this.totalMovingTime,
    this.movingStartTime,
    required this.isCalibrating,
  });

  /// Get current moving time including active movement
  Duration getCurrentMovingTime() {
    Duration current = totalMovingTime;
    if (movingStartTime != null) {
      current += DateTime.now().difference(movingStartTime!);
    }
    return current;
  }

  /// Get session duration
  Duration getSessionDuration() {
    return DateTime.now().difference(sessionStartTime);
  }
}