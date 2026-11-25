// Nouveautés 2.3 : trainers FE-C, capteurs, trame FTMS réécrite, ERG manuel.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controller_manager.dart' show LinkState;
import 'package:shiftlink/src/sensors/bike_sensor.dart';
import 'package:shiftlink/src/trainer/fec.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';

int xorAll(List<int> b) => b.fold(0, (a, x) => a ^ x);

void main() {
  group('FE-C', () {
    test('message ANT : en-tête, page et somme de contrôle', () {
      final m = Fec.targetPower(250);
      expect(m.length, 13);
      expect(m.sublist(0, 4), [0xA4, 9, 0x4F, 5]);
      expect(m[4], 0x31);
      expect(m[10] | (m[11] << 8), 1000); // 0,25 W
      expect(xorAll(m.sublist(0, 12)), m[12]);
    });

    test('pente : (pente + 200) / 0,01 et roulement en 5e-5', () {
      final m = Fec.track(5, 0.004);
      expect(m[4], 0x33);
      expect(m[9] | (m[10] << 8), 20500);
      expect(m[11], 80);
      final down = Fec.track(-3.5, 0.004);
      expect(down[9] | (down[10] << 8), 19650);
    });

    test('commandes FTMS traduites', () {
      final sim = Fec.fromFtms(Ftms.simulation(gradePercent: 4, wind: 2));
      expect(sim.map((m) => m[4]), [0x32, 0x33]);
      expect(sim[0][9], 51); // 0,51 kg/m
      expect(sim[0][10], 127 + 7); // 2 m/s ≈ 7 km/h
      expect(Fec.fromFtms(Ftms.targetResistance(500)).single[11], 100); // 50 % → 100 demi-pour-cent
      expect(Fec.fromFtms(Ftms.targetPower(180)).single[4], 0x31);
      expect(Fec.fromFtms(Ftms.startResume()), isEmpty);
    });

    test('pages reçues → trame FTMS', () {
      final dec = FecDecoder();
      List<int> ant(List<int> page) => [
        0xA4,
        9,
        0x4E,
        5,
        ...page,
        xorAll([0xA4, 9, 0x4E, 5, ...page]),
      ];
      // Page 0x10 : 8,333 m/s = 30 km/h ; page 0x19 : 92 tr/min, 245 W.
      final both = [
        ...ant([0x10, 25, 0, 0, 0x8D, 0x20, 0xFF, 0x24]),
        ...ant([0x19, 1, 92, 0, 0, 245, 0x30, 0x20]),
      ];
      expect(dec.add(both), isTrue);
      final d = BikeData.parse(dec.bikeData);
      expect(d.speedKmh, closeTo(30, 0.05));
      expect(d.cadence, 92);
      expect(d.power, 245);
      expect(d.heartRate, isNull);
    });
  });

  group('trame FTMS réécrite', () {
    test('cadence et puissance remplacées, les autres champs gardés', () {
      // vitesse + cadence + distance + puissance
      final raw = indoorBikeData(const BikeData(speedKmh: 30, cadence: 80, power: 200));
      final out = withValues(raw, cadence: 95, power: 260);
      final d = BikeData.parse(out);
      expect(d.speedKmh, closeTo(30, 0.01));
      expect(d.cadence, 95);
      expect(d.power, 260);
    });

    test('cadence ajoutée quand le trainer n’en donne pas', () {
      final raw = indoorBikeData(const BikeData(speedKmh: 25, power: 150));
      final d = BikeData.parse(withValues(raw, cadence: 88, heartRate: 140));
      expect(d.cadence, 88);
      expect(d.power, 150);
      expect(d.heartRate, 140);
      expect(d.speedKmh, closeTo(25, 0.01));
    });

    test('trame tronquée rendue telle quelle', () {
      final bad = Uint8List.fromList([0x44, 0x00, 0x10]);
      expect(withValues(bad, power: 100), bad);
    });
  });

  group('capteurs', () {
    test('CSC : tours de pédalier', () {
      // drapeaux : roue + pédalier
      expect(BikeSensor.parseCsc([0x03, 1, 0, 0, 0, 0, 0, 10, 0, 0x00, 0x04]), (10, 1024));
      expect(BikeSensor.parseCsc([0x01, 1, 0, 0, 0, 0, 0]), isNull);
    });

    test('puissance avec équilibre et pédalier', () {
      final p = BikeSensor.parsePower([0x21, 0x00, 0xFA, 0x00, 50, 7, 0, 0x00, 0x08]);
      expect(p!.$1, 250);
      expect(p.$2, (7, 2048));
    });

    test('cadence calculée, puis 0 à l’arrêt', () {
      final c = CrankCadence();
      final t0 = DateTime(2026);
      c.add(100, 0, t0);
      // 1 tour en 1 s → 60 tr/min, puis 2 tours en 1,33 s → 90 tr/min
      expect(c.add(101, 1024, t0.add(const Duration(seconds: 1))), closeTo(60, 0.1));
      expect(c.add(103, 1024 + 1365, t0.add(const Duration(seconds: 2))), closeTo(90, 0.2));
      expect(c.add(103, 1024 + 1365, t0.add(const Duration(seconds: 3))), closeTo(90, 0.2));
      expect(c.add(103, 1024 + 1365, t0.add(const Duration(seconds: 6))), 0);
      // compteurs qui repassent par zéro
      final w = CrankCadence();
      w.add(0xFFFF, 0xFC00, t0);
      expect(w.add(0, 0, t0), closeTo(60, 0.1));
    });
  });

  testWidgets('ERG manuel sans appli, puis escalier', (tester) async {
    final sent = <Uint8List>[];
    final proxy = VirtualShiftingProxy(log: (_) {});
    proxy.sendToTrainer = (c) async => sent.add(c);
    expect(proxy.ergAdjust(10, startWatts: 150), isFalse, reason: 'pas de trainer');
    proxy.trainer.state.value = LinkState.connected;
    expect(proxy.ergAdjust(10, startWatts: 150), isTrue);
    expect(sent.last, Ftms.targetPower(150));
    expect(proxy.ergAdjust(10, startWatts: 150), isTrue);
    expect(sent.last, Ftms.targetPower(160));
    expect(proxy.lastErgTarget, 160);

    expect(proxy.startStaircase(startWatts: 100, stepWatts: 20, steps: 2, minutes: 1), isTrue);
    expect(sent.last, Ftms.targetPower(100));
    await tester.pump(const Duration(seconds: 61));
    expect(sent.last, Ftms.targetPower(120));
    expect(proxy.staircase.value!.step, 2);
    await tester.pump(const Duration(seconds: 60));
    expect(proxy.staircase.value, isNull);
    proxy.stopStaircase();
  });

  testWidgets('capteur de puissance : remplace les watts envoyés à l’appli', (tester) async {
    final proxy = VirtualShiftingProxy(log: (_) {});
    proxy.externalPower = () => 300;
    proxy.externalCadence = () => 90;
    proxy.handleBikeData(indoorBikeData(const BikeData(speedKmh: 30, cadence: 70, power: 200)));
    expect(proxy.data.value.power, 300);
    expect(proxy.data.value.cadence, 90);
    expect(proxy.cadence, isNotNull);
  });
}
