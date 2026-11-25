// Manettes « simples » : une caractéristique, des trames courtes.
//
// Code écrit pour ShiftLink. Les identifiants Bluetooth et la forme des trames sont
// des faits imposés par chaque manette : ils ne peuvent pas être autres pour qu'elle
// réponde.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../i18n.dart';
import 'driver.dart';

/// UUID 16 bits du Bluetooth SIG, en forme longue.
Guid _sig16(int short) => Guid('0000${short.toRadixString(16).padLeft(4, '0')}-0000-1000-8000-00805f9b34fb');

const _plusMinus = [ControllerButton('plus', 'Bouton +'), ControllerButton('minus', 'Bouton −')];
const _plusMinusDefaults = {'plus': 'shiftUp', 'minus': 'shiftDown'};

/// Manette à deux boutons + / − qui n'envoie que les appuis.
abstract class _TwoButtonPad extends ControllerDriver {
  @override
  List<ControllerButton> get buttons => _plusMinus;
  @override
  Map<String, String> get defaultClicks => _plusMinusDefaults;
  @override
  bool get reportsRelease => false;
}

/// ThinkRider VS200 : une trame fixe de 5 octets par appui.
class ThinkRiderVs200Driver extends _TwoButtonPad {
  static final service = _sig16(0xfea0);
  static final characteristic = _sig16(0xfea1);

  static const _upFrame = [0xf3, 0x05, 0x03, 0x01, 0xfc];
  static const _downFrame = [0xf3, 0x05, 0x03, 0x00, 0xfb];

  @override
  String get typeId => 'vs200';
  @override
  String get label => 'ThinkRider VS200';
  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (listEquals(bytes, _upFrame)) return tap('plus');
    if (listEquals(bytes, _downFrame)) return tap('minus');
    return const [];
  }
}

/// CYCPLUS BC2 (service Nordic UART). Les octets 6 (+) et 7 (−) prennent une valeur
/// de 1 à 3 qui change à chaque appui ; 0 = rien.
class CycplusBc2Driver extends _TwoButtonPad {
  static final service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final characteristic = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  final _last = [0, 0];

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];
  @override
  String get typeId => 'bc2';
  @override
  String get label => 'CYCPLUS BC2';

  @override
  void reset() {
    super.reset();
    _last.fillRange(0, 2, 0);
  }

  static bool _counting(int v) => v >= 1 && v <= 3;

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (bytes.length < 8) return const [];
    final out = <ButtonEvent>[];
    for (final (slot, id) in const [(0, 'plus'), (1, 'minus')]) {
      final now = bytes[6 + slot];
      if (now != 0 && !_counting(now)) continue; // valeur inconnue : ignorée
      if (_counting(now) && _counting(_last[slot]) && now != _last[slot]) out.addAll(tap(id));
      _last[slot] = now;
    }
    return out;
  }
}

/// Manettes du vélo connecté CYCPLUS T7 : deux appareils, « T7H-L… » (gauche) et
/// « T7H-R… » (droite), sur le service Nordic UART. Il faut d'abord les dissocier du
/// vélo dans l'appli CYCPLUS. Trame de 4 octets : AA, x, boutons, somme des trois
/// premiers. Octet boutons : bit 7 = manette droite ; bits 0, 1, 3, 4 = les quatre
/// boutons de la manette. La trame se répète tant qu'on appuie.
class CycplusT7Driver extends ControllerDriver {
  static final service = CycplusBc2Driver.service;
  static final characteristic = CycplusBc2Driver.characteristic;

  static bool matchesName(String upperName) => upperName.startsWith('T7H-L') || upperName.startsWith('T7H-R');

  static const _bits = {0x01: 'up', 0x02: 'down', 0x08: 'back', 0x10: 'front'};

  @override
  String get typeId => 'cycplusT7';
  @override
  String get label => 'CYCPLUS T7';
  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('leftUp', 'Gauche : levier haut'),
    ControllerButton('leftDown', 'Gauche : levier bas'),
    ControllerButton('leftBack', 'Gauche : flèche arrière'),
    ControllerButton('leftFront', 'Gauche : flèche avant'),
    ControllerButton('rightUp', 'Droite : levier haut'),
    ControllerButton('rightDown', 'Droite : levier bas'),
    ControllerButton('rightBack', 'Droite : flèche arrière'),
    ControllerButton('rightFront', 'Droite : flèche avant'),
  ];
  @override
  Map<String, String> get defaultClicks => const {
    'leftUp': 'shiftDown',
    'leftDown': 'shiftUp',
    'leftBack': 'steerLeft',
    'leftFront': 'frontShift',
    'rightUp': 'shiftUp',
    'rightDown': 'shiftDown',
    'rightBack': 'steerRight',
    'rightFront': 'frontShift',
  };

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  /// Lecture d'une trame : (droite ?, masque des boutons), ou null si elle n'est pas valide.
  static (bool, int)? parse(Uint8List b) {
    if (b.length != 4 || b[0] != 0xAA || ((b[0] + b[1] + b[2]) & 0xFF) != b[3]) return null;
    return (b[2] & 0x80 != 0, b[2] & 0x7F);
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    final frame = parse(bytes);
    if (frame == null) return const [];
    final (right, mask) = frame;
    final side = right ? 'right' : 'left';
    String id(String b) => '$side${b[0].toUpperCase()}${b.substring(1)}';
    return diffState({
      for (final e in _bits.entries)
        if (mask & e.key != 0) id(e.value),
    });
  }
}

/// Elite Square : les octets 3 à 6 forment un masque des leviers (gros-boutiste).
class EliteSquareDriver extends ControllerDriver {
  static final service = Guid('347b0001-7635-408b-8918-8ff3949ce592');
  static final characteristic = Guid('347b0043-7635-408b-8918-8ff3949ce592');

  /// Bit du masque → bouton.
  static const _bits = {1: 'left1', 0: 'left2', 17: 'right1', 16: 'right2'};

  @override
  String get typeId => 'eliteSquare';
  @override
  String get label => 'Elite Square';
  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('left1', 'Levier gauche 1'),
    ControllerButton('left2', 'Levier gauche 2'),
    ControllerButton('right1', 'Levier droit 1'),
    ControllerButton('right2', 'Levier droit 2'),
  ];
  @override
  Map<String, String> get defaultClicks => const {
    'left1': 'shiftUp',
    'left2': 'shiftDown',
    'right1': 'shiftUp',
    'right2': 'shiftDown',
  };

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (bytes.length < 7) return diffState(const {});
    final mask = ByteData.sublistView(bytes, 3, 7).getUint32(0);
    return diffState({
      for (final e in _bits.entries)
        if (mask & (1 << e.key) != 0) e.value,
    });
  }
}

/// Shimano Di2, boutons réglés en canaux D-Fly dans E-TUBE.
/// Après l'octet 0, un octet par canal ; sa valeur change à chaque appui.
class ShimanoDi2Driver extends ControllerDriver {
  static Guid _shimano(String prefix) => Guid('$prefix-5348-494d-414e-4f5f424c4500');
  static final service = _shimano('000018ef');
  static final serviceAlt = _shimano('000018ff');
  static final characteristic = _shimano('00002ac2');
  static const _channels = 4;

  /// Numéro de la première trame d'une connexion, et valeur d'un canal jamais appuyé.
  static const firstReport = 0x20;
  static const unpressed = 0xF0;

  final Guid _service;
  Uint8List? _previous;

  ShimanoDi2Driver({bool alternative = false}) : _service = alternative ? serviceAlt : service;

  @override
  String get typeId => 'di2';
  @override
  String get label => 'Shimano Di2';
  @override
  List<ControllerButton> get buttons => [
    for (var i = 1; i <= _channels; i++) ControllerButton('ch$i', 'Canal D-Fly $i'),
  ];
  @override
  Map<String, String> get defaultClicks => {
    for (var i = 1; i <= _channels; i++) 'ch$i': i.isOdd ? 'shiftUp' : 'shiftDown',
  };
  @override
  bool get reportsRelease => false;

  @override
  String get hint => tr(
    'Règle tes boutons sur les canaux D-Fly dans l’app Shimano E-TUBE. Par défaut, canaux 1 et 3 = vitesse +, canaux 2 et 4 = vitesse −.',
  );

  @override
  List<Subscription> get subscriptions => [Subscription(_service, characteristic)];

  @override
  void reset() {
    super.reset();
    _previous = null;
  }

  /// Si l'état des canaux se lit, on part de lui : le tout premier appui compte aussi.
  @override
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {
    final chr = services.expand((s) => s.characteristics).where((ch) => ch.uuid == characteristic).firstOrNull;
    if (chr == null || !chr.properties.read) return;
    try {
      final state = await chr.read();
      if (state.length >= 2 && _previous == null) _previous = Uint8List.fromList(state.sublist(1));
    } catch (_) {}
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (bytes.length < 2) return const [];
    final now = Uint8List.fromList(bytes.sublist(1));
    var before = _previous;
    _previous = now;
    // Chaque connexion numérote ses trames à partir de 0x20, canaux au repos à 0xF0 :
    // la toute première trame porte donc déjà un appui. Plus tard, elle ne donne que l'état.
    if (before == null && bytes[0] == firstReport) before = Uint8List(now.length)..fillRange(0, now.length, unpressed);
    if (before == null) return const [];
    final out = <ButtonEvent>[];
    final n = [now.length, before.length, _channels].reduce((a, b) => a < b ? a : b);
    for (var ch = 0; ch < n; ch++) {
      if (now[ch] != before[ch]) out.addAll(tap('ch${ch + 1}'));
    }
    return out;
  }
}

/// SRAM AXS : la trame ne dit pas quel bouton : toute notification = un appui.
/// Par défaut, un appui = vitesse +, double appui = vitesse −.
class SramAxsDriver extends ControllerDriver {
  static final advertisedService = _sig16(0xfe51);
  static final service = Guid('d9050053-90aa-4c7c-b036-1e01fb8eb7ee');
  static final characteristic = Guid('d9050054-90aa-4c7c-b036-1e01fb8eb7ee');

  @override
  String get typeId => 'axs';
  @override
  String get label => 'SRAM AXS';
  @override
  List<ControllerButton> get buttons => const [ControllerButton('button', 'Bouton AXS')];
  @override
  Map<String, String> get defaultClicks => const {'button': 'shiftUp'};
  @override
  Map<String, String> get defaultDoubles => const {'button': 'shiftDown'};
  @override
  bool get reportsRelease => false;

  @override
  String get hint => tr(
    'Par défaut, un appui = vitesse +, double appui = vitesse −. Désactive la fonction du bouton dans l’app SRAM AXS.',
  );

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) => tap('button');
}

/// Boutons du Wahoo KICKR Bike (Shift / Pro). Trame de 3 octets : code du bouton sur
/// 16 bits (gros-boutiste), puis un octet dont le bit 7 dit « appuyé ».
class WahooKickrBikeDriver extends ControllerDriver {
  static Guid _wahoo(String prefix) => Guid('$prefix-0a7d-4ab3-97fa-f1500f9feb8b');
  static final service = _wahoo('a026ee0d');
  static final characteristic = _wahoo('a026e03c');

  static const _byCode = <int, ControllerButton>{
    0x0001: ControllerButton('rightTop', 'Droite haut'),
    0x8000: ControllerButton('rightBottom', 'Droite bas'),
    0x0004: ControllerButton('rightPlus', 'Vitesse + droite'),
    0x0002: ControllerButton('rightMinus', 'Vitesse − droite'),
    0x4000: ControllerButton('rightBrake', 'Frein droit'),
    0x0200: ControllerButton('leftTop', 'Gauche haut'),
    0x0400: ControllerButton('leftBottom', 'Gauche bas'),
    0x1000: ControllerButton('leftPlus', 'Vitesse + gauche'),
    0x0800: ControllerButton('leftMinus', 'Vitesse − gauche'),
    0x0100: ControllerButton('leftBrake', 'Frein gauche'),
  };

  final Set<String> _held = {};

  @override
  String get typeId => 'kickrBike';
  @override
  String get label => 'Wahoo KICKR Bike';
  @override
  List<ControllerButton> get buttons => _byCode.values.toList();

  /// Côté droit = plus dur, côté gauche = plus facile.
  @override
  Map<String, String> get defaultClicks => {
    for (final b in _byCode.values) b.id: b.id.startsWith('left') ? 'shiftDown' : 'shiftUp',
  };

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  void reset() {
    super.reset();
    _held.clear();
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (bytes.length != 3) return const [];
    final button = _byCode[(bytes[0] << 8) | bytes[1]];
    if (button == null) return const [];
    final pressed = bytes[2] & 0x80 != 0;
    pressed ? _held.add(button.id) : _held.remove(button.id);
    return diffState({..._held});
  }
}

/// Modèle de commande WHEELTOP EDS, lu dans l'annonce Bluetooth.
enum WheeltopEdsType {
  ox('OX', 0x37),
  txFront('TX avant', 0x39),
  txLeft('TX gauche', 0x36),
  txRight('TX droite', 0x38);

  final String label;
  final int typeByte;
  const WheeltopEdsType(this.label, this.typeByte);

  static WheeltopEdsType? fromByte(int b) => values.where((t) => t.typeByte == b).firstOrNull;
}

/// Commandes de vitesses sans fil WHEELTOP EDS (OX, TX).
/// Service Nordic UART, notifications sur 6e400002. Deux trames possibles :
/// `04 code xor` (OX) ou `04 type code somme` (TX). Codes : 1/2 appui bas/haut,
/// 5/6 appui bas/haut avec l'interrupteur sur « T », 9/10 relâchement bas/haut,
/// 3/4/7/8 répétitions pendant l'appui (ignorées), 0x10 trame d'état des TX.
class WheeltopEdsDriver extends ControllerDriver {
  static final service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final characteristic = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');

  /// Début fixe des données constructeur (les deux premiers octets servent d'identifiant constructeur).
  static const advPrefix = [0x07, 0x0f, 0x00, 0x14, 0x55, 0x6a, 0x84];

  final WheeltopEdsType type;
  WheeltopEdsDriver(this.type);

  final Set<String> _held = {};

  /// Le modèle si ces données constructeur sont celles d'une commande EDS, sinon null.
  static WheeltopEdsType? typeFromAdvertisement(Map<int, List<int>> manufacturerData) {
    for (final MapEntry(key: id, value: payload) in manufacturerData.entries) {
      for (final bytes in [
        [id & 0xff, (id >> 8) & 0xff, ...payload],
        payload,
      ]) {
        if (bytes.length <= advPrefix.length) continue;
        if (!listEquals(bytes.sublist(0, advPrefix.length), advPrefix)) continue;
        final t = WheeltopEdsType.fromByte(bytes[advPrefix.length]);
        if (t != null) return t;
      }
    }
    return null;
  }

  @override
  String get typeId => 'wheeltopEds';
  @override
  String get label => 'WHEELTOP EDS ${type.label}';
  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('top', 'Bouton du haut'),
    ControllerButton('bottom', 'Bouton du bas'),
    ControllerButton('topFine', 'Haut, interrupteur sur T'),
    ControllerButton('bottomFine', 'Bas, interrupteur sur T'),
  ];
  @override
  Map<String, String> get defaultClicks => const {'top': 'shiftUp', 'bottom': 'shiftDown'};

  @override
  String get hint => tr(
    'Éteins le dérailleur arrière (ou mets-le hors de portée) : la commande ne se connecte qu’à un appareil à la fois. Interrupteur sur R = vitesses, sur T = deux boutons de plus.',
  );

  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  void reset() {
    super.reset();
    _held.clear();
  }

  /// Code du bouton si la trame est valide, sinon null.
  static int? opcode(Uint8List b) {
    if (b.length == 3 && b[0] == 0x04 && b[2] == (b[0] ^ b[1])) return b[1];
    if (b.length == 4 &&
        b[0] == 0x04 &&
        WheeltopEdsType.fromByte(b[1]) != null &&
        b[3] == ((b[0] + b[1] + b[2]) & 0xff)) {
      return b[2];
    }
    return null;
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    switch (opcode(bytes)) {
      case 0x01:
        _held.add('bottom');
      case 0x02:
        _held.add('top');
      case 0x05:
        _held.add('bottomFine');
      case 0x06:
        _held.add('topFine');
      case 0x09:
        _held.removeAll(const ['bottom', 'bottomFine']);
      case 0x0a:
        _held.removeAll(const ['top', 'topFine']);
      default:
        return const [];
    }
    return diffState({..._held});
  }
}

/// Magene Onelap Key : croix à cinq boutons. Elle signale elle-même les appuis
/// courts (masque à l'octet 8) et les appuis longs (masque à l'octet 10) ; un
/// appui long dure jusqu'à la trame suivante.
class OnelapKeyDriver extends ControllerDriver {
  static final service = Guid('8ce5cc01-0a4d-11e9-ab14-d663bd873d93');
  static final characteristic = Guid('8ce5cc02-0a4d-11e9-ab14-d663bd873d93');

  /// Bit du masque → bouton.
  static const _bits = ['center', 'left', 'up', 'right', 'down'];

  /// Nom annoncé : « Onelap Key » ou « Onelap Key_12224 ».
  static bool matchesName(String upperName) {
    final n = upperName.trim();
    return n == 'ONELAP KEY' || n.startsWith('ONELAP KEY_');
  }

  final Set<String> _held = {};

  @override
  String get typeId => 'onelapKey';
  @override
  String get label => 'Magene Onelap Key';
  @override
  List<ControllerButton> get buttons => const [
    ControllerButton('up', 'Haut'),
    ControllerButton('down', 'Bas'),
    ControllerButton('left', 'Gauche'),
    ControllerButton('right', 'Droite'),
    ControllerButton('center', 'Centre'),
  ];
  @override
  Map<String, String> get defaultClicks => const {
    'up': 'shiftUp',
    'down': 'shiftDown',
    'left': 'navLeft',
    'right': 'navRight',
    'center': 'select',
  };
  @override
  List<Subscription> get subscriptions => [Subscription(service, characteristic)];

  @override
  void reset() {
    super.reset();
    _held.clear();
  }

  List<ButtonEvent> _releaseHeld() {
    final out = [for (final id in _held) release(id)];
    _held.clear();
    return out;
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    // Toute nouvelle trame termine un appui long en cours.
    final out = _releaseHeld();
    if (bytes.length < 11 || bytes[1] != 0xF5 || bytes[2] != 0x10) return out;
    if (bytes[5] & 0x1F > 2) return out; // type d'appareil inconnu
    final clicks = bytes[8] & 0x1F;
    final longs = bytes[10] & 0x1F;
    for (var i = 0; i < _bits.length; i++) {
      if (clicks & (1 << i) != 0) out.addAll(tap(_bits[i]));
    }
    for (var i = 0; i < _bits.length; i++) {
      if (longs & (1 << i) != 0) {
        _held.add(_bits[i]);
        out.add(press(_bits[i]));
      }
    }
    return out;
  }
}
