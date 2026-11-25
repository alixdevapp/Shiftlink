// Import des séances .erg, .mrc et .fit.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/trainer/workout.dart';

const erg = '''[COURSE HEADER]
VERSION = 2
UNITS = ENGLISH
DESCRIPTION = Deux paliers
FILE NAME = Paliers.erg
FTP = 250
MINUTES WATTS
[END COURSE HEADER]
[COURSE DATA]
0.00	125
5.00	125
5.00	250
10.00	250
10.00	100
12.00	150
[END COURSE DATA]
''';

const mrc = '''[COURSE HEADER]
VERSION = 2
UNITS = ENGLISH
DESCRIPTION = Rampe
MINUTES PERCENT
[END COURSE HEADER]
[COURSE DATA]
0	50
10	100
[END COURSE DATA]
''';

/// Petit écrivain FIT pour les tests : file_id, workout et des workout_step.
Uint8List fitWorkout(String name, List<List<int?>> steps) {
  final data = BytesBuilder();
  void def(int local, int global, List<(int, int, int)> fields) {
    data.addByte(0x40 | local);
    data.add([0, 0, global & 0xFF, global >> 8, fields.length]);
    for (final (n, s, t) in fields) {
      data.add([n, s, t]);
    }
  }

  void u32(int? v) {
    final x = v ?? 0xFFFFFFFF;
    data.add([x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF]);
  }

  def(0, 0, [(0, 1, 0)]);
  data.add([0, 5]); // file_id : type = séance
  final nameBytes = [...utf8.encode(name), 0];
  def(1, 26, [(8, nameBytes.length, 7)]);
  data.addByte(1);
  data.add(nameBytes);
  // message_index, duration_type, duration_value, target_type, target_value, low, high
  def(2, 27, [(254, 2, 0x84), (1, 1, 0), (2, 4, 0x86), (3, 1, 0), (4, 4, 0x86), (5, 4, 0x86), (6, 4, 0x86)]);
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    data.addByte(2);
    data.add([i & 0xFF, i >> 8, s[0]!]);
    u32(s[1]);
    data.addByte(s[2] ?? 0xFF);
    u32(s[3]);
    u32(s[4]);
    u32(s[5]);
  }
  final body = data.toBytes();
  final header = [14, 0x10, 0, 0, body.length & 0xFF, (body.length >> 8) & 0xFF, 0, 0, 0x2E, 0x46, 0x49, 0x54, 0, 0];
  return Uint8List.fromList([...header, ...body, 0, 0]);
}

void main() {
  test('.erg : paliers en watts, ramenés à la FTP du fichier', () {
    final w = Workout.fromFile('x.erg', Uint8List.fromList(utf8.encode(erg)), ftp: 200)!;
    expect(w.name, 'Paliers');
    expect(w.description, 'Deux paliers');
    expect(w.steps.length, 3);
    expect(w.steps[0].seconds, 300);
    expect(w.steps[0].from, closeTo(0.5, 1e-9));
    expect(w.steps[1].from, closeTo(1.0, 1e-9));
    expect(w.steps[2].from, closeTo(0.4, 1e-9));
    expect(w.steps[2].to, closeTo(0.6, 1e-9));
    expect(w.seconds, 12 * 60);
  });

  test('.mrc : pourcentages de FTP, rampe', () {
    final w = Workout.fromFile('Rampe 10 min.mrc', Uint8List.fromList(utf8.encode(mrc)), ftp: 200)!;
    expect(w.name, 'Rampe 10 min');
    expect(w.steps.single.seconds, 600);
    expect(w.steps.single.from, closeTo(0.5, 1e-9));
    expect(w.steps.single.to, closeTo(1.0, 1e-9));
  });

  test('.fit : blocs en temps, cibles en % FTP et en watts, répétitions déroulées', () {
    final bytes = fitWorkout('Fit 3x1', [
      [0, 600000, 4, 0, 50, 70], // 10 min échauffement 50-70 %
      [0, 60000, 4, 0, 1000 + 300, 1000 + 300], // 1 min à 300 W
      [0, 60000, 4, 0, 50, 50], // 1 min à 50 %
      [6, 1, null, 3, null, null], // répéter depuis le bloc 1, 3 fois en tout
    ]);
    final w = Workout.fromFile('a.fit', bytes, ftp: 250)!;
    expect(w.name, 'Fit 3x1');
    expect(w.steps.length, 1 + 2 * 3);
    expect(w.steps[0].seconds, 600);
    expect(w.steps[0].from, closeTo(0.6, 1e-9));
    expect(w.steps[1].from, closeTo(1.2, 1e-9));
    expect(w.steps[2].from, closeTo(0.5, 1e-9));
    expect(w.seconds, 600 + 3 * 120);
  });

  test('un fichier quelconque est refusé', () {
    expect(Workout.fromFile('a.fit', Uint8List.fromList([1, 2, 3]), ftp: 200), isNull);
    expect(Workout.fromFile('a.erg', Uint8List.fromList(utf8.encode('bonjour')), ftp: 200), isNull);
    expect(Workout.fromFile('photo.jpg', Uint8List(100), ftp: 200), isNull);
  });
}
