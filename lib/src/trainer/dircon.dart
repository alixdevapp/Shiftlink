// Trainer émulé sur le Wi-Fi avec le protocole « Wahoo Direct Connect »
// (DIRCON), que Zwift, Rouvy, TrainingPeaks Virtual… savent utiliser.
//
// Chaque message : [version=1, type, séquence, code réponse, longueur (2 octets, big endian)]
// suivi des données. Les UUID font 16 octets.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../net/local_network.dart';
import 'ftms.dart';

class Dircon {
  static const int port = 36866;
  static const String serviceType = '_wahoo-fitness-tnp._tcp';

  static const msgDiscoverServices = 0x01;
  static const msgDiscoverCharacteristics = 0x02;
  static const msgRead = 0x03;
  static const msgWrite = 0x04;
  static const msgEnableNotifications = 0x05;
  static const msgNotification = 0x06;

  static const ok = 0x00;
  static const errUnknownMessage = 0x01;
  static const errServiceNotFound = 0x03;
  static const errCharacteristicNotFound = 0x04;

  static const propRead = 0x01;
  static const propWrite = 0x02;
  static const propNotify = 0x04;

  static Uint8List uuidBytes(int short) => Uint8List.fromList([
    0x00, 0x00, (short >> 8) & 0xff, short & 0xff, //
    0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb,
  ]);

  /// Identifiant 16 bits d'un UUID Bluetooth de base, ou null.
  static int? shortUuid(List<int> b) {
    if (b.length < 16) return null;
    final base = uuidBytes(0);
    for (var i = 4; i < 16; i++) {
      if (b[i] != base[i]) return null;
    }
    if (b[0] != 0 || b[1] != 0) return null;
    return (b[2] << 8) | b[3];
  }

  static Uint8List packet(int type, int seq, int code, List<int> payload) {
    final out = BytesBuilder();
    out.add([1, type, seq & 0xff, code, (payload.length >> 8) & 0xff, payload.length & 0xff]);
    out.add(payload);
    return out.toBytes();
  }
}

class DirconMessage {
  final int type;
  final int seq;
  final Uint8List payload;
  DirconMessage(this.type, this.seq, this.payload);
}

/// Découpe le flux TCP en messages complets.
class DirconFramer {
  final _buf = BytesBuilder();

  List<DirconMessage> add(List<int> data) {
    _buf.add(data);
    final bytes = _buf.takeBytes();
    final out = <DirconMessage>[];
    var i = 0;
    while (bytes.length - i >= 6) {
      final len = (bytes[i + 4] << 8) | bytes[i + 5];
      if (bytes.length - i < 6 + len) break;
      out.add(DirconMessage(bytes[i + 1], bytes[i + 2], Uint8List.fromList(bytes.sublist(i + 6, i + 6 + len))));
      i += 6 + len;
    }
    if (i < bytes.length) _buf.add(bytes.sublist(i));
    return out;
  }
}

class EmulatedCharacteristic {
  final int uuid;
  final int properties;
  Uint8List value;
  EmulatedCharacteristic(this.uuid, this.properties, [Uint8List? value]) : value = value ?? Uint8List(0);
}

/// Serveur DIRCON qui expose un service FTMS.
class DirconServer {
  final ValueNotifier<bool> isStarted = ValueNotifier(false);
  final ValueNotifier<String?> client = ValueNotifier(null);
  final void Function(String) log;

  /// Appelé quand l'appli écrit dans le point de contrôle FTMS.
  /// Doit renvoyer la réponse à indiquer.
  final Uint8List Function(Uint8List command) onControlPoint;

  final String name;
  static const maxClients = 4;
  final _lan = LocalNetwork();
  ServerSocket? _server;
  nsd.Registration? _registration;
  final Map<Socket, Set<int>> _subscriptions = {};

  late final Map<int, EmulatedCharacteristic> characteristics = {
    Ftms.feature: EmulatedCharacteristic(
      Ftms.feature,
      Dircon.propRead,
      // Fonctions : cadence, cardio, puissance. Réglages : résistance, puissance, simulation.
      Uint8List.fromList([0x02, 0x44, 0x00, 0x00, 0x0C, 0x20, 0x00, 0x00]),
    ),
    Ftms.indoorBikeData: EmulatedCharacteristic(Ftms.indoorBikeData, Dircon.propNotify),
    Ftms.trainingStatus: EmulatedCharacteristic(
      Ftms.trainingStatus,
      Dircon.propRead | Dircon.propNotify,
      Uint8List.fromList([0x00, 0x01]),
    ),
    Ftms.supportedResistance: EmulatedCharacteristic(
      Ftms.supportedResistance,
      Dircon.propRead,
      Uint8List.fromList([0x00, 0x00, 0xE8, 0x03, 0x01, 0x00]),
    ),
    Ftms.supportedPower: EmulatedCharacteristic(
      Ftms.supportedPower,
      Dircon.propRead,
      Uint8List.fromList([0x00, 0x00, 0xD0, 0x07, 0x01, 0x00]),
    ),
    Ftms.controlPoint: EmulatedCharacteristic(Ftms.controlPoint, Dircon.propWrite | Dircon.propNotify),
    Ftms.machineStatus: EmulatedCharacteristic(Ftms.machineStatus, Dircon.propNotify),
  };

  DirconServer({required this.log, required this.onControlPoint, this.name = 'ShiftLink'});

  Future<void> start() async {
    if (isStarted.value) return;
    try {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv6, Dircon.port, shared: true);
      } on SocketException {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, Dircon.port, shared: true);
      }
    } catch (e) {
      log('Trainer Wi-Fi : port ${Dircon.port} indisponible ($e)');
      return;
    }
    await _lan.refresh();
    _server!.listen(_onClient);
    try {
      nsd.disableServiceTypeValidation(true);
      _registration = await nsd.register(
        nsd.Service(
          name: name,
          type: Dircon.serviceType,
          port: Dircon.port,
          txt: {
            'ble-service-uuids': Uint8List.fromList('0x1826'.codeUnits),
            'mac-address': Uint8List.fromList('5A-4C-53-48-49-46'.codeUnits),
            'serial-number': Uint8List.fromList('SHIFTLINK1'.codeUnits),
          },
        ),
      );
    } catch (e) {
      log('Trainer Wi-Fi : annonce réseau impossible ($e)');
    }
    isStarted.value = true;
  }

  void _onClient(Socket socket) {
    if (!_lan.allows(socket.remoteAddress)) {
      log('Connexion refusée : ${socket.remoteAddress.address} n’est pas sur ton réseau local');
      socket.destroy();
      return;
    }
    if (_subscriptions.length >= maxClients) {
      log('Connexion refusée : déjà $maxClients applis connectées au trainer ShiftLink');
      socket.destroy();
      return;
    }
    final framer = DirconFramer();
    _subscriptions[socket] = {};
    client.value = socket.remoteAddress.address;
    log('Appli connectée au trainer ShiftLink (${socket.remoteAddress.address})');
    socket.listen(
      (data) {
        for (final m in framer.add(data)) {
          _handle(socket, m);
        }
      },
      onDone: () => _gone(socket),
      onError: (_) => _gone(socket),
      cancelOnError: true,
    );
  }

  void _gone(Socket socket) {
    _subscriptions.remove(socket);
    socket.destroy();
    if (_subscriptions.isEmpty) {
      client.value = null;
      log('Appli déconnectée du trainer ShiftLink');
    }
  }

  @visibleForTesting
  List<Uint8List> handleForTest(DirconMessage m) {
    final out = <Uint8List>[];
    _respond(m, out.add, (_) {});
    return out;
  }

  void _handle(Socket socket, DirconMessage m) {
    _respond(m, socket.add, (uuid) => _subscriptions[socket]?.add(uuid));
  }

  void _respond(DirconMessage m, void Function(Uint8List) send, void Function(int) subscribe) {
    final p = m.payload;
    switch (m.type) {
      case Dircon.msgDiscoverServices:
        send(Dircon.packet(m.type, m.seq, Dircon.ok, Dircon.uuidBytes(Ftms.service)));
      case Dircon.msgDiscoverCharacteristics:
        if (Dircon.shortUuid(p) != Ftms.service) {
          send(Dircon.packet(m.type, m.seq, Dircon.errServiceNotFound, p.length >= 16 ? p.sublist(0, 16) : p));
          return;
        }
        final body = BytesBuilder()..add(Dircon.uuidBytes(Ftms.service));
        for (final c in characteristics.values) {
          body
            ..add(Dircon.uuidBytes(c.uuid))
            ..addByte(c.properties);
        }
        send(Dircon.packet(m.type, m.seq, Dircon.ok, body.toBytes()));
      case Dircon.msgRead:
        final c = characteristics[Dircon.shortUuid(p)];
        if (c == null) {
          send(Dircon.packet(m.type, m.seq, Dircon.errCharacteristicNotFound, p.length >= 16 ? p.sublist(0, 16) : p));
          return;
        }
        send(Dircon.packet(m.type, m.seq, Dircon.ok, [...Dircon.uuidBytes(c.uuid), ...c.value]));
      case Dircon.msgEnableNotifications:
        final id = Dircon.shortUuid(p);
        final c = characteristics[id];
        if (c == null) {
          send(Dircon.packet(m.type, m.seq, Dircon.errCharacteristicNotFound, p.length >= 16 ? p.sublist(0, 16) : p));
          return;
        }
        subscribe(c.uuid);
        send(Dircon.packet(m.type, m.seq, Dircon.ok, Dircon.uuidBytes(c.uuid)));
      case Dircon.msgWrite:
        final id = Dircon.shortUuid(p);
        if (id != Ftms.controlPoint) {
          send(Dircon.packet(m.type, m.seq, Dircon.errCharacteristicNotFound, p.length >= 16 ? p.sublist(0, 16) : p));
          return;
        }
        final command = Uint8List.fromList(p.sublist(16));
        send(Dircon.packet(m.type, m.seq, Dircon.ok, Dircon.uuidBytes(id!)));
        final response = onControlPoint(command);
        send(
          Dircon.packet(Dircon.msgNotification, 0, Dircon.ok, [...Dircon.uuidBytes(Ftms.controlPoint), ...response]),
        );
      default:
        send(Dircon.packet(m.type, m.seq, Dircon.errUnknownMessage, const []));
    }
  }

  /// Envoie une notification aux applis abonnées.
  void notify(int uuid, Uint8List value) {
    final pkt = Dircon.packet(Dircon.msgNotification, 0, Dircon.ok, [...Dircon.uuidBytes(uuid), ...value]);
    for (final e in _subscriptions.entries) {
      if (e.value.contains(uuid)) {
        try {
          e.key.add(pkt);
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    if (_registration != null) {
      try {
        await nsd.unregister(_registration!);
      } catch (_) {}
      _registration = null;
    }
    for (final s in _subscriptions.keys.toList()) {
      s.destroy();
    }
    _subscriptions.clear();
    await _server?.close();
    _server = null;
    client.value = null;
    isStarted.value = false;
  }
}
