import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/ride/fit_writer.dart';
import 'package:shiftlink/src/ride/ride_recorder.dart';

void main() {
  test('CRC FIT : valeur connue', () {
    // Un fichier FIT complet a un CRC final nul quand on l'inclut dans le calcul.
    final bytes = FitWriter.encode([
      RideSample(time: DateTime.utc(2026, 11, 6, 20), power: 200, cadence: 90, heartRate: 140, speed: 8, distance: 0),
      RideSample(
        time: DateTime.utc(2026, 11, 6, 20, 0, 1),
        power: 210,
        cadence: 91,
        heartRate: 141,
        speed: 8,
        distance: 8,
      ),
    ]);
    expect(FitWriter.crc(bytes), 0);
    expect(String.fromCharCodes(bytes.sublist(8, 12)), '.FIT');
    expect(FitWriter.crc(bytes.sublist(0, 14)), 0);
  });

  test('enregistreur : distance cumulée et fichier', () {
    var t = DateTime.utc(2026, 11, 6, 20);
    final r = RideRecorder(read: () => (power: 200, cadence: 90, heartRate: null, speedKmh: 36), now: () => t);
    r.recording.value = true;
    for (var i = 0; i < 120; i++) {
      r.tick();
      t = t.add(const Duration(seconds: 1));
    }
    r.dispose();
    expect(r.distance.value, closeTo(1190, 1));
    final out = File('${Directory.systemTemp.path}/shiftlink_test.fit')..writeAsBytesSync(FitWriter.encode(r.samples));
    expect(out.lengthSync(), greaterThan(1000));
  });
}
