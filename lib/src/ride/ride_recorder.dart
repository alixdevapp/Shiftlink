// Enregistre une sortie seconde par seconde et l'enregistre en .fit.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fit_writer.dart';
import 'ride_history.dart';

/// Valeurs du moment : puissance (W), cadence (tr/min), cardio (bpm), vitesse (km/h).
typedef RideReading = ({int? power, int? cadence, int? heartRate, double? speedKmh});

/// Où on est sur un parcours : position GPS (si la trace en a une) et altitude en mètres.
typedef RidePosition = ({double? lat, double? lon, double? altitude});

class RideRecorder {
  final RideReading Function() read;

  /// Position sur le parcours en cours, ou null hors parcours.
  final RidePosition? Function()? position;
  final DateTime Function() now;

  /// FTP du cycliste, gardée avec la sortie pour calculer sa charge.
  final int Function()? ftp;

  RideRecorder({required this.read, DateTime Function()? now, this.ftp, this.position}) : now = now ?? DateTime.now;

  final ValueNotifier<bool> recording = ValueNotifier(false);

  /// Durée et distance (m) de la sortie en cours, mises à jour chaque seconde.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);
  final ValueNotifier<double> distance = ValueNotifier(0);

  final List<RideSample> samples = [];

  /// Index des points où commence un nouveau tour (bloc de séance).
  final List<int> laps = [];
  Timer? _timer;

  /// Commence un nouveau tour au prochain point. Sans effet hors enregistrement,
  /// ou si le tour en cours vient juste de commencer (moins de 3 s).
  void markLap() {
    if (!recording.value || samples.isEmpty) return;
    final last = laps.isEmpty ? 0 : laps.last;
    if (samples.length - last < 3) return;
    laps.add(samples.length);
  }

  void start() {
    if (recording.value) return;
    samples.clear();
    laps.clear();
    elapsed.value = Duration.zero;
    distance.value = 0;
    recording.value = true;
    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Un point (appelé chaque seconde).
  @visibleForTesting
  void tick() {
    final r = read();
    final t = now();
    final speed = r.speedKmh == null ? null : r.speedKmh! / 3.6;
    if (samples.isNotEmpty && speed != null) {
      final dt = t.difference(samples.last.time).inMilliseconds / 1000;
      distance.value += speed * dt.clamp(0, 5);
    }
    final pos = position?.call();
    samples.add(
      RideSample(
        time: t,
        power: r.power,
        cadence: r.cadence,
        heartRate: r.heartRate,
        speed: speed,
        distance: distance.value,
        lat: pos?.lat,
        lon: pos?.lon,
        altitude: pos?.altitude,
      ),
    );
    elapsed.value = t.difference(samples.first.time);
  }

  /// Arrête et renvoie le fichier .fit, ou null si la sortie est trop courte (moins d'une minute).
  Future<File?> stop() async {
    _timer?.cancel();
    _timer = null;
    recording.value = false;
    if (samples.length < 60) return null;
    final dir = await directory();
    await dir.create(recursive: true);
    final t = samples.first.time;
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'ShiftLink-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}h${two(t.minute)}.fit';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(FitWriter.encode(samples, laps: laps));
    try {
      await RideHistory(dir).save(RideSummary.fromSamples(samples, distance.value, file.path, ftp: ftp?.call()));
    } catch (_) {}
    return file;
  }

  /// Dossier des sorties enregistrées.
  static Future<Directory> directory() async => Directory('${(await getApplicationDocumentsDirectory()).path}/sorties');

  void dispose() => _timer?.cancel();
}
