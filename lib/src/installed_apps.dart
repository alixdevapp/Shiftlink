// Applis d'entraînement installées sur ce téléphone (on ne lit que leur nom).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';

class InstalledApps {
  static const _channel = MethodChannel('shiftlink/apps');
  static final Map<String, Future<bool>> _cache = {};

  /// Pour les captures et les tests : noms d'applis « installées », sans passer par Android.
  static Set<String>? fake;

  /// Nom de l'appli tel qu'il apparaît sur le téléphone, ou null.
  static String? searchName(TargetApp t) => switch (t) {
    TargetApp.mywhoosh || TargetApp.mywhooshProxy => 'MyWhoosh',
    TargetApp.zwift || TargetApp.zwiftRide => 'Zwift',
    TargetApp.rouvy => 'Rouvy',
    TargetApp.tpv => 'TrainingPeaks',
    TargetApp.biketerra || TargetApp.biketerraObc => 'Biketerra',
    TargetApp.trainerroad => 'TrainerRoad',
    TargetApp.incyclist || TargetApp.incyclistObc => 'Incyclist',
    TargetApp.rampida => 'Rampida',
    TargetApp.everycol => 'Everycol',
    _ => null,
  };

  static Future<bool> has(TargetApp t) {
    final name = searchName(t);
    if (name == null) return Future.value(false);
    if (fake != null) return Future.value(fake!.contains(name));
    return _cache[name] ??= _load(name);
  }

  static Future<bool> _load(String name) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('installed', {'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static final Map<String, Future<int?>> _colors = {};

  /// Couleur principale de l'icône de l'appli installée (ARGB), ou null.
  static Future<int?> colorOf(TargetApp t) {
    final name = searchName(t);
    if (name == null || fake != null || defaultTargetPlatform != TargetPlatform.android) return Future.value();
    return _colors[name] ??= _channel
        .invokeMethod<int>('color', {'name': name})
        .then<int?>((v) => _known[name] = v, onError: (_) => null);
  }

  static final Map<String, int?> _known = {};

  /// Couleur déjà lue (sans attendre), pour éviter un clignotement.
  static int? knownColorOf(TargetApp t) => _known[searchName(t)];

  static final Map<String, Future<Uint8List?>> _icons = {};
  static final Map<String, Uint8List?> _knownIcons = {};

  /// Icône de l'appli installée en PNG, ou null (iOS, démo, appli absente).
  static Future<Uint8List?> iconOf(TargetApp t, {int size = 96}) {
    final name = searchName(t);
    if (name == null || fake != null || defaultTargetPlatform != TargetPlatform.android) return Future.value();
    return _icons[name] ??= _channel
        .invokeMethod<Uint8List>('iconPng', {'name': name, 'size': size})
        .then<Uint8List?>((v) => _knownIcons[name] = v, onError: (_) => null);
  }

  /// Icône déjà lue (sans attendre), pour éviter un clignotement.
  static Uint8List? knownIconOf(TargetApp t) => _knownIcons[searchName(t)];

  /// Appli officielle qui met à jour une manette (son nom sur le Play Store), ou null.
  static String? updaterFor(String typeId) => switch (typeId) {
    'zwiftClick' || 'zwiftClickV2' || 'zwiftPlayLeft' || 'zwiftPlayRight' || 'zwiftRide' => 'Zwift Companion',
    'di2' => 'E-TUBE PROJECT Cyclist',
    'axs' => 'SRAM AXS',
    'kickrBike' => 'Wahoo',
    'tacxNeoBike' => 'Tacx Training',
    'vs200' => 'ThinkRider',
    'bc2' || 'cycplusT7' => 'CYCPLUS',
    'eliteSquare' => 'My E-Training',
    'onelapKey' => 'Onelap',
    _ => null,
  };

  /// Ouvre l'appli (ou sa page du Play Store). Renvoie 'app', 'store' ou 'none'.
  static Future<String> open(String name) async {
    if (defaultTargetPlatform != TargetPlatform.android) return 'none';
    // Elle sera peut-être installée au retour : on vérifiera à nouveau.
    _cache.removeWhere((k, _) => k == name);
    try {
      return await _channel.invokeMethod<String>('open', {'name': name}) ?? 'none';
    } catch (_) {
      return 'none';
    }
  }
}
