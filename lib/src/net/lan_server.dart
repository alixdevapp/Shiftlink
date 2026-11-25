// Serveur TCP à un seul client, limité au réseau local.
// Sert à MyWhoosh Link et à OpenBikeControl.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_network.dart';

class LanServer {
  final int port;
  final String name;
  final void Function(String) log;

  /// Données reçues du client.
  void Function(Uint8List data)? onData;

  /// Le client vient d'arriver (adresse) ou de partir (null).
  void Function(String? address)? onClient;

  LanServer({required this.port, required this.name, required this.log});

  ServerSocket? _server;
  Socket? _client;
  StreamSubscription<Uint8List>? _clientSub;
  final _lan = LocalNetwork();

  bool get listening => _server != null;
  bool get hasClient => _client != null;

  /// Ouvre le port, en IPv6 + IPv4 si possible, sinon en IPv4 seul.
  Future<void> open() async {
    if (_server != null) return;
    ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv6, port, shared: true);
    } on SocketException {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    }
    _server = server;
    await _lan.refresh();
    server.listen(_accept);
  }

  void _accept(Socket socket) {
    final from = socket.remoteAddress;
    if (!_lan.allows(from)) {
      log('Connexion refusée : ${from.address} n’est pas sur ton réseau local');
      socket.destroy();
      return;
    }
    // Un seul client : le dernier arrivé remplace le précédent.
    _drop();
    _client = socket;
    _clientSub = socket.listen(
      (data) => onData?.call(data),
      onDone: () => _lost(socket),
      onError: (_) => _lost(socket),
      cancelOnError: true,
    );
    onClient?.call(from.address);
  }

  void _lost(Socket socket) {
    if (!identical(_client, socket)) return;
    _client = null;
    _clientSub = null;
    onClient?.call(null);
  }

  void _drop() {
    _clientSub?.cancel();
    _client?.destroy();
    _clientSub = null;
    _client = null;
  }

  /// Envoie au client. Renvoie false s'il n'y en a pas.
  bool send(List<int> bytes) {
    final c = _client;
    if (c == null) return false;
    c.add(bytes);
    return true;
  }

  Future<void> close() async {
    final had = _client != null;
    _drop();
    await _server?.close();
    _server = null;
    if (had) onClient?.call(null);
  }
}
