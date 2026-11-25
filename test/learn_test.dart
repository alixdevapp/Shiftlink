import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/learned_driver.dart';

void main() {
  const ch = '0000fff1-0000-1000-8000-00805f9b34fb';
  final subs = [Subscription(Guid('fff0'), Guid('fff1'))];

  test('appui + relâchement, avec un compteur qui change : appris et décodé', () {
    final l = ControllerLearner()
      ..startQuiet()
      ..endQuiet()
      ..startButton();
    for (var i = 0; i < 3; i++) {
      l.add(ch, [0x01, i, 0x10]); // + appuyé, compteur i
      l.add(ch, [0x01, i, 0x00]); // relâché
    }
    expect(l.finishButton('b1', 'Bouton +'), isNull);
    l.startButton();
    for (var i = 0; i < 3; i++) {
      l.add(ch, [0x01, 9 + i, 0x20]);
      l.add(ch, [0x01, 9 + i, 0x00]);
    }
    expect(l.finishButton('b2', 'Bouton −'), isNull);
    final p = LearnedProfile.fromJson(l.profile('Wheeltop', subs).toJson());
    final d = LearnedDriver(p);
    expect(d.reportsRelease, isTrue);
    expect(d.defaultClicks, {'b1': 'shiftUp', 'b2': 'shiftDown'});
    final g = Guid(ch);
    expect(d.decode(g, Uint8List.fromList([0x01, 42, 0x10])), [press('b1')]);
    expect(d.decode(g, Uint8List.fromList([0x01, 43, 0x00])), [release('b1')]);
    expect(d.decode(g, Uint8List.fromList([0x01, 44, 0x20])), [press('b2')]);
    expect(d.decode(g, Uint8List.fromList([0x02, 44, 0x20])), isEmpty);
  });

  test('manette qui n’envoie que l’appui : clic simple', () {
    final l = ControllerLearner()..startButton();
    for (var i = 0; i < 3; i++) {
      l.add(ch, [0xA1]);
    }
    expect(l.finishButton('b1', 'Bouton +'), isNull);
    l.startButton();
    for (var i = 0; i < 3; i++) {
      l.add(ch, [0xA2]);
    }
    expect(l.finishButton('b2', 'Bouton −'), isNull);
    final d = LearnedDriver(l.profile('Remote', subs));
    expect(d.reportsRelease, isFalse);
    expect(d.decode(Guid(ch), Uint8List.fromList([0xA2])), [press('b2'), release('b2')]);
  });

  test('caractéristique bavarde ignorée, bouton identique refusé, rien reçu', () {
    const noisy = '0000fff2-0000-1000-8000-00805f9b34fb';
    final l = ControllerLearner()
      ..startQuiet()
      ..add(noisy, [1])
      ..add(noisy, [2])
      ..endQuiet();
    expect(l.noisy, {noisy});
    l.startButton();
    expect(l.finishButton('b1', 'Bouton +'), 'nothing');
    l.startButton();
    for (var i = 0; i < 5; i++) {
      l.add(noisy, [i]);
    }
    for (var i = 0; i < 3; i++) {
      l.add(ch, [7]);
    }
    expect(l.finishButton('b1', 'Bouton +'), isNull);
    expect(l.buttons.single.frame.characteristic, ch);
    l.startButton();
    for (var i = 0; i < 3; i++) {
      l.add(ch, [7]);
    }
    expect(l.finishButton('b2', 'Bouton −'), 'same');
  });
}
