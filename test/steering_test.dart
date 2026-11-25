import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/steering_drivers.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';

Uint8List f32(double v) => (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List();

List<int> varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

void main() {
  group('seuil de direction', () {
    test('appui au-delà du seuil, relâché sous 60 %', () {
      final g = SteeringGate(10);
      expect(g.update(5), isEmpty);
      expect(g.update(12), [press('left')]);
      expect(g.update(8), isEmpty); // hystérésis
      expect(g.update(5), [release('left')]);
      expect(g.update(-15), [press('right')]);
      expect(g.update(20), [release('right'), press('left')]);
    });
  });

  group('Elite Sterzo', () {
    test('calibre sur les 10 premières mesures puis tourne', () {
      final d = EliteSterzoDriver();
      final m = EliteSterzoDriver.measurement;
      for (var i = 0; i < 10; i++) {
        expect(d.decode(m, f32(2)), isEmpty);
      }
      expect(d.decode(m, f32(double.nan)), isEmpty);
      expect(d.decode(m, f32(4)), isEmpty); // 2° : tout droit
      expect(d.decode(m, f32(15)), [press('right')]); // positif = droite pour le Sterzo
      expect(d.decode(m, f32(2)), [release('right')]);
      expect(d.decode(m, f32(-12)), [press('left')]);
      expect(d.defaultClicks['left'], 'steerLeft');
    });

    test('réponse au défi', () {
      final table = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      expect(EliteSterzoDriver.responseFor(1, table), [3, 4]);
      expect(EliteSterzoDriver.responseFor(9, table), [0x96, 0x96]);
      expect(EliteSterzoDriver.responseFor(0, null), [0x96, 0x96]);
    });
  });

  group('direction au téléphone', () {
    SteeringEstimator still(double ax, double ay, double az) {
      final e = SteeringEstimator();
      e.updateAccel(ax, ay, az);
      return e;
    }

    test('téléphone à plat : rotation autour de z', () {
      final e = still(0, 0, 9.81);
      for (var i = 0; i < 100; i++) {
        e.updateGyro(0, 0, 0.5, 0.01); // 0,5 rad/s pendant 1 s ≈ 28,6°
      }
      for (var i = 0; i < 100; i++) {
        e.updateGyro(0, 0, 0, 0.01);
      }
      expect(e.angle, closeTo(0.5 * 180 / pi, 2));
    });

    test('téléphone debout : rotation autour de y, même résultat', () {
      final e = still(0, 9.81, 0);
      for (var i = 0; i < 100; i++) {
        e.updateGyro(0, -0.5, 0, 0.01); // vers la droite
      }
      for (var i = 0; i < 100; i++) {
        e.updateGyro(0, 0, 0, 0.01);
      }
      expect(e.angle, closeTo(-0.5 * 180 / pi, 2));
    });

    test('le biais du gyroscope est appris à l’arrêt', () {
      final e = still(0, 0, 9.81);
      for (var i = 0; i < 3000; i++) {
        e.updateGyro(0, 0, 0.01, 0.01); // dérive lente
      }
      expect(e.bias, closeTo(0.01, 0.002));
      expect(e.angle.abs(), lessThan(5));
    });
  });

  group('Zwift Click v2', () {
    test('message d’ouverture et boutons + / −', () {
      final d = ZwiftClickV2Driver(ZwiftIds.rideService);
      expect(d.startCommand, [...ZwiftIds.rideOn, 0x02, 0x03]);
      final c = Guid('0000fea1-0000-1000-8000-00805f9b34fb');
      const none = 0x3FFFF;
      Uint8List b(int map) => Uint8List.fromList([0x23, 0x08, ...varint(map)]);
      expect(d.decode(c, b(none & ~0x01000)), [press('shiftUpRight')]);
      expect(d.defaultClicks['shiftUpRight'], 'shiftUp');
      expect(d.decode(c, b(none & ~0x00100)), [release('shiftUpRight'), press('shiftUpLeft')]);
      expect(d.defaultClicks['shiftUpLeft'], 'shiftDown');
    });
  });
}
