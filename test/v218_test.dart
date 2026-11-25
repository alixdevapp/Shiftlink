import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/net/garmin_connect.dart';
import 'package:shiftlink/src/ride/fit_fixer.dart';
import 'package:shiftlink/src/ride/fit_writer.dart';
import 'package:shiftlink/src/settings_transfer.dart';

/// Un .fit « façon MyWhoosh » : température dans chaque point, résumé sans moyennes.
Uint8List myWhooshLike({int arch = 0, bool sessionAvgPowerZero = false}) {
  List<int> le(int v, int n) => [for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xFF];
  List<int> en(int v, int n) => arch == 1 ? le(v, n).reversed.toList() : le(v, n);
  final body = <int>[];
  // Définition 0 : record (20) = timestamp, power, heart_rate, cadence, temperature.
  body.addAll([0x40, 0, arch, ...en(20, 2), 5]);
  body.addAll([253, 4, 0x86, 7, 2, 0x84, 3, 1, 0x02, 4, 1, 0x02, 13, 1, 0x01]);
  final points = [(200, 120, 80), (220, 130, 90), (0, 0, 0), (240, 140, 100)];
  for (var i = 0; i < points.length; i++) {
    final (w, hr, cad) = points[i];
    body.addAll([0x00, ...en(1000000000 + i, 4), ...en(w, 2), hr, cad, 25]);
  }
  // Définition 1 : session (18) = timestamp, total_elapsed_time, avg_power (si demandé).
  body.addAll([0x41, 0, arch, ...en(18, 2), sessionAvgPowerZero ? 3 : 2, 253, 4, 0x86, 7, 4, 0x86]);
  if (sessionAvgPowerZero) body.addAll([20, 2, 0x84]);
  body.addAll([0x01, ...en(1000000004, 4), ...en(4000, 4)]);
  if (sessionAvgPowerZero) body.addAll(en(0, 2));
  final header = [14, 0x20, ...le(2132, 2), ...le(body.length, 4), ...'.FIT'.codeUnits];
  final hcrc = FitWriter.crc(header);
  final all = [...header, ...le(hcrc, 2), ...body];
  return Uint8List.fromList([...all, ...le(FitWriter.crc(all), 2)]);
}

/// Lecture minimale : (message global, champ → valeur entière) pour chaque message de données.
List<(int, Map<int, int>)> read(Uint8List b) {
  final out = <(int, Map<int, int>)>[];
  final defs = <int, (int, int, List<(int, int)>)>{};
  final end = b[0] + (b[4] | b[5] << 8 | b[6] << 16 | b[7] << 24);
  var p = b[0];
  while (p < end) {
    final h = b[p++];
    if (h & 0x40 != 0) {
      final arch = b[p + 1];
      final g = arch == 1 ? b[p + 2] << 8 | b[p + 3] : b[p + 2] | b[p + 3] << 8;
      final n = b[p + 4];
      p += 5;
      defs[h & 0xF] = (arch, g, [for (var i = 0; i < n; i++) (b[p + 3 * i], b[p + 3 * i + 1])]);
      p += 3 * n;
    } else {
      final (arch, g, fields) = defs[h & 0xF]!;
      final m = <int, int>{};
      for (final (num, size) in fields) {
        var v = 0;
        for (var i = 0; i < size; i++) {
          v = v << 8 | (arch == 1 ? b[p + i] : b[p + size - 1 - i]);
        }
        m[num] = v;
        p += size;
      }
      out.add((g, m));
    }
  }
  return out;
}

void main() {
  test('.fit MyWhoosh : moyennes ajoutées, température retirée, CRC justes', () {
    for (final arch in [0, 1]) {
      final fixed = FitFixer.fix(myWhooshLike(arch: arch));
      expect(fixed.changed, isTrue);
      final b = fixed.bytes;
      expect(FitWriter.crc(b), 0, reason: 'CRC du fichier');
      expect(FitWriter.crc(b.sublist(0, 14)), 0, reason: 'CRC de l’en-tête');
      final msgs = read(b);
      final records = msgs.where((m) => m.$1 == 20).toList();
      expect(records, hasLength(4));
      expect(records.every((r) => !r.$2.containsKey(13)), isTrue);
      expect(records[1].$2[7], 220);
      final session = msgs.singleWhere((m) => m.$1 == 18).$2;
      expect(session[20], 165); // (200 + 220 + 0 + 240) / 4 : les roues libres comptent
      expect(session[16], 130); // cardio : sans les zéros
      expect(session[18], 90); // cadence : sans les zéros
      expect(session[7], 4000);
      // Une deuxième passe ne change plus rien.
      expect(FitFixer.fix(b).changed, isFalse);
    }
  });

  test('.fit MyWhoosh : une moyenne à 0 est remplacée', () {
    final msgs = read(FitFixer.fix(myWhooshLike(sessionAvgPowerZero: true)).bytes);
    expect(msgs.singleWhere((m) => m.$1 == 18).$2[20], 165);
  });

  test('un .fit de ShiftLink part tel quel', () {
    final t = DateTime.utc(2026, 11, 22, 10);
    final bytes = FitWriter.encode([
      for (var i = 0; i < 5; i++)
        RideSample(time: t.add(Duration(seconds: i)), power: 200, cadence: 90, heartRate: 140, speed: 8, distance: 8.0 * i),
    ]);
    final r = FitFixer.fix(bytes);
    expect(r.changed, isFalse);
    expect(r.bytes, bytes);
  });

  test('un fichier qui n’est pas un .fit est refusé', () {
    expect(() => FitFixer.fix(Uint8List.fromList(List.filled(40, 0x41))), throwsA(isA<FitFormatException>()));
    final cut = myWhooshLike();
    expect(() => FitFixer.fix(Uint8List.fromList(cut.sublist(0, cut.length - 10))), throwsA(isA<FitFormatException>()));
  });

  test('Garmin : ticket trouvé dans l’adresse de retour', () {
    expect(
      GarminConnectClient.ticketIn('https://mobile.integration.garmin.com/gcm/ios?ticket=ST-0123-abcDEF-cas'),
      'ST-0123-abcDEF-cas',
    );
    expect(GarminConnectClient.ticketIn('<a href="https://sso.garmin.com/sso/embed?ticket=ST-99-x">'), 'ST-99-x');
    expect(GarminConnectClient.ticketIn('https://sso.garmin.com/mobile/sso/en_US/sign-in?clientId=GCM_IOS_DARK'), isNull);
    expect(
      GarminConnectClient.ticketIn('{"serviceURL":"x","serviceTicketId":"ST-0456-AbC-cas","responseStatus":{"type":"SUCCESSFUL"}}'),
      'ST-0456-AbC-cas',
    );
    // Même chaîne passée par JavaScript (guillemets échappés).
    expect(GarminConnectClient.ticketIn(r'"{\"serviceTicketId\":\"ST-7-z\"}"'), 'ST-7-z');
    expect(GarminConnectClient.ticketIn('{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}'), isNull);
    expect(GarminLoginFlow.mobile.signInUri.host, 'sso.garmin.com');
    expect(GarminLoginFlow.mobile.signInUri.queryParameters['service'], GarminLoginFlow.mobile.service);
  });

  test('Garmin : réponses à un envoi', () {
    expect(GarminConnectClient.statusOf(201, '{}'), GarminUploadStatus.sent);
    expect(GarminConnectClient.statusOf(202, '{}'), GarminUploadStatus.sent);
    expect(GarminConnectClient.statusOf(409, ''), GarminUploadStatus.duplicate);
    expect(
      () => GarminConnectClient.statusOf(401, ''),
      throwsA(isA<GarminException>().having((e) => e.needsLogin, 'needsLogin', isTrue)),
    );
    expect(() => GarminConnectClient.statusOf(500, ''), throwsA(isA<GarminException>()));
  });

  test('Garmin : le jeton se relit, et ne part jamais dans une sauvegarde', () {
    final t = GarminTokens(access: 'a', refresh: 'r', clientId: 'c', expires: DateTime.utc(2030));
    final back = GarminTokens.fromJson('{"access":"a","refresh":"r","clientId":"c","expires":"2030-01-01T00:00:00.000Z"}')!;
    expect(back.access, t.access);
    expect(back.refresh, 'r');
    expect(back.expires, t.expires);
    expect(back.expiresSoon, isFalse);
    expect(GarminTokens.fromJson('pas du json'), isNull);
    expect(SettingsTransfer.shared('garminTokens'), isFalse);
    expect(SettingsTransfer.shared('garminAuto'), isTrue);
  });
}
