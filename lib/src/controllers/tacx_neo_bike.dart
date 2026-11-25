// Tacx NEO Bike (Smart, Plus) : manettes et boutons du vélo.
//
// Code écrit pour ShiftLink. Faits de protocole (firmware 4.5 et plus), imposés par
// le vélo :
// - service constructeur fe031000-17d0-470a-8798-4ad3e1c1f35b ;
// - fe031001 : fonctions du vélo, 16 bits petit-boutiste (0x80 = tables de vitesses) ;
// - fe031003 : vitesse engagée = [drapeaux, plateau si bit 0, pignon (dernier octet) si bit 1],
//   en nombre de dents ;
// - fe031004 : boutons = [drapeaux, gauche si bit 0, droit (dernier octet) si bit 1],
//   bit 7 de l'octet = appuyé ;
// - fe03100f : point de commande. 0x04 / 0x05 demandent la liste des plateaux / pignons ;
//   réponse [0x20, commande, résultat (1 = OK), nombre, dents…].
// Le vélo dit la vitesse où il est, pas l'appui sur la manette : un changement de
// vitesse devient un appui. Le vélo reste aussi le home trainer (FTMS), relié à part.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../i18n.dart';
import 'driver.dart';

Guid _tacx(String n) => Guid('fe03$n-17d0-470a-8798-4ad3e1c1f35b');

/// Vitesse engagée : nombre de dents du plateau et du pignon (null = absent de la trame).
typedef TacxGear = ({int? chainring, int? sprocket});

/// Lit les trames du vélo. Séparé du pilote pour les tests.
abstract final class TacxNeoBikeFrames {
  /// Deux valeurs optionnelles annoncées par les bits 0 et 1 du premier octet ;
  /// la seconde est toujours le dernier octet.
  static (int?, int?)? _pair(Uint8List b) {
    if (b.isEmpty) return null;
    final hasFirst = b[0] & 0x01 != 0;
    final hasSecond = b[0] & 0x02 != 0;
    final needed = 1 + (hasFirst ? 1 : 0) + (hasSecond ? 1 : 0);
    if ((!hasFirst && !hasSecond) || b.length < needed) return null;
    return (hasFirst ? b[1] : null, hasSecond ? b[b.length - 1] : null);
  }

  static TacxGear? gear(Uint8List b) {
    final p = _pair(b);
    return p == null ? null : (chainring: p.$1, sprocket: p.$2);
  }

  /// Boutons gauche et droit : true = appuyé, null = absent de la trame.
  static (bool?, bool?)? buttons(Uint8List b) {
    final p = _pair(b);
    if (p == null) return null;
    bool? pressed(int? v) => v == null ? null : v & 0x80 != 0;
    return (pressed(p.$1), pressed(p.$2));
  }

  /// Réponse du point de commande à [command] : la liste de dents, ou null.
  static List<int>? teethTable(Uint8List b, int command) {
    if (b.length < 4 || b[0] != 0x20 || b[1] != command || b[2] != 0x01) return null;
    final count = b[3];
    final end = (4 + count).clamp(4, b.length);
    return b.sublist(4, end);
  }
}

/// Transforme les vitesses rapportées par le vélo en appuis.
class TacxShiftCounter {
  /// Jamais plus d'appuis pour une trame : une valeur aberrante ne doit pas
  /// déclencher une rafale de changements.
  static const maxPerFrame = 10;

  List<int>? chainrings;
  List<int>? sprockets;
  int? _chainring;
  int? _sprocket;

  void clear() {
    chainrings = null;
    sprockets = null;
    _chainring = null;
    _sprocket = null;
  }

  /// Nombre de crans entre deux dentures. Sans la liste du vélo : 1.
  static int _steps(List<int>? table, int from, int to) {
    final i = table?.indexOf(from) ?? -1;
    final j = table?.indexOf(to) ?? -1;
    if (i < 0 || j < 0) return 1;
    final n = (i - j).abs();
    return n < 1 ? 1 : (n > maxPerFrame ? maxPerFrame : n);
  }

  /// Boutons « virtuels » à appuyer pour passer à [gear]. La première trame ne fait
  /// que noter la position de départ.
  List<String> next(TacxGear gear) {
    final out = <String>[];
    final ring = gear.chainring;
    if (ring != null) {
      final before = _chainring;
      _chainring = ring;
      // Plus de dents devant = plus dur.
      if (before != null && before != ring) {
        out.addAll(List.filled(_steps(chainrings, before, ring), ring > before ? 'frontHarder' : 'frontEasier'));
      }
    }
    final sprocket = gear.sprocket;
    if (sprocket != null) {
      final before = _sprocket;
      _sprocket = sprocket;
      // Moins de dents derrière = plus dur.
      if (before != null && before != sprocket) {
        out.addAll(
          List.filled(_steps(sprockets, before, sprocket), sprocket < before ? 'rearHarder' : 'rearEasier'),
        );
      }
    }
    return out;
  }
}

class TacxNeoBikeDriver extends ControllerDriver {
  static final service = _tacx('1000');
  static final features = _tacx('1001');
  static final gears = _tacx('1003');
  static final buttonsChar = _tacx('1004');
  static final controlPoint = _tacx('100f');

  static const askChainrings = 0x04;
  static const askSprockets = 0x05;
  static const _featureGearTables = 0x80;

  /// « Tacx Neo Bike … », « NEO Bike Plus … ». Les trainers (« Tacx Neo 2T ») n'ont pas « BIKE ».
  static bool matchesName(String upperName) =>
      (upperName.startsWith('TACX') || upperName.startsWith('NEO')) && upperName.contains('BIKE');

  final counter = TacxShiftCounter();
  final Set<String> _held = {};
  BluetoothCharacteristic? _cp;
  int _asks = 0;
  int _gearFramesWithoutTables = 0;

  @override
  String get typeId => 'tacxNeoBike';
  @override
  String get label => tr('Tacx NEO Bike (bêta)');
  @override
  String get hint => tr('Les manettes et les deux boutons du vélo. Relie aussi le vélo comme home trainer.');
  @override
  String get missingServiceHint => tr('Mets à jour le vélo avec Tacx Training (firmware 4.5 ou plus récent).');

  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('rearHarder', 'Manette droite : plus dur'),
    ControllerButton('rearEasier', 'Manette droite : plus facile'),
    ControllerButton('frontHarder', 'Manette gauche : plus dur'),
    ControllerButton('frontEasier', 'Manette gauche : plus facile'),
    ControllerButton('leftButton', 'Bouton gauche'),
    ControllerButton('rightButton', 'Bouton droit'),
  ];
  @override
  Map<String, String> get defaultClicks => const {
    'rearHarder': 'shiftUp',
    'rearEasier': 'shiftDown',
    'frontHarder': 'shiftUp',
    'frontEasier': 'shiftDown',
    'leftButton': 'steerLeft',
    'rightButton': 'steerRight',
  };

  @override
  List<Subscription> get subscriptions => [
    Subscription(service, gears),
    Subscription(service, buttonsChar, optional: true),
    Subscription(service, controlPoint, optional: true),
  ];

  @override
  void reset() {
    super.reset();
    counter.clear();
    _held.clear();
    _cp = null;
    _asks = 0;
    _gearFramesWithoutTables = 0;
  }

  @override
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {
    final chars = services.where((s) => s.uuid == service).expand((s) => s.characteristics).toList();
    _cp = chars.where((c) => c.uuid == controlPoint).firstOrNull;
    var hasTables = true;
    final f = chars.where((c) => c.uuid == features).firstOrNull;
    if (f != null && f.properties.read) {
      try {
        final v = await f.read();
        if (v.isNotEmpty) hasTables = v[0] & _featureGearTables != 0;
      } catch (_) {}
    }
    if (hasTables) await _askTables();
  }

  /// Demande les listes de plateaux et de pignons (3 essais au plus). Sans elles, un
  /// saut de plusieurs vitesses ne compte que pour un appui.
  Future<void> _askTables() async {
    final cp = _cp;
    if (cp == null || _asks >= 3) return;
    _asks++;
    final quiet = !cp.properties.write && cp.properties.writeWithoutResponse;
    try {
      await cp.write(const [askChainrings], withoutResponse: quiet);
      await cp.write(const [askSprockets], withoutResponse: quiet);
    } catch (_) {}
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (c == controlPoint) {
      counter.chainrings = TacxNeoBikeFrames.teethTable(bytes, askChainrings) ?? counter.chainrings;
      counter.sprockets = TacxNeoBikeFrames.teethTable(bytes, askSprockets) ?? counter.sprockets;
      return const [];
    }
    if (c == gears) {
      final g = TacxNeoBikeFrames.gear(bytes);
      if (g == null) return const [];
      if ((counter.chainrings == null || counter.sprockets == null) && ++_gearFramesWithoutTables % 10 == 0) {
        unawaited(_askTables()); // le vélo ne répond pas toujours juste après la connexion
      }
      return [for (final id in counter.next(g)) ...tap(id)];
    }
    if (c == buttonsChar) {
      final b = TacxNeoBikeFrames.buttons(bytes);
      if (b == null) return const [];
      final (left, right) = b;
      if (left != null) left ? _held.add('leftButton') : _held.remove('leftButton');
      if (right != null) right ? _held.add('rightButton') : _held.remove('rightButton');
      return diffState({..._held});
    }
    return const [];
  }
}
