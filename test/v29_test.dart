import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/actions.dart';
import 'package:shiftlink/src/controller_manager.dart' show LinkState;
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/gestures.dart';
import 'package:shiftlink/src/riders.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/gears.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/route.dart';
import 'package:shiftlink/src/trainer/workout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('manette partie en plein appui', () {
    test('la répétition s’arrête et l’action maintenue est relâchée', () {
      fakeAsync((t) {
        final fired = <String>[];
        final e = GestureEngine(
          reportsRelease: true,
          resolve: (id, g) => switch ((id, g)) {
            ('a', Gesture.click) => ShiftAction.shiftUp,
            ('b', Gesture.click) => ShiftAction.steerLeft,
            _ => null,
          },
          fire: (id, g, a, phase) => fired.add('$id:${a.name}:${phase.name}'),
        );
        e.onEvent(press('a'));
        e.onEvent(press('b'));
        t.elapse(const Duration(seconds: 1));
        final before = fired.length;
        expect(fired.where((f) => f == 'a:shiftUp:once').length, greaterThan(1));
        e.releaseAll();
        expect(fired.last, 'b:steerLeft:end');
        final after = fired.length;
        t.elapse(const Duration(seconds: 5));
        expect(fired.length, after, reason: 'plus rien après la coupure');
        expect(after, before + 1);
      });
    });
  });

  group('vitesses', () {
    test('infinies : 0,5 % de pente par appui, sans butée', () {
      final g = VirtualGears(config: const ShiftingConfig(infinite: true));
      for (var i = 0; i < 30; i++) {
        expect(g.shift(1), isTrue);
      }
      expect(g.extraGrade, 15);
      expect(g.label(), '+15,0 %');
      const flat = SimulationParams(0, 0, 0.004, 0.51);
      expect(g.adjust(flat).gradePercent, greaterThan(10));
      g.config = const ShiftingConfig();
      expect(g.extraGrade, 0);
    });

    test('tout plus dur / plus facile décale toutes les vitesses', () {
      final g = VirtualGears();
      final before = g.ratio();
      expect(g.shiftAll(2), isTrue);
      expect(g.ratio(), closeTo(before * 1.06 * 1.06, 1e-9));
      expect(g.shiftAll(-4), isTrue);
      expect(g.ratio(), lessThan(before));
      for (var i = 0; i < 20; i++) {
        g.shiftAll(1);
      }
      expect(g.offset, VirtualGears.maxOffset);
      expect(g.shiftAll(1), isFalse);
    });
  });

  group('mode enfant', () {
    test('se sauvegarde avec le cycliste', () {
      const r = Rider(name: 'Léo', kg: 30, ftp: 80, kid: true, kidMaxGrade: 2.5, kidPowerFactor: 1.5);
      final back = Rider.decodeList(Rider.encodeList([r])).single;
      expect(back.kid, isTrue);
      expect(back.kidMaxGrade, 2.5);
      expect(back.kidPowerFactor, 1.5);
      expect(back.kidMaxWatts, 120);
      expect(Rider.decodeList(Rider.encodeList([const Rider(name: 'A')])).single.kid, isFalse);
    });

    test('pente et watts plafonnés, watts multipliés pour l’appli', () {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      proxy.configure(const ShiftingConfig(control: 'grade'));
      proxy
        ..maxGrade = 2
        ..maxWatts = 120
        ..appPowerFactor = 1.5;
      proxy.handleControlPoint(Ftms.simulation(gradePercent: 10));
      final grade = ByteData.sublistView(sent.last).getInt16(3, Endian.little) / 100;
      expect(grade, lessThanOrEqualTo(2));
      // L'appli demande 150 W « vus » : 100 W réels.
      proxy.handleControlPoint(Ftms.targetPower(150));
      expect(sent.last, Ftms.targetPower(100));
      // Plafond des watts.
      proxy.handleControlPoint(Ftms.targetPower(600));
      expect(sent.last, Ftms.targetPower(120));
    });
  });

  test('test FTP en rampe : s’arrête quand on lâche', () {
    fakeAsync((async) {
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async {};
      proxy.trainer.state.value = LinkState.connected;
      final ramp = builtInWorkouts.firstWhere((w) => w.ftpTest == 'ramp');
      expect(proxy.startWorkout(ramp, ftp: 200), isTrue);
      proxy.data.value = const BikeData(cadence: 90, power: 250);
      async.elapse(Duration(seconds: ramp.steps.first.seconds + 180));
      expect(proxy.workout.value, isNotNull);
      proxy.data.value = const BikeData(cadence: 30, power: 50);
      async.elapse(const Duration(seconds: 6));
      expect(proxy.workout.value, isNull);
      expect(proxy.finishedWorkout.value, ramp);
      expect(proxy.lastPowerLog.last, 250);
    });
  });

  test('pause manuelle d’un parcours : la distance attend', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      const route = GpxRoute('r', [RoutePoint(0, 0), RoutePoint(10000, 50)]);
      expect(proxy.startRoute(route), isTrue);
      proxy.data.value = const BikeData(speedKmh: 36, cadence: 90);
      async.elapse(const Duration(seconds: 10));
      final d = proxy.routeRun.value!.distance;
      expect(d, closeTo(100, 1));
      proxy.togglePause();
      expect(sent.last, Ftms.simulation(gradePercent: 0));
      async.elapse(const Duration(seconds: 10));
      expect(proxy.routeRun.value!.distance, d);
      proxy.togglePause();
      async.elapse(const Duration(seconds: 10));
      expect(proxy.routeRun.value!.distance, greaterThan(d));
      proxy.stopRoute();
      expect(proxy.manualPause.value, isFalse);
    });
  });

  test('parcours ShiftLink : les vitesses marchent même en « simple relais »', () {
    fakeAsync((async) {
      final sent = <Uint8List>[];
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async => sent.add(c);
      proxy.trainer.state.value = LinkState.connected;
      proxy.configure(const ShiftingConfig(relay: true, control: 'grade'));
      expect(proxy.shift(1), isFalse, reason: 'sans parcours, le relais ne change pas de vitesse');
      const route = GpxRoute('r', [RoutePoint(0, 0), RoutePoint(10000, 500)]);
      expect(proxy.startRoute(route), isTrue);
      proxy.data.value = const BikeData(speedKmh: 20, cadence: 80);
      async.elapse(const Duration(seconds: 3));
      final before = proxy.gear.value;
      final n = sent.length;
      expect(proxy.shift(1), isTrue);
      expect(proxy.gear.value, before + 1);
      expect(sent.length, greaterThan(n), reason: 'la nouvelle résistance part au trainer');
      proxy.stopRoute();
    });
  });
}
