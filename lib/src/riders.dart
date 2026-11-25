// Cyclistes : chaque personne de la maison a son prénom, son poids, sa FTP,
// son cardio max et, si elle veut, son profil de vitesses.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'i18n.dart';

class Rider {
  final String name;

  /// Poids du cycliste seul, en kg.
  final double kg;

  /// Poids du vélo, en kg (ajouté à [kg] pour les côtes et la vitesse).
  final double bikeKg;

  /// Puissance tenue une heure, en watts : base des séances.
  final int ftp;

  /// Fréquence cardiaque maximale : base des zones cardio.
  final int hrMax;

  /// Profil de vitesses repris quand on choisit ce cycliste (null : on ne change pas).
  final String? gearProfile;

  /// Mode enfant : pente plafonnée à [kidMaxGrade] %, watts plafonnés, et watts
  /// envoyés à l'appli multipliés par [kidPowerFactor] (petite roue, petit poids).
  final bool kid;
  final double kidMaxGrade;
  final double kidPowerFactor;

  const Rider({
    required this.name,
    this.kg = 75,
    this.bikeKg = defaultBikeKg,
    this.ftp = 200,
    this.hrMax = 190,
    this.gearProfile,
    this.kid = false,
    this.kidMaxGrade = 3,
    this.kidPowerFactor = 1,
  });

  /// Watts maximum demandés au trainer en mode enfant.
  int get kidMaxWatts => (ftp * 1.5).round();

  /// Poids du vélo quand on ne l'a pas réglé (anciens profils compris).
  static const defaultBikeKg = 9.0;
  static const minBikeKg = 3.0;
  static const maxBikeKg = 30.0;

  static const minKg = 15.0;
  static const maxKg = 150.0;

  /// Poids arrondi au dixième de kilo, dans les bornes.
  static double roundKg(double kg, double min, double max) => ((kg * 10).round() / 10).clamp(min, max);

  /// Poids du vélo arrondi au dixième de kilo, dans les bornes.
  static double roundBikeKg(double kg) => roundKg(kg, minBikeKg, maxBikeKg);
  double get totalKg => kg + bikeKg;

  Rider copyWith({
    String? name,
    double? kg,
    double? bikeKg,
    int? ftp,
    int? hrMax,
    String? gearProfile,
    bool clearProfile = false,
    bool? kid,
    double? kidMaxGrade,
    double? kidPowerFactor,
  }) => Rider(
    name: name ?? this.name,
    kg: kg ?? this.kg,
    bikeKg: bikeKg ?? this.bikeKg,
    ftp: ftp ?? this.ftp,
    hrMax: hrMax ?? this.hrMax,
    gearProfile: clearProfile ? null : (gearProfile ?? this.gearProfile),
    kid: kid ?? this.kid,
    kidMaxGrade: kidMaxGrade ?? this.kidMaxGrade,
    kidPowerFactor: kidPowerFactor ?? this.kidPowerFactor,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'kg': kg,
    'bikeKg': bikeKg,
    'ftp': ftp,
    'hrMax': hrMax,
    if (gearProfile != null) 'gearProfile': gearProfile,
    if (kid) ...{'kid': true, 'kidMaxGrade': kidMaxGrade, 'kidPowerFactor': kidPowerFactor},
  };

  static Rider? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.trim().isEmpty) return null;
    double val(Object? v, double def, double lo, double hi) => (v is num ? v.toDouble() : def).clamp(lo, hi);
    return Rider(
      name: name.trim(),
      kg: roundKg(val(j['kg'], 75, 10, 200), 10, 200),
      bikeKg: roundBikeKg(val(j['bikeKg'], defaultBikeKg, minBikeKg, maxBikeKg)),
      ftp: val(j['ftp'], 200, 30, 600).round(),
      hrMax: val(j['hrMax'], 190, 100, 230).round(),
      gearProfile: j['gearProfile'] is String ? j['gearProfile'] as String : null,
      kid: j['kid'] == true,
      kidMaxGrade: val(j['kidMaxGrade'], 3, 0, 10),
      kidPowerFactor: val(j['kidPowerFactor'], 1, 1, 3),
    );
  }

  static List<Rider> decodeList(String? raw) {
    try {
      final list = jsonDecode(raw ?? '[]');
      if (list is! List) return [];
      return [for (final j in list.take(maxRiders)) ?Rider.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<Rider> riders) => jsonEncode([for (final r in riders) r.toJson()]);

  static const maxRiders = 12;
}

/// Une zone cardio : de 1 (très facile) à 5 (à fond).
class HrZone {
  final int zone;
  const HrZone(this.zone);

  /// Zone pour [bpm] avec un cardio max de [hrMax] : 60, 70, 80 et 90 % du max.
  static HrZone of(int bpm, int hrMax) {
    final pct = bpm / math.max(1, hrMax);
    return HrZone(
      pct < 0.6
          ? 1
          : pct < 0.7
          ? 2
          : pct < 0.8
          ? 3
          : pct < 0.9
          ? 4
          : 5,
    );
  }

  String get label => switch (zone) {
    1 => tr('Très facile'),
    2 => tr('Facile'),
    3 => tr('Moyen'),
    4 => tr('Dur'),
    _ => tr('À fond'),
  };

  Color get color => switch (zone) {
    1 => const Color(0xFF8A94A6),
    2 => const Color(0xFF3B82F6),
    3 => const Color(0xFF22A45D),
    4 => const Color(0xFFF2A900),
    _ => const Color(0xFFEF4444),
  };
}

/// Watts estimés sur le plat à [speedKmh] pour [totalKg] (cycliste + vélo),
/// quand le trainer ne mesure pas la puissance.
/// Vitesse sur la route virtuelle (km/h) après [dt] secondes, d'après les watts,
/// la pente (%) et le poids : comme dehors, on accélère, on ralentit, on roule en
/// roue libre dans les descentes. Même modèle que [estimatePower].
double nextVirtualSpeed(double kmh, int watts, double gradePercent, double totalKg, double dt) {
  const crr = 0.005, cda = 0.40, rho = 1.2, g = 9.81;
  final m = totalKg.clamp(20.0, 200.0);
  var v = kmh / 3.6;
  final angle = math.atan(gradePercent.clamp(-25.0, 25.0) / 100);
  // Petits pas pour rester stable même si une mesure arrive en retard.
  final steps = (dt / 0.25).ceil().clamp(1, 20);
  final h = dt / steps;
  for (var i = 0; i < steps; i++) {
    final drive = watts <= 0 ? 0.0 : watts / math.max(v, 1.0);
    final resist = m * g * (math.sin(angle) + crr * math.cos(angle)) + 0.5 * rho * cda * v * v;
    v += (drive - resist) / (m * 1.03) * h; // +3 % : roues qui tournent
    if (v < 0) v = 0;
  }
  return math.min(v * 3.6, 120);
}

int estimatePower(double speedKmh, double totalKg) {
  if (speedKmh <= 1) return 0;
  final v = speedKmh / 3.6;
  const crr = 0.005, cda = 0.40, rho = 1.2, g = 9.81; // assis en haut du cintre
  final p = (crr * totalKg * g + 0.5 * rho * cda * v * v) * v;
  return p.round().clamp(0, 1500);
}
