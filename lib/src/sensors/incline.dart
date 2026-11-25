// Pente réelle : Wahoo KICKR Climb et Elite Rizer lèvent l'avant du vélo selon la
// pente que l'appli envoie au trainer.
//
// Code écrit pour ShiftLink. Faits de protocole :
// - KICKR Climb : service a026ee0b, caractéristique a026e037 ; 0x67 = prise de contrôle,
//   [0x66, pente × 100 en int16 petit-boutiste] = pente voulue, de −10 à +19 %
//   (relevé au sniffer par Redback Operations, GPL-3.0 :
//   https://github.com/Redback-Operations/redback-smartbike-iot) ;
// - Elite Rizer : service Elite 347b0001, écriture sur 347b0020,
//   [0x0a, pente × 10 en int16 petit-boutiste], de −10 à +20 % (description publique
//   du protocole par OpenBikeControl).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller_manager.dart' show LinkState;
import 'heart_rate.dart' show SensorCandidate;

/// Un appareil qui incline le vélo.
abstract interface class InclineSink {
  /// Applique la pente [percent] (déjà bornée et arrondie). Renvoie false si l'envoi a échoué.
  Future<bool> writeGrade(double percent);
}

/// Int16 petit-boutiste.
List<int> _int16le(int v) {
  final u = v & 0xffff;
  return [u & 0xff, u >> 8];
}

/// Commande KICKR Climb pour une pente en %.
List<int> climbGradeCommand(double percent) =>
    [0x66, ..._int16le((percent.clamp(KickrClimb.minGrade, KickrClimb.maxGrade) * 100).round())];

/// Commande Elite Rizer pour une pente en %.
List<int> rizerGradeCommand(double percent) => [0x0a, ..._int16le((percent.clamp(-10.0, 20.0) * 10).round())];

/// Décide quoi envoyer : pente arrondie au demi-pourcent, pas deux fois la même,
/// et retour à plat quand l'appli n'envoie plus de pente.
class InclineFollower {
  final double min;
  final double max;
  InclineFollower({this.min = -10, this.max = 19});

  double? _last;

  /// Pente à envoyer pour [grade] (null = l'appli n'en donne plus), ou null s'il n'y a rien à faire.
  double? next(double? grade) {
    final want = grade == null ? (_last == null || _last == 0 ? null : 0.0) : (grade.clamp(min, max) * 2).round() / 2;
    if (want == null || want == _last) return null;
    return want;
  }

  /// L'envoi de [grade] a réussi.
  void sent(double grade) => _last = grade;

  void reset() => _last = null;
}

/// Wahoo KICKR Climb, piloté directement (sans passer par le KICKR).
class KickrClimb implements InclineSink {
  static Guid _wahoo(String prefix) => Guid('$prefix-0a7d-4ab3-97fa-f1500f9feb8b');
  static final service = _wahoo('a026ee0b');
  static final control = _wahoo('a026e037');
  static const minGrade = -10.0;
  static const maxGrade = 19.0;
  static const requestControl = [0x67];

  final void Function(String) log;
  KickrClimb({required this.log});

  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.disconnected);
  final ValueNotifier<String?> name = ValueNotifier(null);

  /// Dernière pente envoyée, en %.
  final ValueNotifier<double?> grade = ValueNotifier(null);
  final ValueNotifier<List<SensorCandidate>> candidates = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);
  final follower = InclineFollower();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _ctl;
  StreamSubscription<BluetoothConnectionState>? _watch;
  bool _keepConnected = false;

  bool get isConnected => state.value == LinkState.connected;

  static bool looksLikeClimb(ScanResult r) =>
      r.advertisementData.serviceUuids.contains(service) ||
      r.advertisementData.advName.toUpperCase().contains('KICKR CLIMB');

  Future<void> scan() async {
    if (scanning.value) return;
    scanning.value = true;
    candidates.value = const [];
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      final found = [...candidates.value];
      for (final r in results.where(looksLikeClimb)) {
        if (found.any((c) => c.device.remoteId == r.device.remoteId)) continue;
        final adv = r.advertisementData.advName;
        found.add(SensorCandidate(r.device, adv.isEmpty ? 'KICKR Climb' : adv));
      }
      candidates.value = found;
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((on) => !on).first;
    } catch (e) {
      log('Recherche du KICKR Climb : $e');
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
      if (ctl == null) throw StateError('pas de commande Climb');
      _ctl = ctl;
      if (ctl.properties.notify || ctl.properties.indicate) {
        try {
          await ctl.setNotifyValue(true);
        } catch (_) {}
      }
      await _send(requestControl);
      follower.reset();
      state.value = LinkState.connected;
      log('KICKR Climb $label connecté');
      await _watch?.cancel();
      _watch = device.connectionState.listen((s) => _onConnection(s, device, label));
    } catch (e) {
      state.value = LinkState.disconnected;
      log('KICKR Climb : échec de connexion ($e)');
      try {
        await device.disconnect();
      } catch (_) {}
      if (_keepConnected) Future.delayed(const Duration(seconds: 10), () => _retry(device, label));
    }
  }

  void _retry(BluetoothDevice device, String label) {
    if (_keepConnected && state.value == LinkState.disconnected && _device == device) connect(device, label);
  }

  void _onConnection(BluetoothConnectionState s, BluetoothDevice device, String label) {
    if (s != BluetoothConnectionState.disconnected || state.value != LinkState.connected) return;
    state.value = LinkState.disconnected;
    _ctl = null;
    if (_keepConnected) Future.delayed(const Duration(seconds: 3), () => _retry(device, label));
  }

  Future<bool> _send(List<int> command) async {
    final c = _ctl;
    if (c == null) return false;
    try {
      await c.write(command, withoutResponse: !c.properties.write && c.properties.writeWithoutResponse);
      return true;
    } catch (e) {
      log('KICKR Climb : commande refusée ($e)');
      return false;
    }
  }

  @override
  Future<bool> writeGrade(double percent) async {
    final ok = await _send(climbGradeCommand(percent));
    if (ok) grade.value = percent;
    return ok;
  }

  /// Suit la pente de l'appli (null = plus de pente : retour à plat).
  Future<void> follow(double? appGrade) async {
    if (!isConnected) return;
    final g = follower.next(appGrade);
    if (g != null && await writeGrade(g)) follower.sent(g);
  }

  Future<void> disconnect() async {
    _keepConnected = false;
    await _watch?.cancel();
    if (isConnected) await writeGrade(0);
    state.value = LinkState.disconnected;
    try {
      await _device?.disconnect();
    } catch (_) {}
    name.value = null;
    grade.value = null;
  }
}
