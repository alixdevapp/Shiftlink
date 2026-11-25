// Ventilateur Wahoo KICKR Headwind.
//
// Code écrit pour ShiftLink. Commandes (caractéristique a026e038 du service a026ee0c) :
// [0x04, mode] change le mode (0x04 manuel, 0x02 cardio), [0x02, %] règle la vitesse
// en mode manuel.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller_manager.dart' show LinkState;
import '../i18n.dart';
import 'heart_rate.dart' show SensorCandidate;

/// Qui décide de la vitesse du ventilateur.
enum FanMode {
  manual('Réglé à la main', 'Avec les boutons de ta manette (actions « Ventilateur + / − »).'),
  speed('Suit ta vitesse', 'Plus tu roules vite, plus il souffle. Quand ShiftLink gère les vitesses.'),
  power('Suit ta puissance', 'Plus tu pousses fort, plus il souffle : à fond vers ta FTP. Quand ShiftLink est relié au trainer.'),
  heartRate('Suit ton cardio', 'Mode du ventilateur : il faut l’appairer à ta ceinture dans l’appli Wahoo.'),
  heartRateStrap(
    'Suit ton cardio (ceinture reliée à ShiftLink)',
    'ShiftLink règle le vent avec la ceinture cardio de l’onglet Appareils. Tu choisis où il démarre et où il est à fond.',
  );

  /// Modes où ShiftLink suit une mesure sur une rampe réglable.
  bool get hasRamp => this == power || this == heartRateStrap;

  final String _label;
  String get label => tr(_label);
  final String _description;
  String get description => tr(_description);
  const FanMode(this._label, this._description);
}

class Headwind {
  static Guid _wahoo(String prefix) => Guid('$prefix-0a7d-4ab3-97fa-f1500f9feb8b');
  static final service = _wahoo('a026ee0c');
  static final control = _wahoo('a026e038');

  /// Paliers proposés à l'écran et par les actions « Ventilateur + / − ».
  static const steps = [0, 25, 50, 75, 100];

  static const _modeCommand = 0x04;
  static const _speedCommand = 0x02;
  static const _modeManual = 0x04;
  static const _modeHeartRate = 0x02;

  /// Vitesse de roulage (km/h) qui donne le vent à fond.
  static const fullSpeedKmh = 40.0;

  final void Function(String) log;
  Headwind({required this.log});

  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.disconnected);
  final ValueNotifier<String?> name = ValueNotifier(null);
  final ValueNotifier<int> level = ValueNotifier(0);
  final ValueNotifier<List<SensorCandidate>> candidates = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _ctl;
  StreamSubscription<BluetoothConnectionState>? _watch;
  bool _keepConnected = false;
  bool _inManualMode = false;

  bool get isConnected => state.value == LinkState.connected;

  static List<int> manualMode() => const [_modeCommand, _modeManual];
  static List<int> heartRateMode() => const [_modeCommand, _modeHeartRate];
  static List<int> speedCommand(int percent) => [_speedCommand, percent.clamp(0, 100)];

  /// Palier de vent pour une vitesse de roulage : rien à l'arrêt, à fond à 40 km/h.
  static int forSpeed(double kmh) {
    if (kmh < 3) return 0;
    final wanted = 100 * (kmh / fullSpeedKmh).clamp(0.0, 1.0);
    var best = steps.first;
    for (final s in steps) {
      if ((s - wanted).abs() < (best - wanted).abs()) best = s;
    }
    return best;
  }

  /// Palier de vent pour une puissance : rien en roue libre, à fond vers la FTP.
  static int forPower(int watts, int ftp) {
    if (watts < 30 || ftp <= 0) return 0;
    final wanted = 100 * (watts / (ftp * 0.95)).clamp(0.0, 1.0);
    var best = steps.first;
    for (final s in steps) {
      if ((s - wanted).abs() < (best - wanted).abs()) best = s;
    }
    return best;
  }

  /// Vent voulu (0 à 100, sans arrondi) pour [value] : rien jusqu'à [start], à fond à [full].
  static double rampPercent(num value, num start, num full) {
    if (full <= start) return value >= full ? 100 : 0;
    return 100 * ((value - start) / (full - start)).clamp(0.0, 1.0);
  }

  /// Nouveau réglage du vent, par crans de 10 %, ou [current] si l'écart est trop petit
  /// (évite que le ventilateur hésite entre deux crans).
  static int nextRampLevel(double wanted, int current) {
    final target = ((wanted / 10).round() * 10).clamp(0, 100);
    if (target == current) return current;
    if (target != 0 && target != 100 && (wanted - current).abs() < 7) return current;
    return target;
  }

  static bool _looksLikeHeadwind(ScanResult r) =>
      r.advertisementData.serviceUuids.contains(service) ||
      r.advertisementData.advName.toUpperCase().startsWith('HEADWIND');

  Future<void> scan() async {
    if (scanning.value) return;
    scanning.value = true;
    candidates.value = const [];
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      final found = [...candidates.value];
      for (final r in results.where(_looksLikeHeadwind)) {
        if (found.any((c) => c.device.remoteId == r.device.remoteId)) continue;
        final adv = r.advertisementData.advName;
        found.add(SensorCandidate(r.device, adv.isEmpty ? 'KICKR Headwind' : adv));
      }
      candidates.value = found;
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((on) => !on).first;
    } catch (e) {
      log('Recherche du ventilateur : $e');
    } finally {
      await sub.cancel();
      scanning.value = false;
    }
  }

  Future<void> connectById(String id, String label) => connect(BluetoothDevice.fromId(id), label);

  Future<void> connect(BluetoothDevice device, String label) async {
    _keepConnected = true;
    _device = device;
    name.value = label;
    state.value = LinkState.connecting;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      final ctl = [
        for (final s in services)
          if (s.uuid == service)
            for (final c in s.characteristics)
              if (c.uuid == control) c,
      ].firstOrNull;
      if (ctl == null) throw StateError('pas de commande Headwind');
      _ctl = ctl;
      _inManualMode = false;
      state.value = LinkState.connected;
      log('Ventilateur $label connecté');
      await _watch?.cancel();
      _watch = device.connectionState.listen((s) => _onConnection(s, device, label));
    } catch (e) {
      state.value = LinkState.disconnected;
      log('Ventilateur : échec de connexion ($e)');
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  void _onConnection(BluetoothConnectionState s, BluetoothDevice device, String label) {
    if (s != BluetoothConnectionState.disconnected || state.value != LinkState.connected) return;
    state.value = LinkState.disconnected;
    _ctl = null;
    // Coupure involontaire : on retente un peu plus tard.
    if (_keepConnected) Future.delayed(const Duration(seconds: 3), () => connect(device, label));
  }

  Future<void> _send(List<int> command) async {
    final c = _ctl;
    if (c == null) return;
    try {
      await c.write(command, withoutResponse: c.properties.writeWithoutResponse);
    } catch (e) {
      log('Ventilateur : commande refusée ($e)');
    }
  }

  Future<void> setLevel(int percent) async {
    if (!_inManualMode) {
      await _send(manualMode());
      _inManualMode = true;
    }
    level.value = percent.clamp(0, 100);
    await _send(speedCommand(level.value));
  }

  /// Palier suivant ([direction] = 1) ou précédent (−1).
  Future<void> step(int direction) {
    var i = steps.indexWhere((s) => s >= level.value);
    if (i < 0) i = steps.length - 1;
    return setLevel(steps[(i + direction).clamp(0, steps.length - 1)]);
  }

  Future<void> followHeartRate() async {
    _inManualMode = false;
    await _send(heartRateMode());
  }

  Future<void> disconnect() async {
    _keepConnected = false;
    await _watch?.cancel();
    state.value = LinkState.disconnected;
    try {
      await _device?.disconnect();
    } catch (_) {}
    name.value = null;
  }
}
