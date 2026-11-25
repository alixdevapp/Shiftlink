// Capteurs Bluetooth publics : cadence (CSC, 0x1816) et puissance (Cycling Power, 0x1818).
// Un capteur de puissance donne souvent aussi la cadence.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller_manager.dart' show LinkState;
import 'heart_rate.dart' show SensorCandidate;

enum SensorKind { cadence, power }

/// Calcule la cadence à partir des tours de pédalier cumulés (temps en 1/1024 s).
class CrankCadence {
  int? _revs;
  int? _time;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);
  double? rpm;

  /// Ajoute une mesure. Renvoie la cadence (0 si on ne pédale plus).
  double? add(int revs, int time, [DateTime? now]) {
    final t = now ?? DateTime.now();
    final pr = _revs, pt = _time;
    _revs = revs;
    _time = time;
    if (pr == null || pt == null) return rpm;
    final dr = (revs - pr) & 0xFFFF;
    final dt = (time - pt) & 0xFFFF;
    if (dr == 0 || dt == 0) {
      if (t.difference(_lastChange).inMilliseconds > 2500) rpm = 0;
      return rpm;
    }
    _lastChange = t;
    final v = dr * 60 * 1024 / dt;
    if (v < 250) rpm = v;
    return rpm;
  }
}

class BikeSensor {
  static final cscService = Guid('1816');
  static final cscMeasurement = Guid('2a5b');
  static final powerService = Guid('1818');
  static final powerMeasurement = Guid('2a63');

  final SensorKind kind;
  final void Function(String) log;
  BikeSensor(this.kind, {required this.log});

  Guid get service => kind == SensorKind.power ? powerService : cscService;

  final ValueNotifier<int?> power = ValueNotifier(null);
  final ValueNotifier<double?> cadence = ValueNotifier(null);
  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.disconnected);
  final ValueNotifier<String?> name = ValueNotifier(null);
  final ValueNotifier<List<SensorCandidate>> candidates = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);

  final CrankCadence _crank = CrankCadence();
  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _wanted = false;
  DateTime _lastData = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConnected => state.value == LinkState.connected;

  /// Valeurs récentes seulement (moins de 3 s), sinon null.
  bool get fresh => DateTime.now().difference(_lastData).inSeconds < 3;

  /// Mesure CSC : tours de pédalier (révolutions, temps), ou null.
  static (int, int)? parseCsc(List<int> v) {
    if (v.isEmpty) return null;
    final flags = v[0];
    var i = 1;
    if (flags & 0x01 != 0) i += 6; // roue
    if (flags & 0x02 == 0 || v.length < i + 4) return null;
    return (v[i] | (v[i + 1] << 8), v[i + 2] | (v[i + 3] << 8));
  }

  /// Mesure de puissance : watts et, si présents, tours de pédalier.
  static (int, (int, int)?)? parsePower(List<int> v) {
    if (v.length < 4) return null;
    final flags = v[0] | (v[1] << 8);
    var watts = v[2] | (v[3] << 8);
    if (watts > 0x7FFF) watts -= 0x10000;
    var i = 4;
    if (flags & 0x01 != 0) i += 1; // équilibre gauche / droite
    if (flags & 0x04 != 0) i += 2; // couple cumulé
    if (flags & 0x10 != 0) i += 6; // roue
    (int, int)? crank;
    if (flags & 0x20 != 0 && v.length >= i + 4) {
      crank = (v[i] | (v[i + 1] << 8), v[i + 2] | (v[i + 3] << 8));
    }
    return (watts, crank);
  }

  void _onValue(List<int> v) {
    _lastData = DateTime.now();
    if (kind == SensorKind.power) {
      final p = parsePower(v);
      if (p == null) return;
      power.value = p.$1 < 0 ? 0 : p.$1;
      if (p.$2 != null) cadence.value = _crank.add(p.$2!.$1, p.$2!.$2);
    } else {
      final c = parseCsc(v);
      if (c != null) cadence.value = _crank.add(c.$1, c.$2);
    }
  }

  String get _label => kind == SensorKind.power ? 'Capteur de puissance' : 'Capteur de cadence';

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
      log('$_label : $e');
    }
    await sub.cancel();
    scanning.value = false;
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
      final want = kind == SensorKind.power ? powerMeasurement : cscMeasurement;
      final c = services
          .where((s) => s.uuid == service)
          .expand((s) => s.characteristics)
          .where((c) => c.uuid == want)
          .firstOrNull;
      if (c == null) throw Exception('pas de mesure');
      final sub = c.onValueReceived.listen(_onValue);
      device.cancelWhenDisconnected(sub);
      await c.setNotifyValue(true);
      state.value = LinkState.connected;
      log('$_label $label connecté');
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && state.value == LinkState.connected) {
          state.value = LinkState.disconnected;
          power.value = null;
          cadence.value = null;
          if (_wanted) Future.delayed(const Duration(seconds: 3), () => connect(device, label));
        }
      });
    } catch (e) {
      state.value = LinkState.disconnected;
      log('$_label : échec de connexion ($e)');
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
    power.value = null;
    cadence.value = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    name.value = null;
  }
}
