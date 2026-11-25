import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/net/send_target.dart';

void main() {
  test('applis connectées : Garmin Connect et Intervals.icu (Strava passe par MyWhoosh)', () {
    expect(SendTarget.values.map((t) => t.label), ['Garmin Connect', 'Intervals.icu']);
  });
}
