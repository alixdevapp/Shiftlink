// Statistiques de puissance : meilleurs efforts, puissance normalisée, charge (TSS)
// et forme / fatigue au fil des semaines (modèle « Performance Management »).
import 'dart:math' as math;
import 'dart:typed_data';

/// Durées des meilleurs efforts, en secondes.
const bestEffortDurations = [5, 60, 300, 1200];

/// Meilleure puissance moyenne sur chaque durée (W). Une seconde sans mesure compte 0.
Map<int, int> bestEfforts(List<int?> watts, {List<int> durations = bestEffortDurations}) {
  final out = <int, int>{};
  final n = watts.length;
  if (n == 0) return out;
  // Sommes cumulées : moyenne d'une fenêtre en O(1).
  final sum = List<int>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    sum[i + 1] = sum[i] + (watts[i] ?? 0).clamp(0, 3000);
  }
  for (final d in durations) {
    if (d > n) continue;
    var best = 0;
    for (var i = d; i <= n; i++) {
      final s = sum[i] - sum[i - d];
      if (s > best) best = s;
    }
    out[d] = (best / d).round();
  }
  return out;
}

/// Puissance normalisée : moyenne glissante sur 30 s, puissance 4, moyenne, racine 4.
int? normalizedPower(List<int?> watts) {
  if (watts.length < 30) return null;
  var window = 0.0;
  var acc = 0.0;
  var count = 0;
  for (var i = 0; i < watts.length; i++) {
    window += watts[i] ?? 0;
    if (i >= 30) window -= watts[i - 30] ?? 0;
    if (i >= 29) {
      acc += math.pow(window / 30, 4);
      count++;
    }
  }
  return math.pow(acc / count, 0.25).round();
}

/// Charge d'entraînement (TSS) : 100 = une heure à la FTP.
double? trainingLoad({required int seconds, required int? np, required int ftp}) {
  if (np == null || ftp <= 0 || seconds <= 0) return null;
  final intensity = np / ftp;
  return seconds * np * intensity / (ftp * 3600) * 100;
}

/// Un jour de la courbe de forme.
class FitnessDay {
  final DateTime day;

  /// Forme (CTL, moyenne sur 42 jours), fatigue (ATL, 7 jours), fraîcheur (TSB = forme − fatigue).
  final double fitness;
  final double fatigue;
  double get freshness => fitness - fatigue;
  final double load;
  const FitnessDay(this.day, this.fitness, this.fatigue, this.load);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Forme et fatigue jour après jour, de la première sortie jusqu'à [until].
List<FitnessDay> fitnessCurve(Map<DateTime, double> loads, {DateTime? until}) {
  if (loads.isEmpty) return const [];
  final byDay = <DateTime, double>{};
  for (final e in loads.entries) {
    final d = _day(e.key);
    byDay[d] = (byDay[d] ?? 0) + e.value;
  }
  final days = byDay.keys.toList()..sort();
  final end = _day(until ?? DateTime.now());
  var ctl = 0.0, atl = 0.0;
  final out = <FitnessDay>[];
  for (var d = days.first; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final load = byDay[d] ?? 0;
    ctl += (load - ctl) / 42;
    atl += (load - atl) / 7;
    out.add(FitnessDay(d, ctl, atl, load));
  }
  return out;
}

/// Lit la puissance seconde par seconde d'un fichier .fit (messages « record »).
/// Suffit pour les fichiers écrits par ShiftLink et la plupart des autres. Renvoie
/// une liste vide si le fichier n'est pas lisible.
List<int?> readFitPower(Uint8List b) {
  if (b.length < 14) return const [];
  final headerSize = b[0];
  if (headerSize < 12 || b.length < headerSize) return const [];
  final dataSize = ByteData.sublistView(b, 4, 8).getUint32(0, Endian.little);
  final end = math.min(b.length, headerSize + dataSize);
  final defs = <int, ({int global, bool big, List<(int, int)> fields, int devBytes})>{};
  final out = <int?>[];
  var p = headerSize;
  try {
    while (p < end) {
      final h = b[p++];
      if (h & 0x80 != 0) {
        // En-tête compressé (horodatage) : données d'un type local déjà défini.
        final def = defs[(h >> 5) & 0x3];
        if (def == null) return out;
        p = _readData(b, p, def, out);
        continue;
      }
      final local = h & 0x0F;
      if (h & 0x40 != 0) {
        final big = b[p + 1] == 1;
        final global = big ? (b[p + 2] << 8) | b[p + 3] : b[p + 2] | (b[p + 3] << 8);
        final n = b[p + 4];
        p += 5;
        final fields = <(int, int)>[];
        for (var i = 0; i < n; i++) {
          fields.add((b[p], b[p + 1]));
          p += 3;
        }
        var dev = 0;
        if (h & 0x20 != 0) {
          final nd = b[p++];
          for (var i = 0; i < nd; i++) {
            dev += b[p + 1];
            p += 3;
          }
        }
        defs[local] = (global: global, big: big, fields: fields, devBytes: dev);
      } else {
        final def = defs[local];
        if (def == null) return out;
        p = _readData(b, p, def, out);
      }
    }
  } on RangeError {
    return out;
  }
  return out;
}

int _readData(Uint8List b, int p, ({int global, bool big, List<(int, int)> fields, int devBytes}) def, List<int?> out) {
  int? power;
  for (final (num, size) in def.fields) {
    if (def.global == 20 && num == 7 && size == 2) {
      final v = def.big ? (b[p] << 8) | b[p + 1] : b[p] | (b[p + 1] << 8);
      power = v == 0xFFFF ? null : v;
    }
    p += size;
  }
  if (def.global == 20) out.add(power);
  return p + def.devBytes;
}
