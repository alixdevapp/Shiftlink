import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/sensors/headwind.dart';
import 'package:shiftlink/src/sensors/heart_rate.dart';
import 'package:shiftlink/src/trainer/dircon.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/gears.dart';
import 'package:shiftlink/src/trainer/proxy.dart';

void main() {
  group('FTMS', () {
    test('commande de simulation encodée puis décodée', () {
      final cmd = Ftms.simulation(gradePercent: 5.25, wind: -1.5);
      expect(cmd[0], Ftms.opSetSimulation);
      final p = SimulationParams.parse(cmd)!;
      expect(p.gradePercent, closeTo(5.25, 0.001));
      expect(p.wind, closeTo(-1.5, 0.001));
      expect(p.crr, closeTo(0.004, 0.0001));
      expect(p.cw, closeTo(0.51, 0.001));
    });

    test('Indoor Bike Data : vitesse, cadence, puissance', () {
      // flags = cadence (bit 2) + puissance (bit 6) ; vitesse présente (bit 0 à 0)
      final b = ByteData(8)
        ..setUint16(0, 0x0044, Endian.little)
        ..setUint16(2, 3250, Endian.little) // 32,50 km/h
        ..setUint16(4, 180, Endian.little) // 90 tr/min
        ..setInt16(6, 245, Endian.little);
      final d = BikeData.parse(b.buffer.asUint8List());
      expect(d.speedKmh, closeTo(32.5, 0.01));
      expect(d.cadence, 90);
      expect(d.power, 245);
    });
  });

  group('Vitesses virtuelles', () {
    test('rapports croissants de 0,5 à 2', () {
      final g = VirtualGears();
      expect(g.ratio(1), closeTo(0.5, 1e-9));
      expect(g.ratio(24), closeTo(2.0, 1e-9));
      for (var i = 2; i <= 24; i++) {
        expect(g.ratio(i), greaterThan(g.ratio(i - 1)));
      }
      expect(g.ratio(g.neutralGear), closeTo(1.0, 0.04));
    });

    test('butées', () {
      final g = VirtualGears(initialGear: 24);
      expect(g.shift(1), isFalse);
      expect(g.shift(-1), isTrue);
      expect(g.gear, 23);
    });

    test('rapport 1 = paramètres inchangés', () {
      final g = VirtualGears(count: 3, initialGear: 2);
      expect(g.ratio(), closeTo(1.0, 1e-9));
      final out = g.adjust(const SimulationParams(0, 4, 0.004, 0.51));
      expect(out.gradePercent, closeTo(4, 1e-9));
      expect(out.cw, closeTo(0.51, 1e-9));
    });

    test('grand braquet = plus dur, petit braquet = plus facile', () {
      final g = VirtualGears(count: 3, initialGear: 3);
      final hard = g.adjust(const SimulationParams(0, 4, 0.004, 0.51));
      expect(hard.gradePercent, closeTo((4 + 0.4) * 2 - 0.4, 1e-9));
      expect(hard.cw, closeTo(2.55, 1e-9)); // 0,51 × 8 plafonné
      g.gear = 1;
      final easy = g.adjust(const SimulationParams(2, 4, 0.004, 0.51));
      expect(easy.gradePercent, closeTo((4 + 0.4) * 0.5 - 0.4, 1e-9));
      expect(easy.cw, closeTo(0.51 / 8, 1e-9));
      expect(easy.wind, closeTo(4, 1e-9));
    });
  });

  group('DIRCON', () {
    DirconServer server() => DirconServer(log: (_) {}, onControlPoint: (c) => Ftms.response(c[0], Ftms.resultSuccess));

    test('découpage des messages TCP', () {
      final f = DirconFramer();
      final a = Dircon.packet(Dircon.msgDiscoverServices, 1, 0, const []);
      final b = Dircon.packet(Dircon.msgRead, 2, 0, Dircon.uuidBytes(Ftms.feature));
      final all = [...a, ...b];
      expect(f.add(all.sublist(0, 4)), isEmpty);
      final msgs = f.add(all.sublist(4));
      expect(msgs.map((m) => m.type), [Dircon.msgDiscoverServices, Dircon.msgRead]);
      expect(Dircon.shortUuid(msgs[1].payload), Ftms.feature);
    });

    test('liste des services et caractéristiques', () {
      final s = server();
      final r = s.handleForTest(DirconMessage(Dircon.msgDiscoverServices, 7, Uint8List(0)));
      expect(r.single.sublist(0, 6), [1, Dircon.msgDiscoverServices, 7, 0, 0, 16]);
      expect(Dircon.shortUuid(r.single.sublist(6)), Ftms.service);

      final c = s.handleForTest(DirconMessage(Dircon.msgDiscoverCharacteristics, 8, Dircon.uuidBytes(Ftms.service)));
      final payload = c.single.sublist(6);
      expect((payload.length - 16) % 17, 0);
      final uuids = [for (var i = 16; i < payload.length; i += 17) Dircon.shortUuid(payload.sublist(i, i + 16))];
      expect(uuids, containsAll([Ftms.indoorBikeData, Ftms.controlPoint, Ftms.feature]));
    });

    test('écriture dans le point de contrôle : accusé + indication', () {
      final s = server();
      final cmd = Ftms.simulation(gradePercent: 3);
      final r = s.handleForTest(
        DirconMessage(Dircon.msgWrite, 9, Uint8List.fromList([...Dircon.uuidBytes(Ftms.controlPoint), ...cmd])),
      );
      expect(r, hasLength(2));
      expect(r[0][1], Dircon.msgWrite);
      expect(r[0][3], Dircon.ok);
      expect(r[1][1], Dircon.msgNotification);
      expect(r[1].sublist(22), [Ftms.opResponse, Ftms.opSetSimulation, Ftms.resultSuccess]);
    });

    test('caractéristique inconnue', () {
      final r = server().handleForTest(DirconMessage(Dircon.msgRead, 3, Dircon.uuidBytes(0x2A19)));
      expect(r.single[3], Dircon.errCharacteristicNotFound);
    });
  });

  test('proxy : pente transmise, puis recalculée à chaque changement de vitesse', () {
    final sent = <Uint8List>[];
    final proxy = VirtualShiftingProxy(log: (_) {});
    proxy.sendToTrainer = (c) async => sent.add(c);
    proxy.gears.gear = proxy.gears.neutralGear;
    proxy.gear.value = proxy.gears.gear;

    final resp = proxy.handleControlPoint(Ftms.simulation(gradePercent: 5));
    expect(resp, [Ftms.opResponse, Ftms.opSetSimulation, Ftms.resultSuccess]);
    final first = SimulationParams.parse(sent.last)!.gradePercent;
    expect(first, closeTo(5, 0.3));

    proxy.shift(3);
    final harder = SimulationParams.parse(sent.last)!.gradePercent;
    expect(harder, greaterThan(first));

    // En ERG, la puissance passe telle quelle et les vitesses ne renvoient rien.
    proxy.handleControlPoint(Ftms.targetPower(200));
    final count = sent.length;
    expect(sent.last, Ftms.targetPower(200));
    proxy.shift(1);
    expect(sent.length, count);
  });

  group('réglages des vitesses', () {
    test('transmission route : braquets, développement, braquet réel', () {
      final c = ShiftingConfig.fromPreset(gearPresets.firstWhere((p) => p.id == 'road12'));
      final g = VirtualGears(config: c);
      expect(g.count, 12);
      expect(g.label(1), '50×34');
      expect(g.label(12), '50×11');
      expect(g.development(12), closeTo(50 / 11 * 2.105, 1e-9));
      // Vitesse neutre la plus proche de 50×17.
      expect(g.label(g.neutralGear), '50×17');
      expect(g.ratio(g.neutralGear), closeTo(1, 1e-9));
    });

    test('double plateau : la vitesse garde son pignon, le rapport baisse', () {
      final c = ShiftingConfig.fromPreset(gearPresets.firstWhere((p) => p.id == 'road12')).copyWith(doubleRing: true);
      final g = VirtualGears(config: c);
      final before = g.ratio();
      expect(g.frontShift(), isTrue);
      expect(g.currentRing, 34);
      expect(g.ratio(), closeTo(before * 34 / 50, 1e-9));
      expect(VirtualGears().frontShift(), isFalse);
    });

    test('effet des pentes et poids', () {
      final g = VirtualGears(config: const ShiftingConfig(difficulty: 0.5));
      g.gear = g.neutralGear;
      final half = g.adjust(const SimulationParams(0, 8, 0, 0.51)).gradePercent;
      expect(half, closeTo(4 * g.ratio(), 0.01));
      final heavy = VirtualGears(config: const ShiftingConfig(totalKg: 170));
      heavy.gear = heavy.neutralGear;
      expect(heavy.adjust(const SimulationParams(0, 4, 0, 0.51)).gradePercent, closeTo(8 * heavy.ratio(), 0.01));
    });

    test('lissage : la pente rejoint la cible progressivement', () {
      final g = VirtualGears(config: const ShiftingConfig(smoothing: true));
      g.gear = g.neutralGear;
      final k = g.ratio();
      expect(g.adjust(const SimulationParams(0, 0, 0, 0.51)).gradePercent, closeTo(0, 0.01));
      final step = g.adjust(const SimulationParams(0, 10, 0, 0.51)).gradePercent;
      expect(step, closeTo(3.5 * k, 0.01));
      // Un changement de vitesse ne fait pas avancer le lissage.
      expect(g.adjust(const SimulationParams(0, 10, 0, 0.51), fresh: false).gradePercent, closeTo(step, 0.01));
    });

    test('réglages enregistrés et relus', () {
      const c = ShiftingConfig(presetId: 'gravel', cogs: [44, 11], ring: 40, difficulty: 0.8, ergStep: 20, sound: true);
      final back = ShiftingConfig.decode(c.encode());
      expect(back.cogs, [44, 11]);
      expect(back.difficulty, 0.8);
      expect(back.ergStep, 20);
      expect(back.sound, isTrue);
      expect(ShiftingConfig.decode('pas du json').presetId, 'classic');
    });
  });

  test('proxy ERG : intensité ± depuis la manette', () {
    final sent = <Uint8List>[];
    final proxy = VirtualShiftingProxy(log: (_) {});
    proxy.sendToTrainer = (c) async => sent.add(c);
    expect(proxy.ergAdjust(10), isFalse);
    proxy.handleControlPoint(Ftms.targetPower(200));
    expect(sent.last, Ftms.targetPower(200));
    expect(proxy.ergAdjust(10), isTrue);
    expect(proxy.ergAdjust(10), isTrue);
    expect(sent.last, Ftms.targetPower(220));
    // L'appli change de palier : le décalage reste.
    proxy.handleControlPoint(Ftms.targetPower(150));
    expect(sent.last, Ftms.targetPower(170));
    expect(proxy.ergTarget, 170);
  });

  test('cardio ajouté à la trame du trainer', () {
    // Vitesse 30 km/h, cadence 90, puissance 250.
    final raw = Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xFA, 0x00]);
    final out = withHeartRate(raw, 142);
    final d = BikeData.parse(out);
    expect(d.heartRate, 142);
    expect(d.power, 250);
    expect(d.cadence, 90);
    expect(d.speedKmh, 30);
    // Déjà présent : remplacé, pas ajouté deux fois.
    final again = withHeartRate(out, 150);
    expect(again.length, out.length);
    expect(BikeData.parse(again).heartRate, 150);
  });

  test('ceinture cardio : trames 8 et 16 bits', () {
    expect(HeartRateMonitor.parse([0x00, 72]), 72);
    expect(HeartRateMonitor.parse([0x01, 0x2C, 0x01]), 300);
    expect(HeartRateMonitor.parse([0x00]), isNull);
  });

  test('Headwind : vent selon la vitesse et commandes', () {
    expect(Headwind.forSpeed(0), 0);
    expect(Headwind.forSpeed(10), 25);
    expect(Headwind.forSpeed(21), 50);
    expect(Headwind.forSpeed(55), 100);
    expect(Headwind.speedCommand(150), [0x02, 100]);
    expect(Headwind.manualMode(), [0x04, 0x04]);
  });
}
