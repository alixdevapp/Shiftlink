import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';
import 'package:shiftlink/src/outputs/hid_keyboard.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';
import 'package:shiftlink/src/whoosh_link.dart';

final _c = Guid('0000fea1-0000-1000-8000-00805f9b34fb');
Uint8List _b(List<int> v) => Uint8List.fromList(v);
const up = 'shiftUp';
const down = 'shiftDown';

/// Actions par défaut des boutons appuyés dans ces événements.
List<String> s(ControllerDriver d, List<ButtonEvent> events) => [
  for (final e in events)
    if (e.down) d.defaultClicks[e.id] ?? e.id,
];

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
  test('ThinkRider VS200', () {
    final d = ThinkRiderVs200Driver();
    expect(s(d, d.decode(_c, _b([0xf3, 0x05, 0x03, 0x01, 0xfc]))), [up]);
    expect(s(d, d.decode(_c, _b([0xf3, 0x05, 0x03, 0x00, 0xfb]))), [down]);
    expect(s(d, d.decode(_c, _b([0x01, 0x02]))), isEmpty);
  });

  test('CYCPLUS BC2 : un changement de compteur = un appui', () {
    final d = CycplusBc2Driver();
    List<int> frame(int b6, int b7) => [0, 0, 0, 0, 0, 0, b6, b7];
    expect(s(d, d.decode(_c, _b(frame(1, 1)))), isEmpty);
    expect(s(d, d.decode(_c, _b(frame(2, 1)))), [up]);
    expect(s(d, d.decode(_c, _b(frame(2, 2)))), [down]);
  });

  test('Elite Square : leviers', () {
    final d = EliteSquareDriver();
    expect(s(d, d.decode(_c, _b([0, 0, 0, 0, 0, 0, 0]))), isEmpty);
    expect(s(d, d.decode(_c, _b([0, 0, 0, 0, 0, 0, 2]))), [up]);
    expect(s(d, d.decode(_c, _b([0, 0, 0, 0, 0, 0, 0]))), isEmpty);
    expect(s(d, d.decode(_c, _b([0, 0, 0, 0, 1, 0, 0]))), [down]);
  });

  test('Shimano Di2 : canaux D-Fly', () {
    final d = ShimanoDi2Driver();
    expect(s(d, d.decode(_c, _b([0, 0, 0, 0, 0]))), isEmpty);
    expect(s(d, d.decode(_c, _b([0, 1, 0, 0, 0]))), [up]);
    expect(s(d, d.decode(_c, _b([0, 1, 1, 0, 0]))), [down]);
  });

  test('SRAM AXS : chaque message = un appui bref', () {
    final d = SramAxsDriver();
    expect(d.decode(_c, _b([1])), [press('button'), release('button')]);
    expect(d.defaultDoubles['button'], down);
    expect(d.reportsRelease, isFalse);
  });

  test('Wahoo KICKR Bike : appui puis relâchement', () {
    final d = WahooKickrBikeDriver();
    expect(s(d, d.decode(_c, _b([0x00, 0x04, 0x81]))), [up]);
    expect(s(d, d.decode(_c, _b([0x00, 0x04, 0x82]))), isEmpty);
    expect(s(d, d.decode(_c, _b([0x00, 0x04, 0x03]))), isEmpty);
    expect(s(d, d.decode(_c, _b([0x08, 0x00, 0x84]))), [down]);
  });

  group('Zwift', () {
    test('Click : 0 = appuyé, 1 = relâché', () {
      final d = ZwiftClickDriver();
      expect(s(d, d.decode(_c, _b([0x37, 0x10, 0x01]))), [up]);
      expect(s(d, d.decode(_c, _b([0x37, 0x10, 0x01]))), isEmpty);
      expect(s(d, d.decode(_c, _b([0x37, 0x08, 0x01, 0x10, 0x01]))), isEmpty);
      expect(s(d, d.decode(_c, _b([0x37, 0x08, 0x01]))), [down]);
      expect(s(d, d.decode(_c, _b([0x15]))), isEmpty);
    });

    test('Play : bouton latéral droit et gauche', () {
      final right = ZwiftPlayDriver(left: false);
      expect(s(right, right.decode(_c, _b([0x07, 0x10, 1, 0x18, 1, 0x20, 1, 0x28, 1, 0x38, 1]))), [up]);
      final left = ZwiftPlayDriver(left: true);
      expect(s(left, left.decode(_c, _b([0x07, 0x08, 1, 0x10, 1, 0x18, 1, 0x20, 1, 0x28, 1, 0x38, 1]))), [down]);
    });

    test('Ride : masque de boutons (bit à 0 = appuyé)', () {
      final d = ZwiftRideDriver(ZwiftIds.rideService);
      const none = 0x3FFFF;
      expect(s(d, d.decode(_c, _b([0x23, 0x08, ...varint(none)]))), isEmpty);
      expect(s(d, d.decode(_c, _b([0x23, 0x08, ...varint(none & ~0x01000)]))), [up]);
      expect(s(d, d.decode(_c, _b([0x23, 0x08, ...varint(none)]))), isEmpty);
      expect(s(d, d.decode(_c, _b([0x23, 0x08, ...varint(none & ~0x00200)]))), [down]);
    });

    test('Ride : palette analogique', () {
      final d = ZwiftRideDriver(ZwiftIds.rideService);
      const none = 0x3FFFF;
      // Palette droite (location=1) à 100 (zigzag 200)
      final paddle = [0x08, 0x01, 0x10, ...varint(200)];
      expect(s(d, d.decode(_c, _b([0x23, 0x08, ...varint(none), 0x1a, paddle.length, ...paddle]))), [up]);
    });
  });

  test('message Link de changement de vitesse', () {
    expect(
      WhooshLinkProtocol.encode(WhooshLinkProtocol.gearShift(1)),
      '{"MessageType":"Controls","InGameControls":{"GearShifting":"1"}}',
    );
  });

  test('le serveur Link envoie les vitesses au client connecté', () async {
    final server = WhooshLinkServer(log: (_) {});
    await server.start();
    final client = await Socket.connect(InternetAddress.loopbackIPv4, WhooshLinkProtocol.port);
    final lines = client.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    await Future.delayed(const Duration(milliseconds: 100));
    expect(server.isConnected.value, isTrue);
    expect(server.shift(-1), isTrue);
    final line = await lines.first;
    final json = jsonDecode(line) as Map<String, dynamic>;
    expect((json['InGameControls'] as Map)['GearShifting'], '-1');
    await client.close();
    await server.stop();
  });

  test('OpenBikeControl : messages de boutons et infos appli', () {
    expect(ObcProtocol.buttonState(ObcProtocol.shiftUp, true), [0x01, 0x01, 0x01]);
    expect(ObcProtocol.buttonState(ObcProtocol.shiftDown, false), [0x01, 0x02, 0x00]);
    expect(ObcProtocol.appId([0x04, 0x01, 0x05, ...'rouvy'.codeUnits, 0x00]), 'rouvy');
    expect(ObcProtocol.appId([0x01, 0x01]), isNull);
  });

  test('Clavier : codes HID des touches', () {
    expect(HidKeys.letter('a').usage, 0x04);
    expect(HidKeys.letter('w').usage, 0x1A);
    expect(HidKeys.letter('s').usage, 0x16);
    expect(HidKeys.letter('k').usage, 0x0E);
    expect(HidKeys.letter('i').usage, 0x0C);
    final labels = HidKeys.all.map((k) => k.label).toList();
    expect(labels.toSet().length, labels.length, reason: 'libellés uniques');
  });
}
