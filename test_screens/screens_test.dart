// Captures d'écran et icônes, générées avec : flutter test test_screens --update-goldens
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show BluetoothDevice;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/main.dart';
import 'package:shiftlink/src/actions.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/controller_manager.dart';
import 'package:shiftlink/src/controllers/driver.dart';
import 'package:shiftlink/src/controllers/zwift_drivers.dart';
import 'package:shiftlink/src/installed_apps.dart';
import 'package:shiftlink/src/ride/ride_history.dart';
import 'package:shiftlink/src/riders.dart';
import 'package:shiftlink/src/trainer/gears.dart';
import 'package:shiftlink/src/trainer/workout.dart';
import 'package:shiftlink/src/ui/backup_page.dart';
import 'package:shiftlink/src/ui/brand.dart';
import 'package:shiftlink/src/ui/buttons_page.dart';
import 'package:shiftlink/src/ui/diagnostic_page.dart';
import 'package:shiftlink/src/ui/help_pages.dart';
import 'package:shiftlink/src/ui/home_shell.dart';
import 'package:shiftlink/src/ui/learn_controller_page.dart';
import 'package:shiftlink/src/ui/onboarding.dart';
import 'package:shiftlink/src/ui/problem_page.dart';
import 'package:shiftlink/src/ui/ride_extras.dart';
import 'package:shiftlink/src/ui/rides_page.dart';
import 'package:shiftlink/src/ui/shifting_page.dart';
import 'package:shiftlink/src/ui/tips_page.dart';
import 'package:shiftlink/src/ui/whats_new.dart';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final fonts = '${Platform.environment['HOME']}/sdk/flutter/bin/cache/artifacts/material_fonts';
  setUpAll(() async {
    InstalledApps.fake = {'MyWhoosh', 'Zwift'};
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
      appName: 'ShiftLink',
      packageName: 'app.shiftlink',
      version: '2.2.3',
      buildNumber: '28',
      buildSignature: '',
    );
    await loadFont('Barlow', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Barlow-$w.ttf',
    ]);
    await loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    await loadFont('monospace', ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
  });

  const prefs = <String, Object>{'target': 'mywhoosh', 'onboarded': true, 'kbPreset': 'rouvy'};

  void phone(WidgetTester tester, {double height = 900}) {
    tester.view.physicalSize = Size(412 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final dark in [false, true]) {
    final suffix = dark ? 'dark' : 'light';
    testWidgets('séance $suffix', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(prefs);
      phone(tester);
      await tester.pumpWidget(
        ShiftLinkApp(app: AppState(demo: true), themeMode: dark ? ThemeMode.dark : ThemeMode.light),
      );
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/ride_$suffix.png'));
    });
  }

  testWidgets('séance zwift', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      ...prefs,
      'target': 'zwift',
      'shifting': ShiftingConfig.fromPreset(gearPresets[1]).encode(),
    });
    phone(tester);
    await tester.pumpWidget(ShiftLinkApp(app: AppState(demo: true), themeMode: ThemeMode.dark));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/ride_zwift.png'));
  });

  for (final (name, tab, height) in [('devices', 2, 1700.0), ('settings', 3, 1250.0), ('seances', 1, 1300.0)]) {
    testWidgets('onglet $name', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({...prefs, 'phoneSteering': true});
      phone(tester, height: height);
      final app = AppState(demo: true);
      await app.init();
      app.steeringAngle.value = 14;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shiftLinkTheme(Brightness.dark),
          home: HomeShell(app: app, initialTab: tab),
        ),
      );
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    });
  }

  // Autres langues : séance, appareils, réglages, sans débordement.
  for (final lang in ['en', 'de', 'es', 'it', 'pl']) {
    for (final (name, tab, height) in [
      ('ride', 0, 900.0),
      ('seances', 1, 1300.0),
      ('devices', 2, 1700.0),
      ('settings', 3, 1250.0),
    ]) {
      testWidgets('langue $lang $name', (tester) async {
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({...prefs, 'language': lang, 'target': tab == 0 ? 'zwift' : 'mywhoosh'});
        phone(tester, height: height);
        final app = AppState(demo: true);
        await app.init();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: shiftLinkTheme(Brightness.dark),
            home: HomeShell(app: app, initialTab: tab),
          ),
        );
        await settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${lang}_$name.png'));
        expect(tester.takeException(), isNull);
        await app.setAppLanguage('fr');
      });
    }
  }

  // Grand texte (réglage Android) : aucun écran ne doit déborder.
  for (final (tab, target) in [(0, 'mywhoosh'), (0, 'zwift'), (1, 'mywhoosh'), (2, 'mywhoosh'), (3, 'mywhoosh')]) {
    testWidgets('grand texte onglet $tab $target', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({...prefs, 'phoneSteering': true, 'target': target});
      phone(tester, height: 2600);
      final app = AppState(demo: true);
      await app.init();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shiftLinkTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: HomeShell(app: app, initialTab: tab),
        ),
      );
      await settle(tester);
      if (tab == 0) await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/large_text_$target.png'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sauvegarde et partage', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    phone(tester, height: 1100);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.dark),
        home: BackupPage(app: app),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/backup.png'));
  });

  testWidgets('manette introuvable', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    phone(tester, height: 1500);
    final app = AppState(demo: true);
    await app.init();
    app.controllers.controllers.value = [];
    app.controllers.lastScanEmpty.value = true;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.dark),
        home: HomeShell(app: app, initialTab: 2),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/no_controller.png'));
  });

  for (final step in [0, 1, 2, 3]) {
    testWidgets('assistant étape ${step + 1}', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'target': 'mywhoosh'});
      phone(tester);
      final app = AppState(demo: true);
      await app.init();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shiftLinkTheme(Brightness.light),
          home: OnboardingPage(app: app, initialStep: step),
        ),
      );
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/onboarding_${step + 1}.png'));
    });
  }

  testWidgets('assistant : manette introuvable', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'mywhoosh'});
    phone(tester, height: 1500);
    final app = AppState(demo: true);
    await app.init();
    app.controllers.controllers.value = [];
    app.controllers.lastScanEmpty.value = true;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: OnboardingPage(app: app, initialStep: 1),
      ),
    );
    app.controllers.controllers.value = [];
    app.controllers.scanning.value = false;
    app.controllers.lastScanEmpty.value = true;
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/onboarding_no_controller.png'));
  });

  for (final (name, page) in [
    ('compatible', const CompatibilityPage()),
    ('mots', const WordsPage()),
    (
      'sorties',
      RidesPage(
        demo: [
          RideSummary(
            start: DateTime(2026, 11, 7, 18, 30),
            duration: const Duration(minutes: 62),
            distance: 31400,
            fitPath: '/x/a.fit',
            avgPower: 186,
            maxPower: 512,
            avgHeartRate: 138,
            maxHeartRate: 171,
            avgCadence: 88,
          ),
          RideSummary(
            start: DateTime(2026, 11, 5, 7, 15),
            duration: const Duration(minutes: 45),
            distance: 22100,
            fitPath: '/x/b.fit',
            avgPower: 160,
            maxPower: 340,
            avgCadence: 92,
          ),
          RideSummary(start: DateTime(2026, 10, 30, 19, 2), duration: Duration.zero, distance: 0, fitPath: '/x/c.fit'),
        ],
      ),
    ),
  ]) {
    testWidgets('page $name', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(debugShowCheckedModeBanner: false, theme: shiftLinkTheme(Brightness.light), home: page),
      );
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    });
  }

  testWidgets('apprendre une manette', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'mywhoosh', 'onboarded': true});
    phone(tester);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: LearnControllerPage(app: app),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/apprendre.png'));
  });

  testWidgets('même téléphone', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'target': 'tpv',
      'sameDevice': true,
      'taps.tpv': '{"shiftUp":[22.6,7.1],"shiftDown":[18.1,6.8]}',
    });
    phone(tester, height: 1250);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: OnboardingPage(app: app, initialStep: 2),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/same_device.png'));
  });

  testWidgets('boutons de la manette', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'tpv', 'onboarded': true});
    phone(tester, height: 2300);
    final app = AppState(demo: true);
    await app.init();
    final driver = ZwiftRideDriver(ZwiftIds.rideService);
    final c = ConnectedController(BluetoothDevice.fromId('AA:BB:CC:DD:EE:02'), driver, 'Zwift Ride');
    await app.keymap.set(driver, 'a', Gesture.click, ShiftAction.mediaPlayPause);
    await app.keymap.set(driver, 'a', Gesture.long, ShiftAction.mediaNext);
    await app.keymap.set(driver, 'navLeft', Gesture.click, ShiftAction.steerLeft);
    await app.keymap.set(driver, 'navRight', Gesture.click, ShiftAction.steerRight);
    await app.keymap.set(driver, 'shiftUpRight', Gesture.double, ShiftAction.ergUp);
    await app.keymap.setCombo(driver, 'shiftUpRight', 'shiftUpLeft', ShiftAction.skipInterval);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: ButtonsPage(app: app, controller: c),
      ),
    );
    app.simulateButton(c, press('navLeft'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/buttons.png'));
    app.simulateButton(c, release('navLeft'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('réglage des vitesses', (tester) async {
    final base = ShiftingConfig.fromPreset(gearPresets[1]).copyWith(doubleRing: true, difficulty: 0.8);
    final c = base.copyWith(
      presetId: 'custom',
      ratios: VirtualGears(config: base).allRatios,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'target': 'zwift',
      'onboarded': true,
      'shifting': c.encode(),
      'shiftProfiles': '{"Montagne":"{}","Sprint":"{}"}',
      'activeShiftProfile': 'Montagne',
    });
    phone(tester, height: 2900);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: ShiftingPage(app: app),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/shifting.png'));
  });

  testWidgets('diagnostic', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'zwift', 'onboarded': true});
    phone(tester, height: 1300);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: DiagnosticPage(app: app),
      ),
    );
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/diagnostic.png'));
  });

  testWidgets('pile faible', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    phone(tester);
    final app = AppState(demo: true);
    await tester.pumpWidget(ShiftLinkApp(app: app, themeMode: ThemeMode.light));
    await settle(tester);
    app.controllers.controllers.value.first.battery.value = 15;
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/pile_faible.png'));
  });

  testWidgets('envoyer mon problème', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    phone(tester, height: 1500);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: ProblemPage(app: app),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Le bouton + ne fait rien dans MyWhoosh');
    await tester.tap(find.text('Voir tout le texte'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/probleme.png'));
  });

  testWidgets('quoi de neuf', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: FilledButton(onPressed: () => showWhatsNew(c, onlyLatest: true), child: const Text('go')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/quoi_de_neuf.png'));
  });

  // Icônes d'appli (redimensionnées ensuite pour Android).
  for (final (name, fg, scale) in [('icon_full', false, 1.0), ('icon_foreground', true, 0.62)]) {
    testWidgets('icône $name', (tester) async {
      tester.view.physicalSize = const Size(1024, 1024);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(1024),
              painter: LogoPainter(foregroundOnly: fg, scale: scale),
            ),
          ),
        ),
      );
      await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('out/$name.png'));
    });
  }
  // 2.7 : cyclistes, zones cardio, séances (idées de QZ).
  final family = Rider.encodeList(const [
    Rider(name: 'Alex', kg: 78, ftp: 240, hrMax: 186),
    Rider(name: 'Léo', kg: 21, ftp: 45, hrMax: 205),
  ]);
  testWidgets('cyclistes et zones cardio', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({...prefs, 'target': 'zwift', 'riders': family, 'activeRider': 'Alex'});
    phone(tester, height: 1000);
    await tester.pumpWidget(ShiftLinkApp(app: AppState(demo: true), themeMode: ThemeMode.light));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/qz_ride_riders.png'));
  });

  testWidgets('séance en cours', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({...prefs, 'target': 'zwift', 'riders': family, 'activeRider': 'Léo'});
    phone(tester, height: 1100);
    final app = AppState(demo: true);
    await tester.pumpWidget(ShiftLinkApp(app: app, themeMode: ThemeMode.dark));
    await settle(tester);
    app.proxy.sendToTrainer = (_) async {};
    app.startWorkout(builtInWorkouts[1]);
    await tester.pump(const Duration(seconds: 400));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/qz_workout_running.png'));
    app.proxy.stopWorkout();
  });

  testWidgets('onglet séances, séance en cours', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({...prefs, 'target': 'zwift', 'riders': family, 'activeRider': 'Léo'});
    phone(tester, height: 1000);
    final app = AppState(demo: true);
    await app.init();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        home: HomeShell(app: app, initialTab: 1),
      ),
    );
    await settle(tester);
    app.proxy.sendToTrainer = (_) async {};
    app.startWorkout(builtInWorkouts[2]);
    await tester.pump(const Duration(seconds: 500));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/qz_tab_running.png'));
    app.proxy.stopWorkout();
  });

  testWidgets('séance mywhoosh 30 vitesses', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({...prefs, 'riders': family, 'activeRider': 'Léo'});
    phone(tester);
    await tester.pumpWidget(ShiftLinkApp(app: AppState(demo: true), themeMode: ThemeMode.light));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/qz_ride_mywhoosh.png'));
  });

  for (final (name, build) in [
    ('qz_riders', (AppState a) => RidersPage(app: a)),
    ('conseils', (AppState a) => TipsPage(app: a)),
  ]) {
    testWidgets('page $name', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({...prefs, 'target': 'zwift', 'riders': family, 'activeRider': 'Alex'});
      phone(tester);
      final app = AppState(demo: true);
      await tester.pumpWidget(ShiftLinkApp(app: app, themeMode: ThemeMode.light));
      await settle(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(Scaffold).first)).push(MaterialPageRoute(builder: (_) => build(app))),
      );
      await settle(tester);
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    });
  }

  testWidgets('choix des chiffres', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({...prefs, 'target': 'zwift'});
    phone(tester);
    final app = AppState(demo: true);
    await tester.pumpWidget(ShiftLinkApp(app: app, themeMode: ThemeMode.light));
    await settle(tester);
    unawaited(pickRideMetrics(tester.element(find.byType(Scaffold).first), app));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/qz_metrics.png'));
  });
}
