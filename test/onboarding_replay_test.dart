import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/app_state.dart';
import 'package:shiftlink/src/ui/onboarding.dart';

void main() {
  Future<AppState> replay(WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'target': 'mywhoosh', 'onboarded': true});
    final app = AppState(demo: true);
    await app.init();
    await app.restartOnboarding();
    await tester.pumpWidget(MaterialApp(home: OnboardingPage(app: app)));
    await tester.pump();
    return app;
  }

  testWidgets('assistant relancé : « Continuer » passe à l’étape suivante', (tester) async {
    final app = await replay(tester);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Étape 2 sur 4'), findsOneWidget);
    expect(app.onboarded, isFalse);
  });

  testWidgets('assistant relancé : la flèche de la 1re étape quitte l’assistant', (tester) async {
    final app = await replay(tester);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.onboarded, isTrue);
  });
}
