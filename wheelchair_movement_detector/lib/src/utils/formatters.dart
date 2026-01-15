/// Utility class for formatting movement data
class MovementFormatters {
  /// Format distance in appropriate units (cm, m, or km)
  static String formatDistance(double meters) {
    if (meters < 1) {
      return '${(meters * 100).toStringAsFixed(0)} cm';
    } else if (meters < 1000) {
      return '${meters.toStringAsFixed(2)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(3)} km';
    }
  }

  /// Format duration as HH:MM:SS
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  /// Format velocity in km/h
  static String formatVelocityKmh(double metersPerSecond) {
    return '${(metersPerSecond * 3.6).toStringAsFixed(1)} km/h';
  }

  /// Format velocity in m/s
  static String formatVelocityMs(double metersPerSecond) {
    return '${metersPerSecond.toStringAsFixed(2)} m/s';
  }
}