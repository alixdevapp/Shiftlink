// ShiftLink vu par Zwift comme une manette Zwift Ride (bêta). Zwift fait alors
// ses propres vitesses virtuelles avec un trainer compatible, et ShiftLink lui
// donne tous les boutons : vitesses, direction, power-up, menu, demi-tour…
//
// Code écrit pour ShiftLink d'après la description publique du protocole de la
// Zwift Ride (https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/) :
// poignée de main « RideOn » sans chiffrement, puis messages 0x23 dont le champ 1
// est un masque de boutons inversé (bit à 0 = appuyé). Serveur GATT en Kotlin
// (ZwiftRidePeripheral.kt).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ZwiftRideEmulator {
  static const _channel = MethodChannel('shiftlink/zwiftride');

  /// Bit de chaque bouton dans le masque de la Ride.
  static const bits = {
    'navLeft': 0x1,
    'navUp': 0x2,
    'navRight': 0x4,
    'navDown': 0x8,
    'a': 0x10,
    'b': 0x20,
    'y': 0x40,
    'z': 0x100,
    'shiftUpLeft': 0x200,
    'shiftDownLeft': 0x400,
    'powerUpLeft': 0x800,
    'onOffLeft': 0x1000,
    'shiftUpRight': 0x2000,
    'shiftDownRight': 0x4000,
    'powerUpRight': 0x10000,
    'onOffRight': 0x20000,
  };

  /// Action ShiftLink → bouton de la Ride, tels que Zwift les comprend.
  static const actions = {
    'shiftUp': 'shiftUpRight',
    'shiftDown': 'shiftDownRight',
    'frontShift': 'shiftUpLeft',
    'navUp': 'navUp',
    'navDown': 'navDown',
    'navLeft': 'navLeft',
    'navRight': 'navRight',
    'steerLeft': 'navLeft',
    'steerRight': 'navRight',
    'select': 'a',
    'back': 'z',
    'menu': 'y',
    'uturn': 'navDown',
    'usePowerUp': 'powerUpLeft',
    'emote': 'b',
  };

  /// Message « état des boutons » de la Ride : 0x23, champ 1 = masque inversé.
  static Uint8List keypad(int pressedMask) {
    var v = (~pressedMask) & 0xFFFFFFFF;
    final out = <int>[0x23, 0x08];
    while (v >= 0x80) {
      out.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return Uint8List.fromList(out);
  }

  /// Aucun bouton appuyé (sert aussi de message « je suis là »).
  static final Uint8List idle = keypad(0);

  final void Function(String) log;
  final ValueNotifier<bool> isStarted = ValueNotifier(false);

  /// Zwift a fait la poignée de main : nom de l'appareil connecté.
  final ValueNotifier<String?> client = ValueNotifier(null);

  /// Zwift demande une vibration.
  void Function()? onHaptic;

  int _pressed = 0;

  ZwiftRideEmulator({required this.log});

  bool get isConnected => client.value != null;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'client':
        final name = (call.arguments as Map)['name'] as String?;
        if (name != client.value) log(name == null ? 'Zwift (manette Ride) déconnecté' : 'Zwift connecté à la manette Ride');
        client.value = name;
        if (name == null) _pressed = 0;
      case 'haptic':
        onHaptic?.call();
      case 'log':
        log('Manette Ride : ${(call.arguments as Map)['message']}');
    }
    return null;
  }

  Future<void> start() async {
    if (isStarted.value) return;
    _channel.setMethodCallHandler(_onCall);
    try {
      isStarted.value = await _channel.invokeMethod<bool>('start') ?? false;
      if (!isStarted.value) log('Manette Ride : Bluetooth éteint ou indisponible');
    } catch (e) {
      log('Manette Ride : $e');
    }
  }

  Future<void> stop() async {
    if (!isStarted.value) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    isStarted.value = false;
    client.value = null;
    _pressed = 0;
  }

  void _send() => _channel.invokeMethod('send', {'data': keypad(_pressed)}).catchError((_) {});

  /// Bouton de l'action [action] : [pressed] true = appui, false = relâchement,
  /// null = appui puis relâchement.
  bool button(String action, {bool? pressed}) {
    final bit = bits[actions[action]];
    if (bit == null || !isConnected) return false;
    if (pressed != null) {
      _pressed = pressed ? _pressed | bit : _pressed & ~bit;
      _send();
      return true;
    }
    _pressed |= bit;
    _send();
    Timer(const Duration(milliseconds: 60), () {
      _pressed &= ~bit;
      if (isConnected) _send();
    });
    return true;
  }

  bool shift(int delta) => button(delta > 0 ? 'shiftUp' : 'shiftDown');
}
