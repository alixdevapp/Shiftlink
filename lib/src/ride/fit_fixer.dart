// Répare un .fit avant de l'envoyer sur Garmin Connect (utile pour les fichiers de MyWhoosh) :
// - ajoute les moyennes de puissance, de cardio et de cadence qui manquent au résumé de la sortie ;
// - retire la température de chaque point (MyWhoosh écrit une valeur fausse).
// Le fichier est relu message par message puis réécrit, avec ses CRC recalculés.
import 'dart:typed_data';

import 'fit_writer.dart';

class FitFixResult {
  final Uint8List bytes;

  /// Le fichier a changé (moyenne ajoutée ou température retirée).
  final bool changed;
  const FitFixResult(this.bytes, this.changed);
}

class FitFormatException implements Exception {
  final String message;
  const FitFormatException(this.message);
  @override
  String toString() => message;
}

class _Field {
  final int num;
  final int size;
  final int type;
  const _Field(this.num, this.size, this.type);
}

class _Def {
  final int arch; // 0 : petit-boutiste, 1 : grand-boutiste
  final int global;
  final List<_Field> fields;
  final List<_Field> devFields; // num, taille, index du développeur
  const _Def(this.arch, this.global, this.fields, this.devFields);

  int get dataSize => [...fields, ...devFields].fold(0, (a, f) => a + f.size);

  bool same(_Def o) {
    if (arch != o.arch || global != o.global || fields.length != o.fields.length) return false;
    if (devFields.length != o.devFields.length) return false;
    for (var i = 0; i < fields.length; i++) {
      final a = fields[i], b = o.fields[i];
      if (a.num != b.num || a.size != b.size || a.type != b.type) return false;
    }
    for (var i = 0; i < devFields.length; i++) {
      final a = devFields[i], b = o.devFields[i];
      if (a.num != b.num || a.size != b.size || a.type != b.type) return false;
    }
    return true;
  }
}

class _Data {
  final int header; // octet d'en-tête d'origine (en-tête compressé conservé)
  final int local;
  _Def def;
  final Map<int, Uint8List> values; // champ → octets, dans l'ordre de la définition
  final Uint8List dev;
  _Data(this.header, this.local, this.def, this.values, this.dev);

  int? uint(int field) {
    final v = values[field];
    if (v == null) return null;
    var out = 0;
    for (var i = 0; i < v.length; i++) {
      final byte = def.arch == 1 ? v[i] : v[v.length - 1 - i];
      out = (out << 8) | byte;
    }
    final invalid = (1 << (8 * v.length)) - 1;
    return out == invalid ? null : out;
  }

  void setUint(int field, int size, int type, int value) {
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      final byte = (value >> (8 * i)) & 0xFF;
      bytes[def.arch == 1 ? size - 1 - i : i] = byte;
    }
    if (!def.fields.any((f) => f.num == field)) {
      def = _Def(def.arch, def.global, [...def.fields, _Field(field, size, type)], def.devFields);
    }
    values[field] = bytes;
  }

  void remove(int field) {
    if (!values.containsKey(field)) return;
    values.remove(field);
    def = _Def(def.arch, def.global, def.fields.where((f) => f.num != field).toList(), def.devFields);
  }
}

class FitFixer {
  static const _record = 20, _session = 18;
  static const _recHeartRate = 3, _recCadence = 4, _recPower = 7, _recTemperature = 13;
  static const _sesAvgHeartRate = 16, _sesAvgCadence = 18, _sesAvgPower = 20;

  /// Répare [input]. Lève [FitFormatException] si ce n'est pas un .fit lisible.
  static FitFixResult fix(Uint8List input) {
    if (input.length < 14) throw const FitFormatException('Fichier trop court pour un .fit');
    final headerSize = input[0];
    if ((headerSize != 12 && headerSize != 14) || input.length < headerSize) {
      throw const FitFormatException('En-tête .fit inconnu');
    }
    if (String.fromCharCodes(input.sublist(8, 12)) != '.FIT') {
      throw const FitFormatException('Ce fichier n’est pas un .fit');
    }
    final dataSize = input[4] | (input[5] << 8) | (input[6] << 16) | (input[7] << 24);
    final end = headerSize + dataSize;
    if (end + 2 > input.length) throw const FitFormatException('Fichier .fit coupé');

    final msgs = <Object>[]; // _Def (avec son numéro local) ou _Data
    final defs = <int, _Def>{};
    var p = headerSize;
    while (p < end) {
      final h = input[p++];
      if (h & 0x80 != 0) {
        final local = (h >> 5) & 0x3;
        final def = defs[local] ?? (throw const FitFormatException('Message sans définition'));
        msgs.add(_readData(input, p, h, local, def));
        p += def.dataSize;
      } else if (h & 0x40 != 0) {
        final local = h & 0x0F;
        final hasDev = h & 0x20 != 0;
        if (p + 5 > end) throw const FitFormatException('Définition coupée');
        final arch = input[p + 1];
        final global = arch == 1 ? (input[p + 2] << 8) | input[p + 3] : input[p + 2] | (input[p + 3] << 8);
        final n = input[p + 4];
        p += 5;
        final fields = <_Field>[];
        for (var i = 0; i < n; i++, p += 3) {
          fields.add(_Field(input[p], input[p + 1], input[p + 2]));
        }
        final dev = <_Field>[];
        if (hasDev) {
          final nd = input[p++];
          for (var i = 0; i < nd; i++, p += 3) {
            dev.add(_Field(input[p], input[p + 1], input[p + 2]));
          }
        }
        defs[local] = _Def(arch, global, fields, dev);
      } else {
        final local = h & 0x0F;
        final def = defs[local] ?? (throw const FitFormatException('Message sans définition'));
        msgs.add(_readData(input, p, h, local, def));
        p += def.dataSize;
      }
      if (p > end) throw const FitFormatException('Message coupé');
    }

    // Réparations.
    var changed = false;
    var power = <int>[], hr = <int>[], cad = <int>[];
    for (final m in msgs) {
      if (m is! _Data) continue;
      if (m.def.global == _record) {
        final w = m.uint(_recPower), b = m.uint(_recHeartRate), c = m.uint(_recCadence);
        if (w != null) power.add(w);
        if (b != null && b > 0) hr.add(b);
        if (c != null && c > 0) cad.add(c);
        if (m.values.containsKey(_recTemperature)) {
          m.remove(_recTemperature);
          changed = true;
        }
      } else if (m.def.global == _session) {
        int avg(List<int> v) => (v.reduce((a, b) => a + b) / v.length).round();
        if ((m.uint(_sesAvgPower) ?? 0) == 0 && power.isNotEmpty) {
          m.setUint(_sesAvgPower, 2, 0x84, avg(power).clamp(0, 65534));
          changed = true;
        }
        if ((m.uint(_sesAvgHeartRate) ?? 0) == 0 && hr.isNotEmpty) {
          m.setUint(_sesAvgHeartRate, 1, 0x02, avg(hr).clamp(0, 254));
          changed = true;
        }
        if ((m.uint(_sesAvgCadence) ?? 0) == 0 && cad.isNotEmpty) {
          m.setUint(_sesAvgCadence, 1, 0x02, avg(cad).clamp(0, 254));
          changed = true;
        }
        power = [];
        hr = [];
        cad = [];
      }
    }
    if (!changed) return FitFixResult(input, false);

    // Réécriture : une définition n'est écrite que quand elle change pour ce numéro local.
    final body = BytesBuilder();
    final written = <int, _Def>{};
    for (final m in msgs) {
      if (m is! _Data) continue;
      final cur = written[m.local];
      if (cur == null || !cur.same(m.def)) {
        _writeDef(body, m.local, m.def);
        written[m.local] = m.def;
      }
      body.addByte(m.header);
      for (final f in m.def.fields) {
        body.add(m.values[f.num]!);
      }
      body.add(m.dev);
    }
    final data = body.takeBytes();
    final header = Uint8List.fromList(input.sublist(0, headerSize));
    final size = data.length;
    header[4] = size & 0xFF;
    header[5] = (size >> 8) & 0xFF;
    header[6] = (size >> 16) & 0xFF;
    header[7] = (size >> 24) & 0xFF;
    if (headerSize == 14) {
      final c = FitWriter.crc(header.sublist(0, 12));
      header[12] = c & 0xFF;
      header[13] = c >> 8;
    }
    final all = [...header, ...data];
    final crc = FitWriter.crc(all);
    final out = BytesBuilder()
      ..add(all)
      ..add([crc & 0xFF, crc >> 8]);
    // Fichiers .fit enchaînés (rare) : la suite est gardée telle quelle.
    if (end + 2 < input.length) out.add(input.sublist(end + 2));
    return FitFixResult(out.takeBytes(), true);
  }

  static _Data _readData(Uint8List b, int p, int header, int local, _Def def) {
    if (p + def.dataSize > b.length) throw const FitFormatException('Message coupé');
    final values = <int, Uint8List>{};
    for (final f in def.fields) {
      values[f.num] = Uint8List.fromList(b.sublist(p, p + f.size));
      p += f.size;
    }
    final devSize = def.devFields.fold(0, (a, f) => a + f.size);
    final dev = Uint8List.fromList(b.sublist(p, p + devSize));
    return _Data(header, local, def, values, dev);
  }

  static void _writeDef(BytesBuilder out, int local, _Def d) {
    out.addByte(0x40 | (d.devFields.isEmpty ? 0 : 0x20) | local);
    out.add([0, d.arch]);
    out.add(d.arch == 1 ? [d.global >> 8, d.global & 0xFF] : [d.global & 0xFF, d.global >> 8]);
    out.addByte(d.fields.length);
    for (final f in d.fields) {
      out.add([f.num, f.size, f.type]);
    }
    if (d.devFields.isNotEmpty) {
      out.addByte(d.devFields.length);
      for (final f in d.devFields) {
        out.add([f.num, f.size, f.type]);
      }
    }
  }
}
