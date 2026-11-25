// Vitesses et actions sur le même téléphone : ShiftLink touche les boutons de l'appli
// à l'écran (service d'accessibilité Android, voir ScreenTaps.kt).
// Les positions sont en pourcentage de l'écran (0 à 100).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../actions.dart';

/// Positions par défaut des boutons, par appli, en mode paysage (en % de l'écran).
/// Réglables action par action ; « Montrer les cibles » pour vérifier.
const Map<String, Map<ShiftAction, Offset>> defaultTapPositions = {
  'rouvy': {ShiftAction.shiftUp: Offset(94, 72), ShiftAction.shiftDown: Offset(94, 80)},
  'tpv': {
    ShiftAction.shiftUp: Offset(22.6, 7.1),
    ShiftAction.shiftDown: Offset(18.1, 6.8),
    ShiftAction.steerLeft: Offset(41.1, 92.6),
    ShiftAction.steerRight: Offset(56.8, 92.4),
  },
  'mywhoosh': {
    ShiftAction.shiftUp: Offset(97, 94),
    ShiftAction.shiftDown: Offset(80, 94),
    ShiftAction.steerLeft: Offset(32, 80),
    ShiftAction.steerRight: Offset(60, 80),
  },
};

/// Actions qu'on peut faire en touchant l'écran.
bool isTappable(ShiftAction a) => !a.isMedia && !a.isPhone;

class ScreenTaps {
  static const _channel = MethodChannel('shiftlink/taps');

  final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Change à chaque nouveau réglage des positions.
  final ValueNotifier<int> revision = ValueNotifier(0);
  final ValueNotifier<bool> calibrating = ValueNotifier(false);
  final void Function(String) log;
  SharedPreferences? prefs;

  /// Touche d'une télécommande ou manette externe.
  void Function(String device, String name, String key, bool down)? onKey;

  /// − ou + touché dans la fenêtre par-dessus l'appli.
  void Function(int delta)? onHudShift;

  String? _calTarget;
  List<ShiftAction> _calActions = const [];

  ScreenTaps({required this.log}) {
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'status':
          enabled.value = args['enabled'] == true;
          log(enabled.value ? 'Accessibilité ShiftLink activée' : 'Accessibilité ShiftLink désactivée');
        case 'key':
          onKey?.call(
            args['device'] as String,
            args['name'] as String? ?? 'Appareil',
            args['label'] as String,
            args['down'] == true,
          );
        case 'hudShift':
          onHudShift?.call((args['delta'] as num?)?.toInt() ?? 0);
        case 'calibration':
          calibrating.value = false;
          if (args['state'] != 'done' || _calTarget == null) return;
          final points = (args['points'] as List).map((p) => (p as List).cast<num>()).toList();
          final saved = _saved(_calTarget!);
          for (var i = 0; i < points.length && i < _calActions.length; i++) {
            saved[_calActions[i]] = Offset(points[i][0].toDouble(), points[i][1].toDouble());
          }
          await _save(_calTarget!, saved);
          final pkg = args['package'] as String?;
          log('Positions réglées${pkg != null ? ' (appli $pkg)' : ''}');
      }
    });
  }

  void load(SharedPreferences prefs) => this.prefs = prefs;

  Map<ShiftAction, Offset> _saved(String target) {
    final raw = prefs?.getString('taps.$target');
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          if (ShiftAction.byName(e.key) != null)
            ShiftAction.byName(e.key)!: Offset(
              ((e.value as List)[0] as num).toDouble(),
              ((e.value as List)[1] as num).toDouble(),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(String target, Map<ShiftAction, Offset> m) async {
    await prefs?.setString(
      'taps.$target',
      jsonEncode({
        for (final e in m.entries) e.key.name: [e.value.dx, e.value.dy],
      }),
    );
    revision.value++;
  }

  /// Positions connues : réglées par l'utilisateur, sinon par défaut.
  Map<ShiftAction, Offset> positionsFor(String target) => {...?defaultTapPositions[target], ..._saved(target)};

  bool isCalibrated(String target, ShiftAction a) => _saved(target).containsKey(a);

  Future<void> resetPositions(String target) async {
    await prefs?.remove('taps.$target');
    revision.value++;
  }

  Future<void> refresh() async {
    try {
      enabled.value = await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      enabled.value = false;
    }
    // Retour des réglages sans que ce soit activé : souvent le blocage « paramètre restreint » d'Android.
    if (_openedSettings) {
      _openedSettings = false;
      if (!enabled.value) await onStillOff?.call();
    }
  }

  bool _openedSettings = false;

  /// Appelé au retour des réglages d'accessibilité si ShiftLink n'y est toujours pas activé.
  Future<void> Function()? onStillOff;

  /// Fait vibrer une manette de jeu (si elle a un moteur).
  void rumble(String device, {bool strong = false}) {
    _channel.invokeMethod('rumble', {'device': device, 'strong': strong}).catchError((_) {});
  }

  /// Écran d'explication avant les réglages d'accessibilité (exigé par Google Play).
  /// Rend faux si la personne refuse : les réglages ne s'ouvrent pas.
  Future<bool> Function()? askConsent;

  Future<void> openSettings() async {
    final consent = askConsent;
    if (consent != null && !await consent()) return;
    await _channel.invokeMethod('openSettings');
    _openedSettings = true;
  }

  Future<void> openAppInfo() => _channel.invokeMethod('openAppInfo');

  /// Ouvre les réglages Bluetooth du téléphone (depuis Android 13, une appli ne peut plus l'allumer elle-même).
  Future<void> openBluetoothSettings() => _channel.invokeMethod('openBluetoothSettings');

  /// Affiche la bulle de réglage : l'utilisateur touchera chaque action dans l'ordre.
  Future<bool> calibrate(String target, List<ShiftAction> actions) async {
    if (actions.isEmpty) return false;
    _calTarget = target;
    _calActions = actions;
    final ok =
        await _channel.invokeMethod<bool>('calibrate', {
          'labels': [for (final a in actions) a.label],
        }) ??
        false;
    calibrating.value = ok;
    return ok;
  }

  Future<void> cancelCalibration() async {
    calibrating.value = false;
    await _channel.invokeMethod('cancelCalibration');
  }

  /// Montre les cibles par-dessus l'écran pendant 6 secondes.
  Future<bool> showTargets(String target) async {
    final p = positionsFor(target);
    return await _channel.invokeMethod<bool>('showMarkers', {
          'points': [
            for (final o in p.values) [o.dx, o.dy],
          ],
          'labels': [for (final a in p.keys) a.label],
        }) ??
        false;
  }

  /// Touche la position de [action] pour l'appli [target].
  Future<bool> tap(String target, ShiftAction action) async {
    final o = positionsFor(target)[action];
    if (!enabled.value || o == null) return false;
    try {
      return await _channel.invokeMethod<bool>('tap', {'x': o.dx, 'y': o.dy}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [keys] : touches réglées sur une action (« appareil|TOUCHE »), seules prises ;
  /// [devices] : appareils connus ; [defaults] : touches prises sur un appareil inconnu.
  Future<void> setCaptureKeys(
    bool on, {
    Iterable<String>? keys,
    Iterable<String>? devices,
    Iterable<String>? defaults,
  }) async {
    try {
      await _channel.invokeMethod('captureKeys', {
        'on': on,
        'keys': ?keys?.toList(),
        'devices': ?devices?.toList(),
        'defaults': ?defaults?.toList(),
      });
    } catch (_) {}
  }

  /// Affichage par-dessus l'appli. Renvoie false sans accessibilité.
  Future<bool> hud({required bool show, String title = '', String subtitle = '', bool buttons = false}) async {
    try {
      return await _channel.invokeMethod<bool>('hud', {
            'show': show,
            'title': title,
            'subtitle': subtitle,
            'buttons': buttons,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> global(String name) async {
    try {
      return await _channel.invokeMethod<bool>('global', {'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> media(String key) async {
    try {
      await _channel.invokeMethod('media', {'key': key});
    } catch (_) {}
  }

  Future<void> volume(bool up) async {
    try {
      await _channel.invokeMethod('volume', {'up': up});
    } catch (_) {}
  }
}
