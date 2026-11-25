// Connexion au vrai home trainer : FTMS, FE-C ou ancien protocole Wahoo en
// Bluetooth, ou Wi-Fi (DIRCON).
// Quel que soit le chemin, le reste de ShiftLink parle FTMS : les commandes
// sont traduites pour FE-C, et les données remises en trames FTMS.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../controller_manager.dart' show LinkState;
import 'dircon.dart';
import 'fec.dart';
import 'ftms.dart';
import 'wahoo_cps.dart';

/// Façon de parler au trainer.
enum TrainerKind { ftms, fec, wahoo, wifi }

/// Nom d'un trainer d'avant FTMS qui parle l'ancien protocole Wahoo (et pas d'un
/// simple capteur de puissance, qui annonce le même service).
bool looksLikeWahooTrainer(String name) =>
    RegExp(r'KICKR|SNAP|HAMMER|SARIS|CYCLEOPS|MAGNUS|\bH[23]\b|FLUID2|M2 ', caseSensitive: false).hasMatch(name) &&
    !RegExp(r'HEADWIND|CLIMB|KICKR BIKE', caseSensitive: false).hasMatch(name);

class TrainerCandidate {
  final BluetoothDevice? device;
  final String name;
  final TrainerKind kind;

  /// Trainer Wi-Fi : adresse et port.
  final String? host;
  final int? port;

  const TrainerCandidate(BluetoothDevice this.device, this.name, {this.kind = TrainerKind.ftms})
    : host = null,
      port = null;
  const TrainerCandidate.wifi(String this.host, int this.port, this.name) : device = null, kind = TrainerKind.wifi;

  /// Identifiant gardé dans les réglages.
  String get id => kind == TrainerKind.wifi ? 'wifi:$host:$port' : device!.remoteId.str;
}

class TrainerClient {
  static final _service = Guid(Ftms.uuid128(Ftms.service));
  static final _bikeData = Guid(Ftms.uuid128(Ftms.indoorBikeData));
  static final _controlPoint = Guid(Ftms.uuid128(Ftms.controlPoint));
  static final _feature = Guid(Ftms.uuid128(Ftms.feature));
  static final _machineStatus = Guid(Ftms.uuid128(Ftms.machineStatus));
  static final _resistanceRange = Guid(Ftms.uuid128(Ftms.supportedResistance));
  static final _fecService = Guid(Fec.service);
  static final _fecNotify = Guid(Fec.notify);
  static final _fecWrite = Guid(Fec.write);
  static final _cpsService = Guid(WahooCps.service);
  static final _cpsMeasurement = Guid(WahooCps.measurement);
  static final _wahooControl = Guid(WahooCps.control);

  /// Poids cycliste + vélo (kg), pour la simulation de l'ancien protocole Wahoo.
  double riderKg = 85;

  final void Function(String) log;

  /// Trame « Indoor Bike Data » (FTMS) reçue du trainer.
  final void Function(Uint8List data) onBikeData;

  final ValueNotifier<LinkState> state = ValueNotifier(LinkState.disconnected);
  final ValueNotifier<String?> name = ValueNotifier(null);
  final ValueNotifier<List<TrainerCandidate>> candidates = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);

  /// Ce que le trainer connecté sait faire.
  final ValueNotifier<TrainerCaps> caps = ValueNotifier(const TrainerCaps());

  /// Calibration en cours (ou son résultat). null : aucune.
  final ValueNotifier<SpinDownState?> spinDown = ValueNotifier(null);
  Timer? _spinTimer;

  /// Lance la calibration (« spin down ») du trainer. Le suivi arrive dans [spinDown].
  Future<void> startSpinDown() async {
    if (!isConnected || !caps.value.spinDown) return;
    spinDown.value = const SpinDownState(SpinDownPhase.starting);
    _spinTimer?.cancel();
    // Sans nouvelle du trainer au bout de 3 minutes, on abandonne.
    _spinTimer = Timer(const Duration(minutes: 3), () {
      if (spinDown.value != null && !spinDown.value!.finished) {
        spinDown.value = const SpinDownState(SpinDownPhase.failed);
        unawaited(_write(Ftms.spinDown(start: false)));
      }
    });
    log('Calibration du trainer demandée');
    await _write(Ftms.spinDown());
  }

  /// Abandonne la calibration en cours, ou efface son résultat.
  Future<void> cancelSpinDown() async {
    _spinTimer?.cancel();
    final s = spinDown.value;
    spinDown.value = null;
    if (s != null && !s.finished && isConnected) await _write(Ftms.spinDown(start: false));
  }

  void _onStatus(List<int> v) {
    if (spinDown.value == null) return;
    final s = SpinDownState.fromStatus(v, spinDown.value);
    if (s == null) return;
    spinDown.value = s;
    if (s.finished) {
      _spinTimer?.cancel();
      log(s.phase == SpinDownPhase.success ? 'Calibration réussie' : 'Calibration ratée');
    }
  }

  /// Chemin utilisé avec le trainer connecté.
  final ValueNotifier<TrainerKind?> kind = ValueNotifier(null);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cp;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _wanted = false;
  Future<void> _writeChain = Future.value();

  // FE-C
  final FecDecoder _fec = FecDecoder();

  // Ancien protocole Wahoo
  final CyclingPowerDecoder _cps = CyclingPowerDecoder();

  // Wi-Fi
  Socket? _socket;
  int _seq = 0;

  /// Adresses de ce téléphone, pour ne pas se trouver soi-même en Wi-Fi.
  Set<String> ownAddresses = {};

  TrainerClient({required this.log, required this.onBikeData});

  bool get isConnected => state.value == LinkState.connected;

  /// Cherche les home trainers à proximité (Bluetooth FTMS / FE-C, et Wi-Fi).
  Future<void> scan() async {
    if (scanning.value) return;
    scanning.value = true;
    candidates.value = const [];
    void add(TrainerCandidate c) {
      if (candidates.value.any((x) => x.id == c.id)) return;
      candidates.value = [...candidates.value, c];
    }

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final s = r.advertisementData.serviceUuids;
        final ftms = s.contains(_service);
        final fec = s.contains(_fecService);
        final adv = r.advertisementData.advName;
        final wahoo = !ftms && !fec && s.contains(_cpsService) && looksLikeWahooTrainer(adv);
        if (!ftms && !fec && !wahoo) continue;
        add(
          TrainerCandidate(
            r.device,
            adv.isNotEmpty ? adv : r.device.remoteId.str,
            kind: ftms
                ? TrainerKind.ftms
                : fec
                ? TrainerKind.fec
                : TrainerKind.wahoo,
          ),
        );
      }
    });
    nsd.Discovery? discovery;
    try {
      nsd.disableServiceTypeValidation(true);
      discovery = await nsd.startDiscovery(Dircon.serviceType, ipLookupType: nsd.IpLookupType.v4);
      void onFound() {
        for (final s in discovery!.services) {
          final ip = s.addresses?.firstOrNull?.address ?? s.host;
          if (ip == null || s.port == null || ownAddresses.contains(ip)) continue;
          if ((s.name ?? '').startsWith('ShiftLink')) continue;
          add(TrainerCandidate.wifi(ip, s.port!, '${s.name == null ? ip : wifiModelName(s.name!)} (Wi-Fi)'));
        }
      }

      discovery.addListener(onFound);
    } catch (e) {
      log('Recherche des trainers Wi-Fi impossible ($e)');
    }
    try {
      await FlutterBluePlus.startScan(withServices: [_service, _fecService, _cpsService], timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      log('Recherche du trainer : $e');
    }
    await sub.cancel();
    if (discovery != null) {
      try {
        await nsd.stopDiscovery(discovery);
      } catch (_) {}
    }
    scanning.value = false;
    if (candidates.value.isEmpty) {
      log('Aucun home trainer trouvé. Déconnecte-le des autres applis (Zwift, MyWhoosh…) et réessaie.');
    }
  }

  /// Nom du trainer annoncé en Wi-Fi, ramené au nom qu'il a en Bluetooth quand on le
  /// connaît : Elite annonce « RIVO » en Bluetooth mais « ELITE RIVO 00016 W » en Wi-Fi.
  static String wifiModelName(String name) {
    final elite = RegExp(r'^ELITE[\s_-]+(.+?)[\s_-]+\d+[\s_-]+W$', caseSensitive: false).firstMatch(name.trim());
    return elite?.group(1) ?? name;
  }

  /// Ce qui identifie le trainer quel que soit le chemin (Bluetooth ou Wi-Fi).
  static String twinKey(String name) =>
      wifiModelName(name.replaceAll(' (Wi-Fi)', '')).toUpperCase().replaceAll(RegExp(r'[\s_-]+'), ' ').trim();

  /// Le même trainer apparaît aussi par l'autre chemin dans [list].
  static bool hasTwin(TrainerCandidate c, List<TrainerCandidate> list) => list.any(
    (o) => o.id != c.id && (o.kind == TrainerKind.wifi) != (c.kind == TrainerKind.wifi) && twinKey(o.name) == twinKey(c.name),
  );

  /// Reconnecte un trainer gardé dans les réglages.
  Future<void> connectById(String id, String label) {
    if (id.startsWith('wifi:')) {
      final parts = id.split(':');
      final port = int.tryParse(parts.last) ?? Dircon.port;
      final host = parts.sublist(1, parts.length - 1).join(':');
      return connectCandidate(TrainerCandidate.wifi(host, port, label));
    }
    return connect(BluetoothDevice.fromId(id), label);
  }

  Future<void> connectCandidate(TrainerCandidate c) =>
      c.kind == TrainerKind.wifi ? _connectWifi(c.host!, c.port!, c.name) : connect(c.device!, c.name);

  Future<void> connect(BluetoothDevice device, String label) async {
    _wanted = true;
    _device = device;
    name.value = label;
    state.value = LinkState.connecting;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      try {
        await device.requestMtu(185);
      } catch (_) {}
      final services = await device.discoverServices();
      final s = services.where((s) => s.uuid == _service).firstOrNull;
      final f = services.where((s) => s.uuid == _fecService).firstOrNull;
      final w = services
          .where((s) => s.uuid == _cpsService && s.characteristics.any((c) => c.uuid == _wahooControl))
          .firstOrNull;
      if (s != null) {
        await _setupFtms(device, s);
      } else if (f != null) {
        await _setupFec(device, f);
      } else if (w != null) {
        await _setupWahoo(device, w);
      } else {
        throw Exception('ni FTMS, ni FE-C, ni protocole Wahoo');
      }
      state.value = LinkState.connected;
      final proto = switch (kind.value) {
        TrainerKind.fec => 'FE-C',
        TrainerKind.wahoo => 'ancien protocole Wahoo',
        _ => 'FTMS',
      };
      log('Home trainer $label connecté ($proto)');
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && state.value == LinkState.connected) {
          state.value = LinkState.disconnected;
          log('Home trainer déconnecté, reconnexion…');
          if (_wanted) Future.delayed(const Duration(seconds: 2), () => connect(device, label));
        }
      });
    } catch (e) {
      state.value = LinkState.disconnected;
      log('Home trainer : échec de connexion ($e)');
      try {
        await device.disconnect();
      } catch (_) {}
      _retry(() => connect(device, label));
    }
  }

  void _retry(Future<void> Function() again) {
    if (!_wanted) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (_wanted && state.value == LinkState.disconnected) again();
    });
  }

  Future<void> _setupFtms(BluetoothDevice device, BluetoothService s) async {
    final data = s.characteristics.where((c) => c.uuid == _bikeData).firstOrNull;
    final cp = s.characteristics.where((c) => c.uuid == _controlPoint).firstOrNull;
    if (data == null || cp == null) throw Exception('caractéristiques FTMS manquantes');
    Future<List<int>?> readOpt(Guid id) async {
      try {
        return await s.characteristics.where((c) => c.uuid == id).firstOrNull?.read();
      } catch (_) {
        return null;
      }
    }

    caps.value = TrainerCaps.parse(await readOpt(_feature), await readOpt(_resistanceRange));
    log('Le trainer accepte : ${caps.value.describe()}');
    final dataSub = data.onValueReceived.listen((v) => onBikeData(Uint8List.fromList(v)));
    device.cancelWhenDisconnected(dataSub);
    await data.setNotifyValue(true);
    final cpSub = cp.onValueReceived.listen(_onResponse);
    device.cancelWhenDisconnected(cpSub);
    await cp.setNotifyValue(true);
    // État de la machine : sert au suivi de la calibration. Facultatif.
    final status = s.characteristics.where((c) => c.uuid == _machineStatus).firstOrNull;
    if (status != null) {
      try {
        final stSub = status.onValueReceived.listen(_onStatus);
        device.cancelWhenDisconnected(stSub);
        await status.setNotifyValue(true);
      } catch (_) {}
    }
    _cp = cp;
    kind.value = TrainerKind.ftms;
    await _write(Ftms.requestControl());
    await _write(Ftms.startResume());
  }

  Future<void> _setupFec(BluetoothDevice device, BluetoothService s) async {
    final rx = s.characteristics.where((c) => c.uuid == _fecNotify).firstOrNull;
    final tx = s.characteristics.where((c) => c.uuid == _fecWrite).firstOrNull;
    if (rx == null || tx == null) throw Exception('caractéristiques FE-C manquantes');
    caps.value = const TrainerCaps();
    final sub = rx.onValueReceived.listen((v) {
      if (_fec.add(v)) onBikeData(_fec.bikeData);
    });
    device.cancelWhenDisconnected(sub);
    await rx.setNotifyValue(true);
    _cp = tx;
    kind.value = TrainerKind.fec;
  }

  Future<void> _setupWahoo(BluetoothDevice device, BluetoothService s) async {
    final data = s.characteristics.where((c) => c.uuid == _cpsMeasurement).firstOrNull;
    final ctrl = s.characteristics.where((c) => c.uuid == _wahooControl).firstOrNull;
    if (data == null || ctrl == null) throw Exception('caractéristiques Wahoo manquantes');
    // Puissance imposée, pente et résistance : oui ; pas de calibration depuis ShiftLink.
    caps.value = const TrainerCaps();
    final sub = data.onValueReceived.listen((v) {
      if (_cps.add(v)) onBikeData(_cps.bikeData);
    });
    device.cancelWhenDisconnected(sub);
    await data.setNotifyValue(true);
    try {
      await ctrl.setNotifyValue(true);
    } catch (_) {}
    _cp = ctrl;
    kind.value = TrainerKind.wahoo;
    await _cp!.write(WahooCps.unlock(), timeout: 5);
  }

  void _onResponse(List<int> v) {
    if (spinDown.value != null) {
      final s = SpinDownState.fromResponse(v);
      if (s != null) {
        spinDown.value = s;
        if (s.finished) _spinTimer?.cancel();
      }
    }
    if (v.length >= 3 && v[0] == Ftms.opResponse && v[2] != Ftms.resultSuccess) {
      log('Le trainer refuse la commande 0x${v[1].toRadixString(16)} (code ${v[2]})');
    }
  }

  // --- Wi-Fi (DIRCON) ---

  final Map<int, Completer<Uint8List>> _pending = {};

  Future<Uint8List> _request(int type, List<int> payload) {
    final s = _socket;
    if (s == null) return Future.error(const SocketException('pas connecté'));
    final seq = _seq = (_seq + 1) & 0xFF;
    final done = _pending[seq] = Completer<Uint8List>();
    s.add(Dircon.packet(type, seq, 0, payload));
    return done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(seq);
        throw TimeoutException('pas de réponse');
      },
    );
  }

  void _onDircon(DirconMessage m) {
    if (m.type == Dircon.msgNotification) {
      final id = Dircon.shortUuid(m.payload);
      if (m.payload.length < 16) return;
      final value = Uint8List.fromList(m.payload.sublist(16));
      if (id == Ftms.indoorBikeData) onBikeData(value);
      if (id == Ftms.controlPoint) _onResponse(value);
      if (id == Ftms.machineStatus) _onStatus(value);
      return;
    }
    _pending.remove(m.seq)?.complete(m.payload);
  }

  Future<void> _connectWifi(String host, int port, String label) async {
    _wanted = true;
    name.value = label;
    state.value = LinkState.connecting;
    try {
      // ignore: close_sinks
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
      _socket = socket;
      final framer = DirconFramer();
      socket.listen(
        (d) {
          for (final m in framer.add(d)) {
            _onDircon(m);
          }
        },
        onDone: () => _wifiLost(host, port, label),
        onError: (_) => _wifiLost(host, port, label),
        cancelOnError: true,
      );
      final services = await _request(Dircon.msgDiscoverServices, const []);
      var hasFtms = false;
      for (var i = 0; i + 16 <= services.length; i += 16) {
        if (Dircon.shortUuid(services.sublist(i, i + 16)) == Ftms.service) hasFtms = true;
      }
      if (!hasFtms) throw Exception('pas de service FTMS en Wi-Fi');
      await _request(Dircon.msgDiscoverCharacteristics, Dircon.uuidBytes(Ftms.service));
      Future<List<int>?> read(int id) async {
        try {
          final r = await _request(Dircon.msgRead, Dircon.uuidBytes(id));
          return r.length > 16 ? r.sublist(16) : null;
        } catch (_) {
          return null;
        }
      }

      caps.value = TrainerCaps.parse(await read(Ftms.feature), await read(Ftms.supportedResistance));
      await _request(Dircon.msgEnableNotifications, [...Dircon.uuidBytes(Ftms.indoorBikeData), 1]);
      await _request(Dircon.msgEnableNotifications, [...Dircon.uuidBytes(Ftms.controlPoint), 1]);
      try {
        await _request(Dircon.msgEnableNotifications, [...Dircon.uuidBytes(Ftms.machineStatus), 1]);
      } catch (_) {}
      kind.value = TrainerKind.wifi;
      state.value = LinkState.connected;
      await _write(Ftms.requestControl());
      await _write(Ftms.startResume());
      log('Home trainer $label connecté (Wi-Fi)');
    } catch (e) {
      log('Home trainer Wi-Fi : échec de connexion ($e)');
      _socket?.destroy();
      _socket = null;
      state.value = LinkState.disconnected;
      _retry(() => _connectWifi(host, port, label));
    }
  }

  void _wifiLost(String host, int port, String label) {
    _socket?.destroy();
    _socket = null;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.completeError(const SocketException('fermé'));
    }
    _pending.clear();
    if (state.value != LinkState.connected) return;
    state.value = LinkState.disconnected;
    log('Home trainer Wi-Fi déconnecté, reconnexion…');
    _retry(() => _connectWifi(host, port, label));
  }

  /// Écrit une commande FTMS (traduite si besoin ; les écritures sont mises en file).
  Future<void> _write(Uint8List cmd) {
    final k = kind.value;
    _writeChain = _writeChain.then((_) async {
      try {
        switch (k) {
          case TrainerKind.wifi:
            await _request(Dircon.msgWrite, [...Dircon.uuidBytes(Ftms.controlPoint), ...cmd]);
          case TrainerKind.fec:
            for (final m in Fec.fromFtms(cmd)) {
              await _cp?.write(m, timeout: 5);
            }
          case TrainerKind.wahoo:
            for (final m in WahooCps.fromFtms(cmd, kg: riderKg)) {
              await _cp?.write(m, timeout: 5);
            }
          case TrainerKind.ftms || null:
            await _cp?.write(cmd, timeout: 5);
        }
      } catch (e) {
        log('Commande au trainer échouée ($e)');
      }
    });
    return _writeChain;
  }

  /// Transmet une commande brute du point de contrôle.
  Future<void> send(Uint8List cmd) => isConnected ? _write(cmd) : Future.value();

  Future<void> disconnect() async {
    _wanted = false;
    await _connSub?.cancel();
    state.value = LinkState.disconnected;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _socket?.destroy();
    _socket = null;
    _cp = null;
    _spinTimer?.cancel();
    spinDown.value = null;
    kind.value = null;
    name.value = null;
  }
}
