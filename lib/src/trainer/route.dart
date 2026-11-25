// Parcours GPX : une trace de points (latitude, longitude, altitude) devient une suite de
// pentes le long du parcours. ShiftLink avance « sur la trace » à la vitesse du trainer et
// envoie la pente du moment, comme le ferait une appli de simulation.
import 'dart:math' as math;

import '../i18n.dart';

/// Un point du parcours : distance depuis le départ (m), altitude (m), position GPS.
class RoutePoint {
  final double distance;
  final double elevation;
  final double? lat;
  final double? lon;
  const RoutePoint(this.distance, this.elevation, {this.lat, this.lon});
}

class GpxRoute {
  final String name;
  final List<RoutePoint> points;

  const GpxRoute(this.name, this.points);

  double get length => points.isEmpty ? 0 : points.last.distance;

  /// Dénivelé positif total (m).
  double get climbing {
    var g = 0.0;
    for (var i = 1; i < points.length; i++) {
      final d = points[i].elevation - points[i - 1].elevation;
      if (d > 0) g += d;
    }
    return g;
  }

  /// Pente moyenne (%) autour de [distanceM], lissée sur [windowM] mètres pour éviter le bruit.
  double gradeAt(double distanceM, {double windowM = 50}) {
    if (points.length < 2) return 0;
    final d = distanceM.clamp(0.0, length);
    final before = _interp(d - windowM / 2);
    final after = _interp(d + windowM / 2);
    final dd = after.$1 - before.$1;
    if (dd <= 0.1) return 0;
    return (((after.$2 - before.$2) / dd) * 100).clamp(-25.0, 25.0);
  }

  /// Altitude à la distance donnée (interpolée).
  double elevationAt(double distanceM) => _interp(distanceM.clamp(0.0, length)).$2;

  /// Première montée notable (pente moyenne ≥ 3%) qui démarre après [fromM], dans les [lookAheadM] mètres.
  /// Renvoie (distance jusqu'au pied, longueur de la montée, pente moyenne %) ou null.
  (double, double, double)? nextClimb(double fromM, {double lookAheadM = 1500, double minGrade = 3}) {
    if (points.length < 3) return null;
    final end = (fromM + lookAheadM).clamp(0.0, length);
    double? climbStart;
    double startEl = elevationAt(fromM);
    const step = 50.0;
    for (var d = fromM; d <= end; d += step) {
      final g = gradeAt(d);
      if (g >= minGrade) {
        climbStart ??= d;
      } else if (climbStart != null) {
        final len = d - climbStart;
        final avg = (elevationAt(d) - startEl) / len * 100;
        if (len >= 100 && avg >= minGrade) return (climbStart - fromM, len, avg);
        climbStart = null;
        startEl = elevationAt(d);
      }
      if (climbStart == null) startEl = elevationAt(d + step);
    }
    if (climbStart != null) {
      final len = end - climbStart;
      final avg = (elevationAt(end) - startEl) / len * 100;
      if (len >= 100 && avg >= minGrade) return (climbStart - fromM, len, avg);
    }
    return null;
  }

  (double, double) _interp(double d) {
    if (d <= points.first.distance) return (points.first.distance, points.first.elevation);
    if (d >= points.last.distance) return (points.last.distance, points.last.elevation);
    var lo = 0, hi = points.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) ~/ 2;
      if (points[m].distance <= d) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final a = points[lo], b = points[hi];
    final t = (d - a.distance) / (b.distance - a.distance);
    return (d, a.elevation + (b.elevation - a.elevation) * t);
  }

  Map<String, Object> toJson() => {
    'name': name,
    'points': [
      for (final p in points)
        if (p.lat != null && p.lon != null)
          [p.distance.round(), p.elevation, p.lat, p.lon]
        else
          [p.distance.round(), p.elevation],
    ],
  };

  static GpxRoute? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String || j['points'] is! List) return null;
    final pts = <RoutePoint>[];
    for (final e in (j['points'] as List).take(20000)) {
      if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
        final lat = e.length >= 4 && e[2] is num ? (e[2] as num).toDouble() : null;
        final lon = e.length >= 4 && e[3] is num ? (e[3] as num).toDouble() : null;
        pts.add(RoutePoint((e[0] as num).toDouble(), (e[1] as num).toDouble(), lat: lat, lon: lon));
      }
    }
    return pts.length < 2 ? null : GpxRoute(j['name'] as String, pts);
  }

  /// true si tous les points gardent leur position GPS (trace affichable sur une carte).
  bool get hasTrace => points.length > 1 && points.first.lat != null;

  /// Position GPS à la distance donnée (interpolée), ou null.
  (double, double)? latLonAt(double distanceM) {
    if (!hasTrace) return null;
    final d = distanceM.clamp(0.0, length);
    var lo = 0, hi = points.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) ~/ 2;
      if (points[m].distance <= d) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final a = points[lo], b = points[hi];
    if (a.lat == null || b.lat == null) return null;
    final t = b.distance == a.distance ? 0.0 : (d - a.distance) / (b.distance - a.distance);
    return (a.lat! + (b.lat! - a.lat!) * t, a.lon! + (b.lon! - a.lon!) * t);
  }

  static const _r = 6371000.0;

  /// Taille maximale d'un fichier GPX accepté.
  static const maxFileBytes = 4 * 1024 * 1024;

  /// Lit un fichier GPX. Renvoie null s'il ne contient pas de trace exploitable.
  /// Les points sont ré-échantillonnés tous les ~25 m, pour tenir dans les préférences.
  static GpxRoute? parseGpx(String xml, {String fallbackName = 'Parcours'}) {
    if (xml.length > maxFileBytes) return null;
    if (!xml.contains('<trk') && !xml.contains('<rte')) return null;
    final nameM = RegExp(r'<name>([\s\S]*?)</name>', caseSensitive: false).firstMatch(xml);
    final pt = RegExp(
      r'''<(?:trkpt|rtept)\s+[^>]*lat\s*=\s*["']([^"']+)["'][^>]*lon\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</(?:trkpt|rtept)>''',
      caseSensitive: false,
    );
    final ele = RegExp(r'<ele>([\d.\-+eE]+)</ele>', caseSensitive: false);
    final raw = <(double, double, double)>[];
    for (final m in pt.allMatches(xml)) {
      final lat = double.tryParse(m[1]!);
      final lon = double.tryParse(m[2]!);
      if (lat == null || lon == null) continue;
      final em = ele.firstMatch(m[3]!);
      final el = em == null ? 0.0 : (double.tryParse(em[1]!) ?? 0);
      raw.add((lat, lon, el));
      if (raw.length > 40000) break;
    }
    if (raw.length < 2) return null;
    final pts = <RoutePoint>[];
    var dist = 0.0;
    var lastKept = 0;
    pts.add(RoutePoint(0, raw.first.$3, lat: raw.first.$1, lon: raw.first.$2));
    for (var i = 1; i < raw.length; i++) {
      dist += _haversine(raw[i - 1], raw[i]);
      if (dist - (pts.isEmpty ? 0 : pts.last.distance) >= 25 || i == raw.length - 1) {
        pts.add(RoutePoint(dist, raw[i].$3, lat: raw[i].$1, lon: raw[i].$2));
        lastKept = i;
      }
    }
    if (lastKept != raw.length - 1) {
      pts.add(RoutePoint(dist, raw.last.$3, lat: raw.last.$1, lon: raw.last.$2));
    }
    var name = nameM?[1]?.trim() ?? '';
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) name = fallbackName;
    return GpxRoute(name.length > 60 ? name.substring(0, 60) : name, pts);
  }

  static double _haversine((double, double, double) a, (double, double, double) b) {
    final la1 = a.$1 * math.pi / 180, la2 = b.$1 * math.pi / 180;
    final dla = (b.$1 - a.$1) * math.pi / 180, dlo = (b.$2 - a.$2) * math.pi / 180;
    final x =
        math.sin(dla / 2) * math.sin(dla / 2) + math.cos(la1) * math.cos(la2) * math.sin(dlo / 2) * math.sin(dlo / 2);
    return 2 * _r * math.asin(math.sqrt(x));
  }

  String get title => name;
  String get subtitle =>
      tr('{0} km · {1} m de D+', [(length / 1000).toStringAsFixed(1).replaceAll('.', ','), climbing.round()]);
}

/// État d'un parcours en cours.
class RouteRun {
  final GpxRoute route;
  final double distance;
  final double grade;

  /// Écart en secondes par rapport au fantôme (sortie précédente sur ce parcours).
  /// Positif : tu es en retard. Négatif : tu es en avance. null : pas de fantôme.
  final int? ghostGap;
  const RouteRun(this.route, this.distance, this.grade, {this.ghostGap});

  double get progress => route.length == 0 ? 1 : (distance / route.length).clamp(0.0, 1.0);
  double get remaining => (route.length - distance).clamp(0, route.length);
}

/// Fantôme d'un parcours : paires (seconde depuis le départ, distance en m) pour comparer en temps réel.
class GhostRun {
  final List<(int, double)> samples;
  const GhostRun(this.samples);

  int get seconds => samples.isEmpty ? 0 : samples.last.$1;

  /// Secondes qu'il a mis pour atteindre [distanceM]. null si le fantôme n'y est pas (encore) allé.
  int? timeAt(double distanceM) {
    if (samples.length < 2 || distanceM <= 0) return 0;
    if (distanceM > samples.last.$2) return null;
    var lo = 0, hi = samples.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) ~/ 2;
      if (samples[m].$2 <= distanceM) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final a = samples[lo], b = samples[hi];
    if (b.$2 <= a.$2) return a.$1;
    final t = (distanceM - a.$2) / (b.$2 - a.$2);
    return (a.$1 + (b.$1 - a.$1) * t).round();
  }

  Map<String, Object> toJson() => {
    'samples': [
      for (final s in samples) [s.$1, s.$2.round()],
    ],
  };

  static GhostRun? fromJson(Object? j) {
    if (j is! Map || j['samples'] is! List) return null;
    final out = <(int, double)>[];
    for (final e in (j['samples'] as List).take(20000)) {
      if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
        out.add(((e[0] as num).round(), (e[1] as num).toDouble()));
      }
    }
    return out.length < 2 ? null : GhostRun(out);
  }
}
