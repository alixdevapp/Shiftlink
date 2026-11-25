import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';
import 'package:shiftlink/src/trainer/trainer_client.dart';

void main() {
  test('Biketerra : clavier par défaut, OpenBikeControl en variante', () {
    expect(TargetApp.pickable, contains(TargetApp.biketerra));
    expect(TargetApp.pickable, isNot(contains(TargetApp.biketerraObc)));
    expect(TargetApp.biketerra.transport, Transport.keyboard);
    expect(TargetApp.biketerraObc.transport, Transport.obc);
    expect(TargetApp.biketerraObc.base, TargetApp.biketerra);
    expect(TargetApp.biketerra.alternative, TargetApp.biketerraObc);
    expect(TargetApp.biketerraObc.alternative, TargetApp.biketerra);
  });

  test('OpenBikeControl : noms lisibles des applis', () {
    expect(ObcProtocol.appName('biketerra'), 'Biketerra');
    expect(ObcProtocol.appName('tour-du-pain'), 'Tour du Pain');
    expect(ObcProtocol.appName('Ride Cave'), 'Ride Cave');
    expect(ObcProtocol.appName('grimpa.app'), 'Grimpa');
    expect(ObcProtocol.appName('inconnue'), 'inconnue');
  });

  test('Elite : le nom Wi-Fi est ramené au nom Bluetooth', () {
    expect(TrainerClient.wifiModelName('ELITE RIVO 00016 W'), 'RIVO');
    expect(TrainerClient.wifiModelName('KICKR CORE 1234'), 'KICKR CORE 1234');
    final ble = TrainerCandidate(BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'), 'RIVO');
    const wifi = TrainerCandidate.wifi('192.168.1.2', 36866, 'RIVO (Wi-Fi)');
    const other = TrainerCandidate.wifi('192.168.1.3', 36866, 'KICKR CORE (Wi-Fi)');
    expect(TrainerClient.hasTwin(wifi, [ble, wifi, other]), isTrue);
    expect(TrainerClient.hasTwin(ble, [ble, wifi, other]), isTrue);
    expect(TrainerClient.hasTwin(other, [ble, wifi, other]), isFalse);
  });
}
