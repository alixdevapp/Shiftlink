import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/installed_apps.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';

void main() {
  test('Everycol : sa propre ligne, en OpenBikeControl', () {
    expect(TargetApp.pickable, contains(TargetApp.everycol));
    expect(TargetApp.everycol.transport, Transport.obc);
    expect(InstalledApps.searchName(TargetApp.everycol), 'Everycol');
    expect(ObcProtocol.appName('everycol'), 'Everycol');
  });
}
