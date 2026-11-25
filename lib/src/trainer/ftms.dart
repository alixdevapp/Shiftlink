// Fitness Machine Service (FTMS), norme Bluetooth publique des home trainers.
import 'dart:typed_data';

import '../i18n.dart';

class Ftms {
  static const service = 0x1826;
  static const feature = 0x2ACC;
  static const indoorBikeData = 0x2AD2;
  static const trainingStatus = 0x2AD3;
  static const supportedResistance = 0x2AD6;
  static const supportedPower = 0x2AD8;
  static const controlPoint = 0x2AD9;
  static const machineStatus = 0x2ADA;

  // Codes de commande du point de contrôle.
  static const opRequestControl = 0x00;
  static const opReset = 0x01;
  static const opSetTargetResistance = 0x04;
  static const opSetTargetPower = 0x05;
  static const opStartResume = 0x07;
  static const opStopPause = 0x08;
  static const opSetSimulation = 0x11;
  static const opSetWheelCircumference = 0x12;
  static const opSpinDown = 0x13;
  static const opResponse = 0x80;

  static const resultSuccess = 0x01;
  static const resultNotSupported = 0x02;

  /// UUID 128 bits d'un identifiant Bluetooth 16 bits.
  static String uuid128(int short) => '0000${short.toRadixString(16).padLeft(4, '0')}-0000-1000-8000-00805f9b34fb';

  static Uint8List requestControl() => Uint8List.fromList([opRequestControl]);

  static Uint8List startResume() => Uint8List.fromList([opStartResume]);

  /// Paramètres de simulation : pente en %, vent en m/s, Crr, Cw (kg/m).
  static Uint8List simulation({required double gradePercent, double wind = 0, double crr = 0.004, double cw = 0.51}) {
    final b = ByteData(7);
    b.setUint8(0, opSetSimulation);
    b.setInt16(1, (wind * 1000).round().clamp(-32768, 32767), Endian.little);
    b.setInt16(3, (gradePercent * 100).round().clamp(-32768, 32767), Endian.little);
    b.setUint8(5, (crr * 10000).round().clamp(0, 255));
    b.setUint8(6, (cw * 100).round().clamp(0, 255));
    return b.buffer.asUint8List();
  }

  /// Niveau de résistance, en unités de 0,1 (comme la plage annoncée par le trainer).
  static Uint8List targetResistance(int tenths) {
    final b = ByteData(3);
    b.setUint8(0, opSetTargetResistance);
    b.setInt16(1, tenths, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List targetPower(int watts) {
    final b = ByteData(3);
    b.setUint8(0, opSetTargetPower);
    b.setInt16(1, watts, Endian.little);
    return b.buffer.asUint8List();
  }

  /// Calibration (« spin down ») : démarrer, ou abandonner.
  static Uint8List spinDown({bool start = true}) => Uint8List.fromList([opSpinDown, start ? 0x01 : 0x02]);

  /// Code « état de la calibration » dans la caractéristique Machine Status.
  static const statusSpinDown = 0x14;

  static Uint8List response(int opcode, int result) => Uint8List.fromList([opResponse, opcode, result]);
}

/// Commande de simulation décodée (envoyée par l'appli au trainer émulé).
class SimulationParams {
  final double wind;
  final double gradePercent;
  final double crr;
  final double cw;
  const SimulationParams(this.wind, this.gradePercent, this.crr, this.cw);

  static SimulationParams? parse(Uint8List data) {
    if (data.isEmpty || data[0] != Ftms.opSetSimulation || data.length < 5) return null;
    final b = ByteData.sublistView(data);
    final wind = b.getInt16(1, Endian.little) / 1000;
    final grade = b.getInt16(3, Endian.little) / 100;
    final crr = data.length > 5 ? data[5] / 10000 : 0.004;
    final cw = data.length > 6 ? data[6] / 100 : 0.51;
    return SimulationParams(wind, grade, crr, cw);
  }
}

/// Valeurs utiles d'une trame « Indoor Bike Data ».
class BikeData {
  final double? speedKmh;
  final double? cadence;
  final int? power;
  final int? heartRate;
  const BikeData({this.speedKmh, this.cadence, this.power, this.heartRate});

  static BikeData parse(Uint8List data) {
    if (data.length < 2) return const BikeData();
    final b = ByteData.sublistView(data);
    final flags = b.getUint16(0, Endian.little);
    var i = 2;
    double? speed;
    double? cadence;
    int? power;
    int? heartRate;
    bool has(int bit) => flags & (1 << bit) != 0;
    int u16() {
      final v = b.getUint16(i, Endian.little);
      i += 2;
      return v;
    }

    try {
      // Bit 0 à 0 : vitesse instantanée présente.
      if (!has(0)) speed = u16() / 100;
      if (has(1)) i += 2; // vitesse moyenne
      if (has(2)) cadence = u16() / 2;
      if (has(3)) i += 2; // cadence moyenne
      if (has(4)) i += 3; // distance
      if (has(5)) i += 2; // résistance
      if (has(6)) {
        power = b.getInt16(i, Endian.little);
        i += 2;
      }
      if (has(7)) i += 2; // puissance moyenne
      if (has(8)) i += 5; // énergie
      if (has(9)) heartRate = b.getUint8(i);
    } on RangeError {
      // trame tronquée : on garde ce qu'on a
    }
    return BikeData(speedKmh: speed, cadence: cadence, power: power, heartRate: heartRate);
  }
}

/// Ajoute (ou remplace) la fréquence cardiaque dans une trame « Indoor Bike Data »,
/// pour que l'appli la reçoive avec le reste.
Uint8List withHeartRate(Uint8List data, int bpm) => withValues(data, heartRate: bpm);

/// Taille de chaque champ de « Indoor Bike Data », par bit des drapeaux.
const _bikeDataSizes = [2, 2, 2, 2, 3, 2, 2, 2, 5, 1, 1, 2, 2];

/// Remplace (ou ajoute) cadence, puissance ou cardio dans une trame « Indoor Bike Data »,
/// en gardant les autres champs. Une trame tronquée est rendue telle quelle.
Uint8List withValues(Uint8List data, {double? cadence, int? power, int? heartRate}) {
  if (data.length < 2 || (cadence == null && power == null && heartRate == null)) return data;
  final flags = data[0] | (data[1] << 8);
  bool present(int bit) => bit == 0 ? flags & 1 == 0 : flags & (1 << bit) != 0;
  final fields = <int, List<int>>{};
  var i = 2;
  for (var bit = 0; bit < _bikeDataSizes.length; bit++) {
    if (!present(bit)) continue;
    final n = _bikeDataSizes[bit];
    if (i + n > data.length) return data;
    fields[bit] = data.sublist(i, i + n);
    i += n;
  }
  List<int> u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  if (cadence != null) fields[2] = u16((cadence * 2).round().clamp(0, 0xFFFF));
  if (power != null) fields[6] = u16(power.clamp(-32768, 32767) & 0xFFFF);
  if (heartRate != null) fields[9] = [heartRate.clamp(0, 255)];
  var f = flags & ~0x1FFF;
  final out = <int>[];
  for (var bit = 0; bit < _bikeDataSizes.length; bit++) {
    final v = fields[bit];
    if (bit == 0) {
      if (v == null) f |= 1;
    } else if (v != null) {
      f |= 1 << bit;
    }
    if (v != null) out.addAll(v);
  }
  return Uint8List.fromList([f & 0xFF, (f >> 8) & 0xFF, ...out, ...data.sublist(i)]);
}

/// Ce que le trainer sait faire (caractéristiques « Feature » et plages).
class TrainerCaps {
  final bool simulation;
  final bool power;
  final bool resistance;

  /// Plage de résistance, en dixièmes.
  final int minResistance;
  final int maxResistance;

  /// Le trainer sait se calibrer (« spin down ») sur demande.
  final bool spinDown;

  const TrainerCaps({
    this.spinDown = false,
    this.simulation = true,
    this.power = true,
    this.resistance = true,
    this.minResistance = 0,
    this.maxResistance = 1000,
  });

  /// Lit la caractéristique Feature (8 octets) et, si présente, la plage de résistance.
  static TrainerCaps parse(List<int>? feature, List<int>? resistanceRange) {
    var sim = true, pow = true, res = true, spin = false;
    if (feature != null && feature.length >= 8) {
      final t = ByteData.sublistView(Uint8List.fromList(feature)).getUint32(4, Endian.little);
      res = t & (1 << 2) != 0;
      pow = t & (1 << 3) != 0;
      sim = t & (1 << 13) != 0;
      spin = t & (1 << 15) != 0;
    }
    var lo = 0, hi = 1000;
    if (resistanceRange != null && resistanceRange.length >= 4) {
      final b = ByteData.sublistView(Uint8List.fromList(resistanceRange));
      lo = b.getInt16(0, Endian.little);
      hi = b.getInt16(2, Endian.little);
      if (hi <= lo) hi = lo + 1000;
    }
    return TrainerCaps(
      simulation: sim,
      power: pow,
      resistance: res,
      minResistance: lo,
      maxResistance: hi,
      spinDown: spin,
    );
  }

  /// Mode choisi automatiquement : pente, sinon puissance, sinon résistance.
  String get bestControl => simulation ? 'grade' : (power ? 'power' : 'resistance');

  String describe() =>
      [if (simulation) tr('pente'), if (power) tr('puissance'), if (resistance) tr('résistance')].join(', ');
}

/// Étapes d'une calibration (« spin down »).
enum SpinDownPhase {
  /// Demande envoyée, on attend la réponse du trainer.
  starting,

  /// Accélère jusqu'à la vitesse demandée.
  speedUp,

  /// Arrête de pédaler et laisse la roue ralentir.
  coast,
  success,
  failed,

  /// Le trainer a refusé la commande.
  refused,
}

class SpinDownState {
  final SpinDownPhase phase;

  /// Vitesse à dépasser avant de lâcher (km/h), si le trainer la donne.
  final double? targetKmh;
  const SpinDownState(this.phase, [this.targetKmh]);

  bool get finished =>
      phase == SpinDownPhase.success || phase == SpinDownPhase.failed || phase == SpinDownPhase.refused;

  /// Réponse du point de contrôle à la commande de calibration.
  /// Renvoie null si la trame ne concerne pas la calibration.
  static SpinDownState? fromResponse(List<int> v) {
    if (v.length < 3 || v[0] != Ftms.opResponse || v[1] != Ftms.opSpinDown) return null;
    if (v[2] != Ftms.resultSuccess) return const SpinDownState(SpinDownPhase.refused);
    // Vitesse basse puis haute, en 0,01 km/h. On vise la haute.
    double? target;
    if (v.length >= 7) {
      final hi = (v[5] | (v[6] << 8)) / 100;
      if (hi > 0) target = hi;
    }
    return SpinDownState(SpinDownPhase.speedUp, target);
  }

  /// État annoncé par la caractéristique Machine Status. [current] garde la vitesse cible.
  static SpinDownState? fromStatus(List<int> v, SpinDownState? current) {
    if (v.length < 2 || v[0] != Ftms.statusSpinDown) return null;
    return switch (v[1]) {
      0x01 => SpinDownState(SpinDownPhase.speedUp, current?.targetKmh),
      0x02 => const SpinDownState(SpinDownPhase.success),
      0x03 => const SpinDownState(SpinDownPhase.failed),
      0x04 => SpinDownState(SpinDownPhase.coast, current?.targetKmh),
      _ => null,
    };
  }
}
