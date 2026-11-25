// Écriture d'un fichier .fit (format public de Garmin) pour une sortie sur
// home trainer : lisible par Strava, Garmin Connect, intervals.icu…
import 'dart:typed_data';

/// Un point par seconde.
class RideSample {
  final DateTime time;
  final int? power;
  final int? cadence;
  final int? heartRate;

  /// Vitesse en m/s.
  final double? speed;

  /// Distance cumulée en mètres.
  final double distance;

  /// Position et altitude (m) sur un parcours GPX. null hors parcours.
  final double? lat;
  final double? lon;
  final double? altitude;

  const RideSample({
    required this.time,
    this.power,
    this.cadence,
    this.heartRate,
    this.speed,
    required this.distance,
    this.lat,
    this.lon,
    this.altitude,
  });
}

class FitWriter {
  static final _epoch = DateTime.utc(1989, 12, 31);

  static int fitTime(DateTime t) => t.toUtc().difference(_epoch).inSeconds;

  // Types de base FIT.
  static const _enum = 0x00, _u8 = 0x02, _u16 = 0x84, _s32 = 0x85, _u32 = 0x86, _u32z = 0x8C;

  final _body = BytesBuilder();

  void _define(int local, int global, List<(int, int, int)> fields) {
    _body.addByte(0x40 | local);
    _body.add([0, 0]); // réservé, petit-boutiste
    _body.add(_le(global, 2));
    _body.addByte(fields.length);
    for (final (num, size, type) in fields) {
      _body.add([num, size, type]);
    }
  }

  void _data(int local, List<(int, int)> values) {
    _body.addByte(local);
    for (final (v, size) in values) {
      _body.add(_le(v, size));
    }
  }

  static List<int> _le(int v, int size) => [for (var i = 0; i < size; i++) (v >> (8 * i)) & 0xFF];

  static int _u8or(int? v) => v == null ? 0xFF : v.clamp(0, 254);
  static int _u16or(int? v) => v == null ? 0xFFFF : v.clamp(0, 65534);

  /// Degrés vers « demi-cercles » FIT (entier signé 32 bits).
  static int _semicircles(double? deg) => deg == null ? 0x7FFFFFFF : (deg * (2147483648 / 180)).round();

  /// Altitude FIT : (m + 500) × 5.
  static int _alt(double? m) => m == null ? 0xFFFF : ((m + 500) * 5).round().clamp(0, 65534);

  /// Dénivelé positif (m) entre les points [from] et [to] (inclus). Les trous (hors parcours) sont sautés.
  static int ascent(List<RideSample> samples, [int from = 0, int? to]) {
    var gain = 0.0;
    double? last;
    final end = to ?? samples.length - 1;
    for (var i = from; i <= end; i++) {
      final a = samples[i].altitude;
      if (a == null) {
        last = null;
        continue;
      }
      if (last != null && a > last) gain += a - last;
      last = a;
    }
    return gain.round();
  }

  /// Fichier complet : en-tête, points, tours, séance, activité, CRC.
  /// [laps] : index des points où commence un nouveau tour (un tour par bloc de séance).
  /// Sans [laps], la sortie fait un seul tour.
  /// Quand des points ont une position GPS (parcours), la carte et l'altitude sont écrites
  /// et la sortie est marquée « virtuelle » pour que Strava garde le tracé et le dénivelé.
  static Uint8List encode(List<RideSample> samples, {List<int> laps = const []}) {
    if (samples.isEmpty) throw ArgumentError('Sortie vide');
    final w = FitWriter();
    final start = samples.first.time;
    final end = samples.last.time;
    final elapsedMs = end.difference(start).inMilliseconds;
    final distance = samples.last.distance;
    int? avg(Iterable<int> l) => l.isEmpty ? null : (l.reduce((a, b) => a + b) / l.length).round();
    int? max(Iterable<int> l) => l.isEmpty ? null : l.reduce((a, b) => a > b ? a : b);
    List<int> powersOf(Iterable<RideSample> l) => l.map((s) => s.power).nonNulls.toList();
    List<int> hrsOf(Iterable<RideSample> l) => l.map((s) => s.heartRate).nonNulls.toList();
    List<int> cadsOf(Iterable<RideSample> l) => l.map((s) => s.cadence).nonNulls.where((c) => c > 0).toList();
    final powers = powersOf(samples), hrs = hrsOf(samples), cads = cadsOf(samples);
    final hasGps = samples.any((s) => s.lat != null && s.lon != null);
    final hasAlt = samples.any((s) => s.altitude != null);
    final geo = hasGps || hasAlt;

    // file_id
    w._define(0, 0, [(0, 1, _enum), (1, 2, _u16), (2, 2, _u16), (3, 4, _u32z), (4, 4, _u32)]);
    w._data(0, [(4, 1), (255, 2), (0, 2), (1, 4), (fitTime(start), 4)]);

    // record
    w._define(1, 20, [
      (253, 4, _u32),
      if (geo) ...[(0, 4, _s32), (1, 4, _s32), (2, 2, _u16)],
      (3, 1, _u8),
      (4, 1, _u8),
      (5, 4, _u32),
      (6, 2, _u16),
      (7, 2, _u16),
    ]);
    for (final s in samples) {
      final pos = s.lat != null && s.lon != null;
      w._data(1, [
        (fitTime(s.time), 4),
        if (geo) ...[
          (_semicircles(pos ? s.lat : null), 4),
          (_semicircles(pos ? s.lon : null), 4),
          (_alt(s.altitude), 2),
        ],
        (_u8or(s.heartRate), 1),
        (_u8or(s.cadence), 1),
        ((s.distance * 100).round(), 4),
        (s.speed == null ? 0xFFFF : _u16or((s.speed! * 1000).round()), 2),
        (_u16or(s.power), 2),
      ]);
    }

    final t = fitTime(end);
    // Tours : débuts triés, sans doublon, toujours un tour qui part du premier point.
    final starts = <int>{0, ...laps.where((i) => i > 0 && i < samples.length)}.toList()..sort();
    w._define(2, 19, [
      (254, 2, _u16),
      (253, 4, _u32),
      (2, 4, _u32),
      (7, 4, _u32),
      (8, 4, _u32),
      (9, 4, _u32),
      (0, 1, _enum),
      (1, 1, _enum),
      (19, 2, _u16),
      (20, 2, _u16),
      (15, 1, _u8),
      (16, 1, _u8),
      (17, 1, _u8),
      (21, 2, _u16),
    ]);
    for (var n = 0; n < starts.length; n++) {
      final from = starts[n];
      // Le tour va jusqu'au premier point du suivant (ou jusqu'au dernier point de la sortie).
      final to = n + 1 < starts.length ? starts[n + 1] : samples.length - 1;
      final part = samples.sublist(from, n + 1 < starts.length ? to : to + 1);
      final ms = samples[to].time.difference(samples[from].time).inMilliseconds;
      final lp = powersOf(part), lh = hrsOf(part);
      w._data(2, [
        (n, 2),
        (fitTime(samples[to].time), 4),
        (fitTime(samples[from].time), 4),
        (ms, 4),
        (ms, 4),
        (((samples[to].distance - samples[from].distance) * 100).round(), 4),
        (9, 1),
        (n + 1 < starts.length ? 0 : 1, 1), // 0 = tour manuel, 1 = fin de la sortie
        (_u16or(avg(lp)), 2),
        (_u16or(max(lp)), 2),
        (_u8or(avg(lh)), 1),
        (_u8or(max(lh)), 1),
        (_u8or(avg(cadsOf(part))), 1),
        (hasAlt ? _u16or(ascent(samples, from, to)) : 0xFFFF, 2),
      ]);
    }

    // session
    w._define(3, 18, [
      (253, 4, _u32),
      (2, 4, _u32),
      (7, 4, _u32),
      (8, 4, _u32),
      (9, 4, _u32),
      (5, 1, _enum),
      (6, 1, _enum),
      (0, 1, _enum),
      (1, 1, _enum),
      (20, 2, _u16),
      (21, 2, _u16),
      (16, 1, _u8),
      (17, 1, _u8),
      (18, 1, _u8),
      (25, 2, _u16),
      (26, 2, _u16),
      (22, 2, _u16),
    ]);
    w._data(3, [
      (t, 4),
      (fitTime(start), 4),
      (elapsedMs, 4),
      (elapsedMs, 4),
      ((distance * 100).round(), 4),
      (2, 1), // vélo
      (hasGps ? 58 : 6, 1), // sortie virtuelle (avec carte) ou home trainer
      (8, 1),
      (1, 1),
      (_u16or(avg(powers)), 2),
      (_u16or(max(powers)), 2),
      (_u8or(avg(hrs)), 1),
      (_u8or(max(hrs)), 1),
      (_u8or(avg(cads)), 1),
      (0, 2),
      (starts.length, 2),
      (hasAlt ? _u16or(ascent(samples)) : 0xFFFF, 2),
    ]);

    // activity
    w._define(4, 34, [(253, 4, _u32), (0, 4, _u32), (1, 2, _u16), (2, 1, _enum), (3, 1, _enum), (4, 1, _enum)]);
    w._data(4, [(t, 4), (elapsedMs, 4), (1, 2), (0, 1), (26, 1), (1, 1)]);

    final body = w._body.takeBytes();
    final header = BytesBuilder()
      ..addByte(14)
      ..addByte(0x20)
      ..add(_le(2132, 2))
      ..add(_le(body.length, 4))
      ..add('.FIT'.codeUnits);
    final h = header.takeBytes();
    final out = BytesBuilder()
      ..add(h)
      ..add(_le(crc(h), 2))
      ..add(body);
    final all = out.takeBytes();
    return Uint8List.fromList([...all, ..._le(crc(all), 2)]);
  }

  static const _table = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];

  /// CRC du format FIT.
  static int crc(List<int> bytes) {
    var c = 0;
    for (final b in bytes) {
      var tmp = _table[c & 0xF];
      c = (c >> 4) & 0x0FFF;
      c = c ^ tmp ^ _table[b & 0xF];
      tmp = _table[c & 0xF];
      c = (c >> 4) & 0x0FFF;
      c = c ^ tmp ^ _table[(b >> 4) & 0xF];
    }
    return c;
  }
}
