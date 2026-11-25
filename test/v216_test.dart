import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';

Uint8List frame(int b1, int buttons) => Uint8List.fromList([0xAA, b1, buttons, (0xAA + b1 + buttons) & 0xFF]);

void main() {
  test('CYCPLUS T7 : reconnue par son nom', () {
    expect(CycplusT7Driver.matchesName('T7H-L1234'), isTrue);
    expect(CycplusT7Driver.matchesName('T7H-R1234'), isTrue);
    expect(CycplusT7Driver.matchesName('CYCPLUS BC2'), isFalse);
  });

  test('CYCPLUS T7 : trames, côté et somme de contrôle', () {
    expect(CycplusT7Driver.parse(frame(0x12, 0x01)), (false, 0x01));
    expect(CycplusT7Driver.parse(frame(0x34, 0x82)), (true, 0x02));
    final bad = frame(0x12, 0x01)..[3] ^= 0xFF;
    expect(CycplusT7Driver.parse(bad), isNull);
    expect(CycplusT7Driver.parse(Uint8List.fromList([0xAA, 1, 2])), isNull);
  });

  test('CYCPLUS T7 : appui, répétition ignorée, relâché', () {
    final d = CycplusT7Driver();
    final c = Guid(CycplusT7Driver.characteristic.str);
    final down = d.decode(c, frame(0x05, 0x81));
    expect(down, isNotEmpty);
    expect(d.decode(c, frame(0x05, 0x81)), isEmpty); // la trame se répète tant qu'on appuie
    expect(d.decode(c, frame(0x05, 0x80)), isNotEmpty); // relâché
    for (final id in d.defaultClicks.keys) {
      expect(d.buttons.map((b) => b.id), contains(id));
    }
  });

  test('Rampida : sa propre ligne, en OpenBikeControl', () {
    expect(TargetApp.pickable, contains(TargetApp.rampida));
    expect(TargetApp.rampida.transport, Transport.obc);
  });
}
