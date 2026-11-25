// Lecture d'un fichier GPX minimal et accès à la pente par distance.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/trainer/route.dart';

const gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
  <trk>
    <name>Petite côte</name>
    <trkseg>
      <trkpt lat="45.0000" lon="6.0000"><ele>100</ele></trkpt>
      <trkpt lat="45.0010" lon="6.0000"><ele>110</ele></trkpt>
      <trkpt lat="45.0020" lon="6.0000"><ele>140</ele></trkpt>
      <trkpt lat="45.0030" lon="6.0000"><ele>130</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

void main() {
  test('lit un GPX : nom, distance et dénivelé', () {
    final r = GpxRoute.parseGpx(gpx)!;
    expect(r.name, 'Petite côte');
    expect(r.length, greaterThan(300));
    expect(r.length, lessThan(400));
    expect(r.climbing, closeTo(40, 1));
  });

  test('refuse un fichier sans trace', () {
    expect(GpxRoute.parseGpx('<gpx></gpx>'), isNull);
    expect(GpxRoute.parseGpx('<trk><name>vide</name></trk>'), isNull);
  });

  test('pente positive dans la montée, négative dans la descente', () {
    final r = GpxRoute.parseGpx(gpx)!;
    final mid = r.gradeAt(r.length / 2);
    final end = r.gradeAt(r.length);
    expect(mid, greaterThan(5));
    expect(end, lessThan(0));
  });

  test('se sauvegarde et se relit', () {
    final r = GpxRoute.parseGpx(gpx)!;
    final back = GpxRoute.fromJson(r.toJson());
    expect(back!.name, r.name);
    expect(back.length.round(), r.length.round());
    expect(back.climbing.round(), r.climbing.round());
  });
}
