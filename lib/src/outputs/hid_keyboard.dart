// ShiftLink vu comme un clavier Bluetooth par l'ordinateur ou la tablette
// où tourne l'appli d'entraînement (code natif : HidKeyboard.kt).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions.dart';
import '../i18n.dart';

/// Une touche de clavier (code d'usage HID + modificateur).
class HidKey {
  final String _label;
  String get label => tr(_label);
  final int usage;
  final int modifier;
  const HidKey(this._label, this.usage, [this.modifier = 0]);

  static const shiftModifier = 0x02;
}

class HidKeys {
  static const period = HidKey('.', 0x37);
  static const comma = HidKey(',', 0x36);
  static const keypadPlus = HidKey('+ (pavé num.)', 0x57);
  static const keypadMinus = HidKey('− (pavé num.)', 0x56);
  static const plus = HidKey('+', 0x2E, HidKey.shiftModifier);
  static const minus = HidKey('−', 0x2D);
  static const arrowUp = HidKey('↑', 0x52);
  static const arrowDown = HidKey('↓', 0x51);
  static const arrowLeft = HidKey('←', 0x50);
  static const arrowRight = HidKey('→', 0x4F);
  static const pageUp = HidKey('Page préc.', 0x4B);
  static const pageDown = HidKey('Page suiv.', 0x4E);
  static const space = HidKey('Espace', 0x2C);
  static const enter = HidKey('Entrée', 0x28);
  static const escape = HidKey('Échap', 0x29);
  static const tab = HidKey('Tab', 0x2B);

  static HidKey letter(String l) => HidKey(l.toUpperCase(), 0x04 + l.toLowerCase().codeUnitAt(0) - 0x61);

  /// Touches proposées pour le réglage personnalisé.
  static final List<HidKey> all = [
    period,
    comma,
    keypadPlus,
    keypadMinus,
    plus,
    minus,
    arrowUp,
    arrowDown,
    arrowLeft,
    arrowRight,
    pageUp,
    pageDown,
    space,
    enter,
    escape,
    tab,
    for (final c in '0123456789'.split('')) HidKey(c, c == '0' ? 0x27 : 0x1E + int.parse(c) - 1),
    for (final c in 'abcdefghijklmnopqrstuvwxyz'.split('')) letter(c),
  ];
}

/// Touches d'une appli, action par action.
class KeyPreset {
  final String id;
  final String _name;
  String get name => tr(_name);
  final Map<ShiftAction, HidKey> keys;
  const KeyPreset(this.id, this._name, this.keys);

  HidKey? get up => keys[ShiftAction.shiftUp];
  HidKey? get down => keys[ShiftAction.shiftDown];
}

/// Raccourcis clavier des applis.
/// - Rouvy : aide officielle « Remote controllers and control mapping »
///   (support.rouvy.com/hc/en-us/articles/47742964491665) ;
/// - Zwift : raccourcis clavier publiés (zwiftinsider.com, carte des raccourcis) ;
/// - MyWhoosh, TrainingPeaks Virtual, Biketerra : touches des réglages de l'appli,
///   à vérifier dans l'appli en cas de doute (réglage « Personnalisé » sinon).
final List<KeyPreset> keyPresets = [
  const KeyPreset('rouvy', 'Rouvy', {ShiftAction.shiftUp: HidKeys.period, ShiftAction.shiftDown: HidKeys.comma}),
  KeyPreset('tpv', 'TrainingPeaks Virtual', {
    ShiftAction.shiftUp: HidKeys.keypadPlus,
    ShiftAction.shiftDown: HidKeys.keypadMinus,
    ShiftAction.steerLeft: HidKeys.arrowLeft,
    ShiftAction.steerRight: HidKeys.arrowRight,
    ShiftAction.toggleUi: HidKeys.letter('h'),
    ShiftAction.ergUp: HidKeys.pageUp,
    ShiftAction.ergDown: HidKeys.pageDown,
  }),
  KeyPreset('biketerra', 'Biketerra', {
    ShiftAction.shiftUp: HidKeys.letter('w'),
    ShiftAction.shiftDown: HidKeys.letter('s'),
    ShiftAction.navLeft: HidKeys.arrowLeft,
    ShiftAction.navRight: HidKeys.arrowRight,
    ShiftAction.toggleUi: HidKeys.letter('u'),
  }),
  KeyPreset('mywhoosh', 'MyWhoosh (clavier)', {
    ShiftAction.shiftUp: HidKeys.letter('k'),
    ShiftAction.shiftDown: HidKeys.letter('i'),
    ShiftAction.steerLeft: HidKeys.letter('a'),
    ShiftAction.steerRight: HidKeys.letter('d'),
    ShiftAction.navLeft: HidKeys.arrowLeft,
    ShiftAction.navRight: HidKeys.arrowRight,
    ShiftAction.toggleUi: HidKeys.letter('h'),
  }),
  const KeyPreset('zwift', 'Zwift (clavier)', {
    ShiftAction.navUp: HidKeys.arrowUp,
    ShiftAction.uturn: HidKeys.arrowDown,
    ShiftAction.steerLeft: HidKeys.arrowLeft,
    ShiftAction.steerRight: HidKeys.arrowRight,
    ShiftAction.usePowerUp: HidKeys.space,
    ShiftAction.select: HidKeys.enter,
    ShiftAction.back: HidKeys.escape,
  }),
];

/// Actions qu'on peut associer à une touche dans le réglage personnalisé.
const keyboardActions = [
  ShiftAction.shiftUp,
  ShiftAction.shiftDown,
  ShiftAction.steerLeft,
  ShiftAction.steerRight,
  ShiftAction.uturn,
  ShiftAction.navUp,
  ShiftAction.navDown,
  ShiftAction.navLeft,
  ShiftAction.navRight,
  ShiftAction.select,
  ShiftAction.back,
  ShiftAction.menu,
  ShiftAction.toggleUi,
  ShiftAction.cameraAngle,
  ShiftAction.emote,
  ShiftAction.usePowerUp,
  ShiftAction.ergUp,
  ShiftAction.ergDown,
  ShiftAction.pause,
  ShiftAction.skipInterval,
];

class HostDevice {
  final String address;
  final String name;
  const HostDevice(this.address, this.name);
}

class HidKeyboard {
  static const _channel = MethodChannel('shiftlink/hid');

  final ValueNotifier<bool> registered = ValueNotifier(false);
  final ValueNotifier<String?> connectedHost = ValueNotifier(null);
  final ValueNotifier<String?> connectingHost = ValueNotifier(null);
  final void Function(String) log;

  HidKeyboard({required this.log}) {
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'status':
          registered.value = args['registered'] == true;
        case 'connection':
          final name = args['name'] as String?;
          switch (args['state']) {
            case 'connected':
              connectingHost.value = null;
              connectedHost.value = name;
              log('Clavier connecté à $name');
            case 'connecting':
              connectingHost.value = name;
            default:
              if (connectedHost.value == name) log('Clavier déconnecté de $name');
              if (connectedHost.value == name) connectedHost.value = null;
              if (connectingHost.value == name) connectingHost.value = null;
          }
      }
    });
  }

  /// Pour le mode démo.
  bool? forceSupported;

  Future<bool> isSupported() async {
    if (forceSupported != null) return forceSupported!;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Active le profil clavier et se connecte à [address] si donné.
  Future<void> start({String? address}) => _channel.invokeMethod('start', {'address': address});

  Future<void> stop() async {
    await _channel.invokeMethod('stop');
    registered.value = false;
    connectedHost.value = null;
  }

  Future<void> makeDiscoverable() => _channel.invokeMethod('makeDiscoverable');

  Future<List<HostDevice>> bondedDevices() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('bondedDevices') ?? [];
    return [for (final m in list) HostDevice(m['address'] as String, m['name'] as String)];
  }

  /// Touche maintenue jusqu'à [keyUp] (direction).
  Future<bool> keyDown(HidKey key) async {
    if (connectedHost.value == null) return false;
    try {
      return await _channel.invokeMethod<bool>('keyDown', {'usage': key.usage, 'modifier': key.modifier}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> keyUp() async {
    try {
      await _channel.invokeMethod('keyUp');
    } catch (_) {}
  }

  Future<bool> press(HidKey key) async {
    if (connectedHost.value == null) return false;
    try {
      return await _channel.invokeMethod<bool>('pressKey', {'usage': key.usage, 'modifier': key.modifier}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
