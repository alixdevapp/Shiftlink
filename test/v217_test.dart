import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/steering_drivers.dart';
import 'package:shiftlink/src/controllers/tacx_neo_bike.dart';
import 'package:shiftlink/src/sensors/headwind.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  test('Tacx NEO Bike : reconnu par son nom, pas les trainers NEO', () {
    expect(TacxNeoBikeDriver.matchesName('TACX NEO BIKE 12345'), isTrue);
    expect(TacxNeoBikeDriver.matchesName('NEO BIKE PLUS 0042'), isTrue);
    expect(TacxNeoBikeDriver.matchesName('TACX NEO 2T 12345'), isFalse);
    expect(TacxNeoBikeDriver.matchesName('KICKR BIKE 1234'), isFalse);
  });

  test('Tacx NEO Bike : trames de vitesse et de boutons', () {
    expect(TacxNeoBikeFrames.gear(b([0x03, 50, 15])), (chainring: 50, sprocket: 15));
    expect(TacxNeoBikeFrames.gear(b([0x02, 17])), (chainring: null, sprocket: 17));
    expect(TacxNeoBikeFrames.gear(b([0x00])), isNull);
    expect(TacxNeoBikeFrames.gear(b([0x03, 50])), isNull);
    expect(TacxNeoBikeFrames.buttons(b([0x03, 0x80, 0x00])), (true, false));
    expect(TacxNeoBikeFrames.teethTable(b([0x20, 0x05, 0x01, 3, 11, 13, 15]), 0x05), [11, 13, 15]);
    expect(TacxNeoBikeFrames.teethTable(b([0x20, 0x05, 0x02, 3, 11, 13, 15]), 0x05), isNull);
  });

  test('Tacx NEO Bike : un changement de vitesse devient des appuis', () {
    final d = TacxNeoBikeDriver();
    final gears = Guid(TacxNeoBikeDriver.gears.str);
    expect(d.decode(gears, b([0x03, 34, 17])), isEmpty); // position de départ
    expect(d.decode(gears, b([0x02, 15])), [press('rearHarder'), release('rearHarder')]);
    expect(d.decode(gears, b([0x01, 50])), [press('frontHarder'), release('frontHarder')]);
    // Avec la liste des pignons, un saut de deux pignons fait deux appuis.
    d.decode(Guid(TacxNeoBikeDriver.controlPoint.str), b([0x20, 0x05, 0x01, 4, 11, 13, 15, 17]));
    expect(d.decode(gears, b([0x02, 11])).where((e) => e.down).length, 2);
    for (final id in d.defaultClicks.keys) {
      expect(d.buttons.map((x) => x.id), contains(id));
    }
  });

  test('Tacx NEO Bike : boutons appuyés puis relâchés', () {
    final d = TacxNeoBikeDriver();
    final c = Guid(TacxNeoBikeDriver.buttonsChar.str);
    expect(d.decode(c, b([0x01, 0x80])), [press('leftButton')]);
    expect(d.decode(c, b([0x01, 0x80])), isEmpty);
    expect(d.decode(c, b([0x03, 0x00, 0x00])), [release('leftButton')]);
  });

  test('Elite Rizer : réponses et pente rapportée', () {
    expect(EliteRizerDriver.ackCode(b([0x80, 0x0a, 0x02])), EliteRizerDriver.ackDone);
    expect(EliteRizerDriver.ackCode(b([0x80, 0x0b, 0x02])), isNull);
    expect(EliteRizerDriver.gradeReported(b([0x00, 110])), 5.0);
    expect(EliteRizerDriver.gradeReported(b([0x00, 90])), -5.0);
    final d = EliteRizerDriver();
    d.decode(Guid(EliteRizerDriver.reportedIncline.str), b([0x00, 104]));
    expect(d.reportedGrade.value, 2.0);
  });

  test('Headwind : rampe réglable sans hésitation entre deux crans', () {
    expect(Headwind.rampPercent(100, 100, 170), 0);
    expect(Headwind.rampPercent(170, 100, 170), 100);
    expect(Headwind.rampPercent(135, 100, 170), 50);
    expect(Headwind.nextRampLevel(50, 0), 50);
    expect(Headwind.nextRampLevel(54, 50), 50);
    expect(Headwind.nextRampLevel(58, 50), 60);
    expect(Headwind.nextRampLevel(0, 10), 0);
    expect(FanMode.heartRateStrap.hasRamp, isTrue);
    expect(FanMode.heartRate.hasRamp, isFalse);
  });
}
