// 2.9.3 : Zwift Ride V2, Zwift Play firmware 2, WHEELTOP EDS, Elite Rizer, KICKR Climb.
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/registry.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';
import 'package:shiftlink/src/controllers/steering_drivers.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';
import 'package:shiftlink/src/sensors/incline.dart';

Uint8List _b(List<int> v) => Uint8List.fromList(v);

ScanResult _scan({String name = '', Map<int, List<int>> maker = const {}, List<Guid> services = const []}) =>
    ScanResult(
      device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
      advertisementData: AdvertisementData(
        advName: name,
        txPowerLevel: null,
        appearance: null,
        connectable: true,
        manufacturerData: maker,
        serviceData: const {},
        serviceUuids: services,
      ),
      rssi: -60,
      timeStamp: DateTime(2026),
    );

List<String> _down(List<ButtonEvent> events) => [
  for (final e in events)
    if (e.down) e.id,
];

void main() {
  group('Zwift', () {
    test('Ride V2 reconnue à son firmware 1.3 ou plus', () {
      expect(ZwiftRideDriver.isV2Firmware('1.2.0'), isFalse);
      expect(ZwiftRideDriver.isV2Firmware('1.3.0'), isTrue);
      expect(ZwiftRideDriver.isV2Firmware('1.3.0.24'), isTrue);
      expect(ZwiftRideDriver.isV2Firmware('2.0'), isTrue);
      expect(ZwiftRideDriver.isV2Firmware(null), isFalse);
      expect(ZwiftRideDriver.isV2Firmware('abc'), isFalse);
      final d = ZwiftRideDriver(ZwiftIds.rideService);
      expect(d.label, 'Zwift Ride');
      d.onFirmware('1.3.1');
      expect(d.label, 'Zwift Ride V2');
      expect(d.typeId, 'zwiftRide'); // mêmes réglages de boutons que la V1
      expect(d.missingServiceHint, contains('Zwift'));
    });

    test('la Click v2 n’est pas prise pour une Ride V2', () {
      final d = ZwiftClickV2Driver(ZwiftIds.rideService)..onFirmware('1.3.0');
      expect(d.isV2, isFalse);
      expect(ZwiftClickV2RightDriver(ZwiftIds.rideService).missingServiceHint, isNull);
    });

    test('Play firmware 2 : type 0x0E, format Ride', () {
      final m = identify(_scan(maker: {ZwiftIds.manufacturerId: [0x0E]}, services: [ZwiftIds.rideService]));
      final d = m!.driver!;
      expect(d, isA<ZwiftPlayFw2Driver>());
      const none = 0x3FFFF;
      final v = <int>[];
      var x = none & ~0x01000;
      while (x >= 0x80) {
        v.add((x & 0x7f) | 0x80);
        x >>= 7;
      }
      v.add(x);
      expect(_down(d.decode(ZwiftIds.asyncChar, _b([0x23, 0x08, ...v]))), ['shiftUpRight']);
      expect(d.defaultClicks['shiftUpRight'], 'shiftUp');
    });
  });

  group('WHEELTOP EDS', () {
    test('reconnue par son annonce, sous ses deux formes', () {
      // Les deux premiers octets lus comme identifiant constructeur (0x0f07).
      final a = identify(_scan(maker: {0x0f07: [0x00, 0x14, 0x55, 0x6a, 0x84, 0x37, 1, 2, 1, 0x24]}));
      expect(a!.driver, isA<WheeltopEdsDriver>());
      expect((a.driver! as WheeltopEdsDriver).type, WheeltopEdsType.ox);
      // Ou l'annonce entière dans les données.
      final b = WheeltopEdsDriver.typeFromAdvertisement({
        0x1234: [0x07, 0x0f, 0x00, 0x14, 0x55, 0x6a, 0x84, 0x38],
      });
      expect(b, WheeltopEdsType.txRight);
      expect(WheeltopEdsDriver.typeFromAdvertisement({0x0f07: [0x00, 0x14]}), isNull);
    });

    test('trames OX (xor) et TX (somme), appui et relâchement', () {
      final d = WheeltopEdsDriver(WheeltopEdsType.ox);
      final c = WheeltopEdsDriver.characteristic;
      expect(d.decode(c, _b([0x04, 0x02, 0x06])), [press('top')]);
      expect(d.decode(c, _b([0x04, 0x04, 0x00])), isEmpty); // répétition pendant l'appui
      expect(d.decode(c, _b([0x04, 0x0a, 0x0e])), [release('top')]);
      // TX : 04 type code somme.
      expect(d.decode(c, _b([0x04, 0x38, 0x01, 0x3d])), [press('bottom')]);
      expect(d.decode(c, _b([0x04, 0x38, 0x09, 0x45])), [release('bottom')]);
      // Interrupteur sur T.
      expect(d.decode(c, _b([0x04, 0x06, 0x02])), [press('topFine')]);
      expect(d.decode(c, _b([0x04, 0x0a, 0x0e])), [release('topFine')]);
      // Trame abîmée ou d'état : ignorée.
      expect(d.decode(c, _b([0x04, 0x02, 0x07])), isEmpty);
      expect(d.decode(c, _b([0x04, 0x38, 0x10, 0x4c])), isEmpty);
      expect(d.defaultClicks, {'top': 'shiftUp', 'bottom': 'shiftDown'});
    });
  });

  group('Elite Rizer', () {
    test('reconnu à son nom, pas pris pour un Elite Square', () {
      final m = identify(_scan(name: 'RIZER 1234', services: [EliteRizerDriver.service]));
      expect(m!.driver, isA<EliteRizerDriver>());
    });

    test('direction : zéro puis angle (positif = droite côté Rizer)', () {
      final d = EliteRizerDriver();
      List<int> f(double v) => (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List();
      for (var i = 0; i < 10; i++) {
        expect(d.decode(EliteRizerDriver.measurement, _b(f(2))), isEmpty);
      }
      expect(d.decode(EliteRizerDriver.measurement, _b(f(20))), [press('right')]);
      expect(d.decode(EliteRizerDriver.measurement, _b(f(2))), [release('right')]);
      expect(d.decode(EliteRizerDriver.measurement, _b(f(-15))), [press('left')]);
    });

    test('commande de pente : 0x0a puis dixièmes de % en int16', () {
      expect(rizerGradeCommand(0), [0x0a, 0x00, 0x00]);
      expect(rizerGradeCommand(5), [0x0a, 0x32, 0x00]);
      expect(rizerGradeCommand(-10), [0x0a, 0x9c, 0xff]);
      expect(rizerGradeCommand(30), [0x0a, 0xc8, 0x00]); // borné à 20 %
    });
  });

  group('KICKR Climb', () {
    test('commande de pente : 0x66 puis centièmes de % en int16', () {
      expect(climbGradeCommand(0), [0x66, 0x00, 0x00]);
      expect(climbGradeCommand(0.5), [0x66, 0x32, 0x00]);
      expect(climbGradeCommand(10), [0x66, 0xe8, 0x03]);
      expect(climbGradeCommand(19), [0x66, 0x6c, 0x07]);
      expect(climbGradeCommand(25), [0x66, 0x6c, 0x07]); // borné
      expect(climbGradeCommand(-10), [0x66, 0x18, 0xfc]);
    });

    test('suivi : demi-pourcent, pas de doublon, retour à plat', () {
      final f = InclineFollower();
      expect(f.next(null), isNull); // rien à faire au départ
      expect(f.next(3.2), 3.0);
      f.sent(3.0);
      expect(f.next(3.1), isNull);
      expect(f.next(3.3), 3.5);
      f.sent(3.5);
      expect(f.next(30), 19.0);
      f.sent(19.0);
      expect(f.next(null), 0.0);
      f.sent(0.0);
      expect(f.next(null), isNull);
    });

    test('un échec d’envoi est retenté', () {
      final f = InclineFollower();
      expect(f.next(4), 4.0);
      expect(f.next(4), 4.0); // pas marqué envoyé
    });
  });
}
