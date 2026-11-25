import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controller_manager.dart' show LinkState;
import 'package:shiftlink/src/net/update_check.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/workout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('mise à jour', () {
    test('compare les versions', () {
      expect(compareVersions('2.13.0', '2.12.4'), greaterThan(0));
      expect(compareVersions('v2.12.10', '2.12.9'), greaterThan(0));
      expect(compareVersions('2.12.4', '2.12.4+82'), 0);
      expect(compareVersions('2.9', '2.12.0'), lessThan(0));
    });

    test('lit la dernière release et préfère l’APK', () {
      const body =
          '{"tag_name":"v2.14.0","html_url":"https://github.com/a/b/releases/tag/v2.14.0",'
          '"assets":[{"name":"notes.txt","browser_download_url":"https://github.com/a/b/x.txt"},'
          '{"name":"ShiftLink-2.14.0.apk","browser_download_url":"https://github.com/a/b/releases/download/v2.14.0/ShiftLink-2.14.0.apk"}]}';
      final u = parseLatestRelease(body, '2.13.0')!;
      expect(u.version, '2.14.0');
      expect(u.url, endsWith('ShiftLink-2.14.0.apk'));
    });

    test('rien si même version, pré-version, lien étranger ou réponse illisible', () {
      expect(parseLatestRelease('{"tag_name":"2.13.0","html_url":"https://github.com/a/b"}', '2.13.0'), isNull);
      expect(parseLatestRelease('{"tag_name":"3.0.0","prerelease":true,"html_url":"https://github.com/a"}', '2.13.0'), isNull);
      expect(parseLatestRelease('{"tag_name":"3.0.0","html_url":"https://evil.example/x"}', '2.13.0'), isNull);
      expect(parseLatestRelease('pas du json', '2.13.0'), isNull);
    });
  });

  group('séance au cardio', () {
    test('le régulateur baisse vite si le cœur monte trop, monte doucement sinon', () {
      final r = HeartRateErg(low: 120, high: 135, watts: 150, minWatts: 60, maxWatts: 200);
      for (var i = 0; i < 14; i++) {
        r.tick(110);
      }
      expect(r.watts, 150, reason: 'pas de correction avant 15 s');
      r.tick(110);
      expect(r.watts, 155);
      for (var i = 0; i < 5; i++) {
        r.tick(145);
      }
      expect(r.watts, 140, reason: '5 s suffisent quand le cœur dépasse de plus de 5 bpm');
      for (var i = 0; i < 30; i++) {
        r.tick(128);
      }
      expect(r.watts, 140, reason: 'dans le milieu de la zone : on ne touche à rien');
      for (var i = 0; i < 60; i++) {
        r.tick(null);
      }
      expect(r.watts, 140, reason: 'sans cardio, les watts restent fixes');
    });

    test('les watts restent entre les bornes', () {
      final r = HeartRateErg(low: 100, high: 110, watts: 70, minWatts: 60, maxWatts: 200);
      for (var i = 0; i < 100; i++) {
        r.tick(170);
      }
      expect(r.watts, 60);
    });

    test('les séances au cardio fournies ont une zone et un bloc au cardio', () {
      final hr = builtInWorkouts.where((w) => w.hrRange != null).toList();
      expect(hr.length, 2);
      for (final w in hr) {
        expect(w.steps.where((s) => s.byHeartRate), hasLength(1));
      }
      expect(hr.first.hrTarget(190), (114, 133));
    });

    test('le proxy suit le cœur pendant le bloc au cardio', () {
      fakeAsync((async) {
        final p = VirtualShiftingProxy(log: (_) {});
        final sent = <Uint8List>[];
        p.sendToTrainer = (b) async => sent.add(b);
        p.trainer.state.value = LinkState.connected;
        var bpm = 150;
        p.heartRate = () => bpm;
        const w = Workout(
          'test',
          [WorkoutStep(10, 0.5), WorkoutStep.heartRate(600, 0.6)],
          hrRange: (0.6, 0.7),
        );
        expect(p.startWorkout(w, ftp: 200, hrMax: 200), isTrue);
        // Cadence 90, 100 W.
        p.handleBikeData(Uint8List.fromList([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0x64, 0x00]));
        async.elapse(const Duration(seconds: 10));
        expect(p.workout.value!.followsHeart, isTrue);
        final start = p.workout.value!.watts;
        async.elapse(const Duration(seconds: 20));
        expect(p.workout.value!.watts, lessThan(start), reason: '150 bpm > 140 visé : les watts baissent');
        bpm = 0;
        async.elapse(const Duration(seconds: 25));
        expect(p.workout.value!.noHeartRate, isTrue);
        expect(sent, isNotEmpty);
        expect(sent.last, isNot(Ftms.simulation(gradePercent: 0)));
        p.stopWorkout();
      });
    });
  });
}
