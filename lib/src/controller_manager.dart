// Recherche, connexion et reconnexion automatique des manettes.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'controllers/driver.dart';
import 'controllers/learned_driver.dart';
import 'controllers/registry.dart';

enum LinkState { connecting, connected, disconnected }

class ConnectedController {
  final BluetoothDevice device;
  final ControllerDriver driver;
  final String name;
  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.connecting);

  /// Batterie (%) et version du firmware, si la manette les donne.
  final ValueNotifier<int?> battery = ValueNotifier(null);
  String? firmware;
  int? rssi;

  /// Dernier problème de connexion à montrer à l'écran (manette verrouillée…), ou null.
  String? problem;
  final List<StreamSubscription<Object?>> _subs = [];
  bool forgotten = false;

  /// Endormie pour économiser les piles (fin de séance).
  bool asleep = false;

  ConnectedController(this.device, this.driver, this.name);

  /// Vraie manette Bluetooth (pas le téléphone ni une télécommande appairée).
  bool get isBluetooth => driver.typeId != 'phoneSteering' && !driver.typeId.startsWith('keys.');
}

class ControllerManager {
  final void Function(ConnectedController c, ButtonEvent e) onButton;
  final void Function(String) log;

  final ValueNotifier<List<ConnectedController>> controllers = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);

  /// La dernière recherche s'est terminée sans trouver de manette.
  final ValueNotifier<bool> lastScanEmpty = ValueNotifier(false);
  final Set<String> _reportedUnsupported = {};

  /// Appareils ignorés : identifiant → nom.
  final Map<String, String> ignored = {};

  /// Manettes apprises par ShiftLink, par identifiant Bluetooth.
  final Map<String, LearnedProfile> learned = {};

  /// Manettes endormies en fin de séance.
  final ValueNotifier<bool> asleep = ValueNotifier(false);
  StreamSubscription<List<ScanResult>>? _scanSub;

  ControllerManager({required this.onButton, required this.log});

  Future<void> scan({Duration timeout = const Duration(seconds: 30)}) async {
    if (scanning.value) return;
    if (asleep.value) await wake();
    if (await FlutterBluePlus.isSupported == false) {
      log('Bluetooth non disponible sur cet appareil');
      return;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    scanning.value = true;
    lastScanEmpty.value = false;
    log('Recherche des manettes… appuie sur un bouton pour les réveiller.');
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        _consider(r);
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      log('Erreur de recherche : $e');
    }
    await _scanSub?.cancel();
    scanning.value = false;
    lastScanEmpty.value = controllers.value.isEmpty;
    if (controllers.value.isEmpty) log('Aucune manette trouvée.');
  }

  void _consider(ScanResult r) {
    final id = r.device.remoteId.str;
    if (ignored.containsKey(id)) return;
    if (controllers.value.any((c) => c.device.remoteId.str == id)) return;
    final lp = learned[id];
    final match = lp != null ? Match.driver(LearnedDriver(lp)) : identify(r);
    if (match == null) return;
    if (match.unsupportedReason != null) {
      if (_reportedUnsupported.add(id)) log(match.unsupportedReason!);
      return;
    }
    final adv = r.advertisementData.advName;
    final name = adv.isNotEmpty
        ? adv
        : (r.device.platformName.isNotEmpty ? r.device.platformName : match.driver!.label);
    final c = ConnectedController(r.device, match.driver!, name);
    controllers.value = [...controllers.value, c];
    log('Trouvé : $name (${match.driver!.label})');
    _connect(c);
  }

  /// Ajoute tout de suite une manette qu'on vient d'apprendre.
  void adopt(BluetoothDevice device, LearnedProfile p) {
    learned[device.remoteId.str] = p;
    final old = controllers.value.where((c) => c.device.remoteId.str == device.remoteId.str).firstOrNull;
    if (old != null) controllers.value = controllers.value.where((c) => c != old).toList();
    final c = ConnectedController(device, LearnedDriver(p), p.name);
    controllers.value = [...controllers.value, c];
    log('Manette apprise : ${p.name}');
    _connect(c);
  }

  static final _batteryService = Guid('180f');
  static final _batteryLevel = Guid('2a19');
  static final _infoService = Guid('180a');
  static final _firmwareRev = Guid('2a26');

  /// Batterie, firmware et signal : facultatifs, on ignore les erreurs.
  Future<void> _readInfo(ConnectedController c, List<BluetoothService> services) async {
    try {
      final level = services
          .where((s) => s.uuid == _batteryService)
          .firstOrNull
          ?.characteristics
          .where((ch) => ch.uuid == _batteryLevel)
          .firstOrNull;
      if (level != null) {
        final v = await level.read();
        if (v.isNotEmpty) c.battery.value = v[0];
        if (level.properties.notify) {
          final s = level.onValueReceived.listen((v) {
            if (v.isNotEmpty) c.battery.value = v[0];
          });
          c.device.cancelWhenDisconnected(s);
          await level.setNotifyValue(true);
        }
      }
    } catch (_) {}
    try {
      final fw = services
          .where((s) => s.uuid == _infoService)
          .firstOrNull
          ?.characteristics
          .where((ch) => ch.uuid == _firmwareRev)
          .firstOrNull;
      if (fw != null) {
        final v = await fw.read();
        final text = String.fromCharCodes(v.where((b) => b >= 32 && b < 127)).trim();
        if (text.isNotEmpty) c.firmware = text;
      }
    } catch (_) {}
    try {
      c.rssi = await c.device.readRssi();
    } catch (_) {}
  }

  Future<void> _connect(ConnectedController c) async {
    if (c.forgotten || c.asleep) return;
    c.state.value = LinkState.connecting;
    c.driver.reset();
    try {
      await c.device.connect(timeout: const Duration(seconds: 15));
      try {
        await c.device.requestMtu(247);
      } catch (_) {}
      final services = await c.device.discoverServices();
      for (final sub in c.driver.subscriptions) {
        final service = services.where((s) => s.uuid == sub.service).firstOrNull;
        // Certains firmwares rangent la caractéristique sous un autre service : on la cherche partout.
        final chr =
            service?.characteristics.where((ch) => ch.uuid == sub.characteristic).firstOrNull ??
            services.expand((s) => s.characteristics).where((ch) => ch.uuid == sub.characteristic).firstOrNull;
        if (chr == null && sub.optional) continue;
        if (chr == null) {
          c.problem = c.driver.missingServiceHint;
          throw Exception(c.problem ?? 'service ${sub.service} introuvable (firmware à mettre à jour ?)');
        }
        final s = chr.onValueReceived.listen((bytes) {
          for (final e in c.driver.decode(chr.uuid, Uint8List.fromList(bytes))) {
            onButton(c, e);
          }
        });
        c.device.cancelWhenDisconnected(s);
        await chr.setNotifyValue(true);
      }
      await c.driver.afterSubscribe(c.device, services);
      await _readInfo(c, services);
      final fw = c.firmware;
      if (fw != null) c.driver.onFirmware(fw);
      c.problem = null;
      c.state.value = LinkState.connected;
      log('${c.name} connectée');
      for (final s in c._subs) {
        unawaited(s.cancel());
      }
      c._subs
        ..clear()
        ..add(
          c.device.connectionState.listen((s) {
            if (s == BluetoothConnectionState.disconnected && c.state.value == LinkState.connected) {
              c.state.value = LinkState.disconnected;
              if (c.asleep) return;
              log('${c.name} déconnectée, reconnexion…');
              Future.delayed(const Duration(seconds: 2), () => _connect(c));
            }
          }),
        );
    } catch (e) {
      c.state.value = LinkState.disconnected;
      log('${c.name} : échec de connexion ($e)');
      try {
        await c.device.disconnect();
      } catch (_) {}
      Future.delayed(const Duration(seconds: 5), () {
        if (c.state.value == LinkState.disconnected && !c.asleep) _connect(c);
      });
    }
  }

  /// Déconnecte les manettes Bluetooth sans les oublier.
  Future<void> sleep() async {
    asleep.value = true;
    for (final c in controllers.value.where((c) => c.isBluetooth)) {
      c.asleep = true;
      c.state.value = LinkState.disconnected;
      try {
        await c.device.disconnect();
      } catch (_) {}
    }
  }

  /// Reconnecte les manettes endormies.
  Future<void> wake() async {
    asleep.value = false;
    for (final c in controllers.value.where((c) => c.asleep)) {
      c.asleep = false;
      unawaited(_connect(c));
    }
  }

  Future<void> forget(ConnectedController c) async {
    c.forgotten = true;
    for (final s in c._subs) {
      await s.cancel();
    }
    c.state.value = LinkState.disconnected;
    try {
      await c.device.disconnect();
    } catch (_) {}
    controllers.value = controllers.value.where((x) => x != c).toList();
    log('${c.name} oubliée');
  }

  Future<void> dispose() async {
    await FlutterBluePlus.stopScan();
    for (final c in List.of(controllers.value)) {
      await forget(c);
    }
  }
}
