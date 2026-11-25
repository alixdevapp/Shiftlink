// Voix : annonce la vitesse et les alertes (pile faible, manette déconnectée).
import 'dart:async';

import 'package:flutter/services.dart';

import 'i18n.dart';

class Voice {
  static const _channel = MethodChannel('shiftlink/voice');

  /// Annonce de vitesse en attente : on ne lit que la dernière si on enchaîne les appuis.
  Timer? _gearTimer;

  /// Dit [text] tout de suite, dans la langue de l'appli.
  Future<void> say(String text) async {
    try {
      await _channel.invokeMethod<void>('speak', {'text': text, 'lang': appLanguage.value});
    } catch (_) {}
  }

  /// Annonce le numéro de vitesse un court instant après le dernier appui.
  void gear(int Function() current, {Duration delay = const Duration(milliseconds: 700)}) {
    _gearTimer?.cancel();
    _gearTimer = Timer(delay, () => say(tr('Vitesse {0}', [current()])));
  }

  void dispose() => _gearTimer?.cancel();
}

/// Prévient une seule fois par seuil (20 %, puis 10 %) ; on oublie dès que la pile remonte (recharge).
class BatteryWatch {
  static const low = 20;
  static const critical = 10;
  static const recharged = 30;
  final Map<String, int> _warned = {};

  /// Renvoie le seuil franchi, ou null s'il n'y a rien à dire.
  int? check(String id, int level) {
    if (level >= recharged) {
      _warned.remove(id);
      return null;
    }
    final t = level <= critical ? critical : (level <= low ? low : null);
    if (t == null) return null;
    final last = _warned[id];
    if (last != null && last <= t) return null;
    _warned[id] = t;
    return t;
  }
}

/// Une alerte de pile faible à afficher.
class BatteryAlert {
  final String name;
  final int level;
  const BatteryAlert(this.name, this.level);
}
