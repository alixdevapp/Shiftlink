// 2.11 : ce qui manquait face à BikeControl 7.5.
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controller_manager.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/registry.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';
import 'package:shiftlink/src/outputs/zwift_ride_emulator.dart';
import 'package:shiftlink/src/riders.dart';
import 'package:shiftlink/src/trainer/fec.dart' show indoorBikeData;
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/gears.dart';
import 'package:shiftlink/src/trainer/proxy.dart';
import 'package:shiftlink/src/trainer/trainer_client.dart';
import 'package:shiftlink/src/trainer/wahoo_cps.dart';

ScanResult _scan({String name = '', List<Guid> services = const []}) => ScanResult(
  device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
  advertisementData: AdvertisementData(
    advName: name,
    txPowerLevel: null,
    appearance: null,
    connectable: true,
    manufacturerData: const {},
    serviceData: const {},
    serviceUuids: services,
  ),
  rssi: -60,
  timeStamp: DateTime(2026),
);

Uint8List _b(List<int> v) => Uint8List.fromList(v);
final _c = Guid('2a19');

/// Trame FTMS avec puissance et cadence.
Uint8List _bike({required int power, required double cadence}) =>
    indoorBikeData(BikeData(speedKmh: 30, cadence: cadence, power: power));

VirtualShiftingProxy _proxy(List<Uint8List> sent) {
  final p = VirtualShiftingProxy(log: (_) {});
  p.sendToTrainer = (c) async => sent.add(c);
  p.trainer.state.value = LinkState.connected;
  return p;
}

int? _targetWatts(Uint8List c) =>
    c.isNotEmpty && c[0] == Ftms.opSetTargetPower ? ByteData.sublistView(c).getInt16(1, Endian.little) : null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Capteur de puissance Shimano', () {
    test('un pédalier FC-R8100-P n’est pas pris pour un Di2', () {
      expect(identify(_scan(name: 'FCR8100P 12345', services: [ShimanoDi2Driver.serviceAlt])), isNull);
      expect(
        identify(_scan(name: 'Shimano', services: [ShimanoDi2Driver.serviceAlt, cyclingPowerService])),
        isNull,
      );
    });

    test('un vrai Di2 reste un Di2', () {
      final m = identify(_scan(name: 'RDR7150 1234', services: [ShimanoDi2Driver.serviceAlt]));
      expect(m!.driver, isA<ShimanoDi2Driver>());
    });
  });

  group('Shimano Di2 : premier appui', () {
    test('la première trame d’une connexion compte comme un appui', () {
      final d = ShimanoDi2Driver();
      final events = d.decode(_c, _b([0x20, 0xF1, 0xF0, 0xF0, 0xF0]));
      expect(events.where((e) => e.down).map((e) => e.id), ['ch1']);
    });

    test('plus tard, la première trame ne donne que l’état', () {
      final d = ShimanoDi2Driver();
      expect(d.decode(_c, _b([0x35, 0xF3, 0xF0, 0xF0, 0xF0])), isEmpty);
      expect(d.decode(_c, _b([0x36, 0xF4, 0xF0, 0xF0, 0xF0])).where((e) => e.down).map((e) => e.id), ['ch1']);
    });
  });

  group('Magene Onelap Key', () {
    test('reconnue à son nom', () {
      expect(identify(_scan(name: 'Onelap Key_12224'))!.driver, isA<OnelapKeyDriver>());
      expect(identify(_scan(name: 'Onelap Key'))!.driver, isA<OnelapKeyDriver>());
      expect(identify(_scan(name: 'Onelap QED')), isNull);
    });

    test('clic : appui et relâchement du bon bouton', () {
      final d = OnelapKeyDriver();
      // Masque de clic 0x04 = haut.
      expect(d.decode(_c, _b([0x8b, 0xf5, 0x10, 0xe5, 0x03, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00])), [
        press('up'),
        release('up'),
      ]);
      expect(d.defaultClicks['up'], 'shiftUp');
      expect(d.defaultClicks['down'], 'shiftDown');
    });

    test('appui long : tenu jusqu’à la trame suivante', () {
      final d = OnelapKeyDriver();
      expect(d.decode(_c, _b([0x8b, 0xf5, 0x10, 0xe5, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04])), [press('up')]);
      expect(d.decode(_c, _b([0x8b, 0xf5, 0x10, 0xe5, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00])), [release('up')]);
    });

    test('trame inconnue : rien, mais un appui long en cours se termine', () {
      final d = OnelapKeyDriver();
      d.decode(_c, _b([0x8b, 0xf5, 0x10, 0xe5, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10]));
      expect(d.decode(_c, _b([0x01, 0x02])), [release('down')]);
      expect(d.decode(_c, _b([0x8b, 0xf5, 0x10, 0xe5, 0x03, 0x1F, 0x00, 0x00, 0x04, 0x00, 0x00])), isEmpty);
    });
  });

  group('Ancien protocole Wahoo', () {
    test('commandes traduites depuis FTMS', () {
      expect(WahooCps.fromFtms(Ftms.targetPower(250)), [
        _b([0x42, 250, 0]),
      ]);
      final sim = WahooCps.fromFtms(Ftms.simulation(gradePercent: 5), kg: 80);
      expect(sim.map((m) => m[0]), [WahooCps.opSim, WahooCps.opWindSpeed, WahooCps.opGrade]);
      // Poids 80 kg → 8000 ; pente +5 % → (0,05 + 1) × 32768 = 34406.
      expect(sim[0].sublist(1, 3), [8000 & 0xFF, 8000 >> 8]);
      expect(ByteData.sublistView(sim[2]).getUint16(1, Endian.little), 34406);
      expect(ByteData.sublistView(WahooCps.grade(0)).getUint16(1, Endian.little), 32768);
      expect(WahooCps.unlock(), [0x20, 0xEE, 0xFC]);
    });

    test('mesures de puissance : watts, cadence et vitesse', () {
      final d = CyclingPowerDecoder();
      // Drapeaux : tours de roue (0x10) + tours de pédalier (0x20).
      List<int> m(int watts, int wheelRevs, int wheelT, int crankRevs, int crankT) {
        final b = ByteData(14);
        b.setUint16(0, 0x30, Endian.little);
        b.setInt16(2, watts, Endian.little);
        b.setUint32(4, wheelRevs, Endian.little);
        b.setUint16(8, wheelT, Endian.little);
        b.setUint16(10, crankRevs, Endian.little);
        b.setUint16(12, crankT, Endian.little);
        return b.buffer.asUint8List();
      }

      d.add(m(200, 100, 0, 50, 0));
      d.add(m(210, 104, 2048, 51, 682)); // 4 tours de roue en 1 s, 1 tour de pédale en 2/3 s
      expect(d.power, 210);
      expect(d.cadence, closeTo(90, 0.5));
      expect(d.speedKmh, closeTo(4 * 2.105 * 3.6, 0.1));
      final parsed = BikeData.parse(d.bikeData);
      expect(parsed.power, 210);
    });

    test('un trainer, pas un simple capteur de puissance', () {
      expect(looksLikeWahooTrainer('KICKR 1A2B'), isTrue);
      expect(looksLikeWahooTrainer('Saris H2 1234'), isTrue);
      expect(looksLikeWahooTrainer('CycleOps Hammer'), isTrue);
      expect(looksLikeWahooTrainer('ASSIOMA 1234'), isFalse);
      expect(looksLikeWahooTrainer('KICKR HEADWIND'), isFalse);
    });
  });

  group('Power Lock', () {
    test('garde les watts du moment, même quand l’appli change la pente', () {
      final sent = <Uint8List>[];
      final p = _proxy(sent);
      p.handleControlPoint(Ftms.simulation(gradePercent: 1));
      for (var i = 0; i < 3; i++) {
        p.handleBikeData(_bike(power: 212, cadence: 90));
      }
      expect(p.togglePowerLock(), isTrue);
      expect(p.powerLock.value, 210);
      expect(_targetWatts(sent.last), 210);
      sent.clear();
      p.handleControlPoint(Ftms.simulation(gradePercent: 8));
      expect(sent, isEmpty, reason: 'la montée ne change pas les watts');
      expect(p.appGrade.value, 8);
      expect(p.adjustPowerLock(10), isTrue);
      expect(_targetWatts(sent.last), 220);
    });

    test('se relâche quand on arrête de pédaler, et la pente revient', () {
      final sent = <Uint8List>[];
      final p = _proxy(sent);
      var released = 0;
      p.onPowerLockAutoRelease = () => released++;
      p.handleControlPoint(Ftms.simulation(gradePercent: 4));
      p.handleBikeData(_bike(power: 180, cadence: 85));
      p.togglePowerLock();
      for (var i = 0; i < 6; i++) {
        p.handleBikeData(_bike(power: 0, cadence: 10));
      }
      final t = DateTime.now();
      p.checkPowerLockAt(t.add(const Duration(seconds: 1)));
      expect(p.powerLock.value, isNotNull);
      p.checkPowerLockAt(t.add(const Duration(seconds: 4)));
      expect(p.powerLock.value, isNull);
      expect(released, 1);
      expect(p.mode, TrainerMode.simulation);
    });

    test('réglage « relâcher à l’arrêt » désactivé : le verrou reste', () {
      final p = _proxy([]);
      p.configure(const ShiftingConfig(powerLockRelease: false));
      p.handleBikeData(_bike(power: 180, cadence: 85));
      p.togglePowerLock();
      p.handleBikeData(_bike(power: 0, cadence: 0));
      p.checkPowerLockAt(DateTime.now().add(const Duration(seconds: 10)));
      expect(p.powerLock.value, isNotNull);
    });

    test('l’appli passe en ERG : le verrou s’efface', () {
      final p = _proxy([]);
      p.handleBikeData(_bike(power: 150, cadence: 85));
      p.togglePowerLock();
      p.handleControlPoint(Ftms.targetPower(200));
      expect(p.powerLock.value, isNull);
      expect(p.ergTarget, 200);
    });

    test('réglage gardé dans la configuration', () {
      final c = ShiftingConfig.decode(const ShiftingConfig(powerLockRelease: false).encode());
      expect(c.powerLockRelease, isFalse);
      expect(const ShiftingConfig().powerLockRelease, isTrue);
    });
  });

  group('Vitesse virtuelle', () {
    test('à plat, 200 W stabilisent autour de 33 km/h', () {
      var v = 0.0;
      for (var i = 0; i < 300; i++) {
        v = nextVirtualSpeed(v, 200, 0, 85, 1);
      }
      expect(v, inInclusiveRange(30, 36));
      // Et le même modèle redonne bien ~200 W à cette vitesse.
      expect(estimatePower(v, 85), closeTo(200, 10));
    });

    test('en montée on va moins vite, en descente on roule sans pédaler', () {
      var up = 25.0, down = 25.0;
      for (var i = 0; i < 120; i++) {
        up = nextVirtualSpeed(up, 200, 8, 85, 1);
        down = nextVirtualSpeed(down, 0, -6, 85, 1);
      }
      expect(up, lessThan(15));
      expect(down, greaterThan(35));
    });

    test('sans pédaler sur le plat, on finit par s’arrêter', () {
      var v = 30.0;
      for (var i = 0; i < 600; i++) {
        v = nextVirtualSpeed(v, 0, 0, 85, 1);
      }
      expect(v, lessThan(3));
    });

    test('le proxy calcule la vitesse depuis la puissance, pas la roue du trainer', () {
      final p = _proxy([]);
      final t = DateTime(2026);
      for (var i = 0; i < 120; i++) {
        p.virtualSpeedSample(const BikeData(speedKmh: 12, power: 250), t.add(Duration(seconds: i)));
      }
      expect(p.virtualSpeedKmh.value, greaterThan(30));
    });
  });

  group('Manette Zwift Ride (émulée)', () {
    test('masque inversé : rien d’appuyé', () {
      expect(ZwiftRideEmulator.idle, [0x23, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]);
    });

    test('vitesse + = bouton droit « haut »', () {
      final bit = ZwiftRideEmulator.bits[ZwiftRideEmulator.actions['shiftUp']]!;
      final m = ZwiftRideEmulator.keypad(bit);
      // On relit le varint : le bit du bouton est à 0, les autres à 1.
      var v = 0;
      for (var i = 2, shift = 0; i < m.length; i++, shift += 7) {
        v |= (m[i] & 0x7F) << shift;
      }
      expect(v & bit, 0);
      expect(v | bit, 0xFFFFFFFF);
    });
  });
}
