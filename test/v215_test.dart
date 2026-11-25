import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/registry.dart';
import 'package:shiftlink/src/controllers/simple_drivers.dart';
import 'package:shiftlink/src/outputs/obc_server.dart';
import 'package:shiftlink/src/sensors/headwind.dart';

void main() {
  test('Elite Square : les lecteurs de cartes Square sont écartés', () {
    expect(looksLikeEliteSquare('SQUARE 01234', const []), isTrue);
    expect(looksLikeEliteSquare('SQUARE READER 2F4A', const []), isFalse);
    expect(looksLikeEliteSquare('SQUARE TERMINAL', const []), isFalse);
    expect(looksLikeEliteSquare('SQUARE_STAND', const []), isFalse);
    expect(looksLikeEliteSquare('PEU IMPORTE', [EliteSquareDriver.service]), isTrue);
    expect(looksLikeEliteSquare('KICKR', <Guid>[]), isFalse);
  });

  test('Headwind : le vent suit la puissance', () {
    expect(Headwind.forPower(0, 250), 0);
    expect(Headwind.forPower(20, 250), 0);
    expect(Headwind.forPower(120, 250), 50);
    expect(Headwind.forPower(240, 250), 100);
    expect(Headwind.forPower(400, 250), 100);
    expect(FanMode.values, contains(FanMode.power));
  });

  test('OpenBikeControl : Rampida', () {
    expect(ObcProtocol.appName('rampida'), 'Rampida');
  });
}
