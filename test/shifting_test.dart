import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/gears.dart';
import 'package:shiftlink/src/trainer/proxy.dart';

/// Trame Indoor Bike Data avec cadence et puissance.
Uint8List bikeData(double rpm, int watts) {
  final b = ByteData(8);
  b.setUint16(0, 0x44, Endian.little); // cadence + puissance, vitesse présente
  b.setUint16(2, 3000, Endian.little);
  b.setUint16(4, (rpm * 2).round(), Endian.little);
  b.setInt16(6, watts, Endian.little);
  return b.buffer.asUint8List();
}

int? powerOf(Uint8List cmd) =>
    cmd[0] == Ftms.opSetTargetPower ? ByteData.sublistView(cmd).getInt16(1, Endian.little) : null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('vitesses personnalisées', () {
    test('braquets libres, 1 à 30 vitesses, double plateau', () {
      const c = ShiftingConfig(ratios: [1.0, 1.5, 2.0, 3.0], smallRing: 34, doubleRing: true);
      final g = VirtualGears(config: c, initialGear: 3);
      expect(g.count, 4);
      expect(g.gearRatio(), 2.0);
      expect(g.label(), '2,00');
      expect(g.frontShift(), isTrue);
      expect(g.gearRatio(), closeTo(2.0 * 34 / 50, 1e-9));
      final back = ShiftingConfig.decode(c.encode());
      expect(back.ratios, [1.0, 1.5, 2.0, 3.0]);
      expect(back.custom, isTrue);
    });

    test('personnaliser reprend les braquets actuels', () {
      final g = VirtualGears(config: ShiftingConfig.fromPreset(gearPresets[1]));
      final r = g.allRatios;
      expect(r.length, 12);
      expect(r.first, closeTo(50 / 34, 0.01));
      expect(r.last, closeTo(50 / 11, 0.01));
    });
  });

  test('filtre de cadence : un pic isolé est ignoré', () {
    final f = CadenceFilter();
    expect(f.add(90), 90);
    expect(f.add(91), 91);
    expect(f.add(180), 91);
    expect(f.add(92), 92);
  });

  test('capacités du trainer lues dans Feature', () {
    // Réglages : puissance (bit 3) seulement.
    final caps = TrainerCaps.parse([0, 0, 0, 0, 0x08, 0, 0, 0], [0, 0, 0xC8, 0, 1, 0]);
    expect(caps.simulation, isFalse);
    expect(caps.power, isTrue);
    expect(caps.bestControl, 'power');
    expect(caps.maxResistance, 200);
    expect(TrainerCaps.parse(null, null).bestControl, 'grade');
  });

  group('pilotage du trainer', () {
    VirtualShiftingProxy make(ShiftingConfig c, List<Uint8List> sent) {
      final p = VirtualShiftingProxy(log: (_) {});
      p.sendToTrainer = (cmd) async => sent.add(cmd);
      p.configure(c);
      return p;
    }

    test('puissance : watts de la vitesse à la cadence, plus durs en montant', () {
      final sent = <Uint8List>[];
      final p = make(const ShiftingConfig(control: 'power', cadenceFilter: false), sent);
      p.handleControlPoint(Ftms.simulation(gradePercent: 0));
      p.handleBikeData(bikeData(90, 200));
      final flat = powerOf(sent.last)!;
      expect(flat, greaterThan(50));
      p.shift(2);
      final harder = powerOf(sent.last)!;
      expect(harder, greaterThan(flat));
      p.handleControlPoint(Ftms.simulation(gradePercent: 6));
      expect(powerOf(sent.last)!, greaterThan(harder));
      // Pédalage arrêté : 0 W.
      p.handleBikeData(bikeData(0, 0));
      expect(powerOf(sent.last), 0);
    });

    test('résistance : niveau dans la plage du trainer', () {
      final sent = <Uint8List>[];
      final p = make(const ShiftingConfig(control: 'resistance'), sent);
      p.handleControlPoint(Ftms.simulation(gradePercent: 20));
      expect(sent.last[0], Ftms.opSetTargetResistance);
      final hi = ByteData.sublistView(sent.last).getInt16(1, Endian.little);
      p.handleControlPoint(Ftms.simulation(gradePercent: -10));
      final lo = ByteData.sublistView(sent.last).getInt16(1, Endian.little);
      expect(hi, greaterThan(lo));
      expect(lo, 0);
    });

    test('relais : pente transmise telle quelle, pas de vitesses', () {
      final sent = <Uint8List>[];
      final p = make(const ShiftingConfig(relay: true), sent);
      p.handleControlPoint(Ftms.simulation(gradePercent: 4));
      expect(SimulationParams.parse(sent.last)!.gradePercent, 4);
      expect(p.shift(3), isFalse);
    });
  });

  test('profils de vitesses nommés', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final app = AppState(demo: true);
    await app.init();
    await app.setShifting(ShiftingConfig.fromPreset(gearPresets.firstWhere((p) => p.id == 'mtb')));
    await app.saveShiftProfile('VTT');
    await app.setShifting(const ShiftingConfig());
    await app.saveShiftProfile('Route');
    expect(app.shiftProfileNames, ['Route', 'VTT']);
    await app.loadShiftProfile('VTT');
    expect(app.shifting.presetId, 'mtb');
    expect(app.activeShiftProfile, 'VTT');
    await app.deleteShiftProfile('VTT');
    expect(app.shiftProfileNames, ['Route']);
  });
}
