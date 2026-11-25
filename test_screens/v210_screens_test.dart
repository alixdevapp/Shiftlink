// Captures des nouveautés 2.10 : flutter test test_screens/v210_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/controller_manager.dart';
import 'package:shiftlink/src/i18n.dart';
import 'package:shiftlink/src/trainer/ftms.dart';
import 'package:shiftlink/src/trainer/route.dart';
import 'package:shiftlink/src/trainer/workout.dart';
import 'package:shiftlink/src/ui/brand.dart';
import 'package:shiftlink/src/ui/ride_extras.dart';
import 'package:shiftlink/src/ui/trainer_tools.dart';

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
    await loadFont('Barlow', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Barlow-$w.ttf',
    ]);
    await loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  });
  tearDown(() => setLanguage('fr', 'fr'));

  void phone(WidgetTester tester, {double height = 900, double scale = 1}) {
    tester.view.physicalSize = Size(412 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget wrap(Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: shiftLinkTheme(Brightness.dark),
    home: Scaffold(body: Center(child: home)),
  );

  const route = GpxRoute('Col du Galibier', [RoutePoint(0, 1400), RoutePoint(17500, 2642)]);

  for (final (lang, scale) in [('fr', 1.0), ('de', 1.6)]) {
    testWidgets('départ de parcours $lang', (tester) async {
      setLanguage(lang, lang);
      phone(tester, height: 760, scale: scale);
      await tester.pumpWidget(wrap(const RouteStartDialog(route: route, resumeAt: 8300)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/depart_parcours_$lang.png'));
    });

    testWidgets('séance avec cadence et message $lang', (tester) async {
      setLanguage(lang, lang);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'onboarded': true, 'voice': false});
      phone(tester, height: 620, scale: scale);
      final app = AppState(demo: true);
      await app.init();
      const w = Workout(
        'Vélocité',
        [WorkoutStep(300, 0.5, 0.7), WorkoutStep(240, 0.9, 0.9, 100), WorkoutStep(120, 0.5)],
        messages: [WorkoutMessage(305, 'Tourne vite les jambes, reste souple sur la selle.')],
      );
      app.proxy.workout.value = const WorkoutRun(w, 308, 225, avgPower: 150);
      await tester.pumpWidget(
        wrap(Padding(padding: const EdgeInsets.all(12), child: WorkoutCard(app: app, big: true))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/seance_cadence_$lang.png'));
      app.proxy.workout.value = null;
    });

    testWidgets('calibration $lang', (tester) async {
      setLanguage(lang, lang);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'onboarded': true, 'voice': false});
      phone(tester, height: 760, scale: scale);
      final app = AppState(demo: true);
      await app.init();
      app.proxy.trainer.state.value = LinkState.connected;
      app.proxy.trainer.caps.value = const TrainerCaps(spinDown: true);
      app.proxy.trainer.spinDown.value = const SpinDownState(SpinDownPhase.speedUp, 36);
      app.proxy.data.value = const BikeData(speedKmh: 27.4, cadence: 95, power: 210);
      await tester.pumpWidget(wrap(SpinDownDialog(app: app)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/calibration_$lang.png'));
    });
  }
}
