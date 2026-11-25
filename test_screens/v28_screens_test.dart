// Captures des nouveautés 2.8 : flutter test test_screens/v28_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/i18n.dart';
import 'package:shiftlink/src/ride/ride_history.dart';
import 'package:shiftlink/src/ui/brand.dart';
import 'package:shiftlink/src/ui/home_shell.dart';
import 'package:shiftlink/src/ui/stats_page.dart';
import 'package:shiftlink/src/ui/workout_editor.dart';

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

  void phone(WidgetTester tester, {double height = 900}) {
    tester.view.physicalSize = Size(412 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
  }

  Widget wrap(Widget home) =>
      MaterialApp(debugShowCheckedModeBanner: false, theme: shiftLinkTheme(Brightness.dark), home: home);

  final today = DateTime(2026, 11, 9);
  final rides = [
    for (var i = 0; i < 40; i++)
      RideSummary(
        start: today.subtract(Duration(days: i * 2 + (i % 3))),
        duration: Duration(minutes: 45 + (i % 4) * 15),
        distance: 25000,
        fitPath: '/x/$i.fit',
        avgPower: 180,
        bests: {5: 700 - i * 3, 60: 380 - i * 2, 300: 290 - i, 1200: 250 - i},
        normalizedPower: 200 + (i % 5) * 10,
        ftp: 250,
      ),
  ];

  for (final lang in ['fr', 'en']) {
    testWidgets('statistiques $lang', (tester) async {
      setLanguage(lang, lang);
      phone(tester, height: 1250);
      await tester.pumpWidget(wrap(StatsPage(rides: rides, ftp: 250, today: today)));
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/stats_$lang.png'));
    });

    testWidgets('éditeur de séance $lang', (tester) async {
      setLanguage(lang, lang);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'onboarded': true});
      phone(tester, height: 1500);
      final app = AppState(demo: true);
      await app.init();
      await tester.pumpWidget(wrap(WorkoutEditorPage(app: app)));
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/editor_$lang.png'));
    });

    testWidgets('onglet séances $lang', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'onboarded': true, 'target': 'mywhoosh', 'language': lang});
      phone(tester, height: 2600);
      final app = AppState(demo: true);
      await app.init();
      await tester.pumpWidget(wrap(HomeShell(app: app, initialTab: 1)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/seances28_$lang.png'));
    });
  }
}
