// 2.17.1 : le bouton SIM / ERG ne semblait pas marcher. Un refus doit s'expliquer à l'écran.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/controller_manager.dart';
import 'package:shiftlink/src/trainer/fec.dart' show indoorBikeData;
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/proxy.dart';

void main() {
  Future<AppState> zwiftApp(WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'zwift', 'onboarded': true, 'language': 'fr'});
    final app = AppState(demo: true);
    await tester.runAsync(app.init);
    app.proxy.server.client.value = 'Zwift';
    return app;
  }

  testWidgets('ERG sans pédaler : refusé, avec un message', (tester) async {
    final app = await zwiftApp(tester);
    final notices = <String>[];
    app.onNotice = notices.add;
    expect(app.toggleErg(), isFalse);
    expect(notices.single, contains('Pédale d’abord'));
    expect(app.proxy.mode, isNot(TrainerMode.erg));
  });

  testWidgets('ERG en pédalant : Power Lock aux watts du moment, puis retour en SIM', (tester) async {
    final app = await zwiftApp(tester);
    final notices = <String>[];
    app.onNotice = notices.add;
    for (var i = 0; i < 4; i++) {
      app.proxy.handleBikeData(indoorBikeData(const BikeData(speedKmh: 30, cadence: 90, power: 182)));
    }
    expect(app.toggleErg(), isTrue);
    expect(app.proxy.mode, TrainerMode.erg);
    expect(app.proxy.powerLock.value, 180);
    expect(app.toggleErg(), isTrue);
    expect(app.proxy.powerLock.value, isNull);
    expect(notices, isEmpty);
  });

  testWidgets('trainer non connecté : le message le dit', (tester) async {
    final app = await zwiftApp(tester);
    app.proxy.trainer.state.value = LinkState.disconnected;
    final notices = <String>[];
    app.onNotice = notices.add;
    expect(app.togglePowerLock(), isFalse);
    expect(notices.single, contains('home trainer'));
  });
}
