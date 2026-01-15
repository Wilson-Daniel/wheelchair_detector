import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:math';

class WheelchairMovementDetector extends StatefulWidget {
  const WheelchairMovementDetector({Key? key}) : super(key: key);

  @override
  State<WheelchairMovementDetector> createState() => _WheelchairMovementDetectorState();
}

class _WheelchairMovementDetectorState extends State<WheelchairMovementDetector> {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // Movement detection
  bool isMoving = false;
  String movementType = "Stationary";

  // Distance tracking
  double totalDistance = 0.0; // Total distance in meters
  double velocity = 0.0; // Current velocity in m/s
  double sessionDistance = 0.0; // Distance for current session

  // Time tracking
  DateTime? lastUpdateTime;
  DateTime sessionStartTime = DateTime.now();
  Duration totalMovingTime = Duration.zero;
  DateTime? movingStartTime;

  // Calibration and filtering
  static const double movementThreshold = 0.3; // Lower for wheelchair sensitivity
  static const double maxReasonableAcceleration = 5.0; // Filter out spikes
  static const double velocityDecayRate = 0.92; // How fast velocity drops when stopping
  static const double minVelocityThreshold = 0.05; // Min velocity to consider as moving

  // Rolling averages for smoothing
  List<double> accelerationHistory = [];
  List<double> velocityHistory = [];
  static const int accelerationHistorySize = 15;
  static const int velocityHistorySize = 8;

  // Calibration mode
  bool isCalibrating = false;
  List<double> calibrationReadings = [];
  double baselineNoise = 0.0;

  @override
  void initState() {
    super.initState();
    lastUpdateTime = DateTime.now();
    _startCalibration();
  }

  // Calibrate sensor to detect baseline noise when stationary
  void _startCalibration() {
    setState(() {
      isCalibrating = true;
    });

    Timer(const Duration(seconds: 3), () {
      if (calibrationReadings.isNotEmpty) {
        baselineNoise = calibrationReadings.reduce((a, b) => a + b) /
            calibrationReadings.length;
      }
      setState(() {
        isCalibrating = false;
      });
      _startTracking();
    });
  }

  void _startTracking() {
    // Listen to accelerometer for distance calculation
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (isCalibrating) {
        _collectCalibrationData(event);
      } else {
        _processAccelerometer(event);
      }
    });

    // Listen to gyroscope for turn detection
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      _processGyroscope(event);
    });
  }

  void _collectCalibrationData(AccelerometerEvent event) {
    double magnitude = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2)
    );
    double netAcceleration = (magnitude - 9.8).abs();
    calibrationReadings.add(netAcceleration);
  }

  void _processAccelerometer(AccelerometerEvent event) {
    DateTime now = DateTime.now();
    double deltaTime = (now.difference(lastUpdateTime!).inMilliseconds) / 1000.0;

    // Prevent processing if time interval is too small
    if (deltaTime < 0.02 || deltaTime > 0.5) {
      lastUpdateTime = now;
      return;
    }

    // Calculate total acceleration magnitude
    double magnitude = sqrt(
        pow(event.x, 2) +
            pow(event.y, 2) +
            pow(event.z, 2)
    );

    // Remove gravity to get net acceleration
    double netAcceleration = (magnitude - 9.8).abs();

    // Subtract baseline noise from calibration
    netAcceleration = max(0, netAcceleration - baselineNoise);

    // Filter out unrealistic spikes (sensor errors)
    if (netAcceleration > maxReasonableAcceleration) {
      lastUpdateTime = now;
      return;
    }

    // Add to history for smoothing
    accelerationHistory.add(netAcceleration);
    if (accelerationHistory.length > accelerationHistorySize) {
      accelerationHistory.removeAt(0);
    }

    // Calculate smoothed acceleration using weighted average
    // Recent values have more weight
    double smoothedAcceleration = 0.0;
    double totalWeight = 0.0;
    for (int i = 0; i < accelerationHistory.length; i++) {
      double weight = (i + 1).toDouble(); // Linear weight increase
      smoothedAcceleration += accelerationHistory[i] * weight;
      totalWeight += weight;
    }
    smoothedAcceleration /= totalWeight;

    // Detect if moving
    bool wasMoving = isMoving;
    isMoving = smoothedAcceleration > movementThreshold;

    if (isMoving) {
      // Track moving time
      if (!wasMoving) {
        movingStartTime = now;
      }

      // Update velocity: v = u + at
      velocity += smoothedAcceleration * deltaTime;

      // Calculate distance: s = vt + 0.5at²
      double distanceIncrement = (velocity * deltaTime) +
          (0.5 * smoothedAcceleration * pow(deltaTime, 2));

      // Only add distance if it's reasonable
      if (distanceIncrement > 0 && distanceIncrement < 0.5) {
        totalDistance += distanceIncrement;
        sessionDistance += distanceIncrement;
      }

    } else {
      // Apply velocity decay when not moving
      velocity *= velocityDecayRate;

      // Reset velocity if below threshold
      if (velocity < minVelocityThreshold) {
        velocity = 0;
      }

      // Update moving time
      if (wasMoving && movingStartTime != null) {
        totalMovingTime += now.difference(movingStartTime!);
        movingStartTime = null;
      }
    }

    // Store velocity for averaging
    velocityHistory.add(velocity);
    if (velocityHistory.length > velocityHistorySize) {
      velocityHistory.removeAt(0);
    }

    // Calculate average velocity
    double avgVelocity = velocityHistory.isEmpty ? 0 :
    velocityHistory.reduce((a, b) => a + b) / velocityHistory.length;

    setState(() {
      velocity = avgVelocity;

      if (!isMoving) {
        movementType = "Stationary";
      } else if (smoothedAcceleration > movementThreshold * 2.5) {
        movementType = "Moving Fast";
      } else {
        movementType = "Moving";
      }
    });

    lastUpdateTime = now;
  }

  void _processGyroscope(GyroscopeEvent event) {
    // Detect turning based on z-axis rotation
    const double turningThreshold = 0.4;
    double rotationMagnitude = event.z.abs();

    if (isMoving && rotationMagnitude > turningThreshold) {
      setState(() {
        if (event.z > 0) {
          movementType = "Turning Left";
        } else {
          movementType = "Turning Right";
        }
      });
    }
  }

  void _resetSession() {
    setState(() {
      sessionDistance = 0.0;
      sessionStartTime = DateTime.now();
      totalMovingTime = Duration.zero;
      movingStartTime = null;
    });
  }

  void _resetAll() {
    setState(() {
      totalDistance = 0.0;
      sessionDistance = 0.0;
      velocity = 0.0;
      accelerationHistory.clear();
      velocityHistory.clear();
      sessionStartTime = DateTime.now();
      totalMovingTime = Duration.zero;
      movingStartTime = null;
    });
  }

  String _formatDistance(double meters) {
    if (meters < 1) {
      return '${(meters * 100).toStringAsFixed(0)} cm';
    } else if (meters < 1000) {
      return '${meters.toStringAsFixed(2)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(3)} km';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  double _calculateAverageSpeed() {
    if (totalMovingTime.inSeconds == 0) return 0.0;
    return sessionDistance / totalMovingTime.inSeconds;
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Duration sessionDuration = DateTime.now().difference(sessionStartTime);
    Duration currentMovingTime = totalMovingTime;
    if (movingStartTime != null) {
      currentMovingTime += DateTime.now().difference(movingStartTime!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.grey,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            onPressed: _resetSession,
            tooltip: 'Reset Session',
          ),
        ],
      ),
      body: isCalibrating
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Calibrating sensors...',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'Keep device still',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Movement Status
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isMoving
                        ? [Colors.green.shade400, Colors.green.shade600]
                        : [Colors.grey.shade300, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      isMoving ? Icons.accessible : Icons.accessibility_new,
                      size: 60,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      movementType,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Session Distance (Main Display)
              Container(
                padding: const EdgeInsets.all(24),
                // decoration: BoxDecoration(
                //   color: Colors.blue.shade50,
                //   borderRadius: BorderRadius.circular(16),
                //   border: Border.all(color: Colors.blue.shade200, width: 3),
                // ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.straighten, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Session Distance',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatDistance(sessionDistance),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // Stats Grid
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Current Speed',
                      '${(velocity).toStringAsFixed(1)} km/h',
                      '${velocity.toStringAsFixed(2)} m/s',
                      Icons.speed,
                      Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      'Avg Speed',
                      '${(_calculateAverageSpeed() * 3.6).toStringAsFixed(1)} km/h',
                      '${_calculateAverageSpeed().toStringAsFixed(2)} m/s',
                      Icons.av_timer,
                      Colors.black54,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Moving Time',
                      _formatDuration(currentMovingTime),
                      'Active',
                      Icons.timer,
                      Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      'Session Time',
                      _formatDuration(sessionDuration),
                      'Total',
                      Icons.access_time,
                      Colors.black54,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // Total Distance
              // Container(
              //   padding: const EdgeInsets.all(16),
              //   // decoration: BoxDecoration(
              //   //   color: Colors.indigo.shade50,
              //   //   borderRadius: BorderRadius.circular(12),
              //   //   border: Border.all(color: Colors.indigo.shade200, width: 2),
              //   // ),
              //   child: Row(
              //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //     children: [
              //       Row(
              //         children: [
              //           Icon(Icons.analytics, color: Colors.indigo.shade700),
              //           const SizedBox(width: 8),
              //           const Text(
              //             'Total Distance',
              //             style: TextStyle(
              //               fontSize: 16,
              //               fontWeight: FontWeight.w600,
              //             ),
              //           ),
              //         ],
              //       ),
              //       Text(
              //         _formatDistance(totalDistance),
              //         style: TextStyle(
              //           fontSize: 20,
              //           fontWeight: FontWeight.bold,
              //           color: Colors.black45,
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
              //
              // const SizedBox(height: 20),

              // // Action Buttons
              // Row(
              //   children: [
              //     Expanded(
              //       child: ElevatedButton.icon(
              //         onPressed: _resetSession,
              //         icon: const Icon(Icons.refresh),
              //         label: const Text('Reset Session'),
              //         style: ElevatedButton.styleFrom(
              //           backgroundColor: Colors.orange,
              //           foregroundColor: Colors.white,
              //           padding: const EdgeInsets.symmetric(vertical: 12),
              //         ),
              //       ),
              //     ),
              //     const SizedBox(width: 10),
              //     Expanded(
              //       child: ElevatedButton.icon(
              //         onPressed: _resetAll,
              //         icon: const Icon(Icons.delete_forever),
              //         label: const Text('Reset All'),
              //         style: ElevatedButton.styleFrom(
              //           backgroundColor: Colors.red,
              //           foregroundColor: Colors.white,
              //           padding: const EdgeInsets.symmetric(vertical: 12),
              //         ),
              //       ),
              //     ),
              //   ],
              // ),
              //
              // const SizedBox(height: 20),
              //
              // // Accuracy Note
              // Container(
              //   padding: const EdgeInsets.all(12),
              //   decoration: BoxDecoration(
              //     color: Colors.amber.shade50,
              //     borderRadius: BorderRadius.circular(8),
              //     border: Border.all(color: Colors.amber.shade300),
              //   ),
              //   child: Row(
              //     children: [
              //       Icon(Icons.info_outline,
              //           color: Colors.amber.shade700, size: 20),
              //       const SizedBox(width: 8),
              //       Expanded(
              //         child: Text(
              //           'Keep phone mounted securely for best accuracy',
              //           style: TextStyle(
              //             fontSize: 12,
              //             color: Colors.amber.shade900,
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      // decoration: BoxDecoration(
      //   color: color.withOpacity(0.1),
      //   borderRadius: BorderRadius.circular(12),
      //   border: Border.all(color: color.withOpacity(0.3), width: 2),
      // ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}