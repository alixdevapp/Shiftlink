// Vitesses virtuelles : chaque vitesse change la résistance comme le ferait
// un braquet plus ou moins grand.
import 'dart:convert';
import 'dart:math' as math;

import '../i18n.dart';
import 'ftms.dart';

/// Une cassette ou une transmission toute prête.
class GearPreset {
  final String id;
  final String _name;
  String get name => tr(_name);

  /// Pignons, du plus facile (le plus grand) au plus dur.
  final List<int> cogs;
  final int ring;
  final int smallRing;
  const GearPreset(this.id, this._name, this.cogs, this.ring, [this.smallRing = 0]);
}

const gearPresets = [
  GearPreset('classic', '24 vitesses régulières', [], 50),
  GearPreset('road12', 'Route 2×12 (50/34 × 11-34)', [34, 30, 27, 24, 21, 19, 17, 15, 14, 13, 12, 11], 50, 34),
  GearPreset('road12_30', 'Route 2×12 (52/36 × 11-30)', [30, 27, 24, 21, 19, 17, 16, 15, 14, 13, 12, 11], 52, 36),
  GearPreset('road11', 'Route 2×11 (50/34 × 11-28)', [28, 25, 23, 21, 19, 17, 15, 14, 13, 12, 11], 50, 34),
  GearPreset('road11_30', 'Route 2×11 (50/34 × 11-30)', [30, 27, 24, 21, 19, 17, 15, 14, 13, 12, 11], 50, 34),
  GearPreset('road11_32', 'Route 2×11 (50/34 × 11-32)', [32, 28, 25, 22, 20, 18, 16, 14, 13, 12, 11], 50, 34),
  GearPreset('gravel', 'Gravel 1×12 (40 × 10-44)', [44, 38, 32, 28, 24, 21, 19, 17, 15, 13, 11, 10], 40),
  GearPreset('mtb', 'VTT 1×12 (32 × 10-52)', [52, 42, 36, 32, 28, 24, 21, 18, 16, 14, 12, 10], 32),
];

/// Réglages des vitesses virtuelles.
class ShiftingConfig {
  final String presetId;
  final List<int> cogs;
  final int ring;
  final int smallRing;

  /// Vitesses personnalisées : braquet (plateau / pignon) de chaque vitesse,
  /// du plus facile au plus dur. Remplace la cassette si non vide.
  final List<double> ratios;

  /// Façon de piloter le trainer : 'grade' (pente), 'power' (puissance cible)
  /// ou 'resistance' (niveau de résistance, pour les trainers simples).
  final String control;

  /// Ignore les pics de cadence qui donnent des à-coups (mode puissance).
  final bool cadenceFilter;

  /// Simple relais : l'appli pilote le trainer sans vitesses ShiftLink.
  final bool relay;

  /// Double plateau : l'action « Plateau » passe du grand au petit.
  final bool doubleRing;

  /// Braquet réellement engagé sur le vélo posé sur le trainer.
  final int realRing;
  final int realCog;

  /// Effet de la pente : 1 = pente réelle, 0,5 = deux fois moins dure.
  final double difficulty;

  /// Poids cycliste + vélo, en kg (le trainer suppose environ 85 kg).
  final double totalKg;

  /// Adoucit les changements brusques de pente.
  final bool smoothing;

  /// Pas des boutons « Intensité » en ERG, en watts.
  final int ergStep;

  /// ERG manuel (sans appli) : départ à la dernière cible ('last') ou à la puissance actuelle ('current').
  final String ergStart;

  final bool vibrate;
  final bool sound;

  /// Vitesses infinies : chaque appui = ±0,5 % de pente (ou ±5 W en ERG), sans butée.
  final bool infinite;

  /// Power Lock : se relâche quand on arrête de pédaler.
  final bool powerLockRelease;

  const ShiftingConfig({
    this.presetId = 'classic',
    this.cogs = const [],
    this.ring = 50,
    this.smallRing = 0,
    this.ratios = const [],
    this.control = 'auto',
    this.cadenceFilter = true,
    this.relay = false,
    this.doubleRing = false,
    this.realRing = 50,
    this.realCog = 17,
    this.difficulty = 1,
    this.totalKg = referenceKg,
    this.smoothing = false,
    this.ergStep = 10,
    this.ergStart = 'last',
    this.vibrate = true,
    this.sound = false,
    this.infinite = false,
    this.powerLockRelease = true,
  });

  static const referenceKg = 85.0;
  static const wheelMeters = 2.105; // 700×28C

  static const maxGears = 30;
  static const controls = {'auto': 'Auto', 'grade': 'Pente', 'power': 'Puissance', 'resistance': 'Résistance'};

  factory ShiftingConfig.fromPreset(GearPreset p, [ShiftingConfig base = const ShiftingConfig()]) => base.copyWith(
    presetId: p.id,
    ratios: const [],
    cogs: p.cogs,
    ring: p.ring,
    smallRing: p.smallRing,
    doubleRing: p.smallRing > 0 && base.doubleRing,
  );

  bool get custom => ratios.isNotEmpty;
  bool get classic => !custom && cogs.isEmpty;

  ShiftingConfig copyWith({
    String? presetId,
    List<int>? cogs,
    int? ring,
    int? smallRing,
    List<double>? ratios,
    String? control,
    bool? cadenceFilter,
    bool? relay,
    bool? doubleRing,
    int? realRing,
    int? realCog,
    double? difficulty,
    double? totalKg,
    bool? smoothing,
    int? ergStep,
    String? ergStart,
    bool? vibrate,
    bool? sound,
    bool? infinite,
    bool? powerLockRelease,
  }) => ShiftingConfig(
    presetId: presetId ?? this.presetId,
    cogs: cogs ?? this.cogs,
    ring: ring ?? this.ring,
    smallRing: smallRing ?? this.smallRing,
    ratios: ratios ?? this.ratios,
    control: control ?? this.control,
    cadenceFilter: cadenceFilter ?? this.cadenceFilter,
    relay: relay ?? this.relay,
    doubleRing: doubleRing ?? this.doubleRing,
    realRing: realRing ?? this.realRing,
    realCog: realCog ?? this.realCog,
    difficulty: difficulty ?? this.difficulty,
    totalKg: totalKg ?? this.totalKg,
    smoothing: smoothing ?? this.smoothing,
    ergStep: ergStep ?? this.ergStep,
    ergStart: ergStart ?? this.ergStart,
    vibrate: vibrate ?? this.vibrate,
    sound: sound ?? this.sound,
    infinite: infinite ?? this.infinite,
    powerLockRelease: powerLockRelease ?? this.powerLockRelease,
  );

  Map<String, Object> toJson() => {
    'presetId': presetId,
    'cogs': cogs,
    'ring': ring,
    'smallRing': smallRing,
    'ratios': ratios,
    'control': control,
    'cadenceFilter': cadenceFilter,
    'relay': relay,
    'doubleRing': doubleRing,
    'realRing': realRing,
    'realCog': realCog,
    'difficulty': difficulty,
    'totalKg': totalKg,
    'smoothing': smoothing,
    'ergStep': ergStep,
    'ergStart': ergStart,
    'vibrate': vibrate,
    'sound': sound,
    'infinite': infinite,
    'powerLockRelease': powerLockRelease,
  };

  String encode() => jsonEncode(toJson());

  static ShiftingConfig decode(String? raw) {
    if (raw == null) return const ShiftingConfig();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      const d = ShiftingConfig();
      return ShiftingConfig(
        presetId: m['presetId'] as String? ?? d.presetId,
        cogs: (m['cogs'] as List?)?.cast<int>() ?? d.cogs,
        ring: m['ring'] as int? ?? d.ring,
        smallRing: m['smallRing'] as int? ?? d.smallRing,
        ratios: (m['ratios'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? d.ratios,
        control: m['control'] as String? ?? d.control,
        cadenceFilter: m['cadenceFilter'] as bool? ?? d.cadenceFilter,
        relay: m['relay'] as bool? ?? d.relay,
        doubleRing: m['doubleRing'] as bool? ?? d.doubleRing,
        realRing: m['realRing'] as int? ?? d.realRing,
        realCog: m['realCog'] as int? ?? d.realCog,
        difficulty: (m['difficulty'] as num?)?.toDouble() ?? d.difficulty,
        totalKg: (m['totalKg'] as num?)?.toDouble() ?? d.totalKg,
        smoothing: m['smoothing'] as bool? ?? d.smoothing,
        ergStep: m['ergStep'] as int? ?? d.ergStep,
        ergStart: m['ergStart'] as String? ?? d.ergStart,
        vibrate: m['vibrate'] as bool? ?? d.vibrate,
        sound: m['sound'] as bool? ?? d.sound,
        infinite: m['infinite'] as bool? ?? d.infinite,
        powerLockRelease: m['powerLockRelease'] as bool? ?? d.powerLockRelease,
      );
    } catch (_) {
      return const ShiftingConfig();
    }
  }
}

class VirtualGears {
  ShiftingConfig _config;

  /// Réglage « 24 vitesses régulières » : de [minRatio] à [maxRatio] fois le braquet réel.
  final int _classicCount;
  final double minRatio;
  final double maxRatio;

  int gear;

  /// Sur le petit plateau (double plateau).
  bool smallRing = false;

  double? _smoothedGrade;

  /// « Tout plus dur / tout plus facile » : décale toutes les vitesses d'un cran
  /// de 6 % par pas (positif = plus dur).
  int offset = 0;
  static const offsetStep = 1.06;
  static const maxOffset = 8;
  double get offsetFactor => math.pow(offsetStep, offset).toDouble();

  /// Vitesses infinies : pente ajoutée (%), 0,5 % par appui.
  double extraGrade = 0;
  static const infiniteStep = 0.5;
  static const maxExtraGrade = 20.0;

  VirtualGears({int count = 24, this.minRatio = 0.5, this.maxRatio = 2.0, int? initialGear, ShiftingConfig? config})
    : _classicCount = count,
      _config = config ?? const ShiftingConfig(),
      gear = 1 {
    gear = initialGear ?? neutralGear;
  }

  ShiftingConfig get config => _config;

  /// Change les réglages en gardant une sensation proche.
  set config(ShiftingConfig c) {
    final before = gearRatio();
    _config = c;
    if (!c.doubleRing) smallRing = false;
    if (!c.infinite) extraGrade = 0;
    gear = _gearForAbsolute(before);
  }

  int get count => _config.custom ? _config.ratios.length : (_config.classic ? _classicCount : _config.cogs.length);

  double get realRatio => _config.realRing / _config.realCog;

  int get currentRing => _config.doubleRing && smallRing ? _config.smallRing : _config.ring;

  /// Nombre de dents du pignon de la vitesse [g], ou null en mode régulier.
  int? cog([int? g]) => _config.classic || _config.custom ? null : _config.cogs[(g ?? gear).clamp(1, count) - 1];

  /// Braquet absolu (plateau / pignon) de la vitesse [g].
  double gearRatio([int? g]) {
    final i = (g ?? gear).clamp(1, count);
    if (_config.custom) {
      final r = _config.ratios[i - 1];
      return _config.doubleRing && smallRing && _config.ring > 0 ? r * _config.smallRing / _config.ring : r;
    }
    if (_config.classic) {
      if (count == 1) return realRatio;
      final t = (i - 1) / (count - 1);
      return realRatio * minRatio * math.pow(maxRatio / minRatio, t);
    }
    return currentRing / _config.cogs[i - 1];
  }

  /// Rapport de la vitesse [g] relatif au braquet réel (1 = même sensation que sans vitesses virtuelles).
  double ratio([int? g]) => gearRatio(g) / realRatio * offsetFactor;

  /// Développement (mètres par tour de pédale).
  double development([int? g]) => gearRatio(g) * ShiftingConfig.wheelMeters * offsetFactor;

  /// Vitesse où le rapport vaut 1.
  int get neutralGear => _gearForAbsolute(realRatio);

  int _gearForAbsolute(double r) {
    var best = 1;
    for (var i = 1; i <= count; i++) {
      if ((gearRatio(i) - r).abs() < (gearRatio(best) - r).abs()) best = i;
    }
    return best;
  }

  bool shift(int delta) {
    if (_config.infinite) {
      final next = (extraGrade + delta * infiniteStep).clamp(-maxExtraGrade, maxExtraGrade);
      if (next == extraGrade) return false;
      extraGrade = next;
      return true;
    }
    final next = (gear + delta).clamp(1, count);
    if (next == gear) return false;
    gear = next;
    return true;
  }

  /// Décale toutes les vitesses. Renvoie false en butée.
  bool shiftAll(int delta) {
    final next = (offset + delta).clamp(-maxOffset, maxOffset);
    if (next == offset) return false;
    offset = next;
    return true;
  }

  /// Passe d'un plateau à l'autre. Renvoie false sans double plateau.
  bool frontShift() {
    if (!_config.doubleRing || _config.smallRing <= 0 || _config.smallRing >= _config.ring) return false;
    smallRing = !smallRing;
    return true;
  }

  /// Libellé du braquet : « 50×17 », « 2,94 » (personnalisé) ou « ×1.09 ».
  String label([int? g]) {
    if (_config.infinite && g == null) {
      final e = extraGrade.toStringAsFixed(1).replaceAll('.', ',');
      return '${extraGrade >= 0 ? '+' : ''}$e %';
    }
    final c = cog(g);
    if (c != null) return '$currentRing×$c';
    if (_config.custom) return gearRatio(g).toStringAsFixed(2).replaceAll('.', ',');
    return '×${ratio(g).toStringAsFixed(2)}';
  }

  /// Braquets de toutes les vitesses actuelles, pour les personnaliser.
  List<double> get allRatios {
    final keep = smallRing;
    smallRing = false;
    final out = [for (var i = 1; i <= count; i++) double.parse(gearRatio(i).toStringAsFixed(2))];
    smallRing = keep;
    return out;
  }

  /// Puissance (W) qu'il faudrait sur la route dans la vitesse actuelle, à
  /// cette cadence, avec la pente et l'air demandés par l'appli.
  double roadPower(SimulationParams p, double cadence) {
    final v = cadence / 60 * development(); // m/s
    if (v <= 0) return 0;
    final m = _config.totalKg;
    final grade = (p.gradePercent * _config.difficulty + extraGrade) / 100;
    final angle = math.atan(grade);
    final gravity = m * 9.81 * (math.sin(angle) + p.crr * math.cos(angle));
    final air = p.cw * (v + p.wind) * (v + p.wind).abs();
    return math.max(0, (gravity + air) * v);
  }

  /// Paramètres à envoyer au trainer pour ceux demandés par l'appli.
  ///
  /// Avec un braquet k fois plus grand, la roue virtuelle va k fois plus vite
  /// que la roue du trainer, et la force aux pédales est k fois plus grande à
  /// puissance égale. Côté trainer, il faut donc :
  /// - multiplier pente + roulement par k (et par le rapport de poids) ;
  /// - multiplier le coefficient aérodynamique par k³ (force ∝ vitesse²)
  ///   et diviser le vent par k.
  /// [fresh] : nouvelle pente reçue de l'appli (sinon simple changement de vitesse).
  SimulationParams adjust(SimulationParams p, {bool fresh = true}) {
    final k = ratio();
    final mass = _config.totalKg / ShiftingConfig.referenceKg;
    var target = p.gradePercent * _config.difficulty;
    if (!fresh && _smoothedGrade != null) {
      target = _smoothedGrade!;
    } else if (_config.smoothing) {
      final prev = _smoothedGrade ?? target;
      target = prev + (target - prev) * 0.35;
    }
    _smoothedGrade = target;
    final rolling = p.crr * 100; // en % de pente équivalente
    final grade = ((target + extraGrade + rolling) * k * mass - rolling).clamp(-15.0, 25.0);
    final cw = (p.cw * k * k * k).clamp(0.0, 2.55);
    return SimulationParams(p.wind / k, grade, p.crr, cw);
  }
}

/// Cadence sans pics : médiane des 3 dernières mesures.
class CadenceFilter {
  final List<double> _last = [];

  double add(double rpm) {
    _last.add(rpm);
    if (_last.length > 3) _last.removeAt(0);
    final sorted = [..._last]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void reset() => _last.clear();
}
