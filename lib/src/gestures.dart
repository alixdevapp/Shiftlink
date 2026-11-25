// Reconnaît clic, double clic, appui long et combinaisons de deux boutons
// à partir des appuis et relâchements.
import 'dart:async';

import 'actions.dart';
import 'controllers/driver.dart';

/// Moment d'une action : ponctuelle, ou début / fin d'un maintien (direction).
enum Phase { once, start, end }

typedef ActionResolver = ShiftAction? Function(String buttonId, Gesture gesture);
typedef ComboResolver = ShiftAction? Function(String first, String second);
typedef ActionSink = void Function(String buttonId, Gesture gesture, ShiftAction action, Phase phase);

class GestureEngine {
  static const defaultDoubleWindow = Duration(milliseconds: 300);
  static const defaultLongDelay = Duration(milliseconds: 500);
  static const repeatEvery = Duration(milliseconds: 250);

  final ActionResolver resolve;
  final ActionSink fire;
  final bool reportsRelease;

  /// Action de deux boutons appuyés ensemble, ou null.
  final ComboResolver? resolveCombo;

  /// Le bouton fait-il partie d'une combinaison ? Son clic attend alors le relâchement.
  final bool Function(String buttonId)? inCombo;

  final Duration doubleWindow;
  final Duration longDelay;
  final Map<String, _ButtonState> _states = {};

  GestureEngine({
    required this.resolve,
    required this.fire,
    required this.reportsRelease,
    this.resolveCombo,
    this.inCombo,
    this.doubleWindow = defaultDoubleWindow,
    this.longDelay = defaultLongDelay,
  });

  /// Identifiant d'une combinaison, indépendant de l'ordre des boutons.
  static String comboId(String a, String b) => a.compareTo(b) <= 0 ? '$a&$b' : '$b&$a';

  /// Les deux boutons d'une combinaison.
  static List<String> comboParts(String comboId) => comboId.split('&');

  static bool isCombo(String buttonId) => buttonId.contains('&');

  void onEvent(ButtonEvent e) => e.down ? _down(e.id) : _up(e.id);

  void _down(String id) {
    final st = _states[id] ??= _ButtonState();
    st.isDown = true;
    if (_tryCombo(id, st)) return;
    final click = resolve(id, Gesture.click);
    final dbl = resolve(id, Gesture.double);
    final long = reportsRelease ? resolve(id, Gesture.long) : null;
    final waitsCombo = reportsRelease && (inCombo?.call(id) ?? false);
    st.cancelTimers();

    if (st.awaitingSecond) {
      st.awaitingSecond = false;
      st.consumed = true;
      if (dbl != null) _once(id, Gesture.double, dbl);
      return;
    }
    if (dbl == null && long == null && !waitsCombo) {
      // Rien à attendre : on réagit dès l'appui, sans délai.
      st.consumed = true;
      if (click == null) return;
      if (click.hold && reportsRelease) {
        st.holding = click;
        fire(id, Gesture.click, click, Phase.start);
      } else {
        _once(id, Gesture.click, click);
        if (click.repeat && reportsRelease) _startRepeat(st, id, Gesture.click, click);
      }
      return;
    }
    st.consumed = false;
    if (long != null) {
      st.longTimer = Timer(longDelay, () {
        st.consumed = true;
        if (long.hold) {
          st.holding = long;
          fire(id, Gesture.long, long, Phase.start);
        } else {
          fire(id, Gesture.long, long, Phase.once);
          if (long.repeat) {
            st.repeatTimer = Timer.periodic(repeatEvery, (_) => fire(id, Gesture.long, long, Phase.once));
          }
        }
      });
    }
  }

  /// Un autre bouton est déjà appuyé : déclenche leur combinaison si elle existe.
  bool _tryCombo(String id, _ButtonState st) {
    final combo = resolveCombo;
    if (combo == null || !reportsRelease) return false;
    for (final e in _states.entries) {
      final other = e.value;
      if (e.key == id || !other.isDown || other.holding != null) continue;
      final a = combo(e.key, id);
      if (a == null) continue;
      for (final s in [st, other]) {
        s.cancelTimers();
        s.awaitingSecond = false;
        s.consumed = true;
      }
      _once(comboId(e.key, id), Gesture.combo, a);
      return true;
    }
    return false;
  }

  void _up(String id) {
    final st = _states[id] ??= _ButtonState();
    st.isDown = false;
    st.cancelTimers();
    final held = st.holding;
    if (held != null) {
      st.holding = null;
      fire(id, Gesture.click, held, Phase.end);
    }
    if (st.consumed) return;
    st.consumed = true;
    final click = resolve(id, Gesture.click);
    final dbl = resolve(id, Gesture.double);
    if (dbl != null) {
      st.awaitingSecond = true;
      st.doubleTimer = Timer(doubleWindow, () {
        st.awaitingSecond = false;
        if (click != null) _once(id, Gesture.click, click);
      });
    } else if (click != null) {
      _once(id, Gesture.click, click);
    }
  }

  void _once(String id, Gesture g, ShiftAction a) {
    if (a.hold) {
      fire(id, g, a, Phase.start);
      Timer(const Duration(milliseconds: 300), () => fire(id, g, a, Phase.end));
    } else {
      fire(id, g, a, Phase.once);
    }
  }

  void _startRepeat(_ButtonState st, String id, Gesture g, ShiftAction a) {
    st.longTimer = Timer(longDelay, () {
      st.repeatTimer = Timer.periodic(repeatEvery, (_) => fire(id, g, a, Phase.once));
    });
  }

  /// La manette est partie (déconnexion, veille, oubli) : ses relâchements n'arriveront
  /// plus. On arrête les répétitions et on termine les actions maintenues.
  void releaseAll() {
    for (final e in _states.entries) {
      final st = e.value;
      st.cancelTimers();
      st.isDown = false;
      st.awaitingSecond = false;
      st.consumed = true;
      final held = st.holding;
      if (held != null) {
        st.holding = null;
        fire(e.key, Gesture.click, held, Phase.end);
      }
    }
    _states.clear();
  }

  void dispose() {
    for (final s in _states.values) {
      s.cancelTimers();
    }
  }
}

class _ButtonState {
  Timer? longTimer;
  Timer? repeatTimer;
  Timer? doubleTimer;
  bool isDown = false;
  bool awaitingSecond = false;
  bool consumed = true;
  ShiftAction? holding;

  void cancelTimers() {
    longTimer?.cancel();
    repeatTimer?.cancel();
    doubleTimer?.cancel();
    longTimer = repeatTimer = doubleTimer = null;
  }
}
