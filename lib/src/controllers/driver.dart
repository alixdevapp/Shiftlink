// Base commune des manettes Bluetooth.
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../i18n.dart';

String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Un bouton physique d'une manette.
class ControllerButton {
  final String id;
  final String _label;
  String get label => tr(_label);
  const ControllerButton(this.id, this._label);
}

/// Un bouton appuyé ([down] = true) ou relâché.
class ButtonEvent {
  final String id;
  final bool down;
  const ButtonEvent(this.id, this.down);

  @override
  bool operator ==(Object other) => other is ButtonEvent && other.id == id && other.down == down;
  @override
  int get hashCode => Object.hash(id, down);
  @override
  String toString() => '${down ? '↓' : '↑'}$id';
}

/// Raccourcis pour les tests et les pilotes.
ButtonEvent press(String id) => ButtonEvent(id, true);
ButtonEvent release(String id) => ButtonEvent(id, false);

/// Une caractéristique à laquelle s'abonner.
class Subscription {
  final Guid service;
  final Guid characteristic;

  /// Si la caractéristique manque (autre firmware), on continue sans elle.
  final bool optional;
  const Subscription(this.service, this.characteristic, {this.optional = false});
}

/// Pilote d'une manette : sait à quoi s'abonner et comment décoder les trames.
abstract class ControllerDriver {
  /// Identifiant stable du type de manette (sert aux réglages des boutons).
  String get typeId;

  /// Nom affiché du type de manette (« Zwift Click », « ThinkRider VS200 »…).
  String get label;

  /// Boutons de la manette, dans l'ordre d'affichage.
  List<ControllerButton> get buttons;

  /// Action par défaut d'un clic : 'shiftUp', 'shiftDown' ou absent.
  Map<String, String> get defaultClicks;

  /// Action par défaut d'un double clic (SRAM AXS).
  Map<String, String> get defaultDoubles => const {};

  /// La manette signale-t-elle le relâchement des boutons ? Sinon pas d'appui long.
  bool get reportsRelease => true;

  /// Caractéristiques à écouter (notifications ou indications).
  List<Subscription> get subscriptions;

  /// Appelé une fois abonné, pour un éventuel message d'initialisation.
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {}

  /// Décode une trame : boutons appuyés et relâchés.
  List<ButtonEvent> decode(Guid characteristic, Uint8List bytes);

  /// Fait vibrer la manette, si elle a un vibreur. Renvoie false sinon.
  Future<bool> vibrate({bool strong = false}) async => false;

  /// Remet à zéro l'état interne (après une reconnexion).
  void reset() => _pressed.clear();

  /// Nom affiché d'un bouton.
  String labelOf(String buttonId) => buttons.where((b) => b.id == buttonId).firstOrNull?.label ?? buttonId;

  /// Message d'aide affiché sous la manette, ou null.
  String? get hint => null;

  /// Explication quand la manette ne montre pas son service (verrouillée…), ou null.
  String? get missingServiceHint => null;

  /// Version du firmware lue à la connexion (certaines manettes en dépendent).
  void onFirmware(String firmware) {}

  final Set<String> _pressed = {};

  /// Pour les manettes qui envoient l'état complet des boutons : renvoie les changements.
  List<ButtonEvent> diffState(Set<String> now) {
    final out = [
      for (final id in _pressed)
        if (!now.contains(id)) release(id),
      for (final id in now)
        if (!_pressed.contains(id)) press(id),
    ];
    _pressed
      ..clear()
      ..addAll(now);
    return out;
  }

  /// Pour les manettes qui ne signalent qu'un appui : appui + relâchement immédiats.
  List<ButtonEvent> tap(String id) => [press(id), release(id)];
}
