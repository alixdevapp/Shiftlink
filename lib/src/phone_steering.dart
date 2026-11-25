// Direction avec le téléphone fixé au guidon (gyroscope + accéléromètre).
import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'controllers/driver.dart';
import 'controllers/steering_drivers.dart';

/// Où en est la direction au téléphone, pour l'écran de réglage.
enum SteeringStatus { off, starting, noGyro, ok }

class PhoneSteering {
  final void Function(ButtonEvent e) onEvent;
  final void Function(double angle)? onAngle;
  final void Function(SteeringStatus s)? onStatus;

  /// Sans moment immobile (vibrations du home trainer, téléphone tenu à la main),
  /// le zéro est pris au bout de ce délai.
  static const calibrationTimeout = Duration(milliseconds: 1500);

  /// Sans mesure du gyroscope après ce délai, le téléphone n'en a sans doute pas.
  static const gyroTimeout = Duration(seconds: 3);
  DateTime? _startedAt;
  Timer? _gyroCheck;
  bool _gyroSeen = false;
  final estimator = SteeringEstimator();
  final SteeringGate gate;
  final List<StreamSubscription<Object?>> _subs = [];
  DateTime? _last;
  bool _calibrated = false;

  PhoneSteering({required this.onEvent, this.onAngle, this.onStatus, double threshold = 8})
    : gate = SteeringGate(threshold);

  bool get running => _subs.isNotEmpty;

  void start() {
    if (running) return;
    estimator.reset();
    gate.reset();
    _calibrated = false;
    _last = null;
    _gyroSeen = false;
    _startedAt = DateTime.now();
    onStatus?.call(SteeringStatus.starting);
    _gyroCheck?.cancel();
    _gyroCheck = Timer(gyroTimeout, () {
      if (!_gyroSeen && running) onStatus?.call(SteeringStatus.noGyro);
    });
    _subs.add(
      accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) => estimator.updateAccel(e.x, e.y, e.z), onError: (_) {}),
    );
    _subs.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_gyro, onError: (_) {}));
  }

  void _gyro(GyroscopeEvent e) {
    _gyroSeen = true;
    final now = DateTime.now();
    final last = _last;
    _last = now;
    if (last == null || !estimator.hasAccel) return;
    final dt = now.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt >= 1) return;
    final a = estimator.updateGyro(e.x, e.y, e.z, dt);
    if (!_calibrated) {
      // Zéro quand le téléphone est resté immobile un instant.
      // Sinon, au bout d'un instant, la position actuelle devient le zéro.
      final waited = now.difference(_startedAt ?? now) >= calibrationTimeout;
      if (estimator.stillTime >= 0.6 || waited) {
        estimator.center();
        _calibrated = true;
        onStatus?.call(SteeringStatus.ok);
      }
      return;
    }
    onAngle?.call(a);
    for (final ev in gate.update(a)) {
      onEvent(ev);
    }
  }

  /// Guidon droit maintenant : nouveau zéro.
  void recenter() {
    estimator.center();
    if (!_calibrated && _gyroSeen) {
      _calibrated = true;
      onStatus?.call(SteeringStatus.ok);
    }
    for (final ev in gate.update(0)) {
      onEvent(ev);
    }
  }

  void stop() {
    _gyroCheck?.cancel();
    onStatus?.call(SteeringStatus.off);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final ev in gate.update(0)) {
      onEvent(ev);
    }
  }
}
