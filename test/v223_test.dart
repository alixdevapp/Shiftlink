import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/actions.dart';
import 'package:shiftlink/src/controllers/steering_drivers.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';
import 'package:shiftlink/src/keymap.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';

void main() {
  test('cinq nouvelles applis OpenBikeControl reconnues par leur nom', () {
    expect(ObcProtocol.appName('pedalcraft'), 'PedalCraft');
    expect(ObcProtocol.appName('suffer.online'), 'suffer.online');
    expect(ObcProtocol.appName('Kardiacs'), 'Kardiacs');
    expect(ObcProtocol.appName('sueur'), 'Sueur');
    expect(ObcProtocol.appName('TrainerKit'), 'TrainerKit');
  });

  test('palettes Zwift : vers l’intérieur = positif à gauche, négatif à droite', () {
    expect(zwiftPaddleInward(right: false, value: 100), isTrue);
    expect(zwiftPaddleInward(right: false, value: -100), isFalse);
    expect(zwiftPaddleInward(right: true, value: -100), isTrue);
    expect(zwiftPaddleInward(right: true, value: 100), isFalse);
  });

  test('palettes séparées : un ancien réglage vaut pour les deux sens', () async {
    SharedPreferences.setMockInitialValues({
      'keymap.test': '{"zwiftRide/paddleLeft":{"click":"steerLeft"}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final k = Keymap(prefs, 'test');
    final d = ZwiftRideDriver(ZwiftIds.rideService);
    expect(d.buttons.map((b) => b.id), containsAll(['paddleLeftIn', 'paddleLeftOut', 'paddleRightIn', 'paddleRightOut']));
    expect(d.buttons.map((b) => b.id), isNot(contains('paddleLeft')));
    expect(k.actionFor(d, 'paddleLeftIn', Gesture.click), ShiftAction.byName('steerLeft'));
    expect(k.actionFor(d, 'paddleLeftOut', Gesture.click), ShiftAction.byName('steerLeft'));
    // Sans réglage : vitesses comme avant.
    expect(k.actionFor(d, 'paddleRightIn', Gesture.click), ShiftAction.shiftUp);
    // Un nouveau réglage d'un sens ne touche pas l'autre.
    await k.set(d, 'paddleLeftOut', Gesture.click, ShiftAction.shiftDown);
    expect(k.actionFor(d, 'paddleLeftOut', Gesture.click), ShiftAction.shiftDown);
    expect(k.actionFor(d, 'paddleLeftIn', Gesture.click), ShiftAction.byName('steerLeft'));
  });

  test('Zwift Play : la palette donne un bouton par sens', () {
    final left = ZwiftPlayDriver(left: true);
    expect(left.buttons.map((b) => b.id), containsAll(['paddleIn', 'paddleOut']));
    expect(left.defaultClicks['paddleIn'], 'shiftDown');
    expect(left.legacyButtonOf('paddleOut'), 'paddle');
  });

  test('Rizer verrouillé : réponse 5 = verrouillé, une seule ligne de journal', () {
    final r = EliteRizerDriver();
    expect(EliteRizerDriver.ackCode(Uint8List.fromList([0x80, 0x0a, 0x05])), EliteRizerDriver.ackLocked);
    expect(r.handleAck(5, 3), isFalse);
    expect(r.locked.value, isTrue);
    expect(r.lastRefusal, contains('verrouillé'));
    r.lastRefusal = null;
    expect(r.handleAck(5, 3), isFalse);
    expect(r.lastRefusal, isNull); // pas une ligne par seconde
    expect(r.handleAck(2, 3), isTrue);
    expect(r.locked.value, isFalse);
    expect(r.lastRefusal, contains('déverrouillé'));
    expect(r.handleAck(1, 3), isFalse);
    expect(r.lastRefusal, contains('hors limites'));
  });
}
