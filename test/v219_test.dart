import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/net/mywhoosh_account.dart';
import 'package:shiftlink/src/settings_transfer.dart';

void main() {
  test('MyWhoosh : connexion acceptée ou refusée', () {
    final s = MyWhooshAccount.parseLogin({'Success': true, 'AccessToken': 'tok', 'WhooshId': 123456789012});
    expect(s.token, 'tok');
    expect(s.whooshId, '123456789012');
    expect(MyWhooshSession.fromJson(s.toJson())!.whooshId, '123456789012');
    expect(
      () => MyWhooshAccount.parseLogin({'Success': false}),
      throwsA(isA<MyWhooshException>().having((e) => e.needsLogin, 'needsLogin', isTrue)),
    );
    expect(() => MyWhooshAccount.parseLogin({'Success': true, 'AccessToken': ''}), throwsA(isA<MyWhooshException>()));
  });

  test('MyWhoosh : liste des sorties, quelle que soit l’enveloppe', () {
    final item = {'id': 42, 'name': 'Alpe', 'date': '2026-11-22T09:30:00Z', 'activityFileId': 'f-1'};
    for (final res in [
      [item],
      {'data': [item]},
      {
        'data': {
          'results': [item],
        },
      },
    ]) {
      final list = MyWhooshAccount.parseActivities(res);
      expect(list, hasLength(1));
      expect(list.first.id, '42');
      expect(list.first.name, 'Alpe');
      expect(list.first.downloadable, isTrue);
      expect(list.first.start!.toUtc(), DateTime.utc(2026, 11, 22, 9, 30));
    }
    final noFile = MyWhooshAccount.parseActivities([
      {'_id': 'x', 'title': 'Sans fichier', 'startTime': 1763803800},
    ]);
    expect(noFile.first.downloadable, isFalse);
    expect(noFile.first.start!.toUtc().year, 2025);
    expect(() => MyWhooshAccount.parseActivities({'error': true}), throwsA(isA<MyWhooshException>()));
  });

  test('MyWhoosh : dates en secondes, millisecondes ou texte', () {
    expect(MyWhooshAccount.parseTime(1763803800)!.toUtc(), MyWhooshAccount.parseTime(1763803800000)!.toUtc());
    expect(MyWhooshAccount.parseTime('1763803800')!.toUtc().year, 2025);
    expect(MyWhooshAccount.parseTime(null), isNull);
    expect(MyWhooshAccount.parseTime('pas une date'), isNull);
  });

  test('MyWhoosh : identifiant d’appareil au format UUID v4', () {
    final id = MyWhooshAccount.newDeviceId(Random(1));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
  });

  test('MyWhoosh : la session ne part jamais dans une sauvegarde', () {
    for (final k in ['mywhooshSession', 'mywhooshDevice', 'mywhooshSent', 'mywhooshSince']) {
      expect(SettingsTransfer.shared(k), isFalse, reason: k);
    }
    expect(SettingsTransfer.shared('mywhooshAuto'), isTrue);
  });
}
