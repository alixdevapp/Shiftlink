import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/controller_manager.dart';
import 'package:shiftlink/src/ride/fit_writer.dart';
import 'package:shiftlink/src/ride/power_stats.dart';
import 'package:shiftlink/src/ride/ride_recorder.dart';
import 'package:shiftlink/src/settings_transfer.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/route.dart';
import 'package:shiftlink/src/trainer/workout.dart';

/// Lecteur FIT minimal pour les tests : (message global, {champ: valeur}) dans l'ordre du fichier.
List<(int, Map<int, int>)> readFit(Uint8List b) {
  final out = <(int, Map<int, int>)>[];
  final defs = <int, (int, List<(int, int, int)>)>{};
  final end = b[0] + ByteData.sublistView(b, 4, 8).getUint32(0, Endian.little);
  var p = b[0];
  while (p < end) {
    final h = b[p++];
    if (h & 0x40 != 0) {
      final global = b[p + 2] | (b[p + 3] << 8);
      final n = b[p + 4];
      p += 5;
      final fields = <(int, int, int)>[];
      for (var i = 0; i < n; i++) {
        fields.add((b[p], b[p + 1], b[p + 2]));
        p += 3;
      }
      defs[h & 0xF] = (global, fields);
    } else {
      final (global, fields) = defs[h & 0xF]!;
      final values = <int, int>{};
      for (final (num, size, type) in fields) {
        var v = 0;
        for (var i = 0; i < size; i++) {
          v |= b[p + i] << (8 * i);
        }
        if (type == 0x85) v = v.toSigned(32);
        values[num] = v;
        p += size;
      }
      out.add((global, values));
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.utc(2026, 11, 11, 18);
  RideSample sample(int i, {int power = 200, double? lat, double? lon, double? alt}) => RideSample(
    time: t0.add(Duration(seconds: i)),
    power: power,
    cadence: 90,
    heartRate: 140,
    speed: 8,
    distance: 8.0 * i,
    lat: lat,
    lon: lon,
    altitude: alt,
  );

  group('.fit : carte, dénivelé et tours', () {
    test('sortie sans parcours : pas de position, home trainer, un seul tour', () {
      final bytes = FitWriter.encode([for (var i = 0; i < 100; i++) sample(i)]);
      expect(FitWriter.crc(bytes), 0);
      final msgs = readFit(bytes);
      final rec = msgs.firstWhere((m) => m.$1 == 20).$2;
      expect(rec.containsKey(0), isFalse);
      expect(rec.containsKey(2), isFalse);
      expect(msgs.where((m) => m.$1 == 19), hasLength(1));
      final session = msgs.firstWhere((m) => m.$1 == 18).$2;
      expect(session[6], 6, reason: 'sous-sport home trainer');
      expect(session[26], 1);
      expect(readFitPower(bytes), hasLength(100));
    });

    test('sortie sur un parcours : position, altitude, dénivelé, sortie virtuelle', () {
      final samples = [
        for (var i = 0; i < 100; i++) sample(i, lat: 45.5 + i * 0.0001, lon: -6.25 - i * 0.0001, alt: 300 + i * 0.5),
      ];
      final bytes = FitWriter.encode(samples);
      expect(FitWriter.crc(bytes), 0);
      final msgs = readFit(bytes);
      final recs = msgs.where((m) => m.$1 == 20).map((m) => m.$2).toList();
      expect(recs, hasLength(100));
      expect(recs[10][0]! * 180 / 2147483648, closeTo(45.501, 0.00001));
      expect(recs[10][1]! * 180 / 2147483648, closeTo(-6.251, 0.00001));
      expect(recs[10][2]! / 5 - 500, closeTo(305, 0.2));
      expect(recs[10][7], 200, reason: 'les watts restent lisibles');
      final session = msgs.firstWhere((m) => m.$1 == 18).$2;
      expect(session[6], 58, reason: 'sortie virtuelle : Strava garde la carte et le dénivelé');
      expect(session[22], closeTo(50, 1));
      expect(readFitPower(bytes).whereType<int>().every((w) => w == 200), isTrue);
    });

    test('parcours sans trace GPS : altitude seule, positions invalides', () {
      final bytes = FitWriter.encode([for (var i = 0; i < 70; i++) sample(i, alt: 100)]);
      final msgs = readFit(bytes);
      final rec = msgs.firstWhere((m) => m.$1 == 20).$2;
      expect(rec[0], 0x7FFFFFFF);
      expect(rec[2], 3000);
      expect(msgs.firstWhere((m) => m.$1 == 18).$2[6], 6);
    });

    test('un tour par bloc : moyennes par tour', () {
      final samples = [for (var i = 0; i < 180; i++) sample(i, power: i < 60 ? 100 : (i < 120 ? 300 : 150))];
      final bytes = FitWriter.encode(samples, laps: [60, 120, 500, 0, 60]);
      expect(FitWriter.crc(bytes), 0);
      final msgs = readFit(bytes);
      final laps = msgs.where((m) => m.$1 == 19).map((m) => m.$2).toList();
      expect(laps, hasLength(3));
      expect(laps.map((l) => l[254]), [0, 1, 2]);
      expect(laps.map((l) => l[19]), [100, 300, 150]);
      expect(laps.map((l) => l[7]), [60000, 60000, 59000]);
      expect(laps[1][2], FitWriter.fitTime(t0.add(const Duration(seconds: 60))));
      // Les distances des tours s'additionnent pour donner celle de la sortie.
      expect(laps.fold<int>(0, (a, l) => a + l[9]!), (samples.last.distance * 100).round());
      expect(msgs.firstWhere((m) => m.$1 == 18).$2[26], 3);
    });

    test('enregistreur : position du parcours et tours', () {
      var t = t0;
      ({double? lat, double? lon, double? altitude})? pos;
      final r = RideRecorder(
        read: () => (power: 200, cadence: 90, heartRate: null, speedKmh: 36),
        now: () => t,
        position: () => pos,
      );
      r.markLap();
      expect(r.laps, isEmpty, reason: 'pas d’enregistrement, pas de tour');
      r.recording.value = true;
      for (var i = 0; i < 30; i++) {
        if (i == 10) {
          pos = (lat: 45.0, lon: 6.0, altitude: 1200.0);
          r.markLap();
          r.markLap();
        }
        if (i == 11) r.markLap();
        r.tick();
        t = t.add(const Duration(seconds: 1));
      }
      r.dispose();
      expect(r.laps, [10], reason: 'deux tours collés n’en font qu’un');
      expect(r.samples[5].lat, isNull);
      expect(r.samples[15].lat, 45.0);
      expect(r.samples[15].altitude, 1200.0);
    });
  });

  group('parcours : reprise et départ au km choisi', () {
    GpxRoute hill() => const GpxRoute('col', [RoutePoint(0, 0), RoutePoint(5000, 0), RoutePoint(10000, 400)]);

    test('départ à 6 km : la distance et la pente partent de là', () {
      fakeAsync((async) {
        final sent = <Uint8List>[];
        final progress = <(String, double?)>[];
        final proxy = VirtualShiftingProxy(log: (_) {});
        proxy.sendToTrainer = (c) async => sent.add(c);
        proxy.trainer.state.value = LinkState.connected;
        proxy.onRouteProgress = (n, d) => progress.add((n, d));
        expect(proxy.startRoute(hill(), fromM: 6000), isTrue);
        expect(proxy.routeRun.value!.distance, 6000);
        expect(proxy.routeRun.value!.grade, closeTo(8, 0.1));
        proxy.data.value = const BikeData(speedKmh: 36, cadence: 90);
        async.elapse(const Duration(seconds: 25));
        expect(proxy.routeRun.value!.distance, closeTo(6250, 1));
        expect(progress.single.$2, closeTo(6200, 1), reason: 'position gardée toutes les 20 s');
        proxy.stopRoute();
        expect(progress.last.$2, closeTo(6250, 1), reason: 'et à l’arrêt');
      });
    });

    test('parcours fini : plus de reprise ; le fantôme ne compte que depuis le début', () {
      fakeAsync((async) {
        final progress = <double?>[];
        final ghosts = <GhostRun>[];
        final proxy = VirtualShiftingProxy(log: (_) {});
        proxy.sendToTrainer = (c) async {};
        proxy.trainer.state.value = LinkState.connected;
        proxy.onRouteProgress = (_, d) => progress.add(d);
        proxy.onRouteFinished = (_, g) => ghosts.add(g);
        proxy.startRoute(hill(), fromM: 9000);
        proxy.data.value = const BikeData(speedKmh: 36, cadence: 90);
        async.elapse(const Duration(seconds: 110));
        expect(proxy.routeRun.value, isNull);
        expect(proxy.finishedRoute.value, 'col');
        expect(progress.last, isNull);
        expect(ghosts, isEmpty);
        proxy.startRoute(hill());
        async.elapse(const Duration(seconds: 1010));
        expect(ghosts, hasLength(1));
      });
    });

    test('fantôme comparé depuis le même endroit', () {
      fakeAsync((async) {
        final proxy = VirtualShiftingProxy(log: (_) {});
        proxy.sendToTrainer = (c) async {};
        proxy.trainer.state.value = LinkState.connected;
        // Le fantôme roulait à 10 m/s tout du long.
        proxy.ghostLookup = (_) => GhostRun([for (var s = 0; s <= 1000; s++) (s, s * 10.0)]);
        proxy.startRoute(hill(), fromM: 5000);
        proxy.data.value = const BikeData(speedKmh: 18, cadence: 90); // 5 m/s : deux fois plus lent
        async.elapse(const Duration(seconds: 100));
        expect(proxy.routeRun.value!.ghostGap, closeTo(50, 1));
        proxy.stopRoute();
      });
    });

    test('un départ trop près de l’arrivée est ramené avant', () {
      final proxy = VirtualShiftingProxy(log: (_) {});
      proxy.sendToTrainer = (c) async {};
      proxy.trainer.state.value = LinkState.connected;
      proxy.startRoute(hill(), fromM: 99999);
      expect(proxy.routeRun.value!.distance, 9900);
      proxy.stopRoute();
    });
  });

  group('parcours : un fichier chacun, plus de 20', () {
    GpxRoute route(String name) =>
        GpxRoute(name, const [RoutePoint(0, 0, lat: 45, lon: 6), RoutePoint(3000, 90, lat: 45.02, lon: 6)]);

    test('anciens parcours déplacés, 25 parcours gardés, reprise et suppression', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = Directory.systemTemp.createTempSync('shiftlink_routes');
      addTearDown(() => dir.deleteSync(recursive: true));
      SharedPreferences.setMockInitialValues({
        'routes': jsonEncode([route('Ancien').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final app = AppState(demo: true)
        ..prefs = prefs
        ..routesDir = dir;
      await app.loadRoutes();
      expect(app.routes.map((r) => r.name), ['Ancien']);
      expect(prefs.getString('routes'), isNull, reason: 'l’ancienne liste est vidée une fois déplacée');
      for (var i = 0; i < 25; i++) {
        expect(await app.addRoute(route('Parcours ${i.toString().padLeft(2, '0')} / été:?')), isTrue);
      }
      expect(app.routes, hasLength(26));
      expect(dir.listSync(), hasLength(26));

      // Relecture depuis le dossier, comme au redémarrage.
      final again = AppState(demo: true)
        ..prefs = prefs
        ..routesDir = dir;
      await again.loadRoutes();
      expect(again.routes, hasLength(26));
      expect(again.routes.first.name, 'Ancien');
      expect(again.routes.first.hasTrace, isTrue);

      await prefs.setDouble('routePos.Ancien', 1500);
      expect(again.routeResumeAt(again.routes.first), 1500);
      await prefs.setDouble('routePos.Ancien', 2950);
      expect(again.routeResumeAt(again.routes.first), isNull, reason: 'presque fini : on repart du début');
      await again.deleteRoute('Ancien');
      expect(again.routes, hasLength(25));
      expect(dir.listSync(), hasLength(25));
      expect(prefs.getDouble('routePos.Ancien'), isNull);
    });

    test('la sauvegarde des réglages laisse de côté parcours, fantômes et reprises', () {
      expect(SettingsTransfer.shared('routes'), isFalse);
      expect(SettingsTransfer.shared('ghost.col'), isFalse);
      expect(SettingsTransfer.shared('routePos.col'), isFalse);
      expect(SettingsTransfer.shared('ftp'), isTrue);
    });
  });

  group('.zwo : cadence et messages', () {
    const zwo = '''
<workout_file>
  <name>Vélocité</name>
  <description>Test</description>
  <workout>
    <Warmup Duration="300" PowerLow="0.4" PowerHigh="0.7">
      <textevent timeoffset="10" message="Bienvenue ! C'est parti, &quot;tranquille&quot;"/>
    </Warmup>
    <SteadyState Duration="120" Power="0.9" Cadence="100">
      <textevent timeoffset="0" message="Tourne vite les jambes"/>
      <textevent timeoffset="60" message="Encore une minute" duration="20"/>
    </SteadyState>
    <IntervalsT Repeat="2" OnDuration="30" OffDuration="30" OnPower="1.2" OffPower="0.5" Cadence="110" CadenceResting="85">
      <textevent timeoffset="35" message="Récupère"/>
    </IntervalsT>
    <Cooldown Duration="60" PowerLow="0.6" PowerHigh="0.4"/>
  </workout>
</workout_file>''';

    test('lecture', () {
      final w = Workout.parseZwo(zwo)!;
      expect(w.steps.map((s) => s.seconds), [300, 120, 30, 30, 30, 30, 60]);
      expect(w.steps.map((s) => s.cadence), [null, 100, 110, 85, 110, 85, null]);
      expect(w.hasCadence, isTrue);
      expect(w.messages.map((m) => m.at), [10, 300, 360, 455]);
      expect(w.messages.first.text, 'Bienvenue ! C\'est parti, "tranquille"');
      expect(w.messageAt(9), isNull);
      expect(w.messageAt(12)!.text, startsWith('Bienvenue'));
      expect(w.messageAt(20), isNull, reason: 'un message reste 10 s');
      expect(w.messageAt(375)!.text, 'Encore une minute');
      expect(w.messageAt(380), isNull);
      final run = WorkoutRun(w, 305, 200);
      expect(run.cadenceTarget, 100);
      expect(run.message!.text, 'Tourne vite les jambes');
      expect(WorkoutRun(w, 100, 100).cadenceTarget, isNull);
    });

    test('gardés à l’enregistrement, et les anciennes séances se relisent', () {
      final w = Workout.parseZwo(zwo)!;
      final back = Workout.decodeList(Workout.encodeList([w])).single;
      expect(back.steps.map((s) => s.cadence), w.steps.map((s) => s.cadence));
      expect(back.messages.map((m) => (m.at, m.text, m.seconds)), w.messages.map((m) => (m.at, m.text, m.seconds)));
      final old = Workout.fromJson({
        'name': 'Vieille',
        'steps': [
          [60, 0.5, 0.5],
        ],
      })!;
      expect(old.steps.single.cadence, isNull);
      expect(old.messages, isEmpty);
    });
  });

  group('calibration (spin down)', () {
    test('le trainer l’annonce dans ses capacités', () {
      List<int> feature(int target) => [
        0,
        0,
        0,
        0,
        ...(ByteData(4)..setUint32(0, target, Endian.little)).buffer.asUint8List(),
      ];
      expect(TrainerCaps.parse(feature((1 << 13) | (1 << 15)), null).spinDown, isTrue);
      expect(TrainerCaps.parse(feature(1 << 13), null).spinDown, isFalse);
      expect(TrainerCaps.parse(null, null).spinDown, isFalse);
      expect(const TrainerCaps().spinDown, isFalse);
    });

    test('commandes et suivi', () {
      expect(Ftms.spinDown(), [0x13, 0x01]);
      expect(Ftms.spinDown(start: false), [0x13, 0x02]);
      // Réponse : succès, vitesse basse 20,00 km/h, haute 36,00 km/h.
      final ok = SpinDownState.fromResponse([0x80, 0x13, 0x01, 0xD0, 0x07, 0x10, 0x0E])!;
      expect(ok.phase, SpinDownPhase.speedUp);
      expect(ok.targetKmh, 36);
      expect(SpinDownState.fromResponse([0x80, 0x13, 0x01])!.targetKmh, isNull);
      expect(SpinDownState.fromResponse([0x80, 0x13, 0x02])!.phase, SpinDownPhase.refused);
      expect(SpinDownState.fromResponse([0x80, 0x11, 0x01]), isNull);
      final coast = SpinDownState.fromStatus([0x14, 0x04], ok)!;
      expect(coast.phase, SpinDownPhase.coast);
      expect(coast.targetKmh, 36);
      expect(coast.finished, isFalse);
      expect(SpinDownState.fromStatus([0x14, 0x02], coast)!.phase, SpinDownPhase.success);
      expect(SpinDownState.fromStatus([0x14, 0x03], coast)!.finished, isTrue);
      expect(SpinDownState.fromStatus([0x12, 0x02], coast), isNull);
    });

    test('pas de calibration pendant une séance ou si le trainer ne la propose pas', () {
      fakeAsync((async) {
        final sent = <Uint8List>[];
        final proxy = VirtualShiftingProxy(log: (_) {});
        proxy.sendToTrainer = (c) async => sent.add(c);
        proxy.trainer.state.value = LinkState.connected;
        expect(proxy.canCalibrate, isFalse);
        proxy.trainer.caps.value = const TrainerCaps(spinDown: true);
        expect(proxy.canCalibrate, isTrue);
        proxy.startWorkout(const Workout('w', [WorkoutStep(60, 0.5)]), ftp: 200);
        expect(proxy.canCalibrate, isFalse);
        proxy.stopWorkout();
        expect(proxy.canCalibrate, isTrue);
      });
    });
  });
}
