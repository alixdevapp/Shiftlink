// Séances : une suite de blocs en % de la FTP, jouée en ERG sans appli.
// Lit aussi les fichiers de séance Zwift (.zwo), TrainerRoad / Golden Cheetah (.erg, .mrc)
// et les séances structurées Garmin / TrainingPeaks / Intervals.icu (.fit).
import 'dart:convert';
import 'dart:typed_data';

import '../i18n.dart';

/// Un bloc : [seconds] secondes, de [from] à [to] × FTP (égaux pour un palier).
class WorkoutStep {
  final int seconds;
  final double from;
  final double to;

  /// Cadence demandée pendant le bloc (tr/min), si la séance en donne une.
  final int? cadence;

  /// Bloc piloté par le cardio : [from] n'est que la puissance de départ, ShiftLink
  /// ajuste ensuite les watts pour garder le cœur dans la zone de la séance.
  final bool byHeartRate;
  const WorkoutStep(this.seconds, this.from, [double? to, this.cadence]) : to = to ?? from, byHeartRate = false;
  const WorkoutStep.heartRate(this.seconds, this.from) : to = from, cadence = null, byHeartRate = true;

  double at(double t) => from + (to - from) * t.clamp(0.0, 1.0);

  List<Object> toJson() => [seconds, from, to, ?cadence];
}

/// Petit texte de coaching d'une séance, affiché à [at] secondes du début pendant [seconds] secondes.
class WorkoutMessage {
  final int at;
  final String text;
  final int seconds;
  const WorkoutMessage(this.at, this.text, [this.seconds = 10]);

  List<Object> toJson() => [at, text, seconds];
}

class Workout {
  final String name;
  final String description;
  final List<WorkoutStep> steps;

  /// Séance fournie avec ShiftLink (son nom se traduit, elle ne se supprime pas).
  final bool builtIn;

  /// Test FTP : à la fin, l'app propose d'enregistrer la nouvelle FTP mesurée.
  /// 'ramp' = dernière minute × 0,75 · '20min' = puissance moyenne × 0,95.
  final String? ftpTest;

  /// Messages de coaching, rangés par heure d'affichage.
  final List<WorkoutMessage> messages;

  /// Séance au cardio : zone visée, en fraction du cardio max (bas, haut).
  final (double, double)? hrRange;

  const Workout(
    this.name,
    this.steps, {
    this.description = '',
    this.builtIn = false,
    this.ftpTest,
    this.messages = const [],
    this.hrRange,
  });

  /// Cardio visé en bpm pour un cardio max de [hrMax].
  (int, int)? hrTarget(int hrMax) {
    final r = hrRange;
    return r == null ? null : ((r.$1 * hrMax).round(), (r.$2 * hrMax).round());
  }

  /// Message à montrer à [elapsed] secondes (le plus récent encore affiché), ou null.
  WorkoutMessage? messageAt(int elapsed) {
    WorkoutMessage? found;
    for (final m in messages) {
      if (m.at > elapsed) break;
      if (elapsed < m.at + m.seconds) found = m;
    }
    return found;
  }

  /// Au moins un bloc demande une cadence.
  bool get hasCadence => steps.any((s) => s.cadence != null);

  String get title => builtIn ? tr(name) : name;
  String get subtitle => builtIn ? tr(description) : description;

  int get seconds => steps.fold(0, (a, s) => a + s.seconds);

  /// Bloc en cours et temps écoulé dedans, à [elapsed] secondes du début. null : séance finie.
  (int, int)? stepAt(int elapsed) {
    var t = elapsed;
    for (var i = 0; i < steps.length; i++) {
      if (t < steps[i].seconds) return (i, t);
      t -= steps[i].seconds;
    }
    return null;
  }

  /// Fraction de FTP demandée à [elapsed] secondes.
  double? intensityAt(int elapsed) {
    final at = stepAt(elapsed);
    if (at == null) return null;
    final s = steps[at.$1];
    return s.at(s.seconds <= 1 ? 0 : at.$2 / (s.seconds - 1));
  }

  Map<String, Object> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'steps': [for (final s in steps) s.toJson()],
    if (messages.isNotEmpty) 'messages': [for (final m in messages) m.toJson()],
  };

  static Workout? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String || j['steps'] is! List) return null;
    final steps = <WorkoutStep>[];
    for (final s in (j['steps'] as List).take(maxSteps)) {
      if (s is List && s.length >= 3 && s.every((v) => v is num)) {
        final st = _step(
          (s[0] as num).round(),
          (s[1] as num).toDouble(),
          (s[2] as num).toDouble(),
          s.length >= 4 ? (s[3] as num).round() : null,
        );
        if (st != null) steps.add(st);
      }
    }
    if (steps.isEmpty) return null;
    final messages = <WorkoutMessage>[];
    if (j['messages'] is List) {
      for (final m in (j['messages'] as List).take(maxMessages)) {
        if (m is List && m.length >= 2 && m[0] is num && m[1] is String) {
          final msg = _message(
            (m[0] as num).round(),
            m[1] as String,
            m.length >= 3 && m[2] is num ? (m[2] as num).round() : 10,
          );
          if (msg != null) messages.add(msg);
        }
      }
      messages.sort((a, b) => a.at.compareTo(b.at));
    }
    return Workout(
      j['name'] as String,
      steps,
      description: j['description'] is String ? j['description'] as String : '',
      messages: messages,
    );
  }

  static List<Workout> decodeList(String? raw) {
    try {
      final list = jsonDecode(raw ?? '[]');
      if (list is! List) return [];
      return [for (final j in list.take(maxImported)) ?Workout.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<Workout> list) => jsonEncode([for (final w in list) w.toJson()]);

  static const maxSteps = 400;
  static const maxImported = 30;
  static const maxFileBytes = 512 * 1024;

  static const maxMessages = 200;

  static WorkoutStep? _step(int seconds, double from, double to, [int? cadence]) {
    if (seconds <= 0) return null;
    return WorkoutStep(
      seconds.clamp(1, 4 * 3600),
      from.clamp(0.1, 3.0),
      to.clamp(0.1, 3.0),
      cadence != null && cadence >= 30 && cadence <= 200 ? cadence : null,
    );
  }

  static WorkoutMessage? _message(int at, String text, [int seconds = 10]) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (at < 0 || t.isEmpty) return null;
    return WorkoutMessage(at, t.length > 160 ? '${t.substring(0, 160)}…' : t, seconds.clamp(5, 30));
  }

  /// Lit un fichier Zwift .zwo. Renvoie null si ce n'est pas une séance lisible.
  static Workout? parseZwo(String xml, {String fallbackName = 'Séance'}) {
    if (xml.length > maxFileBytes || !xml.contains('<workout')) return null;
    String? tag(String name) {
      final m = RegExp('<$name>([\\s\\S]*?)</$name>', caseSensitive: false).firstMatch(xml);
      return m == null ? null : _unescape(m[1]!.trim());
    }

    final body = RegExp(r'<workout>([\s\S]*?)</workout>', caseSensitive: false).firstMatch(xml)?[1];
    if (body == null) return null;
    final steps = <WorkoutStep>[];
    final messages = <WorkoutMessage>[];
    // Secondes écoulées avant le bloc en cours de lecture, et à sa fin : les messages
    // (<textevent>) sont rangés dans leur bloc, avec une heure comptée depuis son début.
    var blockStart = 0, total = 0;
    void add(int seconds, double from, [double? to, int? cadence]) {
      final s = _step(seconds, from, to ?? from, cadence);
      if (s != null && steps.length < maxSteps) {
        steps.add(s);
        total += s.seconds;
      }
    }

    final el = RegExp(r'''<(\w+)\b((?:"[^"]*"|'[^']*'|[^>"'])*?)/?>''');
    final attr = RegExp(r'''(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    for (final m in el.allMatches(body)) {
      final a = {for (final x in attr.allMatches(m[2]!)) x[1]!.toLowerCase(): x[2] ?? x[3] ?? ''};
      double? d(String k) => double.tryParse(a[k] ?? '');
      int? cad(String k) => d(k)?.round();
      final dur = (d('duration') ?? 0).round();
      final tagName = m[1]!.toLowerCase();
      if (tagName == 'textevent' || tagName == 'textnotification') {
        final msg = _message(
          blockStart + (d('timeoffset') ?? 0).round(),
          _unescape(a['message'] ?? a['text'] ?? ''),
          (d('duration') ?? 10).round(),
        );
        if (msg != null && messages.length < maxMessages) messages.add(msg);
        continue;
      }
      final before = total;
      switch (tagName) {
        case 'steadystate':
          add(dur, d('power') ?? d('powerlow') ?? 0.6, d('power') ?? d('powerhigh'), cad('cadence'));
        case 'warmup' || 'cooldown' || 'ramp':
          add(dur, d('powerlow') ?? 0.5, d('powerhigh') ?? d('powerlow') ?? 0.5, cad('cadence'));
        case 'intervalst':
          final n = (d('repeat') ?? 1).round().clamp(1, 100);
          final on = (d('onduration') ?? 0).round(), off = (d('offduration') ?? 0).round();
          for (var i = 0; i < n; i++) {
            add(on, d('onpower') ?? d('poweronhigh') ?? 1.0, null, cad('cadence'));
            add(off, d('offpower') ?? d('poweroffhigh') ?? 0.5, null, cad('cadenceresting'));
          }
        case 'freeride':
          add(dur, 0.55, null, cad('cadence'));
        case 'maxeffort':
          add(dur, 1.3);
        default:
          continue;
      }
      blockStart = before;
    }
    messages.removeWhere((m) => m.at >= total);
    messages.sort((a, b) => a.at.compareTo(b.at));
    if (steps.isEmpty) return null;
    final name = tag('name');
    return Workout(
      (name == null || name.isEmpty) ? fallbackName : (name.length > 60 ? name.substring(0, 60) : name),
      steps,
      description: _short(tag('description') ?? ''),
      messages: messages,
    );
  }

  /// Lit un fichier de séance d'après son extension : .zwo, .erg, .mrc ou .fit.
  /// [ftp] sert à convertir les watts d'un .erg qui ne donne pas sa propre FTP.
  static Workout? fromFile(String fileName, Uint8List bytes, {required int ftp, String fallbackName = 'Séance'}) {
    if (bytes.length > maxFileBytes) return null;
    final lower = fileName.toLowerCase();
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final name = base.isEmpty ? fallbackName : base;
    if (lower.endsWith('.fit')) return parseFit(bytes, ftp: ftp, fallbackName: name);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (lower.endsWith('.erg') || lower.endsWith('.mrc')) return parseErg(text, ftp: ftp, fallbackName: name);
    if (lower.endsWith('.zwo')) return parseZwo(text, fallbackName: name);
    // Extension inconnue : on essaie selon le contenu.
    if (bytes.length > 12 && bytes[8] == 0x2E && bytes[9] == 0x46 && bytes[10] == 0x49 && bytes[11] == 0x54) {
      return parseFit(bytes, ftp: ftp, fallbackName: name);
    }
    return parseZwo(text, fallbackName: name) ?? parseErg(text, ftp: ftp, fallbackName: name);
  }

  /// Lit un fichier .erg (watts) ou .mrc (% de FTP), format TrainerRoad / Golden Cheetah / PerfPRO.
  /// Les points (minutes, valeur) sont reliés en ligne droite ; deux points à la même minute font un saut.
  static Workout? parseErg(String text, {required int ftp, String fallbackName = 'Séance'}) {
    if (text.length > maxFileBytes) return null;
    final upper = text.toUpperCase();
    final start = upper.indexOf('[COURSE DATA]');
    if (start < 0) return null;
    final end = upper.indexOf('[END COURSE DATA]', start);
    final header = text.substring(0, start);
    String? field(String key) {
      final m = RegExp('^\\s*$key\\s*=\\s*(.+?)\\s*\$', caseSensitive: false, multiLine: true).firstMatch(header);
      return m?[1];
    }

    // Colonnes : « MINUTES WATTS » (.erg) ou « MINUTES PERCENT » (.mrc).
    final percent = RegExp(r'MINUTES\s+PERCENT', caseSensitive: false).hasMatch(header);
    final fileFtp = double.tryParse(field('FTP') ?? '');
    final base = (fileFtp != null && fileFtp > 30) ? fileFtp : ftp.toDouble();
    final points = <(double, double)>[];
    final data = text.substring(start + 13, end < 0 ? text.length : end);
    for (final line in const LineSplitter().convert(data)) {
      final parts = line.trim().split(RegExp(r'[\s,;]+'));
      if (parts.length < 2) continue;
      final t = double.tryParse(parts[0]), v = double.tryParse(parts[1]);
      if (t == null || v == null || t < 0) continue;
      points.add((t, percent ? v / 100 : v / base));
    }
    final steps = <WorkoutStep>[];
    for (var i = 0; i + 1 < points.length && steps.length < maxSteps; i++) {
      final (t1, v1) = points[i];
      final (t2, v2) = points[i + 1];
      final s = _step(((t2 - t1) * 60).round(), v1, v2);
      if (s != null) steps.add(s);
    }
    if (steps.isEmpty) return null;
    final desc = field('DESCRIPTION') ?? '';
    var name = field('FILE NAME') ?? '';
    name = name.replaceAll(RegExp(r'\.(erg|mrc)$', caseSensitive: false), '');
    if (name.isEmpty) name = fallbackName;
    return Workout(name.length > 60 ? name.substring(0, 60) : name, steps, description: _short(desc));
  }

  /// Lit une séance structurée .fit (Garmin, TrainingPeaks, Intervals.icu…).
  /// Garde les blocs à durée en temps et leurs cibles de puissance ; déroule les répétitions.
  static Workout? parseFit(Uint8List bytes, {required int ftp, String fallbackName = 'Séance'}) {
    final msgs = _FitReader(bytes).read();
    if (msgs == null) return null;
    String? name;
    final raw = <Map<int, Object>>[];
    for (final (global, fields) in msgs) {
      if (global == 26 && fields[8] is String) name = fields[8] as String; // workout : wkt_name
      if (global == 27) raw.add(fields); // workout_step
    }
    if (raw.isEmpty) return null;
    // Les blocs sont rangés par message_index (champ 254) quand il est là.
    raw.sort((a, b) => ((a[254] as int?) ?? 0).compareTo((b[254] as int?) ?? 0));

    const zones = [0.5, 0.45, 0.65, 0.83, 0.98, 1.13, 1.35, 1.6];
    double target(Map<int, Object> f, int which) {
      final type = f[3] as int?;
      if (type != 4) return 0.55; // pas une cible de puissance : allure tranquille
      final low = f[5] as int?, high = f[6] as int?, zone = f[4] as int?;
      int? v = which == 0 ? (low ?? high) : (high ?? low);
      if (low != null && high != null && which == 2) v = ((low + high) / 2).round();
      if (v == null || v == 0) return zone != null && zone > 0 && zone < zones.length ? zones[zone] : 0.6;
      // Sous 1000 : % de FTP. Au-delà : watts + 1000.
      return v < 1000 ? v / 100 : (v - 1000) / (ftp > 0 ? ftp : 200);
    }

    final out = <WorkoutStep>[];
    final startOf = <int, int>{};
    for (var i = 0; i < raw.length && out.length < maxSteps; i++) {
      final f = raw[i];
      startOf[i] = out.length;
      final kind = f[1] as int? ?? 0;
      final value = f[2] as int? ?? 0;
      if (kind == 0) {
        // Durée en millisecondes.
        final mid = target(f, 2);
        final s = _step((value / 1000).round(), mid, mid);
        if (s != null) out.add(s);
      } else if (kind == 6) {
        // Répéter depuis le bloc [value] jusqu'ici, [target_value] fois en tout.
        final from = startOf[value] ?? out.length;
        final times = ((f[4] as int?) ?? 1).clamp(1, 50);
        final block = out.sublist(from);
        for (var k = 1; k < times && out.length + block.length <= maxSteps; k++) {
          out.addAll(block);
        }
      } else if (kind == 5) {
        // Bloc « ouvert » (jusqu'à l'appui sur un bouton) : 5 min.
        final mid = target(f, 2);
        final s = _step(300, mid, mid);
        if (s != null) out.add(s);
      }
    }
    if (out.isEmpty) return null;
    final n = (name == null || name.isEmpty) ? fallbackName : name;
    return Workout(n.length > 60 ? n.substring(0, 60) : n, out);
  }

  static String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Lecteur minimal de fichier FIT : renvoie (numéro de message global, champs) pour chaque message.
class _FitReader {
  final Uint8List b;
  _FitReader(this.b);

  List<(int, Map<int, Object>)>? read() {
    if (b.length < 14) return null;
    final headerSize = b[0];
    if (headerSize < 12 || b[8] != 0x2E || b[9] != 0x46 || b[10] != 0x49 || b[11] != 0x54) return null;
    final dataSize = b[4] | b[5] << 8 | b[6] << 16 | b[7] << 24;
    final end = (headerSize + dataSize).clamp(0, b.length);
    final defs = <int, _FitDef>{};
    final out = <(int, Map<int, Object>)>[];
    var i = headerSize;
    try {
      while (i < end) {
        final h = b[i++];
        if (h & 0x80 != 0) {
          // En-tête à horodatage compressé : message de données.
          final def = defs[(h >> 5) & 0x03];
          if (def == null) return out;
          i = _data(def, i, out);
          continue;
        }
        final local = h & 0x0F;
        if (h & 0x40 != 0) {
          final big = b[i + 1] == 1;
          final global = big ? (b[i + 2] << 8 | b[i + 3]) : (b[i + 2] | b[i + 3] << 8);
          final n = b[i + 4];
          i += 5;
          final fields = <(int, int, int)>[];
          for (var k = 0; k < n; k++) {
            fields.add((b[i], b[i + 1], b[i + 2]));
            i += 3;
          }
          var devBytes = 0;
          if (h & 0x20 != 0) {
            final nd = b[i++];
            for (var k = 0; k < nd; k++) {
              devBytes += b[i + 1];
              i += 3;
            }
          }
          defs[local] = _FitDef(global, big, fields, devBytes);
        } else {
          final def = defs[local];
          if (def == null) return out;
          i = _data(def, i, out);
        }
        if (out.length > 5000) break;
      }
    } on RangeError {
      return out;
    }
    return out;
  }

  int _data(_FitDef def, int i, List<(int, Map<int, Object>)> out) {
    final fields = <int, Object>{};
    for (final (num, size, type) in def.fields) {
      final v = _value(i, size, type & 0x1F, def.big);
      if (v != null) fields[num] = v;
      i += size;
    }
    out.add((def.global, fields));
    return i + def.devBytes;
  }

  Object? _value(int i, int size, int type, bool big) {
    if (type == 7) {
      // Chaîne terminée par 0.
      var e = i;
      while (e < i + size && b[e] != 0) {
        e++;
      }
      final s = utf8.decode(b.sublist(i, e), allowMalformed: true).trim();
      return s.isEmpty ? null : s;
    }
    final width = switch (type) {
      0 || 1 || 2 || 10 || 13 => 1,
      3 || 4 || 11 => 2,
      5 || 6 || 8 || 12 => 4,
      _ => 0,
    };
    if (width == 0 || size < width) return null;
    var v = 0;
    for (var k = 0; k < width; k++) {
      v |= b[i + (big ? width - 1 - k : k)] << (8 * k);
    }
    // Valeurs « invalide » du format FIT.
    final invalid = switch (type) {
      0 || 2 || 13 => 0xFF,
      1 => 0x7F,
      10 => 0x00,
      3 => 0x7FFF,
      4 => 0xFFFF,
      11 => 0x0000,
      5 => 0x7FFFFFFF,
      6 => 0xFFFFFFFF,
      12 => 0x00000000,
      _ => -1,
    };
    if (v == invalid && type != 10 && type != 11 && type != 12) return null;
    if (type == 1 && v > 0x7F) v -= 0x100;
    if (type == 3 && v > 0x7FFF) v -= 0x10000;
    if (type == 5 && v > 0x7FFFFFFF) v -= 0x100000000;
    return v;
  }
}

class _FitDef {
  final int global;
  final bool big;
  final List<(int, int, int)> fields;
  final int devBytes;
  const _FitDef(this.global, this.big, this.fields, this.devBytes);
}

/// Séances fournies avec ShiftLink, du plus doux au plus dur.
final builtInWorkouts = [
  Workout(
    'Test FTP (rampe)',
    [const WorkoutStep(300, 0.40, 0.50), for (var i = 0; i < 20; i++) WorkoutStep(60, 0.50 + i * 0.10)],
    description: '+10 % de ta FTP chaque minute (20 W pour 200 W). Lâche quand tu ne tiens plus : ShiftLink le voit tout seul. FTP = dernière minute × 0,75.',
    builtIn: true,
    ftpTest: 'ramp',
  ),
  const Workout(
    'Test FTP (20 min)',
    [
      WorkoutStep(600, 0.45, 0.70),
      WorkoutStep(60, 1.00),
      WorkoutStep(60, 0.55),
      WorkoutStep(60, 1.10),
      WorkoutStep(60, 0.55),
      WorkoutStep(60, 1.20),
      WorkoutStep(300, 0.55),
      WorkoutStep(1200, 1.00),
      WorkoutStep(300, 0.50, 0.40),
    ],
    description: '20 min à bloc après échauffement. FTP = watts moyens × 0,95.',
    builtIn: true,
    ftpTest: '20min',
  ),
  const Workout(
    'Sweet Spot 20 min',
    [WorkoutStep(600, 0.45, 0.70), WorkoutStep(1200, 0.88), WorkoutStep(300, 0.55, 0.40)],
    description: '35 min : 20 min à 88% de FTP, le meilleur rapport fatigue / progrès.',
    builtIn: true,
  ),
  Workout(
    'VO2max 5 × 3 min',
    [
      const WorkoutStep(600, 0.45, 0.70),
      for (var i = 0; i < 5; i++) ...const [WorkoutStep(180, 1.15), WorkoutStep(180, 0.55)],
      const WorkoutStep(300, 0.55, 0.40),
    ],
    description: '45 min : 5 fois 3 min à 115%, 3 min facile.',
    builtIn: true,
  ),
  const Workout(
    'Endurance au cardio 45 min',
    [WorkoutStep(300, 0.40, 0.60), WorkoutStep.heartRate(2100, 0.60), WorkoutStep(300, 0.55, 0.40)],
    description: '45 min en zone 2 (60 à 70 % de ton cardio max) : les watts suivent ton cœur. Ceinture cardio nécessaire.',
    builtIn: true,
    hrRange: (0.60, 0.70),
  ),
  const Workout(
    'Récupération au cardio 30 min',
    [WorkoutStep(300, 0.40, 0.50), WorkoutStep.heartRate(1200, 0.50), WorkoutStep(300, 0.45, 0.35)],
    description: '30 min sous 60 % de ton cardio max, pour récupérer. Ceinture cardio nécessaire.',
    builtIn: true,
    hrRange: (0.50, 0.60),
  ),
  const Workout(
    'Balade facile',
    [WorkoutStep(300, 0.40, 0.60), WorkoutStep(600, 0.60), WorkoutStep(300, 0.60, 0.40)],
    description: '20 min tout doux',
    builtIn: true,
  ),
  const Workout(
    'Pyramide',
    [
      WorkoutStep(300, 0.40, 0.65),
      WorkoutStep(120, 0.70),
      WorkoutStep(120, 0.80),
      WorkoutStep(120, 0.90),
      WorkoutStep(120, 1.00),
      WorkoutStep(120, 0.90),
      WorkoutStep(120, 0.80),
      WorkoutStep(120, 0.70),
      WorkoutStep(300, 0.60, 0.40),
    ],
    description: '24 min : ça monte, puis ça redescend',
    builtIn: true,
  ),
  Workout(
    'Intervalles 30/30',
    [
      const WorkoutStep(480, 0.40, 0.70),
      for (var i = 0; i < 8; i++) ...const [WorkoutStep(30, 1.10), WorkoutStep(30, 0.50)],
      const WorkoutStep(300, 0.60, 0.40),
    ],
    description: '21 min : 30 s fort, 30 s facile, 8 fois',
    builtIn: true,
  ),
];

/// Séance en cours.
class WorkoutRun {
  final Workout workout;
  final int elapsed;
  final int watts;

  /// Pas de pédalage : le chrono attend.
  final bool paused;

  /// Le trainer donne nettement plus de watts que demandé depuis plusieurs secondes.
  final bool tooHard;

  /// Puissance moyenne mesurée depuis le début (0 si rien mesuré).
  final int avgPower;

  /// Puissance moyenne de la dernière minute (0 si pas encore une minute).
  final int lastMinutePower;

  /// Séance au cardio : zone visée en bpm (bas, haut), sinon null.
  final (int, int)? hrTarget;

  /// Séance au cardio sans battements reçus depuis un moment : les watts ne bougent plus.
  final bool noHeartRate;
  const WorkoutRun(
    this.workout,
    this.elapsed,
    this.watts, {
    this.paused = false,
    this.tooHard = false,
    this.avgPower = 0,
    this.lastMinutePower = 0,
    this.hrTarget,
    this.noHeartRate = false,
  });

  /// Le bloc en cours suit le cardio.
  bool get followsHeart => hrTarget != null && workout.steps[step - 1].byHeartRate;

  int get step => (workout.stepAt(elapsed)?.$1 ?? workout.steps.length - 1) + 1;
  int get steps => workout.steps.length;
  int get stepSecondsLeft {
    final at = workout.stepAt(elapsed);
    if (at == null) return 0;
    return workout.steps[at.$1].seconds - at.$2;
  }

  /// Cadence demandée par le bloc en cours, ou null.
  int? get cadenceTarget => workout.steps[step - 1].cadence;

  /// Message de coaching à montrer maintenant, ou null.
  WorkoutMessage? get message => workout.messageAt(elapsed);

  int get secondsLeft => (workout.seconds - elapsed).clamp(0, workout.seconds);
  double get progress => workout.seconds == 0 ? 1 : (elapsed / workout.seconds).clamp(0.0, 1.0);
}

/// Règle les watts d'un bloc « au cardio » : le cœur réagit avec 30 s à 1 min de
/// retard, donc on corrige par petites touches toutes les 15 s, et plus vite si le
/// cœur monte trop haut.
class HeartRateErg {
  final int low;
  final int high;
  final int minWatts;
  final int maxWatts;
  int watts;
  int _since = 0;

  HeartRateErg({
    required this.low,
    required this.high,
    required int watts,
    required this.minWatts,
    required this.maxWatts,
  }) : watts = watts.clamp(minWatts, maxWatts);

  /// Une seconde de pédalage avec le cardio [bpm] (null : pas de mesure). Renvoie la cible.
  int tick(int? bpm) {
    if (bpm == null || bpm <= 0) {
      _since = 0;
      return watts;
    }
    _since++;
    final every = bpm > high + 5 ? 5 : 15;
    if (_since < every) return watts;
    _since = 0;
    final mid = (low + high) / 2;
    final delta = bpm > high + 5
        ? -15
        : bpm > high
        ? -8
        : bpm < low - 10
        ? 10
        : bpm < low
        ? 5
        : bpm > mid + 2
        ? -3
        : bpm < mid - 2
        ? 3
        : 0;
    watts = (watts + delta).clamp(minWatts, maxWatts);
    return watts;
  }
}

/// Résultat d'un test FTP qui vient de se finir.
class FtpTestResult {
  final int ftp;

  /// 'ramp' ou '20min'.
  final String kind;
  const FtpTestResult(this.ftp, this.kind);
}

/// Durée lisible : « 1:05 » ou « 1 h 05 ».
String clock(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}
