// MyWhoosh « Link » : MyWhoosh se connecte en TCP (port 21587) à l'appareil qui joue
// le rôle de l'app « MyWhoosh Link » et reçoit une ligne JSON par commande.
//
// Code écrit pour ShiftLink. Le format des messages (MessageType « Controls »,
// InGameControls) est celui qu'attend MyWhoosh.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'net/lan_server.dart';

class WhooshLinkProtocol {
  static const int port = 21587;

  /// Commande de jeu : un ou plusieurs contrôles, valeurs en texte.
  static Map<String, dynamic> controls(Map<String, String> values) => {
    'MessageType': 'Controls',
    'InGameControls': values,
  };

  /// Changement de vitesse : +1 plus dur, −1 plus facile.
  static Map<String, dynamic> gearShift(int delta) => controls({'GearShifting': '$delta'});

  static String encode(Map<String, dynamic> msg) => jsonEncode(msg);
}

class WhooshLinkServer {
  final ValueNotifier<bool> isStarted = ValueNotifier(false);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<String?> clientAddress = ValueNotifier(null);
  final void Function(String) log;

  late final LanServer _server = LanServer(port: WhooshLinkProtocol.port, name: 'Link', log: log)
    ..onClient = _clientChanged
    ..onData = (data) {
      if (kDebugMode) debugPrint('MyWhoosh → ${utf8.decode(data, allowMalformed: true)}');
    };

  WhooshLinkServer({required this.log});

  /// Actions autres que les vitesses que MyWhoosh comprend par Link.
  static const controls = {'steerLeft', 'steerRight', 'uturn', 'cameraAngle', 'emote'};

  // MyWhoosh propose 6 caméras et 6 emotes : on les fait défiler.
  int _camera = 0;
  int _emote = 0;

  void _clientChanged(String? address) {
    clientAddress.value = address;
    isConnected.value = address != null;
    log(address != null ? 'MyWhoosh connecté ($address)' : 'MyWhoosh déconnecté');
  }

  Future<void> start() async {
    if (isStarted.value) return;
    try {
      await _server.open();
    } catch (e) {
      log('Impossible de démarrer le serveur Link ($e). Vérifie que l’app « MyWhoosh Link » est fermée.');
      rethrow;
    }
    isStarted.value = true;
    log('Serveur Link prêt sur le port ${WhooshLinkProtocol.port}');
  }

  bool _sendLine(Map<String, dynamic> msg) => _server.send(utf8.encode('${WhooshLinkProtocol.encode(msg)}\n'));

  /// Envoie un changement de vitesse. Renvoie false si MyWhoosh n'est pas connecté.
  bool shift(int delta) => _sendLine(WhooshLinkProtocol.gearShift(delta));

  /// Commande autre qu'une vitesse. [down] : début (true) ou fin (false) d'un
  /// maintien, pour la direction.
  bool control(String action, {bool down = true}) {
    if (!_server.hasClient) return false;
    final Map<String, String>? values = switch (action) {
      'steerLeft' => {'Steering': down ? '-1' : '0'},
      'steerRight' => {'Steering': down ? '1' : '0'},
      'uturn' => {'UTurn': 'true'},
      'cameraAngle' => {'CameraAngle': '${_camera = _camera % 6 + 1}'},
      'emote' => {'Emote': '${_emote = _emote % 6 + 1}'},
      _ => null,
    };
    return values != null && _sendLine(WhooshLinkProtocol.controls(values));
  }

  Future<void> stop() async {
    await _server.close();
    isStarted.value = false;
    isConnected.value = false;
    clientAddress.value = null;
  }

  static Future<List<String>> localAddresses() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses) a.address,
  ];
}
