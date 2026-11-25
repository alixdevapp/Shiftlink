// Ceinture cardio Bluetooth (service public Heart Rate, 0x180D).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller_manager.dart' show LinkState;

class SensorCandidate {
  final BluetoothDevice device;
  final String name;
  const SensorCandidate(this.device, this.name);
}

class HeartRateMonitor {
  static final service = Guid('180d');
  static final measurement = Guid('2a37');

  final void Function(String) log;
  HeartRateMonitor({required this.log});

  final ValueNotifier<int?> bpm = ValueNotifier(null);
  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.disconnected);
  final ValueNotifier<String?> name = ValueNotifier(null);
  final ValueNotifier<List<SensorCandidate>> candidates = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _wanted = false;

  bool get isConnected => state.value == LinkState.connected;

  /// Fréquence cardiaque d'une trame « Heart Rate Measurement ».
  static int? parse(List<int> v) {
    if (v.length < 2) return null;
    final wide = v[0] & 0x01 != 0;
    if (wide) return v.length < 3 ? null : ByteData.sublistView(Uint8List.fromList(v)).getUint16(1, Endian.little);
    return v[1];
  }

  Future<void> scan() async {
    if (scanning.value) return;
    scanning.value = true;
    candidates.value = const [];
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      final list = [...candidates.value];
      for (final r in results) {
        if (!r.advertisementData.serviceUuids.contains(service)) continue;
        if (list.any((c) => c.device.remoteId == r.device.remoteId)) continue;
        final adv = r.advertisementData.advName;
        list.add(SensorCandidate(r.device, adv.isNotEmpty ? adv : r.device.remoteId.str));
      }
      candidates.value = list;
    });
    try {
      await FlutterBluePlus.startScan(withServices: [service], timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      log('Recherche de la ceinture cardio : $e');
    }
    await sub.cancel();
    scanning.value = false;
    if (candidates.value.isEmpty) log('Aucune ceinture cardio trouvée. Mouille les électrodes et porte-la.');
  }

  Future<void> connectById(String id, String label) => connect(BluetoothDevice.fromId(id), label);

  Future<void> connect(BluetoothDevice device, String label) async {
    _wanted = true;
    _device = device;
    name.value = label;
    state.value = LinkState.connecting;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      final c = services
          .where((s) => s.uuid == service)
          .expand((s) => s.characteristics)
          .where((c) => c.uuid == measurement)
          .firstOrNull;
      if (c == null) throw Exception('pas de mesure cardio');
      final sub = c.onValueReceived.listen((v) => bpm.value = parse(v));
      device.cancelWhenDisconnected(sub);
      await c.setNotifyValue(true);
      state.value = LinkState.connected;
      log('Ceinture cardio $label connectée');
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && state.value == LinkState.connected) {
          state.value = LinkState.disconnected;
          bpm.value = null;
          if (_wanted) Future.delayed(const Duration(seconds: 3), () => connect(device, label));
        }
      });
    } catch (e) {
      state.value = LinkState.disconnected;
      log('Ceinture cardio : échec de connexion ($e)');
      try {
        await device.disconnect();
      } catch (_) {}
      if (_wanted) {
        Future.delayed(const Duration(seconds: 8), () {
          if (_wanted && state.value == LinkState.disconnected) connect(device, label);
        });
      }
    }
  }

  Future<void> disconnect() async {
    _wanted = false;
    await _connSub?.cancel();
    state.value = LinkState.disconnected;
    bpm.value = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    name.value = null;
  }
}
