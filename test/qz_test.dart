// Cyclistes, zones cardio, séances .zwo et watts estimés (idées reprises de QZ).
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controller_manager.dart' show LinkState;
import 'package:shiftlink/src/riders.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/workout.dart';

const zwo = '''<?xml version="1.0"?>
<workout_file>
  <author>Moi</author>
  <name>Test &amp; sprint</name>
  <description>Petite séance</description>
  <sportType>bike</sportType>
  <workout>
    <Warmup Duration="600" PowerLow="0.25" PowerHigh="0.75"/>
    <SteadyState Duration="300" Power="0.88" pace="0">
      <textevent timeoffset="10" message="Allez !"/>
    </SteadyState>
    <IntervalsT Repeat="3" OnDuration="60" OffDuration="30" OnPower="1.2" OffPower="0.5"/>
    <FreeRide Duration="120" FlatRoad="1"/>
    <Cooldown Duration="300" PowerLow="0.7" PowerHigh="0.3"/>
  </workout>
</workout_file>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('séances .zwo', () {
    test('lit les blocs, les répétitions et le nom', () {
      final w = Workout.parseZwo(zwo)!;
      expect(w.name, 'Test & sprint');
      expect(w.description, 'Petite séance');
      expect(w.steps.length, 1 + 1 + 6 + 1 + 1);
      expect(w.seconds, 600 + 300 + 3 * 90 + 120 + 300);
      expect(w.intensityAt(0), closeTo(0.25, 0.001));
      expect(w.intensityAt(599), closeTo(0.75, 0.001));
      expect(w.intensityAt(700), closeTo(0.88, 0.001));
      expect(w.intensityAt(900), closeTo(1.2, 0.001));
      expect(w.intensityAt(960), closeTo(0.5, 0.001));
      expect(w.intensityAt(w.seconds), isNull);
    });

    test('refuse ce qui n’est pas une séance', () {
      expect(Workout.parseZwo('bonjour'), isNull);
      expect(Workout.parseZwo('<workout_file><workout></workout></workout_file>'), isNull);
    });

    test('se sauvegarde et se relit', () {
      final w = Workout.parseZwo(zwo)!;
      final back = Workout.decodeList(Workout.encodeList([w]));
      expect(back.single.name, w.name);
      expect(back.single.seconds, w.seconds);
      expect(Workout.decodeList('pas du json'), isEmpty);
    });

    test('séances fournies : durées annoncées', () {
      // Les trois séances d'origine (balade, pyramide, 30/30) restent à la fin de la liste.
      final minutes = builtInWorkouts.map((w) => w.seconds ~/ 60).toList();
      expect(minutes.sublist(minutes.length - 3), [20, 24, 21]);
    });
  });

  group('cyclistes', () {
    test('JSON : valeurs bornées, prénom obligatoire', () {
      final list = Rider.decodeList(
        '[{"name":"Léo","kg":22,"ftp":60,"hrMax":205},{"name":""},{"name":"Papa","kg":9999}]',
      );
      expect(list.map((r) => r.name), ['Léo', 'Papa']);
      expect(list.first.totalKg, 22 + Rider.defaultBikeKg);
      expect(list.last.kg, 200);
      final again = Rider.decodeList(Rider.encodeList(list));
      expect(again.first.ftp, 60);
    });

    test('poids du vélo : réglable par cycliste, 9 kg pour les anciens profils', () {
      final list = Rider.decodeList(
        '[{"name":"Alex","kg":70,"bikeKg":14.53},{"name":"Léa","kg":55},{"name":"X","bikeKg":999}]',
      );
      expect(list[0].bikeKg, 14.5);
      expect(list[0].totalKg, 84.5);
      expect(list[1].bikeKg, Rider.defaultBikeKg);
      expect(list[2].bikeKg, Rider.maxBikeKg);
      expect(Rider.roundBikeKg(8.66), 8.7);
      expect(Rider.roundBikeKg(8.6 + 0.1), 8.7);
      final again = Rider.decodeList(Rider.encodeList(list));
      expect(again.first.bikeKg, 14.5);
      expect(list[0].copyWith(bikeKg: 7).totalKg, 77);
    });

    test('zones cardio', () {
      expect(HrZone.of(100, 200).zone, 1);
      expect(HrZone.of(125, 200).zone, 2);
      expect(HrZone.of(150, 200).zone, 3);
      expect(HrZone.of(170, 200).zone, 4);
      expect(HrZone.of(195, 200).zone, 5);
    });

    test('watts estimés sur le plat', () {
      expect(estimatePower(0, 80), 0);
      expect(estimatePower(30, 84), inInclusiveRange(150, 230));
      expect(estimatePower(20, 30), lessThan(estimatePower(20, 90)));
    });
  });

  test('trainer sans puissance : watts estimés envoyés à l’appli', () {
    final proxy = VirtualShiftingProxy(log: (_) {});
    // Vitesse 30 km/h, cadence 90, sans puissance.
    proxy.handleBikeData(Uint8List.fromList([0x04, 0x00, 0xB8, 0x0B, 0xB4, 0x00]));
    expect(proxy.data.value.power, greaterThan(100));
    expect(proxy.estimatedPower.value, isTrue);
    // Puissance mesurée : on la garde.
    proxy.handleBikeData(Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xFA, 0x00]));
    expect(proxy.data.value.power, 250);
    expect(proxy.estimatedPower.value, isFalse);
  });

  test('séance sans appli : watts selon la FTP, chrono en pause sans pédaler', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      const w = Workout('t', [WorkoutStep(10, 0.5), WorkoutStep(10, 1.0)]);
      expect(proxy.startWorkout(w, ftp: 200), isTrue);
      expect(sent.last, Ftms.targetPower(100));
      // Sans pédaler : rien n'avance.
      async.elapse(const Duration(seconds: 15));
      expect(proxy.workout.value!.elapsed, 0);
      expect(proxy.workout.value!.paused, isTrue);
      // Cadence 90 : le chrono tourne, deuxième bloc à 200 W.
      proxy.handleBikeData(Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0x64, 0x00]));
      async.elapse(const Duration(seconds: 11));
      expect(sent.last, Ftms.targetPower(200));
      // L'intensité ± de la manette s'ajoute.
      proxy.ergAdjust(10);
      expect(sent.last, Ftms.targetPower(210));
      async.elapse(const Duration(seconds: 10));
      expect(proxy.workout.value, isNull);
      expect(proxy.finishedWorkout.value?.name, 't');
      expect(sent.last, Ftms.simulation(gradePercent: 0));
    });
  });

  test('l’appli reprend la main : la séance s’arrête', () {
    fakeAsync((async) {
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async {};
      proxy.trainer.state.value = LinkState.connected;
      proxy.startWorkout(builtInWorkouts.first, ftp: 200);
      proxy.handleControlPoint(Ftms.simulation(gradePercent: 3));
      expect(proxy.workout.value, isNull);
    });
  });

  test('séance : ergAlone vrai, la manette change les watts', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      expect(proxy.ergAlone, isFalse);
      proxy.startWorkout(const Workout('t', [WorkoutStep(60, 0.5)]), ftp: 200);
      expect(proxy.ergAlone, isTrue);
      proxy.ergAdjust(-10);
      expect(sent.last, Ftms.targetPower(90));
      proxy.stopWorkout();
      expect(proxy.ergAlone, isFalse);
    });
  });

  test('trainer sans ERG : ShiftLink règle la résistance vers les watts', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      proxy.trainer.caps.value = const TrainerCaps(power: false);
      proxy.startWorkout(const Workout('t', [WorkoutStep(60, 1.0)]), ftp: 200);
      // Le cycliste pousse 100 W à 90 tr/min : il faut plus de résistance.
      final low = Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0x64, 0x00]);
      proxy.handleBikeData(low);
      async.elapse(const Duration(seconds: 1));
      final first = sent.last;
      expect(first[0], Ftms.opSetTargetResistance);
      async.elapse(const Duration(seconds: 3));
      final later = sent.last;
      int level(Uint8List c) => c[1] | (c[2] << 8);
      expect(level(later), greaterThan(level(first)));
      proxy.stopWorkout();
    });
  });

  test('trainer qui donne trop de watts : conseil du petit braquet', () {
    fakeAsync((async) {
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async {};
      proxy.trainer.state.value = LinkState.connected;
      proxy.startWorkout(const Workout('t', [WorkoutStep(60, 0.5)]), ftp: 200);
      // 250 W pour 100 demandés, à 90 tr/min.
      proxy.handleBikeData(Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xFA, 0x00]));
      async.elapse(const Duration(seconds: 10));
      expect(proxy.workout.value!.tooHard, isTrue);
      proxy.stopWorkout();
    });
  });
}
