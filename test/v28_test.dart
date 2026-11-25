import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controller_manager.dart' show LinkState;
import 'package:shiftlink/src/ride/fit_writer.dart';
import 'package:shiftlink/src/ride/power_stats.dart';
import 'package:shiftlink/src/ride/ride_history.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/workout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('statistiques de puissance', () {
    test('meilleurs efforts sur 5 s, 1 min, 5 min, 20 min', () {
      final watts = <int?>[
        for (var i = 0; i < 1200; i++) 200,
        for (var i = 0; i < 300; i++) 300,
        for (var i = 0; i < 5; i++) 800,
        null,
      ];
      final b = bestEfforts(watts);
      expect(b[5], 800);
      expect(b[60], ((55 * 300 + 5 * 800) / 60).round());
      expect(b[300], ((295 * 300 + 5 * 800) / 300).round());
      expect(b[1200], greaterThan(200));
      expect(bestEfforts([100, 100]), isEmpty);
    });

    test('puissance normalisée et charge : 1 h à la FTP = 100', () {
      final steady = List<int?>.filled(3600, 250);
      expect(normalizedPower(steady), 250);
      expect(trainingLoad(seconds: 3600, np: 250, ftp: 250)!.round(), 100);
      expect(trainingLoad(seconds: 3600, np: null, ftp: 250), isNull);
    });

    test('forme et fatigue montent avec l’entraînement, la fatigue plus vite', () {
      final start = DateTime(2026, 10, 2);
      final loads = {for (var d = 0; d < 14; d++) start.add(Duration(days: d)): 80.0};
      final curve = fitnessCurve(loads, until: start.add(const Duration(days: 13)));
      expect(curve.length, 14);
      expect(curve.last.fatigue, greaterThan(curve.last.fitness));
      expect(curve.last.freshness, lessThan(0));
    });

    test('la puissance se relit dans le .fit écrit par ShiftLink', () {
      final t0 = DateTime(2026, 11, 9, 18);
      final samples = [
        for (var i = 0; i < 90; i++)
          RideSample(time: t0.add(Duration(seconds: i)), power: i < 45 ? 150 : null, distance: i * 8.0),
      ];
      final watts = readFitPower(FitWriter.encode(samples));
      expect(watts.length, 90);
      expect(watts.first, 150);
      expect(watts.last, isNull);
    });

    test('le résumé garde ses statistiques', () {
      final t0 = DateTime(2026, 11, 9, 18);
      final samples = [
        for (var i = 0; i < 400; i++) RideSample(time: t0.add(Duration(seconds: i)), power: 220, distance: i * 8.0),
      ];
      final s = RideSummary.fromSamples(samples, 3200, '/x/a.fit', ftp: 250);
      expect(s.bests[300], 220);
      final back = RideSummary.fromJson(s.toJson(), '/x/a.fit')!;
      expect(back.bests, s.bests);
      expect(back.normalizedPower, 220);
      expect(back.ftp, 250);
      expect(back.load, isNotNull);
    });
  });

  test('ERG fixe : le trainer tient les watts, puis repart en simulation', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      expect(proxy.startFixedErg(180), isTrue);
      expect(sent.last, Ftms.targetPower(180));
      expect(proxy.fixedErg.value, 180);
      proxy.setFixedErg(200);
      expect(sent.last, Ftms.targetPower(200));
      proxy.ergAdjust(10);
      expect(proxy.fixedErg.value, 210);
      // Une séance arrête l'ERG fixe.
      proxy.startWorkout(const Workout('t', [WorkoutStep(60, 0.5)]), ftp: 200);
      expect(proxy.fixedErg.value, isNull);
      proxy.stopWorkout();
      expect(proxy.startFixedErg(150), isTrue);
      proxy.stopFixedErg();
      expect(proxy.fixedErg.value, isNull);
      expect(sent.last, Ftms.simulation(gradePercent: 0));
    });
  });

  test('séance perso : se sauvegarde et se relit', () {
    const w = Workout('Ma séance', [WorkoutStep(600, 0.5, 0.75), WorkoutStep(180, 1.1), WorkoutStep(120, 0.6)]);
    final back = Workout.decodeList(Workout.encodeList([w])).single;
    expect(back.seconds, 900);
    expect(back.steps[0].to, 0.75);
    expect(back.intensityAt(600), 1.1);
  });
}
