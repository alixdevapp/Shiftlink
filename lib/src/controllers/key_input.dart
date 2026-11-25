// Télécommandes Bluetooth, manettes de jeu et claviers appairés au téléphone :
// leurs touches arrivent par le service d'accessibilité (voir ScreenTaps.kt).
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../i18n.dart';
import 'driver.dart';

/// Noms lisibles des touches les plus courantes.
const _keyLabels = {
  'VOLUME_UP': 'Volume +',
  'VOLUME_DOWN': 'Volume −',
  'DPAD_UP': 'Croix : haut',
  'DPAD_DOWN': 'Croix : bas',
  'DPAD_LEFT': 'Croix : gauche',
  'DPAD_RIGHT': 'Croix : droite',
  'DPAD_CENTER': 'Croix : centre',
  'ENTER': 'Entrée',
  'SPACE': 'Espace',
  'MEDIA_PLAY_PAUSE': 'Lecture / pause',
  'MEDIA_NEXT': 'Suivant',
  'MEDIA_PREVIOUS': 'Précédent',
  'PAGE_UP': 'Page précédente',
  'PAGE_DOWN': 'Page suivante',
  'BUTTON_A': 'A',
  'BUTTON_B': 'B',
  'BUTTON_X': 'X',
  'BUTTON_Y': 'Y',
  'BUTTON_L1': 'L1',
  'BUTTON_R1': 'R1',
  'BUTTON_L2': 'L2',
  'BUTTON_R2': 'R2',
  'BUTTON_START': 'Start',
  'BUTTON_SELECT': 'Select',
  'CAMERA': 'Appareil photo',
};

const _upKeys = {'VOLUME_UP', 'DPAD_UP', 'PAGE_UP', 'MEDIA_NEXT', 'BUTTON_R1', 'BUTTON_R2', 'DPAD_RIGHT'};
const _downKeys = {'VOLUME_DOWN', 'DPAD_DOWN', 'PAGE_DOWN', 'MEDIA_PREVIOUS', 'BUTTON_L1', 'BUTTON_L2', 'DPAD_LEFT'};

/// Touches réglées par défaut (vitesse + / −) sur un appareil encore inconnu.
const defaultKeyActions = {..._upKeys, ..._downKeys};

String keyLabel(String key) => _keyLabels[key] != null ? tr(_keyLabels[key]!) : key.replaceAll('_', ' ').toLowerCase();

class KeyInputDriver extends ControllerDriver {
  final String descriptor;
  final List<String> keys;
  KeyInputDriver(this.descriptor, [List<String>? keys]) : keys = keys ?? [];

  @override
  String get typeId => 'keys.$descriptor';
  @override
  String get label => tr('Télécommande, manette de jeu ou clavier');
  @override
  List<ControllerButton> get buttons => [for (final k in keys) ControllerButton(k, keyLabel(k))];
  @override
  Map<String, String> get defaultClicks => {
    for (final k in keys)
      if (_upKeys.contains(k)) k: 'shiftUp' else if (_downKeys.contains(k)) k: 'shiftDown',
  };
  @override
  String get hint => tr('Appuie sur chaque touche une fois pour qu’elle apparaisse dans la liste.');
  @override
  List<Subscription> get subscriptions => const [];
  @override
  List<ButtonEvent> decode(Guid characteristic, Uint8List bytes) => const [];

  /// Ajoute une touche découverte. Renvoie true si elle est nouvelle.
  bool learn(String key) {
    if (keys.contains(key)) return false;
    keys.add(key);
    return true;
  }
}
