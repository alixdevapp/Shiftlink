// Captures des nouveautés 2.14 : flutter test test_screens/v214_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/i18n.dart';
import 'package:shiftlink/src/installed_apps.dart';
import 'package:shiftlink/src/ui/brand.dart';
import 'package:shiftlink/src/ui/home_shell.dart';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/sdk/flutter'}/bin/cache/artifacts/material_fonts';
  setUpAll(() async {
    InstalledApps.fake = {'Biketerra'};
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
      appName: 'ShiftLink',
      packageName: 'app.shiftlink',
      version: '2.14.0',
      buildNumber: '84',
      buildSignature: '',
    );
    await loadFont('Barlow', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Barlow-$w.ttf',
    ]);
    await loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  });
  tearDown(() => setLanguage('fr', 'fr'));

  for (final (lang, scale) in [('fr', 1.0), ('de', 1.6)]) {
    testWidgets('Biketerra : clavier ou OpenBikeControl $lang', (tester) async {
      setLanguage(lang, lang);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'onboarded': true, 'voice': false, 'target': 'biketerraObc', 'language': lang});
      tester.view.physicalSize = const Size(412 * 2, 1100 * 2);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = AppState(demo: true);
      await app.init();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shiftLinkTheme(Brightness.dark),
          home: HomeShell(app: app, initialTab: 2),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text(tr('Comment relier ShiftLink à {0} ?', ['Biketerra'])), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/biketerra_obc_$lang.png'));
    });
  }
}
