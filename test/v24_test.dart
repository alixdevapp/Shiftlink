import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/ride/fit_writer.dart';
import 'package:shiftlink/src/ride/ride_history.dart';
import 'package:shiftlink/src/ui/help_pages.dart';

void main() {
  final t0 = DateTime(2026, 11, 7, 18, 30);
  List<RideSample> samples() => [
    for (var i = 0; i < 120; i++)
      RideSample(
        time: t0.add(Duration(seconds: i)),
        power: i < 10 ? 0 : 150 + (i % 2) * 100,
        cadence: i < 10 ? null : 90,
        heartRate: 130,
        distance: i * 8.0,
      ),
  ];

  test('résumé : moyennes sans les zéros, maximum, durée', () {
    final s = RideSummary.fromSamples(samples(), 952, '/x/a.fit');
    expect(s.duration, const Duration(seconds: 119));
    expect(s.avgPower, 200);
    expect(s.maxPower, 250);
    expect(s.avgCadence, 90);
    expect(s.avgHeartRate, 130);
    final back = RideSummary.fromJson(s.toJson(), '/x/a.fit')!;
    expect(back.avgPower, 200);
    expect(back.start, t0);
  });

  test('historique : liste triée, ancienne sortie sans résumé, suppression', () async {
    final dir = await Directory.systemTemp.createTemp('rides');
    final h = RideHistory(dir);
    final a = File('${dir.path}/a.fit')..writeAsBytesSync([1]);
    File('${dir.path}/old.fit').writeAsBytesSync([1]);
    await h.save(RideSummary.fromSamples(samples(), 952, a.path));
    final list = await h.list();
    expect(list, hasLength(2));
    final withSummary = list.firstWhere((r) => r.fitPath == a.path);
    expect(withSummary.avgPower, 200);
    expect(list.firstWhere((r) => r.fitPath != a.path).duration, Duration.zero);
    await h.delete(withSummary);
    expect(a.existsSync(), isFalse);
    expect(File(RideHistory.summaryPath(a.path)).existsSync(), isFalse);
    expect(await h.list(), hasLength(1));
    await dir.delete(recursive: true);
  });

  test('aide : listes non vides, mots avec synonymes', () {
    expect(CompatibilityPage.items().length, greaterThan(20));
    expect(WordsPage.words().every((w) => w.$1.isNotEmpty && w.$2.isNotEmpty && w.$3.isNotEmpty), isTrue);
  });
}
