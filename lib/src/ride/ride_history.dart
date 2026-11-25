// Historique des sorties : un résumé .json à côté de chaque fichier .fit.
import 'dart:convert';
import 'dart:io';

import 'fit_writer.dart';
import 'power_stats.dart' as stats;

class RideSummary {
  final DateTime start;
  final Duration duration;

  /// Distance en mètres.
  final double distance;
  final int? avgPower;
  final int? maxPower;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? avgCadence;

  /// Meilleurs efforts (durée en s → W), puissance normalisée, FTP du moment.
  /// Vides pour les sorties d'avant la 2.8 tant qu'on ne les a pas recalculés.
  final Map<int, int> bests;
  final int? normalizedPower;
  final int? ftp;

  /// Charge (TSS) de la sortie, si on connaît la puissance normalisée et la FTP.
  double? get load => stats.trainingLoad(seconds: duration.inSeconds, np: normalizedPower, ftp: ftp ?? 0);

  /// Les statistiques de puissance sont-elles calculées ?
  bool get hasStats => bests.isNotEmpty || normalizedPower != null;

  /// Fichier .fit de la sortie (peut manquer si on l'a supprimé à la main).
  final String fitPath;

  const RideSummary({
    required this.start,
    required this.duration,
    required this.distance,
    required this.fitPath,
    this.avgPower,
    this.maxPower,
    this.avgHeartRate,
    this.maxHeartRate,
    this.avgCadence,
    this.bests = const {},
    this.normalizedPower,
    this.ftp,
  });

  RideSummary withStats(List<int?> watts, int? ftp) => RideSummary(
    start: start,
    duration: duration,
    distance: distance,
    fitPath: fitPath,
    avgPower: avgPower,
    maxPower: maxPower,
    avgHeartRate: avgHeartRate,
    maxHeartRate: maxHeartRate,
    avgCadence: avgCadence,
    bests: stats.bestEfforts(watts),
    normalizedPower: stats.normalizedPower(watts),
    ftp: this.ftp ?? ftp,
  );

  /// Moyennes calculées sur les seules secondes où la valeur existe (et > 0 pour la puissance et la cadence).
  static RideSummary fromSamples(List<RideSample> samples, double distance, String fitPath, {int? ftp}) {
    int? avg(Iterable<int> v) => v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
    int? max(Iterable<int> v) => v.isEmpty ? null : v.reduce((a, b) => a > b ? a : b);
    final power = samples.map((s) => s.power).whereType<int>().where((p) => p > 0);
    final hr = samples.map((s) => s.heartRate).whereType<int>().where((h) => h > 0);
    final cad = samples.map((s) => s.cadence).whereType<int>().where((c) => c > 0);
    final watts = [for (final s in samples) s.power];
    return RideSummary(
      start: samples.first.time,
      duration: samples.last.time.difference(samples.first.time),
      distance: distance,
      fitPath: fitPath,
      avgPower: avg(power),
      maxPower: max(power),
      avgHeartRate: avg(hr),
      maxHeartRate: max(hr),
      avgCadence: avg(cad),
      bests: stats.bestEfforts(watts),
      normalizedPower: stats.normalizedPower(watts),
      ftp: ftp,
    );
  }

  Map<String, Object?> toJson() => {
    'start': start.toIso8601String(),
    'seconds': duration.inSeconds,
    'distance': distance,
    'avgPower': avgPower,
    'maxPower': maxPower,
    'avgHeartRate': avgHeartRate,
    'maxHeartRate': maxHeartRate,
    'avgCadence': avgCadence,
    if (bests.isNotEmpty) 'bests': {for (final e in bests.entries) '${e.key}': e.value},
    'np': ?normalizedPower,
    'ftp': ?ftp,
  };

  static RideSummary? fromJson(Map<String, Object?> j, String fitPath) {
    final start = DateTime.tryParse('${j['start']}');
    if (start == null) return null;
    int? i(String k) => (j[k] as num?)?.round();
    return RideSummary(
      start: start,
      duration: Duration(seconds: i('seconds') ?? 0),
      distance: (j['distance'] as num?)?.toDouble() ?? 0,
      fitPath: fitPath,
      avgPower: i('avgPower'),
      maxPower: i('maxPower'),
      avgHeartRate: i('avgHeartRate'),
      maxHeartRate: i('maxHeartRate'),
      avgCadence: i('avgCadence'),
      bests: {
        if (j['bests'] case final Map<String, Object?> m)
          for (final e in m.entries)
            if (int.tryParse(e.key) != null && e.value is num) int.parse(e.key): (e.value as num).round(),
      },
      normalizedPower: i('np'),
      ftp: i('ftp'),
    );
  }
}

class RideHistory {
  final Directory dir;
  const RideHistory(this.dir);

  static String summaryPath(String fitPath) => fitPath.replaceFirst(RegExp(r'\.fit$'), '.json');

  Future<void> save(RideSummary s) => File(summaryPath(s.fitPath)).writeAsString(jsonEncode(s.toJson()));

  /// Les sorties, la plus récente d'abord. Un .fit sans résumé (versions avant 2.4) garde sa date de fichier.
  Future<List<RideSummary>> list() async {
    if (!await dir.exists()) return [];
    final out = <RideSummary>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.fit')) continue;
      final js = File(summaryPath(f.path));
      RideSummary? s;
      if (await js.exists()) {
        try {
          s = RideSummary.fromJson((jsonDecode(await js.readAsString()) as Map).cast<String, Object?>(), f.path);
        } catch (_) {}
      }
      s ??= RideSummary(start: (await f.stat()).modified, duration: Duration.zero, distance: 0, fitPath: f.path);
      out.add(s);
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  /// Calcule les statistiques de puissance des sorties qui n'en ont pas (lues dans
  /// leur .fit) et les garde dans leur résumé. [ftp] sert aux sorties sans FTP notée.
  Future<List<RideSummary>> withStats(List<RideSummary> rides, int ftp) async {
    final out = <RideSummary>[];
    for (final r in rides) {
      var s = r;
      if (!r.hasStats || r.ftp == null) {
        try {
          final f = File(r.fitPath);
          if (await f.exists()) {
            s = r.withStats(stats.readFitPower(await f.readAsBytes()), ftp);
            if (s.duration > Duration.zero) await save(s);
          }
        } catch (_) {}
      }
      out.add(s);
    }
    return out;
  }

  Future<void> delete(RideSummary s) async {
    for (final p in [s.fitPath, summaryPath(s.fitPath)]) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
  }
}
