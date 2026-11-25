// Envoi des sorties à Health Connect (Android). Le code natif est dans HealthConnect.kt.
import 'package:flutter/services.dart';

import 'fit_writer.dart';

class HealthConnect {
  static const _channel = MethodChannel('shiftlink/health');

  /// Health Connect est-elle installée (et à jour) sur ce téléphone ?
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Demande l'accès en écriture. Renvoie false si refusé ou si Health Connect est absent.
  Future<bool> requestAccess() async {
    try {
      return await _channel.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Écrit une séance de vélo d'intérieur : durée, distance, puissance, cadence et cardio.
  Future<bool> saveRide(List<RideSample> samples, double distanceMeters) async {
    if (samples.length < 2) return false;
    try {
      return await _channel.invokeMethod<bool>('save', {
            'start': samples.first.time.millisecondsSinceEpoch,
            'end': samples.last.time.millisecondsSinceEpoch,
            'distance': distanceMeters,
            'times': [for (final s in samples) s.time.millisecondsSinceEpoch],
            'power': [for (final s in samples) s.power ?? -1],
            'cadence': [for (final s in samples) s.cadence ?? -1],
            'heartRate': [for (final s in samples) s.heartRate ?? -1],
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
