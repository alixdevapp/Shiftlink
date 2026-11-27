// OpenBikeControl : protocole ouvert que parlent MyWhoosh, Rouvy, Grimpa,
// Ride Cave, Velotoss… pour recevoir les boutons d'une manette. En Wi-Fi (ici)
// et en Bluetooth (serveur GATT en Kotlin, ObcPeripheral.kt) : mêmes messages.
//
// Code écrit pour ShiftLink d'après la description publique du protocole
// (https://openbikecontrol.org) :
// - annonce mDNS `_openbikecontrol._tcp`, serveur TCP côté manette ;
// - manette → appli : [0x01, bouton, état] (1 appuyé, 0 relâché) ;
// - appli → manette : [0x03, motif] retour haptique, [0x04, 0x01, longueur, id…] infos appli.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n.dart';
import '../net/lan_server.dart';

class ObcProtocol {
  static const int port = 36867;
  static const String serviceType = '_openbikecontrol._tcp';
  static const String serviceUuid = 'd273f680-d548-419d-b9d1-fa0472345229';

  static const int msgButtonState = 0x01;
  static const int msgHaptic = 0x03;
  static const int msgAppInfo = 0x04;

  static const int shiftUp = 0x01;
  static const int shiftDown = 0x02;

  static Uint8List buttonState(int button, bool pressed) =>
      Uint8List.fromList([msgButtonState, button, if (pressed) 1 else 0]);

  /// Identifiant de l'appli dans un message « infos appli », ou null.
  static String? appId(List<int> data) {
    if (data.length < 3 || data[0] != msgAppInfo || data[1] != 0x01) return null;
    final end = 3 + data[2];
    if (end > data.length) return null;
    return utf8.decode(data.sublist(3, end), allowMalformed: true);
  }

  /// Nom lisible d'une appli à partir de son identifiant (« incyclist » → « Incyclist »).
  static String appName(String id) {
    final key = id.toLowerCase().replaceAll(RegExp(r'[\s_.-]+'), '');
    for (final MapEntry(key: k, value: v) in _knownApps.entries) {
      if (key == k || key.startsWith(k)) return v;
    }
    return id;
  }

  /// Applis OpenBikeControl connues (identifiant sans espaces ni tirets → nom affiché).
  static const _knownApps = {
    'incyclist': 'Incyclist',
    'mywhoosh': 'MyWhoosh',
    'rouvy': 'Rouvy',
    'biketerra': 'Biketerra',
    'trainingpeaks': 'TrainingPeaks Virtual',
    'tpv': 'TrainingPeaks Virtual',
    'grimpa': 'Grimpa',
    'ictrainer': 'icTrainer',
    'auuki': 'Auuki',
    'ridecave': 'Ride Cave',
    'velotoss': 'Velotoss',
    'voxvelo': 'VoxVelo',
    'veloworkout': 'VeloWorkout',
    'pedalparty': 'Pedalparty',
    'rampida': 'Rampida',
    'everycol': 'Everycol',
    'pedalmania': 'Pedal Mania',
    'velopopuli': 'VeloPopuli',
    'vieta': 'Vieta',
    'dirtwatts': 'DirtWatts',
    'wattlog': 'WattLog.pro',
    'rezvivo': 'REZVIVO',
    'openradlr': 'OpenRadlr',
    'zwotrainer': 'zwoTrainer',
    'tourdupain': 'Tour du Pain',
    'ridewarp': 'Warp',
    'warp': 'Warp',
    'hupser': 'hupser',
    'strappo': 'Strappo',
    'saddleout': 'SaddleOut',
    'pedalcraft': 'PedalCraft',
    'suffer': 'suffer.online',
    'kardiacs': 'Kardiacs',
    'sueur': 'Sueur',
    'trainerkit': 'TrainerKit',
  };

  /// Champs TXT de l'annonce mDNS (valeurs en texte).
  static Map<String, Uint8List?> txt() => {
    for (final e in const {
      'version': '1',
      'id': 'shiftlink',
      'name': 'ShiftLink',
      'service-uuids': serviceUuid,
      'manufacturer': 'ShiftLink',
      'model': 'ShiftLink',
    }.entries)
      e.key: Uint8List.fromList(utf8.encode(e.value)),
  };
}

class ObcServer {
  final ValueNotifier<bool> isStarted = ValueNotifier(false);
  final ValueNotifier<String?> connectedApp = ValueNotifier(null);
  final void Function(String) log;

  /// Retour haptique demandé par l'appli (motif 1 = simple, 6 = avertissement…).
  void Function(int pattern)? onHaptic;

  late final LanServer _server = LanServer(port: ObcProtocol.port, name: 'OpenBikeControl', log: log)
    ..onClient = _clientChanged
    ..onData = _received;
  nsd.Registration? _announce;

  ObcServer({required this.log});

  static const _ble = MethodChannel('shiftlink/obc');

  /// Appli connectée en Bluetooth (son nom d'appareil), ou null.
  final ValueNotifier<String?> bleClient = ValueNotifier(null);
  final ValueNotifier<bool> bleStarted = ValueNotifier(false);

  bool get isConnected => _server.hasClient || bleClient.value != null;

  void _send(Uint8List data) {
    if (_server.hasClient) _server.send(data);
    if (bleClient.value != null) _ble.invokeMethod('send', {'data': data}).catchError((_) {});
  }

  /// Se montre aussi comme manette OpenBikeControl en Bluetooth.
  Future<void> startBluetooth() async {
    if (bleStarted.value) return;
    _ble.setMethodCallHandler(_onBle);
    try {
      // Version lue dans l'APK : elle ne reste plus en retard d'une version à l'autre.
      final version = await PackageInfo.fromPlatform().then((p) => p.version, onError: (_) => '1');
      bleStarted.value = await _ble.invokeMethod<bool>('start', {'version': version}) ?? false;
      if (!bleStarted.value) log('OpenBikeControl Bluetooth : Bluetooth éteint ou indisponible');
    } catch (e) {
      log('OpenBikeControl Bluetooth : $e');
    }
  }

  Future<void> stopBluetooth() async {
    if (!bleStarted.value) return;
    try {
      await _ble.invokeMethod('stop');
    } catch (_) {}
    bleStarted.value = false;
    _bleChanged(null);
  }

  Future<dynamic> _onBle(MethodCall call) async {
    switch (call.method) {
      case 'client':
        _bleChanged((call.arguments as Map)['name'] as String?);
      case 'received':
        _received(Uint8List.fromList((call.arguments as List).cast<int>()));
      case 'log':
        log('OpenBikeControl Bluetooth : ${(call.arguments as Map)['message']}');
    }
    return null;
  }

  void _bleChanged(String? name) {
    if (name == bleClient.value) return;
    bleClient.value = name;
    if (name == null) {
      if (!_server.hasClient) connectedApp.value = null;
      log('Appli OpenBikeControl (Bluetooth) déconnectée');
    } else {
      connectedApp.value ??= tr('l’appli');
      log('Appli OpenBikeControl connectée en Bluetooth ($name)');
    }
  }

  /// Numéro de bouton OpenBikeControl de chaque action ShiftLink.
  static const buttons = {
    'shiftUp': 0x01,
    'shiftDown': 0x02,
    'navUp': 0x10,
    'navDown': 0x11,
    'navLeft': 0x12,
    'navRight': 0x13,
    'select': 0x14,
    'back': 0x15,
    'menu': 0x16,
    'steerLeft': 0x18,
    'steerRight': 0x19,
    'emote': 0x20,
    'ergUp': 0x30,
    'ergDown': 0x31,
    'skipInterval': 0x32,
    'pause': 0x33,
    'uturn': 0x37,
    'cameraAngle': 0x40,
    'toggleUi': 0x44,
    'usePowerUp': 0x50,
  };

  Future<void> start() async {
    if (isStarted.value) return;
    try {
      await _server.open();
    } catch (e) {
      log('OpenBikeControl : impossible d’ouvrir le port ${ObcProtocol.port} ($e)');
      return;
    }
    try {
      nsd.disableServiceTypeValidation(true);
      _announce = await nsd.register(
        nsd.Service(name: 'ShiftLink', type: ObcProtocol.serviceType, port: ObcProtocol.port, txt: ObcProtocol.txt()),
      );
    } catch (e) {
      log('OpenBikeControl : annonce réseau impossible ($e)');
    }
    isStarted.value = true;
  }

  void _clientChanged(String? address) {
    if (address == null) {
      if (bleClient.value == null) connectedApp.value = null;
      log('Appli OpenBikeControl déconnectée');
      return;
    }
    connectedApp.value = tr('l’appli'); // remplacé par son nom dès qu'elle se présente
    log('Appli OpenBikeControl connectée ($address)');
  }

  void _received(Uint8List data) {
    if (data.isEmpty) return;
    if (data[0] == ObcProtocol.msgHaptic) onHaptic?.call(data.length > 1 ? data[1] : 1);
    final id = ObcProtocol.appId(data);
    if (id != null) {
      connectedApp.value = ObcProtocol.appName(id);
      log('Appli OpenBikeControl : $id');
    }
  }

  /// Bouton de l'action [action] : [pressed] true = appui, false = relâchement,
  /// null = appui puis relâchement.
  bool button(String action, {bool? pressed}) {
    final id = buttons[action];
    if (id == null || !isConnected) return false;
    if (pressed != null) {
      _send(ObcProtocol.buttonState(id, pressed));
      return true;
    }
    // Appui puis relâchement, avec un petit écart : envoyés d'affilée, ils partent
    // souvent dans le même paquet TCP et certaines applis perdent le relâchement.
    _send(ObcProtocol.buttonState(id, true));
    Timer(const Duration(milliseconds: 30), () {
      if (isConnected) _send(ObcProtocol.buttonState(id, false));
    });
    return true;
  }

  bool shift(int delta) => button(delta > 0 ? 'shiftUp' : 'shiftDown');

  Future<void> stop() async {
    final a = _announce;
    _announce = null;
    if (a != null) {
      try {
        await nsd.unregister(a);
      } catch (_) {}
    }
    await _server.close();
    connectedApp.value = null;
    isStarted.value = false;
  }
}
