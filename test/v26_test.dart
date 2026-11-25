import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/installed_apps.dart';
import 'package:shiftlink/src/problem_report.dart';
import 'package:shiftlink/src/voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pile faible : une alerte à 20 %, une à 10 %, puis plus rien jusqu’à la recharge', () {
    final w = BatteryWatch();
    expect(w.check('a', 80), isNull);
    expect(w.check('a', 21), isNull);
    expect(w.check('a', 20), 20);
    expect(w.check('a', 18), isNull);
    expect(w.check('a', 9), 10);
    expect(w.check('a', 5), isNull);
    expect(w.check('b', 7), 10, reason: 'chaque manette a ses alertes');
    expect(w.check('a', 100), isNull);
    expect(w.check('a', 15), 20, reason: 'après une recharge on prévient de nouveau');
  });

  test('rapport : version, manette, journal et texte de la personne', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(demo: true);
    await app.init();
    final r = buildProblemReport(
      app,
      version: '2.6.0',
      what: 'Le bouton + ne fait rien',
      checks: const [(title: 'Bluetooth', ok: true, detail: 'Activé')],
    );
    expect(r, startsWith('ShiftLink 2.6.0'));
    expect(r, contains('Le bouton + ne fait rien'));
    expect(r, contains('THINK VS200'));
    expect(r, contains('pile 27 %'));
    expect(r, contains('✓ Bluetooth : Activé'));
    expect(r, contains('Journal'));
  });

  test('quoi de neuf : pas à la première installation, une fois après une mise à jour', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    app.prefs = await SharedPreferences.getInstance();
    expect(app.shouldShowWhatsNew('2.6.0'), isFalse, reason: 'nouvelle installation');
    await app.prefs!.setBool('onboarded', true);
    expect(app.shouldShowWhatsNew('2.6.0'), isFalse, reason: 'déjà vue');
    expect(app.shouldShowWhatsNew('2.7.0'), isTrue);
    expect(app.shouldShowWhatsNew('2.7.0'), isFalse);
  });

  test('mise à jour par l’appli de la marque', () {
    expect(InstalledApps.updaterFor('zwiftClickV2'), 'Zwift Companion');
    expect(InstalledApps.updaterFor('di2'), 'E-TUBE PROJECT Cyclist');
    expect(InstalledApps.updaterFor('learned.X'), isNull);
    expect(InstalledApps.updaterFor('phoneSteering'), isNull);
  });

  test('la voix est active par défaut et se coupe', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    app.prefs = await SharedPreferences.getInstance();
    expect(app.voice, isTrue);
    await app.setVoice(false);
    expect(app.voice, isFalse);
  });
}
