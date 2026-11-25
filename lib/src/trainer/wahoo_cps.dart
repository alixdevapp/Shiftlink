// Ancien protocole Wahoo : trainers d'avant FTMS (anciens KICKR, KICKR Snap,
// Saris / CycleOps Hammer et H2 sur ancien firmware…). Ils annoncent le service
// public « Cycling Power » (0x1818) et une caractéristique de commande Wahoo.
//
// Code écrit pour ShiftLink d'après la description publique de ce protocole
// (utilisée par plusieurs logiciels libres d'entraînement). Comme pour FE-C,
// le reste de ShiftLink parle FTMS : ce fichier traduit les commandes FTMS en
// commandes Wahoo, et les mesures de puissance en trames FTMS.
import 'dart:typed_data';

import 'fec.dart' show indoorBikeData;
import 'ftms.dart';

class WahooCps {
  static const service = '00001818-0000-1000-8000-00805f9b34fb';
  static const measurement = '00002a63-0000-1000-8000-00805f9b34fb';
  static const control = 'a026e005-0a7d-4ab3-97fa-f1500f9feb8b';

  static const opUnlock = 0x20;
  static const opResistance = 0x40;
  static const opErg = 0x42;
  static const opSim = 0x43;
  static const opGrade = 0x46;
  static const opWindSpeed = 0x47;

  /// Déverrouille la commande (à envoyer une fois après la connexion).
  static Uint8List unlock() => Uint8List.fromList([opUnlock, 0xEE, 0xFC]);

  static Uint8List _u16(int op, int v) {
    final x = v.clamp(0, 0xFFFF);
    return Uint8List.fromList([op, x & 0xFF, x >> 8]);
  }

  /// Puissance imposée (ERG).
  static Uint8List erg(int watts) => _u16(opErg, watts.clamp(0, 2000));

  /// Passe en simulation : poids total (kg), roulement, coefficient d'air (kg/m).
  static Uint8List simMode({double kg = 85, double crr = 0.004, double cw = 0.51}) {
    final w = (kg * 100).round().clamp(0, 0xFFFF);
    final c = (crr * 10000).round().clamp(0, 0xFFFF);
    final a = (cw * 1000).round().clamp(0, 0xFFFF);
    return Uint8List.fromList([opSim, w & 0xFF, w >> 8, c & 0xFF, c >> 8, a & 0xFF, a >> 8]);
  }

  /// Pente en % : codée sur 16 bits, 0x8000 = plat, de −100 % à +100 %.
  static Uint8List grade(double percent) =>
      _u16(opGrade, (((percent.clamp(-100.0, 100.0) / 100) + 1) * 32768).round());

  /// Vent de face en m/s.
  static Uint8List windSpeed(double ms) => _u16(opWindSpeed, ((ms.clamp(-32.0, 32.0) + 32.768) * 1000).round());

  /// Résistance de 0 à 1 (1 = la plus dure).
  static Uint8List resistance(double level) => _u16(opResistance, ((1 - level.clamp(0.0, 1.0)) * 16383).round());

  /// Traduit une commande FTMS du point de contrôle. Liste vide : rien à envoyer.
  static List<Uint8List> fromFtms(Uint8List cmd, {double kg = 85}) {
    if (cmd.isEmpty) return const [];
    final b = ByteData.sublistView(cmd);
    switch (cmd[0]) {
      case Ftms.opSetSimulation:
        final sim = SimulationParams.parse(cmd);
        if (sim == null) return const [];
        return [simMode(kg: kg, crr: sim.crr, cw: sim.cw), windSpeed(sim.wind), grade(sim.gradePercent)];
      case Ftms.opSetTargetPower when cmd.length >= 3:
        return [erg(b.getInt16(1, Endian.little))];
      case Ftms.opSetTargetResistance when cmd.length >= 2:
        final tenths = cmd.length >= 3 ? b.getInt16(1, Endian.little) : cmd[1];
        return [resistance(tenths / 1000)];
      default:
        return const [];
    }
  }
}

/// Lit les mesures « Cycling Power » et en fait des trames FTMS.
class CyclingPowerDecoder {
  int? power;
  double? cadence;
  double? speedKmh;

  /// Circonférence de roue utilisée pour la vitesse (m).
  final double wheelMeters;
  CyclingPowerDecoder({this.wheelMeters = 2.105});

  (int, int)? _lastCrank; // tours, temps (1/1024 s)
  (int, int)? _lastWheel; // tours, temps (1/2048 s)
  int _crankIdle = 0;
  int _wheelIdle = 0;

  /// Lit une mesure. Renvoie true si elle a été comprise.
  bool add(List<int> v) {
    if (v.length < 4) return false;
    final b = ByteData.sublistView(Uint8List.fromList(v));
    final flags = b.getUint16(0, Endian.little);
    power = b.getInt16(2, Endian.little).clamp(0, 4000);
    var i = 4;
    if (flags & 0x01 != 0) i += 1; // équilibre gauche / droite
    if (flags & 0x04 != 0) i += 2; // couple cumulé
    if (flags & 0x10 != 0) {
      if (i + 6 > v.length) return true;
      final revs = b.getUint32(i, Endian.little);
      final t = b.getUint16(i + 4, Endian.little);
      i += 6;
      final last = _lastWheel;
      if (last != null) {
        final dt = (t - last.$2) & 0xFFFF;
        final dr = (revs - last.$1) & 0xFFFFFFFF;
        if (dt > 0 && dr < 1000) {
          speedKmh = dr * wheelMeters / (dt / 2048) * 3.6;
          _wheelIdle = 0;
        } else if (dt == 0 && ++_wheelIdle >= 3) {
          speedKmh = 0;
        }
      }
      _lastWheel = (revs, t);
    }
    if (flags & 0x20 != 0) {
      if (i + 4 > v.length) return true;
      final revs = b.getUint16(i, Endian.little);
      final t = b.getUint16(i + 2, Endian.little);
      final last = _lastCrank;
      if (last != null) {
        final dt = (t - last.$2) & 0xFFFF;
        final dr = (revs - last.$1) & 0xFFFF;
        if (dt > 0 && dr < 20) {
          cadence = (dr * 60 / (dt / 1024)).clamp(0, 250).toDouble();
          _crankIdle = 0;
        } else if (dt == 0 && ++_crankIdle >= 3) {
          cadence = 0;
        }
      }
      _lastCrank = (revs, t);
    }
    return true;
  }

  Uint8List get bikeData => indoorBikeData(BikeData(speedKmh: speedKmh, cadence: cadence, power: power));
}
