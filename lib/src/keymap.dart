// Action de chaque bouton de manette, par geste et par appli.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'actions.dart';
import 'controllers/driver.dart';
import 'gestures.dart';

class Keymap {
  final SharedPreferences prefs;
  final String target;
  final Map<String, Map<String, String>> _data;

  Keymap(this.prefs, this.target) : _data = _load(prefs, target);

  static String _prefKey(String target) => 'keymap.$target';

  static Map<String, Map<String, String>> _load(SharedPreferences prefs, String target) {
    final raw = prefs.getString(_prefKey(target));
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as Map).cast<String, String>()};
    } catch (_) {
      return {};
    }
  }

  static String buttonKey(ControllerDriver d, String buttonId) => '${d.typeId}/$buttonId';

  /// Action d'un geste, ou null (rien). Sans réglage : valeur par défaut de la manette.
  ShiftAction? actionFor(ControllerDriver d, String buttonId, Gesture g) {
    if (g == Gesture.long && !d.reportsRelease) return null;
    if (g == Gesture.combo) return null;
    final legacy = d.legacyButtonOf(buttonId);
    final custom =
        _data[buttonKey(d, buttonId)]?[g.name] ?? (legacy == null ? null : _data[buttonKey(d, legacy)]?[g.name]);
    if (custom != null) return ShiftAction.byName(custom);
    return switch (g) {
      Gesture.click => ShiftAction.byName(d.defaultClicks[buttonId] ?? d.defaultClicks[legacy]),
      Gesture.double => ShiftAction.byName(d.defaultDoubles[buttonId] ?? d.defaultDoubles[legacy]),
      Gesture.long || Gesture.combo => null,
    };
  }

  /// Action de deux boutons appuyés ensemble, ou null.
  ShiftAction? comboFor(ControllerDriver d, String a, String b) {
    if (!d.reportsRelease) return null;
    return ShiftAction.byName(_data[buttonKey(d, GestureEngine.comboId(a, b))]?[Gesture.combo.name]);
  }

  /// Combinaisons réglées pour cette manette : identifiant « a&b » vers action.
  Map<String, ShiftAction> combos(ControllerDriver d) {
    final prefix = '${d.typeId}/';
    return {
      for (final e in _data.entries)
        if (e.key.startsWith(prefix) && GestureEngine.isCombo(e.key))
          e.key.substring(prefix.length): ?ShiftAction.byName(e.value[Gesture.combo.name]),
    };
  }

  /// Le bouton fait-il partie d'une combinaison réglée ?
  bool inCombo(ControllerDriver d, String buttonId) =>
      combos(d).keys.any((id) => GestureEngine.comboParts(id).contains(buttonId));

  /// Règle (ou retire, avec null) la combinaison de deux boutons.
  Future<void> setCombo(ControllerDriver d, String a, String b, ShiftAction? action) async {
    final key = buttonKey(d, GestureEngine.comboId(a, b));
    if (action == null) {
      _data.remove(key);
    } else {
      _data[key] = {Gesture.combo.name: action.name};
    }
    await _save();
  }

  bool isCustom(ControllerDriver d) => _data.keys.any((k) => k.startsWith('${d.typeId}/'));

  Future<void> set(ControllerDriver d, String buttonId, Gesture g, ShiftAction? a) async {
    (_data[buttonKey(d, buttonId)] ??= {})[g.name] = a?.name ?? 'none';
    await _save();
  }

  Future<void> reset(ControllerDriver d) async {
    _data.removeWhere((k, _) => k.startsWith('${d.typeId}/'));
    await _save();
  }

  Future<void> _save() => prefs.setString(_prefKey(target), jsonEncode(_data));

  /// Toutes les actions utilisées par ces manettes (pour régler les appuis à l'écran).
  Set<ShiftAction> usedActions(Iterable<ControllerDriver> drivers) => {
    for (final d in drivers)
      for (final b in d.buttons)
        for (final g in Gesture.values) ?actionFor(d, b.id, g),
    for (final d in drivers) ...combos(d).values,
  };
}
