import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:light_sensor/light_sensor.dart';

class AmbientSensorService {
  StreamSubscription? _accelSub;
  StreamSubscription? _lightSub;

  bool _isMoving = false;
  int _luxLevel = 0;

  bool get isMoving => _isMoving;
  bool get isDark => _luxLevel < 10;

  /// Start fusing data from multiple hardware sensors to deduce context
  void startSensorFusion() {
    _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      // Basic movement threshold
      double acceleration = event.x.abs() + event.y.abs() + event.z.abs();
      _isMoving = acceleration > 12.0; 
    });

    try {
      _lightSub = LightSensor.lightSensorStream.listen((int lux) {
        _luxLevel = lux;
      });
    } catch (e) {
      // Light sensor not available on this device
    }
  }

  /// Deduce physical context (e.g., in a pocket, on a desk, walking)
  String deduceContext() {
    if (_isMoving && isDark) {
      return "User is likely walking with the device in a pocket or bag.";
    } else if (!_isMoving && isDark) {
      return "Device is resting in a dark room (possibly sleeping).";
    } else if (_isMoving && !isDark) {
      return "User is actively holding and moving the device.";
    } else {
      return "Device is resting on a desk or flat surface in a lit room.";
    }
  }

  void stop() {
    _accelSub?.cancel();
    _lightSub?.cancel();
  }
}
