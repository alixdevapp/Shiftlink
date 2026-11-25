import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show Guid;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/actions.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/key_input.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';
import 'package:shiftlink/src/gestures.dart';
import 'package:shiftlink/src/keymap.dart';

void main() {
  late List<String> fired;

  GestureEngine engine(Map<(String, Gesture), ShiftAction> map, {bool release = true}) => GestureEngine(
    reportsRelease: release,
    resolve: (id, g) => map[(id, g)],
    fire: (id, g, a, phase) => fired.add('${g.name}:${a.name}:${phase.name}'),
  );

  setUp(() => fired = []);

  test('clic seul : action dès l’appui, sans délai', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp});
      e.onEvent(press('b'));
      expect(fired, ['click:shiftUp:once']);
      e.onEvent(release('b'));
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['click:shiftUp:once']);
    });
  });

  test('vitesse maintenue : répétition après 500 ms', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp});
      e.onEvent(press('b'));
      t.elapse(const Duration(milliseconds: 1010));
      e.onEvent(release('b'));
      t.elapse(const Duration(seconds: 1));
      // 1 au départ + répétitions à 750 et 1000 ms
      expect(fired.length, 3);
    });
  });

  GestureEngine comboEngine(Map<(String, Gesture), ShiftAction> map, Map<String, ShiftAction> combos) => GestureEngine(
    reportsRelease: true,
    resolve: (id, g) => map[(id, g)],
    resolveCombo: (a, b) => combos[GestureEngine.comboId(a, b)],
    inCombo: (id) => combos.keys.any((k) => GestureEngine.comboParts(k).contains(id)),
    fire: (id, g, a, phase) => fired.add('$id:${g.name}:${a.name}:${phase.name}'),
  );

  test('combinaison : deux boutons ensemble déclenchent leur action, pas leurs clics', () {
    fakeAsync((t) {
      final e = comboEngine(
        {('+', Gesture.click): ShiftAction.shiftUp, ('-', Gesture.click): ShiftAction.shiftDown},
        {GestureEngine.comboId('+', '-'): ShiftAction.frontShift},
      );
      e.onEvent(press('+'));
      t.elapse(const Duration(milliseconds: 40));
      e.onEvent(press('-'));
      e.onEvent(release('+'));
      e.onEvent(release('-'));
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['${GestureEngine.comboId('+', '-')}:combo:frontShift:once']);
    });
  });

  test('combinaison : un bouton seul garde son clic, au relâchement', () {
    fakeAsync((t) {
      final e = comboEngine(
        {('+', Gesture.click): ShiftAction.shiftUp, ('-', Gesture.click): ShiftAction.shiftDown},
        {GestureEngine.comboId('+', '-'): ShiftAction.frontShift},
      );
      e.onEvent(press('+'));
      expect(fired, isEmpty);
      e.onEvent(release('+'));
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['+:click:shiftUp:once']);
    });
  });

  test('délai d’appui long réglable', () {
    fakeAsync((t) {
      final e = GestureEngine(
        reportsRelease: true,
        longDelay: const Duration(milliseconds: 900),
        resolve: (id, g) => g == Gesture.long ? ShiftAction.shiftUp : null,
        fire: (id, g, a, phase) => fired.add(g.name),
      );
      e.onEvent(press('b'));
      t.elapse(const Duration(milliseconds: 600));
      expect(fired, isEmpty);
      t.elapse(const Duration(milliseconds: 400));
      expect(fired, ['long']);
      e.onEvent(release('b'));
    });
  });

  test('double clic', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp, ('b', Gesture.double): ShiftAction.shiftDown});
      e.onEvent(press('b'));
      e.onEvent(release('b'));
      t.elapse(const Duration(milliseconds: 100));
      e.onEvent(press('b'));
      e.onEvent(release('b'));
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['double:shiftDown:once']);
    });
  });

  test('clic simple quand un double clic est réglé : après la fenêtre', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp, ('b', Gesture.double): ShiftAction.shiftDown});
      e.onEvent(press('b'));
      e.onEvent(release('b'));
      expect(fired, isEmpty);
      t.elapse(GestureEngine.defaultDoubleWindow + const Duration(milliseconds: 10));
      expect(fired, ['click:shiftUp:once']);
    });
  });

  test('appui long', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp, ('b', Gesture.long): ShiftAction.mediaNext});
      e.onEvent(press('b'));
      t.elapse(const Duration(milliseconds: 600));
      e.onEvent(release('b'));
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['long:mediaNext:once']);
    });
  });

  test('appui court avec appui long réglé : clic au relâchement', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.shiftUp, ('b', Gesture.long): ShiftAction.mediaNext});
      e.onEvent(press('b'));
      t.elapse(const Duration(milliseconds: 100));
      e.onEvent(release('b'));
      expect(fired, ['click:shiftUp:once']);
    });
  });

  test('direction : maintien du début à la fin', () {
    fakeAsync((t) {
      final e = engine({('b', Gesture.click): ShiftAction.steerLeft});
      e.onEvent(press('b'));
      t.elapse(const Duration(seconds: 2));
      e.onEvent(release('b'));
      expect(fired, ['click:steerLeft:start', 'click:steerLeft:end']);
    });
  });

  test('SRAM AXS : double appui par défaut = plus facile', () {
    fakeAsync((t) {
      final d = SramAxsDriver();
      final e = GestureEngine(
        reportsRelease: false,
        resolve: (id, g) => switch (g) {
          Gesture.click => ShiftAction.byName(d.defaultClicks[id]),
          Gesture.double => ShiftAction.byName(d.defaultDoubles[id]),
          _ => null,
        },
        fire: (id, g, a, phase) => fired.add(a.name),
      );
      for (final ev in d.decode(Guid('0000'), Uint8List(1))) {
        e.onEvent(ev);
      }
      t.elapse(const Duration(seconds: 1));
      for (var i = 0; i < 2; i++) {
        for (final ev in d.decode(Guid('0000'), Uint8List(1))) {
          e.onEvent(ev);
        }
        t.elapse(const Duration(milliseconds: 100));
      }
      t.elapse(const Duration(seconds: 1));
      expect(fired, ['shiftUp', 'shiftDown']);
    });
  });

  test('réglage des boutons : défauts, changement, remise à zéro', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final d = ZwiftRideDriver(ZwiftIds.rideService);
    final k = Keymap(prefs, 'rouvy');
    expect(k.actionFor(d, 'shiftUpRight', Gesture.click), ShiftAction.shiftUp);
    expect(k.actionFor(d, 'a', Gesture.click), isNull);
    await k.set(d, 'a', Gesture.long, ShiftAction.mediaPlayPause);
    await k.set(d, 'shiftUpRight', Gesture.click, null);
    final reloaded = Keymap(prefs, 'rouvy');
    expect(reloaded.actionFor(d, 'a', Gesture.long), ShiftAction.mediaPlayPause);
    expect(reloaded.actionFor(d, 'shiftUpRight', Gesture.click), isNull);
    expect(Keymap(prefs, 'tpv').actionFor(d, 'shiftUpRight', Gesture.click), ShiftAction.shiftUp);
    await reloaded.reset(d);
    expect(reloaded.actionFor(d, 'shiftUpRight', Gesture.click), ShiftAction.shiftUp);
  });

  test('télécommande : touches apprises, volume = vitesses par défaut', () {
    final d = KeyInputDriver('abc');
    expect(d.learn('VOLUME_UP'), isTrue);
    expect(d.learn('VOLUME_UP'), isFalse);
    d.learn('BUTTON_A');
    d.learn('DPAD_DOWN');
    expect(d.buttons.map((b) => b.label), ['Volume +', 'A', 'Croix : bas']);
    expect(d.defaultClicks, {'VOLUME_UP': 'shiftUp', 'DPAD_DOWN': 'shiftDown'});
    expect(d.typeId, 'keys.abc');
  });
}
