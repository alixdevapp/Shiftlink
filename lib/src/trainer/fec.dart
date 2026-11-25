// ANT+ FE-C par Bluetooth : protocole public des home trainers qui ne parlent
// pas FTMS (anciens Tacx Flux, Neo, Vortex…). Les pages ANT+ de 8 octets sont
// enveloppées dans un message ANT [A4, longueur, 4E, canal, données…, somme].
//
// ShiftLink pilote toujours le trainer « en FTMS » : ce fichier traduit les
// commandes FTMS en pages FE-C, et les pages reçues en trame FTMS.
import 'dart:typed_data';

import 'ftms.dart';

class Fec {
  static const service = '6e40fec1-b5a3-f393-e0a9-e50e24dcca9e';
  static const notify = '6e40fec2-b5a3-f393-e0a9-e50e24dcca9e';
  static const write = '6e40fec3-b5a3-f393-e0a9-e50e24dcca9e';

  static const _sync = 0xA4;
  static const _ack = 0x4F;
  static const _channel = 0x05;

  static const pageGeneral = 0x10;
  static const pageTrainer = 0x19;
  static const pageBasicResistance = 0x30;
  static const pageTargetPower = 0x31;
  static const pageWind = 0x32;
  static const pageTrack = 0x33;

  /// Message ANT « données acquittées » portant une page de 8 octets.
  static Uint8List message(List<int> page) {
    assert(page.length == 8);
    final m = [_sync, 9, _ack, _channel, ...page];
    var cs = 0;
    for (final b in m) {
      cs ^= b;
    }
    return Uint8List.fromList([...m, cs]);
  }

  /// Pente (%) et coefficient de roulement.
  static Uint8List track(double gradePercent, double crr) {
    final g = ((gradePercent.clamp(-200.0, 200.0) + 200) * 100).round().clamp(0, 0xFFFF);
    final c = (crr / 0.00005).round().clamp(0, 255);
    return message([pageTrack, 0xFF, 0xFF, 0xFF, 0xFF, g & 0xFF, g >> 8, c]);
  }

  /// Air : coefficient (kg/m), vent de face (m/s), aspiration 100 %.
  static Uint8List wind(double cw, double windMs) {
    final k = (cw / 0.01).round().clamp(0, 255);
    final w = ((windMs * 3.6).round() + 127).clamp(0, 254);
    return message([pageWind, 0xFF, 0xFF, 0xFF, 0xFF, k, w, 100]);
  }

  static Uint8List targetPower(int watts) {
    final p = watts.clamp(0, 4000) * 4;
    return message([pageTargetPower, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, p & 0xFF, p >> 8]);
  }

  /// Résistance de 0 à 100 %.
  static Uint8List resistance(double percent) {
    final r = (percent.clamp(0.0, 100.0) * 2).round();
    return message([pageBasicResistance, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, r]);
  }

  /// Traduit une commande FTMS du point de contrôle. Liste vide : rien à envoyer.
  static List<Uint8List> fromFtms(Uint8List cmd) {
    if (cmd.isEmpty) return const [];
    final b = ByteData.sublistView(cmd);
    switch (cmd[0]) {
      case Ftms.opSetSimulation:
        final sim = SimulationParams.parse(cmd);
        if (sim == null) return const [];
        return [wind(sim.cw, sim.wind), track(sim.gradePercent, sim.crr)];
      case Ftms.opSetTargetPower when cmd.length >= 3:
        return [targetPower(b.getInt16(1, Endian.little))];
      case Ftms.opSetTargetResistance when cmd.length >= 2:
        // Plage annoncée : 0 à 1000 dixièmes, soit 0 à 100 %.
        final tenths = cmd.length >= 3 ? b.getInt16(1, Endian.little) : cmd[1];
        return [resistance(tenths / 10)];
      default:
        return const [];
    }
  }
}

/// Assemble les pages FE-C reçues en trames FTMS « Indoor Bike Data ».
class FecDecoder {
  double? speedKmh;
  double? cadence;
  int? power;
  int? heartRate;

  /// Lit une notification (un ou plusieurs messages ANT). Renvoie true si une valeur a changé.
  bool add(List<int> bytes) {
    var changed = false;
    var i = 0;
    while (i + 12 <= bytes.length) {
      if (bytes[i] != 0xA4) {
        i++;
        continue;
      }
      final len = bytes[i + 1];
      if (len < 9 || i + 4 + len > bytes.length) break;
      final page = bytes.sublist(i + 4, i + 12);
      changed |= _page(page);
      i += 4 + len;
    }
    return changed;
  }

  bool _page(List<int> p) {
    switch (p[0]) {
      case Fec.pageGeneral:
        final raw = p[4] | (p[5] << 8);
        if (raw != 0xFFFF) speedKmh = raw * 0.001 * 3.6;
        if (p[6] != 0xFF && p[6] != 0) heartRate = p[6];
        return true;
      case Fec.pageTrainer:
        if (p[2] != 0xFF) cadence = p[2].toDouble();
        final w = p[5] | ((p[6] & 0x0F) << 8);
        if (w != 0xFFF) power = w;
        return true;
    }
    return false;
  }

  Uint8List get bikeData =>
      indoorBikeData(BikeData(speedKmh: speedKmh, cadence: cadence, power: power, heartRate: heartRate));
}

/// Trame FTMS « Indoor Bike Data » à partir de valeurs.
Uint8List indoorBikeData(BikeData d) {
  var flags = 0;
  final body = BytesBuilder();
  void u16(int v) => body.add([v & 0xFF, (v >> 8) & 0xFF]);
  if (d.speedKmh != null) {
    u16((d.speedKmh! * 100).round().clamp(0, 0xFFFF));
  } else {
    flags |= 1; // vitesse absente
  }
  if (d.cadence != null) {
    flags |= 1 << 2;
    u16((d.cadence! * 2).round().clamp(0, 0xFFFF));
  }
  if (d.power != null) {
    flags |= 1 << 6;
    u16(d.power!.clamp(-32768, 32767) & 0xFFFF);
  }
  if (d.heartRate != null) {
    flags |= 1 << 9;
    body.addByte(d.heartRate!.clamp(0, 255));
  }
  return Uint8List.fromList([flags & 0xFF, flags >> 8, ...body.toBytes()]);
}
