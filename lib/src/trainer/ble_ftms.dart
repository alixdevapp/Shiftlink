// ShiftLink vu comme un home trainer Bluetooth (FTMS) par l'appli
// d'entraînement, sur un autre appareil. Le serveur GATT est en Kotlin
// (FtmsPeripheral.kt) ; ici on relaie les commandes et les données.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BleFtmsServer {
  static const _channel = MethodChannel('shiftlink/ftms');

  final void Function(String) log;
  final Uint8List Function(Uint8List command) onControlPoint;
  final ValueNotifier<bool> isStarted = ValueNotifier(false);

  /// Nom de l'appareil connecté (l'appli), ou null.
  final ValueNotifier<String?> client = ValueNotifier(null);

  BleFtmsServer({required this.log, required this.onControlPoint}) {
    _channel.setMethodCallHandler(_onCall);
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'controlPoint':
        return onControlPoint(Uint8List.fromList((call.arguments as List).cast<int>()));
      case 'client':
        final m = (call.arguments as Map).cast<String, Object?>();
        final name = m['name'] as String?;
        if (name != client.value) {
          log(name == null ? 'Appli Bluetooth déconnectée' : 'Appli connectée en Bluetooth ($name)');
        }
        client.value = name;
      case 'log':
        log('Trainer Bluetooth : ${(call.arguments as Map)['message']}');
    }
    return null;
  }

  Future<void> start() async {
    if (isStarted.value) return;
    try {
      final ok = await _channel.invokeMethod<bool>('start') ?? false;
      isStarted.value = ok;
      if (!ok) log('Trainer Bluetooth : Bluetooth éteint ou indisponible');
    } catch (e) {
      log('Trainer Bluetooth : $e');
    }
  }

  void notify(int uuid, Uint8List data) {
    if (!isStarted.value || client.value == null) return;
    _channel.invokeMethod('notify', {'uuid': uuid, 'data': data}).catchError((_) {});
  }

  Future<void> stop() async {
    if (!isStarted.value) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    isStarted.value = false;
    client.value = null;
  }
}
