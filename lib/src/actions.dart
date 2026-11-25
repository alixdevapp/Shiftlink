// Actions qu'un bouton de manette peut déclencher, et gestes (clic, double, long).
import 'package:flutter/material.dart';

import 'i18n.dart';

enum Gesture {
  click('Clic'),
  double('Double clic'),
  long('Appui long'),
  combo('Ensemble');

  final String _label;
  String get label => tr(_label);
  const Gesture(this._label);
}

enum ActionGroup {
  shifting('Vitesses'),
  ride('Pilotage'),
  game('Dans l’appli'),
  training('Entraînement'),
  accessories('Accessoires'),
  media('Musique'),
  phone('Téléphone');

  final String _label;
  String get label => tr(_label);
  const ActionGroup(this._label);
}

enum ShiftAction {
  shiftUp('Plus dur', Icons.add, ActionGroup.shifting, repeat: true),
  shiftDown('Plus facile', Icons.remove, ActionGroup.shifting, repeat: true),
  frontShift('Changer de plateau', Icons.swap_vert, ActionGroup.shifting),
  steerLeft('Tourner à gauche', Icons.turn_left, ActionGroup.ride, hold: true),
  steerRight('Tourner à droite', Icons.turn_right, ActionGroup.ride, hold: true),
  uturn('Demi-tour', Icons.u_turn_left, ActionGroup.ride),
  navUp('Haut', Icons.keyboard_arrow_up, ActionGroup.game),
  navDown('Bas', Icons.keyboard_arrow_down, ActionGroup.game),
  navLeft('Gauche', Icons.keyboard_arrow_left, ActionGroup.game),
  navRight('Droite', Icons.keyboard_arrow_right, ActionGroup.game),
  select('Valider', Icons.check_circle_outline, ActionGroup.game),
  back('Retour (appli)', Icons.undo, ActionGroup.game),
  menu('Menu', Icons.menu, ActionGroup.game),
  toggleUi('Afficher / masquer l’interface', Icons.visibility_outlined, ActionGroup.game),
  cameraAngle('Changer de caméra', Icons.videocam_outlined, ActionGroup.game),
  emote('Emote', Icons.emoji_emotions_outlined, ActionGroup.game),
  usePowerUp('Power-up', Icons.bolt, ActionGroup.game),
  ergUp('Intensité +', Icons.trending_up, ActionGroup.training, repeat: true),
  ergDown('Intensité −', Icons.trending_down, ActionGroup.training, repeat: true),
  powerLock('Power Lock', Icons.lock_outline, ActionGroup.training),
  pause('Pause', Icons.pause_circle_outline, ActionGroup.training),
  skipInterval('Intervalle suivant', Icons.skip_next_outlined, ActionGroup.training),
  fanUp('Ventilateur +', Icons.air, ActionGroup.accessories),
  fanDown('Ventilateur −', Icons.mode_fan_off_outlined, ActionGroup.accessories),
  mediaPlayPause('Lecture / pause', Icons.play_arrow, ActionGroup.media),
  mediaNext('Morceau suivant', Icons.skip_next, ActionGroup.media),
  mediaPrevious('Morceau précédent', Icons.skip_previous, ActionGroup.media),
  volumeUp('Volume +', Icons.volume_up, ActionGroup.media, repeat: true),
  volumeDown('Volume −', Icons.volume_down, ActionGroup.media, repeat: true),
  phoneBack('Retour Android', Icons.arrow_back, ActionGroup.phone),
  phoneHome('Écran d’accueil', Icons.home_outlined, ActionGroup.phone),
  phoneRecents('Applis récentes', Icons.layers_outlined, ActionGroup.phone),
  phoneScreenshot('Capture d’écran', Icons.screenshot_outlined, ActionGroup.phone);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final ActionGroup group;

  /// Répétée tant que le bouton est tenu (appui long).
  final bool repeat;

  /// Active tant que le bouton est tenu (direction).
  final bool hold;

  const ShiftAction(this._label, this.icon, this.group, {this.repeat = false, this.hold = false});

  static ShiftAction? byName(String? name) => ShiftAction.values.where((a) => a.name == name).firstOrNull;

  bool get isMedia => group == ActionGroup.media;
  bool get isPhone => group == ActionGroup.phone;
}
