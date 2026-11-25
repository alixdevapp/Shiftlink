// Plans d'entraînement : plusieurs semaines, une séance par jour.
// Chaque case contient un nom de séance (même intitulé que dans builtInWorkouts), ou '' pour repos.
import 'i18n.dart';

class TrainingPlan {
  final String id;
  final String _name;
  final String _description;
  final List<List<String>> weeks;

  const TrainingPlan(this.id, this._name, this._description, this.weeks);

  String get name => tr(_name);
  String get description => tr(_description);
  int get totalWeeks => weeks.length;

  /// Nom de la séance prévue au [weekday] (1 = lundi, 7 = dimanche) de la [weekIndex]-ième semaine (0-based).
  /// Renvoie null si c'est un jour de repos ou si le plan est fini.
  String? workoutFor(int weekIndex, int weekday) {
    if (weekIndex < 0 || weekIndex >= weeks.length) return null;
    final idx = (weekday - 1).clamp(0, 6);
    final n = weeks[weekIndex][idx];
    return n.isEmpty ? null : n;
  }
}

/// Plans fournis avec ShiftLink. Chaque intitulé doit correspondre à une séance de builtInWorkouts
/// ou à une séance importée du même nom.
final builtInPlans = <TrainingPlan>[
  const TrainingPlan('base_sweetspot_4w', 'Base Sweet Spot – 4 semaines', 'Bâtir le socle. 4 séances par semaine, pas de dur.', [
    // Lun     Mar                  Mer    Jeu              Ven    Sam                  Dim
    ['', 'Balade facile', '', 'Sweet Spot 20 min', '', 'Balade facile', ''],
    ['', 'Sweet Spot 20 min', '', 'Balade facile', '', 'Sweet Spot 20 min', ''],
    ['', 'Sweet Spot 20 min', '', 'Pyramide', '', 'Sweet Spot 20 min', ''],
    ['', 'Balade facile', '', 'Sweet Spot 20 min', '', 'Balade facile', ''],
  ]),
  const TrainingPlan('vo2max_4w', 'VO2max – 4 semaines', 'Gagner en puissance maximale. Pic à la troisième semaine.', [
    ['', 'Intervalles 30/30', '', 'Sweet Spot 20 min', '', 'Balade facile', ''],
    ['', 'VO2max 5 × 3 min', '', 'Sweet Spot 20 min', '', 'Balade facile', ''],
    ['', 'VO2max 5 × 3 min', '', 'Intervalles 30/30', '', 'Sweet Spot 20 min', ''],
    ['', 'Balade facile', '', 'Sweet Spot 20 min', '', 'Balade facile', ''],
  ]),
];
