import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';

void main() {
  test('Incyclist : une seule ligne, ShiftLink pilote le trainer par défaut', () {
    expect(TargetApp.pickable, contains(TargetApp.incyclist));
    expect(TargetApp.pickable, isNot(contains(TargetApp.incyclistObc)));
    expect(TargetApp.incyclist.transport, Transport.proxy);
    expect(TargetApp.incyclistObc.transport, Transport.obc);
    expect(TargetApp.incyclistObc.base, TargetApp.incyclist);
    expect(TargetApp.incyclist.alternative, TargetApp.incyclistObc);
    expect(TargetApp.incyclistObc.alternative, TargetApp.incyclist);
  });

  test('OpenBikeControl : l’id « incyclist » s’affiche « Incyclist »', () {
    expect(ObcProtocol.appName('incyclist'), 'Incyclist');
    expect(ObcProtocol.appName('autre'), 'autre');
  });
}
