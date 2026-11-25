import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftlink/src/settings_transfer.dart';

void main() {
  test('export puis import : mêmes réglages, sans ceux du téléphone', () async {
    SharedPreferences.setMockInitialValues({
      'target': 'zwift',
      'doubleClickMs': 350,
      'steerThreshold': 9.5,
      'hud': true,
      'keymap.zwift': '{"ride/a":{"click":"shiftUp"}}',
      'trainerId': 'AA:BB',
      'onboarded': true,
      'taps.rouvy': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final json = SettingsTransfer.export(prefs);
    expect(json, isNot(contains('AA:BB')));
    expect(json, isNot(contains('taps.rouvy')));

    final parsed = SettingsTransfer.parse(SettingsTransfer.compact(json));
    expect(parsed, {
      'doubleClickMs': 350,
      'hud': true,
      'keymap.zwift': '{"ride/a":{"click":"shiftUp"}}',
      'steerThreshold': 9.5,
      'target': 'zwift',
    });

    SharedPreferences.setMockInitialValues({'trainerId': 'CC:DD'});
    final other = await SharedPreferences.getInstance();
    await SettingsTransfer.apply(other, parsed);
    expect(other.getString('target'), 'zwift');
    expect(other.getInt('doubleClickMs'), 350);
    expect(other.getString('trainerId'), 'CC:DD');
  });

  test('fichier qui n’est pas à ShiftLink : refusé', () {
    expect(() => SettingsTransfer.parse('bonjour'), throwsFormatException);
    expect(() => SettingsTransfer.parse('{"format":"Autre","settings":{}}'), throwsFormatException);
    expect(
      () => SettingsTransfer.parse(jsonEncode({'format': 'ShiftLink', 'version': 99, 'settings': {}})),
      throwsFormatException,
    );
  });

  test('valeurs piégées ignorées, clés du téléphone refusées', () {
    final parsed = SettingsTransfer.parse(
      jsonEncode({
        'format': 'ShiftLink',
        'version': 1,
        'settings': {
          'target': 'rouvy',
          'trainerId': 'EE:FF',
          'bad': {'nested': true},
          'list': [1, 2],
        },
      }),
    );
    expect(parsed, {'target': 'rouvy'});
  });

  test('fichier géant refusé', () {
    final big = 'x' * (SettingsTransfer.maxBytes + 1);
    expect(() => SettingsTransfer.parse(big), throwsFormatException);
  });
}
