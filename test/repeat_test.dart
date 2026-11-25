import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/ui/widgets.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester) async {
    var n = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ShiftButton(up: true, onTap: () => n++)),
        ),
      ),
    );
    return () => n;
  }

  testWidgets('un appui court : une seule vitesse', (tester) async {
    final count = await pump(tester);
    await tester.tap(find.byType(ShiftButton));
    await tester.pump(const Duration(seconds: 1));
    expect(count(), 1);
  });

  testWidgets('rester appuyé : les vitesses défilent, et s’arrêtent au relâché', (tester) async {
    final count = await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byType(ShiftButton)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(count(), 1);
    await tester.pump(const Duration(milliseconds: 1000)); // 400 ms puis toutes les 200 ms
    expect(count(), greaterThanOrEqualTo(4));
    await g.up();
    final after = count();
    await tester.pump(const Duration(seconds: 1));
    expect(count(), after);
  });
}
