import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

import 'models/movement_data.dart';

/// Main class that handles wheelchair movement detection and tracking
class MovementDetector {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // Movement detection
  bool _isMoving = false;
  String _movementType = "Stationary";

  // Distance tracking
  double _totalDistance = 0.0;
  double _velocity = 0.0;
  double _sessionDistance = 0.0;

  // Time tracking
  DateTime? _lastUpdateTime;
  DateTime _sessionStartTime = DateTime.now();
  Duration _totalMovingTime = Duration.zero;
  DateTime? _movingStartTime;

  // Calibration and filtering
  static const double movementThreshold = 0.3;
  static const double maxReasonableAcceleration = 5.0;
  static const double velocityDecayRate = 0.92;
  static const double minVelocityThreshold = 0.05;

  // Rolling averages for smoothing
  final List<double> _accelerationHistory = [];
  final List<double> _velocityHistory = [];
  static const int accelerationHistorySize = 15;
  static const int velocityHistorySize = 8;

  // Calibration mode
  bool _isCalibrating = false;
  final List<double> _calibrationReadings = [];
  double _baselineNoise = 0.0;

  // Stream controller for broadcasting movement data
  final _movementDataController = StreamController<MovementData>.broadcast();

  /// Stream that emits movement data updates
  Stream<MovementData> get movementDataStream => _movementDataController.stream;

  /// Current movement data
  MovementData get currentData => MovementData(
    isMoving: _isMoving,
    movementType: _movementType,
    totalDistance: _totalDistance,
    sessionDistance: _sessionDistance,
    velocity: _velocity,
    sessionStartTime: _sessionStartTime,
    totalMovingTime: _totalMovingTime,
    movingStartTime: _movingStartTime,
    isCalibrating: _isCalibrating,
  );

  /// Initialize and start the movement detector
  Future<void> initialize() async {
    _lastUpdateTime = DateTime.now();
    await _startCalibration();
  }

  /// Calibrate sensor to detect baseline noise when stationary
  Future<void> _startCalibration() async {
    _isCalibrating = true;
    _emitData();

    // Start listening to accelerometer for calibration
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      if (_isCalibrating) {
        _collectCalibrationData(event);
      }
    });

    // Wait for calibration period
    await Future.delayed(const Duration(seconds: 3));

    if (_calibrationReadings.isNotEmpty) {
      _baselineNoise =
          _calibrationReadings.reduce((a, b) => a + b) / _calibrationReadings.length;
    }

    _isCalibrating = false;
    _emitData();

    // Restart subscriptions for actual tracking
    await _accelerometerSubscription?.cancel();
    _startTracking();
  }

  void _startTracking() {
    // Listen to accelerometer for distance calculation
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      _processAccelerometer(event);
    });

    // Listen to gyroscope for turn detection
    _gyroscopeSubscription = gyroscopeEvents.listen((event) {
      _processGyroscope(event);
    });
  }

  void _collectCalibrationData(AccelerometerEvent event) {
    double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));
    double netAcceleration = (magnitude - 9.8).abs();
    _calibrationReadings.add(netAcceleration);
  }

  void _processAccelerometer(AccelerometerEvent event) {
    DateTime now = DateTime.now();
    double deltaTime = (now.difference(_lastUpdateTime!).inMilliseconds) / 1000.0;

    if (deltaTime < 0.02 || deltaTime > 0.5) {
      _lastUpdateTime = now;
      return;
    }

    double magnitude = sqrt(
      pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
    );

    double netAcceleration = (magnitude - 9.8).abs();
    netAcceleration = max(0, netAcceleration - _baselineNoise);

    if (netAcceleration > maxReasonableAcceleration) {
      _lastUpdateTime = now;
      return;
    }

    _accelerationHistory.add(netAcceleration);
    if (_accelerationHistory.length > accelerationHistorySize) {
      _accelerationHistory.removeAt(0);
    }

    double smoothedAcceleration = 0.0;
    double totalWeight = 0.0;
    for (int i = 0; i < _accelerationHistory.length; i++) {
      double weight = (i + 1).toDouble();
      smoothedAcceleration += _accelerationHistory[i] * weight;
      totalWeight += weight;
    }
    smoothedAcceleration /= totalWeight;

    bool wasMoving = _isMoving;
    _isMoving = smoothedAcceleration > movementThreshold;

    if (_isMoving) {
      if (!wasMoving) {
        _movingStartTime = now;
      }

      _velocity += smoothedAcceleration * deltaTime;

      double distanceIncrement =
          (_velocity * deltaTime) + (0.5 * smoothedAcceleration * pow(deltaTime, 2));

      if (distanceIncrement > 0 && distanceIncrement < 0.5) {
        _totalDistance += distanceIncrement;
        _sessionDistance += distanceIncrement;
      }
    } else {
      _velocity *= velocityDecayRate;

      if (_velocity < minVelocityThreshold) {
        _velocity = 0;
      }

      if (wasMoving && _movingStartTime != null) {
        _totalMovingTime += now.difference(_movingStartTime!);
        _movingStartTime = null;
      }
    }

    _velocityHistory.add(_velocity);
    if (_velocityHistory.length > velocityHistorySize) {
      _velocityHistory.removeAt(0);
    }

    double avgVelocity = _velocityHistory.isEmpty
        ? 0
        : _velocityHistory.reduce((a, b) => a + b) / _velocityHistory.length;

    _velocity = avgVelocity;

    if (!_isMoving) {
      _movementType = "Stationary";
    } else if (smoothedAcceleration > movementThreshold * 2.5) {
      _movementType = "Moving Fast";
    } else {
      _movementType = "Moving";
    }

    _lastUpdateTime = now;
    _emitData();
  }

  void _processGyroscope(GyroscopeEvent event) {
    const double turningThreshold = 0.4;
    double rotationMagnitude = event.z.abs();

    if (_isMoving && rotationMagnitude > turningThreshold) {
      if (event.z > 0) {
        _movementType = "Turning Left";
      } else {
        _movementType = "Turning Right";
      }
      _emitData();
    }
  }

  /// Reset current session data
  void resetSession() {
    _sessionDistance = 0.0;
    _sessionStartTime = DateTime.now();
    _totalMovingTime = Duration.zero;
    _movingStartTime = null;
    _emitData();
  }

  /// Reset all tracking data
  void resetAll() {
    _totalDistance = 0.0;
    _sessionDistance = 0.0;
    _velocity = 0.0;
    _accelerationHistory.clear();
    _velocityHistory.clear();
    _sessionStartTime = DateTime.now();
    _totalMovingTime = Duration.zero;
    _movingStartTime = null;
    _emitData();
  }

  /// Calculate average speed for the session
  double calculateAverageSpeed() {
    if (_totalMovingTime.inSeconds == 0) return 0.0;
    return _sessionDistance / _totalMovingTime.inSeconds;
  }

  void _emitData() {
    if (!_movementDataController.isClosed) {
      _movementDataController.add(currentData);
    }
  }

  /// Dispose and cleanup resources
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _movementDataController.close();
  }
}