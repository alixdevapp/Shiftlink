import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/i18n.dart';
import 'package:shiftlink/src/riders.dart';
import 'package:shiftlink/src/ui/ride_extras.dart';

void main() {
  for (final lang in ['fr', 'de']) {
    testWidgets('poids du cycliste et du vélo au dixième, dialogue $lang', (tester) async {
      setLanguage(lang, lang);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final app = AppState(demo: true);
      await tester.runAsync(app.init);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold();
            },
          ),
        ),
      );
      editRider(ctx, app, const Rider(name: 'Alex', kg: 70.4, bikeKg: 8.6, ftp: 213, hrMax: 187));
      await tester.pumpAndSettle();
      expect(find.textContaining('70,4'), findsWidgets);
      expect(find.textContaining('8,6'), findsWidgets);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded).at(1));
      await tester.pump();
      expect(find.textContaining('70,5'), findsWidgets);
      expect(find.textContaining('8,7'), findsWidgets);
      expect(find.textContaining('79,2'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pump();
      expect(find.textContaining('79,1'), findsOneWidget);
      // FTP au watt près.
      expect(find.textContaining('213 W'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded).at(2));
      await tester.pump();
      expect(find.textContaining('214 W'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded).at(2));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_rounded).at(2));
      await tester.pump();
      expect(find.textContaining('212 W'), findsOneWidget);
      // Cardio max au battement près.
      expect(find.textContaining('187'), findsOneWidget);
      await tester.ensureVisible(find.byIcon(Icons.add_rounded).at(3));
      await tester.tap(find.byIcon(Icons.add_rounded).at(3));
      await tester.pump();
      expect(find.textContaining('188'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded).at(3));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_rounded).at(3));
      await tester.pump();
      expect(find.textContaining('186'), findsOneWidget);
    });
  }
}
