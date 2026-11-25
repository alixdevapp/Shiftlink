// Manettes Zwift : Click (1re génération), Play, Ride (V1 et V2) et Click v2.
//
// Code écrit pour ShiftLink. Faits de protocole tirés des descriptions publiques :
// - service 00000001-19ca-4651-86e5-fa29dcdd09d1, caractéristiques 2/3/4, poignée de
//   main « RideOn » : https://github.com/ajchellew/zwiftplay ;
// - Zwift Ride / Click v2 (service 0xFC82, message 0x23, masque de boutons, palettes) :
//   https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/
// Les messages sont des protobufs : on lit les champs nous-mêmes (pas de dépendance).
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../i18n.dart';
import 'driver.dart';

/// Identifiants Bluetooth et types d'appareils Zwift.
class ZwiftIds {
  static Guid _zwift(int n) => Guid('0000000$n-19ca-4651-86e5-fa29dcdd09d1');

  static final customService = _zwift(1);
  static final rideService = Guid('0000fc82-0000-1000-8000-00805f9b34fb');
  static final asyncChar = _zwift(2);
  static final syncRxChar = _zwift(3);
  static final syncTxChar = _zwift(4);

  /// Identifiant constructeur Zwift dans l'annonce (0x094A).
  static const manufacturerId = 0x094A;

  // Premier octet des données constructeur : type d'appareil.
  static const playRight = 2;
  static const playLeft = 3;
  static const rideRight = 7;
  static const rideLeft = 8;
  static const click = 9;
  static const clickV2Right = 10;
  static const clickV2Left = 11;

  /// Zwift Play mise à jour en firmware 2 : elle parle comme la Ride.
  static const playFw2 = 14;

  /// « RideOn » en ASCII : message d'ouverture.
  static final List<int> rideOn = 'RideOn'.codeUnits;

  // Premier octet d'une notification : type du message.
  static const clickMsg = 0x37;
  static const playMsg = 0x07;
  static const rideMsg = 0x23;

  /// Début du message de vibration (suivi de la force).
  static const vibrate = [0x12, 0x12, 0x08, 0x0A, 0x06, 0x08, 0x02, 0x10, 0x00, 0x18];
}

/// Un champ protobuf : numéro, valeur entière (varint) ou octets bruts.
class _PbField {
  final int number;
  final int? value;
  final Uint8List? data;
  const _PbField(this.number, {this.value, this.data});
}

/// Parcourt un message protobuf. S'arrête net sur un type inconnu ou une trame tronquée.
Iterable<_PbField> _pbFields(Uint8List buf) sync* {
  var pos = 0;
  int? varint() {
    var v = 0;
    for (var shift = 0; pos < buf.length && shift < 64; shift += 7) {
      final byte = buf[pos++];
      v |= (byte & 0x7f) << shift;
      if (byte < 0x80) return v;
    }
    return null;
  }

  while (pos < buf.length) {
    final tag = varint();
    if (tag == null) return;
    final number = tag >> 3;
    switch (tag & 7) {
      case 0:
        final v = varint();
        if (v == null) return;
        yield _PbField(number, value: v);
      case 2:
        final len = varint();
        if (len == null || pos + len > buf.length) return;
        yield _PbField(number, data: Uint8List.sublistView(buf, pos, pos + len));
        pos += len;
      case 1:
        pos += 8;
      case 5:
        pos += 4;
      default:
        return;
    }
  }
}

/// Champs entiers d'un message (le dernier l'emporte).
Map<int, int> _pbInts(Uint8List buf) => {
  for (final f in _pbFields(buf))
    if (f.value != null) f.number: f.value!,
};

/// Décodage « zigzag » des entiers signés (sint32).
int _unzigzag(int n) => n.isEven ? n ~/ 2 : -(n + 1) ~/ 2;

/// Base des manettes Zwift : abonnements, « RideOn », état des boutons.
abstract class _ZwiftController extends ControllerDriver {
  final Guid service;
  _ZwiftController(this.service);

  /// Type de message qui porte l'état des boutons.
  int get buttonMessage;

  /// Boutons appuyés d'après le contenu du message (sans l'octet de type).
  Set<String> pressedButtons(Uint8List body);

  /// Message d'ouverture écrit sur la caractéristique « sync RX ».
  List<int> get startCommand => ZwiftIds.rideOn;

  @override
  List<Subscription> get subscriptions => [
    Subscription(service, ZwiftIds.asyncChar),
    Subscription(service, ZwiftIds.syncTxChar),
  ];

  @override
  String get hint => tr('Ferme Zwift et Zwift Companion : la manette ne se connecte qu’à une app à la fois.');

  BluetoothCharacteristic? _rx;

  /// La manette a-t-elle un vibreur (Play, Ride) ?
  bool get hasVibrator => false;

  @override
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {
    final rx = services
        .where((s) => s.uuid == service)
        .expand((s) => s.characteristics)
        .firstWhere((c) => c.uuid == ZwiftIds.syncRxChar);
    _rx = rx;
    await rx.write(startCommand, withoutResponse: true);
  }

  /// Vibration : message 0x12 (retour haptique) écrit sur « sync RX », dernier octet = force.
  @override
  Future<bool> vibrate({bool strong = false}) async {
    final rx = _rx;
    if (!hasVibrator || rx == null) return false;
    try {
      await rx.write([...ZwiftIds.vibrate, strong ? 0x40 : 0x20], withoutResponse: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isRideOnReply(Uint8List b) {
    final r = ZwiftIds.rideOn;
    if (b.length < r.length) return false;
    for (var i = 0; i < r.length; i++) {
      if (b[i] != r[i]) return false;
    }
    return true;
  }

  bool acceptsMessage(int type) => type == buttonMessage;

  @override
  List<ButtonEvent> decode(Guid characteristic, Uint8List bytes) {
    if (bytes.isEmpty || _isRideOnReply(bytes)) return const [];
    if (!acceptsMessage(bytes[0])) return const [];
    // L'état est répété tant qu'on tient un bouton : on ne garde que les changements.
    return diffState(pressedButtons(Uint8List.sublistView(bytes, 1)));
  }
}

/// Dans les messages Click et Play, chaque bouton a son champ : 0 (ou absent) = appuyé.
bool _down(Map<int, int> fields, int number) => (fields[number] ?? 0) == 0;

/// Zwift Click (première génération) : champ 1 = +, champ 2 = −.
class ZwiftClickDriver extends _ZwiftController {
  ZwiftClickDriver() : super(ZwiftIds.customService);

  @override
  String get typeId => 'zwiftClick';
  @override
  String get label => 'Zwift Click';
  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('plus', 'Bouton +'),
    ControllerButton('minus', 'Bouton −'),
  ];
  @override
  Map<String, String> get defaultClicks => const {'plus': 'shiftUp', 'minus': 'shiftDown'};

  @override
  int get buttonMessage => ZwiftIds.clickMsg;

  // Certains firmwares envoient le format du Play.
  @override
  bool acceptsMessage(int type) => type == ZwiftIds.clickMsg || type == ZwiftIds.playMsg;

  @override
  Set<String> pressedButtons(Uint8List body) {
    final f = _pbInts(body);
    return {if (_down(f, 1)) 'plus', if (_down(f, 2)) 'minus'};
  }
}

/// Zwift Play : une poignée = un appareil.
/// Champs 2 à 5 : les quatre boutons de la face (croix à gauche, Y/Z/A/B à droite),
/// 6 : bouton latéral, 7 : marche, 8 : palette analogique (sint32, −100 à 100).
class ZwiftPlayDriver extends _ZwiftController {
  final bool left;
  ZwiftPlayDriver({required this.left}) : super(ZwiftIds.customService);

  @override
  bool get hasVibrator => true;

  static const _leftFace = {2: 'up', 3: 'left', 4: 'right', 5: 'down'};
  static const _rightFace = {2: 'y', 3: 'z', 4: 'a', 5: 'b'};

  @override
  String get typeId => left ? 'zwiftPlayLeft' : 'zwiftPlayRight';
  @override
  String get label => tr('Zwift Play ({0})', [left ? tr('gauche') : tr('droite')]);

  @override
  List<ControllerButton> get buttons => [
    const ControllerButton('side', 'Bouton latéral'),
    const ControllerButton('paddle', 'Palette'),
    ...left
        ? const [
            ControllerButton('up', 'Haut'),
            ControllerButton('down', 'Bas'),
            ControllerButton('left', 'Gauche'),
            ControllerButton('right', 'Droite'),
          ]
        : const [
            ControllerButton('y', 'Y'),
            ControllerButton('z', 'Z'),
            ControllerButton('a', 'A'),
            ControllerButton('b', 'B'),
          ],
    const ControllerButton('power', 'Bouton marche'),
  ];

  @override
  Map<String, String> get defaultClicks {
    final action = left ? 'shiftDown' : 'shiftUp';
    return {'side': action, 'paddle': action};
  }

  @override
  int get buttonMessage => ZwiftIds.playMsg;

  @override
  Set<String> pressedButtons(Uint8List body) {
    final f = _pbInts(body);
    final face = left ? _leftFace : _rightFace;
    final out = <String>{
      for (final e in face.entries)
        if (_down(f, e.key)) e.value,
    };
    if (_down(f, 6)) out.add('side');
    if (_down(f, 7)) out.add('power');
    // La palette compte comme appuyée seulement à fond.
    if (_unzigzag(f[8] ?? 0).abs() >= 100) out.add('paddle');
    return out;
  }
}

/// Zwift Ride : la poignée gauche relaie la droite.
/// Champ 1 : masque des boutons (bit à 0 = appuyé) ; champ 3 (répété) : palettes
/// analogiques { 1 : position (0 gauche, 1 droite), 2 : valeur sint32 }.
class ZwiftRideDriver extends _ZwiftController {
  ZwiftRideDriver(super.service);

  @override
  bool get hasVibrator => true;

  /// Boutons dans l'ordre des bits du masque (bit 0 en premier).
  static const _bitOrder = [
    'navLeft', 'navUp', 'navRight', 'navDown', //
    'a', 'b', 'y', 'z',
    'shiftUpLeft', 'shiftDownLeft', 'powerUpLeft', 'onOffLeft',
    'shiftUpRight', 'shiftDownRight', 'powerUpRight', 'onOffRight',
  ];

  /// Une palette à partir de ce niveau compte comme un appui.
  static const paddleThreshold = 25;

  static const _labels = {
    'shiftUpRight': 'Droite : vitesse haut',
    'shiftDownRight': 'Droite : vitesse bas',
    'paddleRight': 'Palette droite',
    'shiftUpLeft': 'Gauche : vitesse haut',
    'shiftDownLeft': 'Gauche : vitesse bas',
    'paddleLeft': 'Palette gauche',
    'navUp': 'Croix : haut',
    'navDown': 'Croix : bas',
    'navLeft': 'Croix : gauche',
    'navRight': 'Croix : droite',
    'a': 'A',
    'b': 'B',
    'y': 'Y',
    'z': 'Z',
    'powerUpLeft': 'Power-up gauche',
    'powerUpRight': 'Power-up droite',
    'onOffLeft': 'Marche gauche',
    'onOffRight': 'Marche droite',
  };

  /// Firmware lu à la connexion. La Ride V2 se reconnaît à son firmware 1.3 ou plus.
  String? firmware;

  /// Premier firmware de la Zwift Ride V2.
  static const rideV2Firmware = (1, 3);

  /// Le firmware [fw] (« 1.3.0 », « 1.3.0.24 »…) est-il celui d'une Ride V2 ?
  static bool isV2Firmware(String? fw) {
    final m = RegExp(r'^\s*(\d+)\.(\d+)').firstMatch(fw ?? '');
    if (m == null) return false;
    final (major, minor) = (int.parse(m[1]!), int.parse(m[2]!));
    return major > rideV2Firmware.$1 || (major == rideV2Firmware.$1 && minor >= rideV2Firmware.$2);
  }

  bool get isV2 => runtimeType == ZwiftRideDriver && isV2Firmware(firmware);

  @override
  void onFirmware(String firmware) => this.firmware = firmware;

  @override
  String get typeId => 'zwiftRide';
  @override
  String get label => isV2 ? 'Zwift Ride V2' : 'Zwift Ride';

  @override
  String get hint => isV2
      ? tr('Zwift Ride V2 : si elle se coupe ou ne répond plus, connecte-la 30 s dans l’appli Zwift, ferme Zwift, puis reviens ici.')
      : tr('Ferme Zwift et Zwift Companion. Si rien ne se passe, mets à jour le firmware dans Companion.');

  /// Une Ride V2 verrouillée cache son service Zwift jusqu'à ce que Zwift la déverrouille.
  @override
  String? get missingServiceHint => tr(
    'Zwift Ride V2 verrouillée : connecte-la 30 s dans l’appli Zwift (pas Companion), ferme Zwift, puis reviens ici.',
  );

  @override
  List<ControllerButton> get buttons => [for (final e in _labels.entries) ControllerButton(e.key, e.value)];

  @override
  Map<String, String> get defaultClicks => const {
    'shiftUpRight': 'shiftUp',
    'shiftDownRight': 'shiftUp',
    'paddleRight': 'shiftUp',
    'shiftUpLeft': 'shiftDown',
    'shiftDownLeft': 'shiftDown',
    'paddleLeft': 'shiftDown',
  };

  @override
  int get buttonMessage => ZwiftIds.rideMsg;

  @override
  Set<String> pressedButtons(Uint8List body) {
    var mask = -1; // aucun bouton si le champ manque
    final out = <String>{};
    for (final field in _pbFields(body)) {
      if (field.number == 1 && field.value != null) mask = field.value!;
      if (field.number == 3 && field.data != null) {
        final p = _pbInts(field.data!);
        if (_unzigzag(p[2] ?? 0).abs() < paddleThreshold) continue;
        switch (p[1] ?? 0) {
          case 0:
            out.add('paddleLeft');
          case 1:
            out.add('paddleRight');
        }
      }
    }
    for (var bit = 0; bit < _bitOrder.length; bit++) {
      if ((mask >> bit) & 1 == 0) out.add(_bitOrder[bit]);
    }
    return out;
  }
}

/// Zwift Click v2 : même format que la Ride, moins de boutons.
/// Elle ne répond qu'aux applis qui l'ont « déverrouillée » récemment : il faut l'avoir
/// connectée à l'appli Zwift (pas Companion) peu avant.
class ZwiftClickV2Driver extends ZwiftRideDriver {
  ZwiftClickV2Driver(super.service);

  @override
  bool get hasVibrator => false;

  @override
  String get typeId => 'zwiftClickV2';

  @override
  List<int> get startCommand => [...ZwiftIds.rideOn, 0x02, 0x03];

  @override
  String get label => tr('Zwift Click v2 (bêta)');

  @override
  String get hint => tr(
    'Si elle se déconnecte au bout d’une minute : active « Click v2 : côté droit seul » dans Appareils (rien à faire dans Zwift), ou connecte-la 30 s dans l’appli Zwift chaque jour.',
  );

  @override
  String? get missingServiceHint => tr(
    'Click v2 verrouillée : active « Click v2 : côté droit seul » dans Appareils, ou connecte-la 30 s dans l’appli Zwift.',
  );

  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('shiftUpRight', 'Bouton +'),
    ControllerButton('shiftUpLeft', 'Bouton −'),
    ControllerButton('navUp', 'Croix : haut'),
    ControllerButton('navDown', 'Croix : bas'),
    ControllerButton('navLeft', 'Croix : gauche'),
    ControllerButton('navRight', 'Croix : droite'),
    ControllerButton('a', 'A'),
    ControllerButton('b', 'B'),
    ControllerButton('y', 'Y'),
    ControllerButton('z', 'Z'),
  ];

  @override
  Map<String, String> get defaultClicks => const {'shiftUpRight': 'shiftUp', 'shiftUpLeft': 'shiftDown'};
}

/// Zwift Click v2, côté droit seul : pas de déverrouillage dans Zwift.
/// + passe plus dur, B plus facile ; le côté gauche reste éteint.
class ZwiftClickV2RightDriver extends ZwiftClickV2Driver {
  ZwiftClickV2RightDriver(super.service);

  @override
  String get typeId => 'zwiftClickV2Right';
  @override
  String get label => tr('Zwift Click v2 (côté droit)');

  @override
  String get hint => tr('Côté droit seul : pas besoin de Zwift. + passe plus dur, B plus facile.');

  @override
  String? get missingServiceHint => null;

  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('shiftUpRight', 'Bouton +'),
    ControllerButton('a', 'A'),
    ControllerButton('b', 'B'),
    ControllerButton('y', 'Y'),
    ControllerButton('z', 'Z'),
  ];

  @override
  Map<String, String> get defaultClicks => const {'shiftUpRight': 'shiftUp', 'b': 'shiftDown'};
}

/// Zwift Play mise à jour en firmware 2 : même format que la Ride, sans les boutons
/// de vitesse du bas. Chaque poignée se connecte seule.
class ZwiftPlayFw2Driver extends ZwiftRideDriver {
  ZwiftPlayFw2Driver(super.service);

  @override
  String get typeId => 'zwiftPlayFw2';
  @override
  String get label => tr('Zwift Play (firmware 2)');

  @override
  String get hint => tr('Ferme Zwift et Zwift Companion : la manette ne se connecte qu’à une app à la fois.');

  @override
  String? get missingServiceHint => null;

  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('shiftUpRight', 'Droite : bouton latéral'),
    ControllerButton('paddleRight', 'Palette droite'),
    ControllerButton('shiftUpLeft', 'Gauche : bouton latéral'),
    ControllerButton('paddleLeft', 'Palette gauche'),
    ControllerButton('navUp', 'Croix : haut'),
    ControllerButton('navDown', 'Croix : bas'),
    ControllerButton('navLeft', 'Croix : gauche'),
    ControllerButton('navRight', 'Croix : droite'),
    ControllerButton('a', 'A'),
    ControllerButton('b', 'B'),
    ControllerButton('y', 'Y'),
    ControllerButton('z', 'Z'),
    ControllerButton('onOffLeft', 'Marche gauche'),
    ControllerButton('onOffRight', 'Marche droite'),
  ];

  @override
  Map<String, String> get defaultClicks => const {
    'shiftUpRight': 'shiftUp',
    'paddleRight': 'shiftUp',
    'shiftUpLeft': 'shiftDown',
    'paddleLeft': 'shiftDown',
  };
}
