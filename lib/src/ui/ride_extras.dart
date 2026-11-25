// Cyclistes, zones cardio, séances sans appli, chiffres affichés et nombre de
// vitesses de l'appli (idées reprises de QZ / qdomyos-zwift).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../app_state.dart';
import '../controller_manager.dart' show LinkState;
import '../i18n.dart';
import '../riders.dart';
import '../trainer/route.dart';
import '../trainer/workout.dart';
import '../training_plans.dart';
import 'brand.dart';
import 'ride_page.dart' show RecordBar;
import 'rides_page.dart';
import 'trainer_tools.dart' show SpinDownButton;
import 'widgets.dart';
import 'workout_editor.dart';

/// « Combien de vitesses dans ton appli ? » : un pignon dessiné par vitesse.
Future<void> pickAppGearCount(BuildContext context, AppState app) async {
  var n = app.appGearCount;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('Vitesses dans {0}', [app.target.label])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Un pignon dessiné pour chaque vitesse de l’appli.')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: n > AppState.minAppGears ? () => set(() => n--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '$n',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: n < AppState.maxAppGears ? () => set(() => n++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => set(() => n = AppState.defaultAppGears(app.target)),
              child: Text(tr('Par défaut : {0}', [AppState.defaultAppGears(app.target)])),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('OK'))),
        ],
      ),
    ),
  );
  if (ok == true) await app.setAppGearCount(n);
}

// ───────────────────────── Cyclistes ─────────────────────────

/// Pastilles « qui roule ? » en haut de l'écran Rouler.
class RiderChips extends StatelessWidget {
  final AppState app;
  const RiderChips({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final riders = app.riders;
    if (riders.isEmpty) return const SizedBox.shrink();
    final active = app.rider?.name;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in riders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: r.name == active ? Colors.white : Brand.orange,
                  child: Text(
                    r.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: r.name == active ? Brand.orange : Colors.white,
                    ),
                  ),
                ),
                label: Text(r.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                selected: r.name == active,
                selectedColor: Brand.orange,
                labelStyle: TextStyle(color: r.name == active ? Colors.white : null),
                showCheckmark: false,
                onSelected: (_) => app.selectRider(r.name),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.edit_rounded, size: 18),
            label: Text(tr('Cyclistes')),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RidersPage(app: app))),
          ),
        ],
      ),
    );
  }
}

class RidersPage extends StatelessWidget {
  final AppState app;
  const RidersPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cyclistes'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: app.riders.length >= Rider.maxRiders ? null : () => editRider(context, app),
        icon: const Icon(Icons.person_add_rounded),
        label: Text(tr('Ajouter')),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final riders = app.riders;
          final active = app.rider?.name;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              HintBox(
                text: tr(
                  'Un cycliste par personne : son poids, sa FTP pour les séances et son cardio max pour les zones. Touche son prénom sur l’écran Rouler pour passer de l’un à l’autre.',
                ),
              ),
              const SizedBox(height: 12),
              if (riders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Personne pour l’instant.'), textAlign: TextAlign.center),
                ),
              if (riders.isNotEmpty)
                GroupCard(
                  children: [
                    for (final r in riders)
                      SettingRow(
                        icon: r.name == active ? Icons.check_circle_rounded : Icons.person_rounded,
                        color: r.name == active ? Tones.green : Tones.blue,
                        title: r.name,
                        subtitle:
                            tr('{0} kg + vélo {1} kg · FTP {2} W · cardio max {3}', [
                              _kgText(r.kg),
                              _kgText(r.bikeKg),
                              r.ftp,
                              r.hrMax,
                            ]) +
                            (r.gearProfile == null ? '' : ' · ${r.gearProfile}') +
                            (r.kid ? ' · ${tr('Mode enfant')}' : ''),
                        trailing: IconButton(
                          tooltip: tr('Modifier'),
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => editRider(context, app, r),
                        ),
                        onTap: () => app.selectRider(r.name),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Ajoute ou modifie un cycliste.
Future<void> editRider(BuildContext context, AppState app, [Rider? old]) async {
  final name = TextEditingController(text: old?.name ?? '');
  var r = old ?? const Rider(name: '');
  final profiles = app.shiftProfileNames;
  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        Widget slider(String label, double value, double min, double max, int div, ValueChanged<double> on) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(value: value.clamp(min, max), min: min, max: max, divisions: div, onChanged: on),
          ],
        );
        // Réglage fin (0,1 kg, 1 W…) : − et + de part et d'autre du curseur.
        Widget fineSlider(
          String label,
          double value,
          double min,
          double max,
          ValueChanged<double> on, {
          double step = 0.1,
        }) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(
              children: [
                IconButton(
                  tooltip: tr('Moins'),
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: value <= min ? null : () => on(value - step),
                ),
                Expanded(
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: ((max - min) / step).round(),
                    onChanged: on,
                  ),
                ),
                IconButton(
                  tooltip: tr('Plus'),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: value >= max ? null : () => on(value + step),
                ),
              ],
            ),
          ],
        );
        return AlertDialog(
          title: Text(old == null ? tr('Nouveau cycliste') : old.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: old == null,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Prénom')),
                ),
                // Au dixième de kilo : curseur pour aller vite, − et + pour finir.
                fineSlider(
                  tr('Poids : {0} kg', [_kgText(r.kg)]),
                  r.kg,
                  Rider.minKg,
                  Rider.maxKg,
                  (v) => set(() => r = r.copyWith(kg: Rider.roundKg(v, Rider.minKg, Rider.maxKg))),
                ),
                fineSlider(
                  tr('Poids du vélo : {0} kg', [_kgText(r.bikeKg)]),
                  r.bikeKg,
                  Rider.minBikeKg,
                  Rider.maxBikeKg,
                  (v) => set(() => r = r.copyWith(bikeKg: Rider.roundBikeKg(v))),
                ),
                Text(
                  tr('Total cycliste + vélo : {0} kg. Plus il est lourd, plus les côtes sont dures.', [
                    _kgText(r.totalKg),
                  ]),
                  style: TextStyle(fontSize: 12.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                fineSlider(
                  tr('FTP : {0} W', [r.ftp]),
                  r.ftp.toDouble(),
                  40,
                  450,
                  (v) => set(() => r = r.copyWith(ftp: v.round().clamp(40, 450))),
                  step: 1,
                ),
                Text(
                  tr('Pas sûr ? 2,5 W par kg pour un adulte, 1,5 W par kg pour un enfant.'),
                  style: TextStyle(fontSize: 12.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                fineSlider(
                  tr('Cardio max : {0}', [r.hrMax]),
                  r.hrMax.toDouble(),
                  120,
                  220,
                  (v) => set(() => r = r.copyWith(hrMax: v.round().clamp(120, 220))),
                  step: 1,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Mode enfant'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('Pente et watts plafonnés pour un petit vélo.')),
                  value: r.kid,
                  onChanged: (v) => set(() => r = r.copyWith(kid: v)),
                ),
                if (r.kid) ...[
                  slider(
                    tr('Pente maximale : {0} %', [r.kidMaxGrade.toStringAsFixed(1).replaceAll('.', ',')]),
                    r.kidMaxGrade,
                    0,
                    8,
                    16,
                    (v) => set(() => r = r.copyWith(kidMaxGrade: (v * 2).round() / 2)),
                  ),
                  slider(
                    tr('Watts envoyés à l’appli : × {0}', [r.kidPowerFactor.toStringAsFixed(2).replaceAll('.', ',')]),
                    r.kidPowerFactor,
                    1,
                    2,
                    4,
                    (v) => set(() => r = r.copyWith(kidPowerFactor: (v * 4).round() / 4)),
                  ),
                  Text(
                    tr(
                      'Au-delà de × 1, l’avatar avance plus vite que les vrais watts : utile avec une petite roue ou sous le poids minimum de l’appli. Watts limités à {0} W (1,5 × FTP).',
                      [r.kidMaxWatts],
                    ),
                    style: TextStyle(fontSize: 12.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                ],
                if (profiles.isNotEmpty) ...[
                  Text(tr('Profil de vitesses'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  DropdownButton<String?>(
                    isExpanded: true,
                    value: profiles.contains(r.gearProfile) ? r.gearProfile : null,
                    items: [
                      DropdownMenuItem(child: Text(tr('Ne pas changer'))),
                      for (final p in profiles) DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) =>
                        set(() => r = v == null ? r.copyWith(clearProfile: true) : r.copyWith(gearProfile: v)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (old != null)
              TextButton(
                onPressed: () => Navigator.pop(c, 'delete'),
                child: Text(tr('Supprimer'), style: const TextStyle(color: Tones.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(tr('Enregistrer'))),
          ],
        );
      },
    ),
  );
  if (result == 'delete' && old != null) return app.deleteRider(old.name);
  final n = name.text.trim();
  if (result != 'save' || n.isEmpty) return;
  await app.saveRider(r.copyWith(name: n), replacing: old?.name);
  if (old == null) await app.selectRider(n);
}

// ───────────────────────── Zones cardio ─────────────────────────

/// Le pouls, coloré selon la zone, avec son nom (« Facile »…).
class HeartZoneMetric extends StatelessWidget {
  final int bpm;
  final HrZone zone;
  const HeartZoneMetric({super.key, required this.bpm, required this.zone});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: tr('Cardio {0}, zone {1}, {2}', [bpm, zone.zone, zone.label]),
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            '$bpm',
            style: text.headlineSmall?.copyWith(color: zone.color, fontWeight: FontWeight.w800),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: zone.color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Z${zone.zone} ${zone.label}',
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre des 5 zones, la zone actuelle en avant.
class HeartZoneBar extends StatelessWidget {
  final HrZone zone;
  const HeartZoneBar({super.key, required this.zone});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        for (var z = 1; z <= 5; z++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: z == zone.zone ? 10 : 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: HrZone(z).color.withValues(alpha: z == zone.zone ? 1 : 0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
      ],
    ),
  );
}

// ───────────────────────── Chiffres affichés ─────────────────────────

String rideMetricLabel(String m) => switch (m) {
  'power' => tr('Watts'),
  'cadence' => tr('Cadence'),
  'grade' => tr('Pente ou cible ERG'),
  'hr' => tr('Cardio'),
  'speed' => tr('Vitesse'),
  _ => m,
};

/// Choix des chiffres de l'écran Rouler (4 au plus).
Future<void> pickRideMetrics(BuildContext context, AppState app) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (c) => ListenableBuilder(
    listenable: app,
    builder: (c, _) {
      final on = app.rideMetrics;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Chiffres pendant la sortie'), style: Theme.of(c).textTheme.titleLarge),
              Text(tr('{0} au plus. Touche pour ajouter ou enlever.', [AppState.maxRideMetrics])),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in AppState.rideMetricChoices)
                    FilterChip(
                      label: Text(rideMetricLabel(m), style: const TextStyle(fontSize: 16)),
                      selected: on.contains(m),
                      onSelected: on.contains(m) || on.length < AppState.maxRideMetrics
                          ? (_) => app.toggleRideMetric(m)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ),
);

/// Nom d'un chiffre de la fenêtre par-dessus l'appli.
String hudFieldLabel(String f) => switch (f) {
  'power' => tr('Watts'),
  'cadence' => tr('Cadence'),
  'erg' => tr('Cible ERG'),
  'ratio' => tr('Braquet'),
  'speed' => tr('Vitesse (km/h)'),
  'hr' => tr('Cardio'),
  _ => f,
};

Future<void> pickHudFields(BuildContext context, AppState app) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (c) => ListenableBuilder(
    listenable: app,
    builder: (c, _) {
      final on = app.hudFields;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Dans la fenêtre'), style: Theme.of(c).textTheme.titleLarge),
              Text(tr('La vitesse est toujours là, en grand. Ajoute ce que tu veux voir dessous.')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in AppState.hudFieldChoices)
                    FilterChip(
                      label: Text(hudFieldLabel(f), style: const TextStyle(fontSize: 16)),
                      selected: on.contains(f),
                      onSelected: (_) => app.toggleHudField(f),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Boutons − et +')),
                subtitle: Text(tr('Change de vitesse en touchant la fenêtre, sans quitter l’appli.')),
                value: app.hudButtons,
                onChanged: app.setHudButtons,
              ),
            ],
          ),
        ),
      );
    },
  ),
);

// ───────────────────────── Séances ─────────────────────────

/// Petit dessin de la séance : un bâton par seconde, coloré selon l'effort.
class WorkoutShape extends StatelessWidget {
  final Workout workout;
  final double height;

  /// Avancement (0 à 1) : la partie faite est plus pâle.
  final double? progress;
  const WorkoutShape({super.key, required this.workout, this.height = 36, this.progress});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ShapePainter(workout, progress, Theme.of(context).colorScheme.onSurface)),
    ),
  );
}

Color intensityColor(double f) => f < 0.6
    ? const Color(0xFF8A94A6)
    : f < 0.76
    ? const Color(0xFF3B82F6)
    : f < 0.9
    ? const Color(0xFF22A45D)
    : f < 1.05
    ? const Color(0xFFF2A900)
    : const Color(0xFFEF4444);

class _ShapePainter extends CustomPainter {
  final Workout w;
  final double? progress;
  final Color ink;
  _ShapePainter(this.w, this.progress, this.ink);

  @override
  void paint(Canvas canvas, Size s) {
    final total = w.seconds;
    if (total == 0) return;
    final top = w.steps.map((x) => math.max(x.from, x.to)).reduce(math.max).clamp(1.0, 3.0);
    final cols = math.max(1, s.width.round());
    for (var i = 0; i < cols; i++) {
      final t = (i + 0.5) / cols * total;
      final f = w.intensityAt(t.floor()) ?? 0;
      final x0 = s.width * i / cols, x1 = s.width * (i + 1) / cols;
      final h = s.height * (f / top).clamp(0.05, 1.0);
      final done = progress != null && (i + 1) / cols <= progress!;
      canvas.drawRect(
        Rect.fromLTRB(x0, s.height - h, x1 + 0.5, s.height),
        Paint()..color = intensityColor(f).withValues(alpha: done ? 0.35 : 1),
      );
    }
    if (progress != null) {
      final x = s.width * progress!;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, s.height),
        Paint()
          ..color = ink
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.w != w || old.progress != progress || old.ink != ink;
}

/// Onglet « Séances » : le home trainer suit une séance tout seul, sans appli.
/// Il montre lui-même ce qui manque (trainer à connecter, appli à fermer).
class WorkoutsTab extends StatelessWidget {
  final AppState app;
  const WorkoutsTab({super.key, required this.app});

  Future<void> _import(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !context.mounted) return;
    final file = picked.first.xFile;
    void toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    // Une trace GPX est bien plus grosse qu'une séance.
    final isGpx = file.name.toLowerCase().endsWith('.gpx');
    if (await file.length() > (isGpx ? GpxRoute.maxFileBytes : Workout.maxFileBytes)) {
      if (context.mounted) toast(tr('Fichier trop volumineux.'));
      return;
    }
    final bytes = await file.readAsBytes();
    if (isGpx) {
      final r = GpxRoute.parseGpx(utf8.decode(bytes, allowMalformed: true), fallbackName: tr('Parcours'));
      if (!context.mounted) return;
      if (r == null) return toast(tr('Ce fichier GPX n’a pas de trace lisible.'));
      if (!await app.addRoute(r)) {
        if (context.mounted) toast(tr('Trop de parcours : supprimes-en un.'));
        return;
      }
      if (context.mounted) toast(tr('Parcours « {0} » ajouté.', [r.name]));
      return;
    }
    final w = Workout.fromFile(file.name, bytes, ftp: app.ftp, fallbackName: tr('Séance'));
    if (!context.mounted) return;
    if (w == null) return toast(tr('Ce fichier n’est pas une séance lisible (.zwo, .erg, .mrc, .fit ou .gpx).'));
    if (!await app.addWorkout(w)) {
      if (context.mounted) toast(tr('Trop de séances : supprimes-en une.'));
      return;
    }
    if (context.mounted) toast(tr('Séance « {0} » ajoutée.', [w.name]));
  }

  Future<void> _start(BuildContext context, Workout w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(w.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkoutShape(workout: w, height: 60),
            const SizedBox(height: 12),
            Text(tr('{0} · le trainer règle les watts tout seul.', [clock(w.seconds)])),
            const SizedBox(height: 6),
            Text(
              app.rider == null
                  ? tr('Base : FTP {0} W. Ajoute un cycliste pour la changer.', [app.ftp])
                  : tr('Pour {0} : FTP {1} W.', [app.rider!.name, app.ftp]),
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
            if (w.hrTarget(app.hrMax) case (final lo, final hi)) ...[
              const SizedBox(height: 6),
              Text(tr('Cardio visé : {0} à {1} bpm (cardio max {2}).', [lo, hi, app.hrMax])),
              if (app.heartRate.bpm.value == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr('Connecte ta ceinture cardio : sans elle, les watts restent fixes.'),
                    style: const TextStyle(color: Tones.orange, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Text(
              tr('Arrête de pédaler : le chrono attend.'),
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('C’est parti'))),
        ],
      ),
    );
    if (ok == true) app.startWorkout(w);
  }

  Future<void> _startRoute(BuildContext context, GpxRoute r) async {
    final resume = app.routeResumeAt(r);
    final from = await showDialog<double>(
      context: context,
      builder: (c) => RouteStartDialog(route: r, resumeAt: resume),
    );
    if (from != null) app.startRoute(r, fromM: from);
  }

  Future<void> _importFromIntervals(BuildContext context) async {
    void toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    if (app.intervalsAthleteId.isEmpty || app.intervalsApiKey.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => IntervalsIcuSetup(app: app),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    toast(tr('Récupération en cours…'));
    try {
      final (added, skipped) = await app.importIntervalsIcuWorkouts();
      if (!context.mounted) return;
      if (added == 0 && skipped == 0) {
        toast(tr('Aucune séance prévue dans les 30 prochains jours.'));
      } else {
        toast(tr('{0} séance(s) ajoutée(s), {1} ignorée(s).', [added, skipped]));
      }
    } catch (e) {
      if (context.mounted) toast(tr('Intervals.icu : {0}', ['$e']));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.healthListenable, app.proxy.fixedErg, app.proxy.routeRun, app.proxy.data]),
      builder: (context, _) {
        final running = app.proxy.workout.value != null;
        final ergRunning = app.proxy.fixedErg.value != null;
        final routeRunning = app.proxy.routeRun.value != null;
        final can = app.proxy.canRunAlone;
        final cs = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (running) ...[
              WorkoutCard(app: app, big: true),
              const SizedBox(height: 12),
              _IntensityButtons(app: app),
              const SizedBox(height: 12),
              _LiveMetrics(app: app),
              const SizedBox(height: 12),
              _RecordCard(app: app),
            ] else if (ergRunning) ...[
              FixedErgCard(app: app),
              const SizedBox(height: 12),
              _LiveMetrics(app: app),
              const SizedBox(height: 12),
              _RecordCard(app: app),
            ] else if (routeRunning) ...[
              RouteCard(app: app, run: app.proxy.routeRun.value!),
              const SizedBox(height: 12),
              RouteGears(app: app),
              const SizedBox(height: 12),
              // Les mêmes chiffres qu'en plein écran.
              _RouteBigStats(app: app, run: app.proxy.routeRun.value!),
              const SizedBox(height: 12),
              _RecordCard(app: app),
            ] else ...[
              Text(
                tr('Le home trainer règle les watts tout seul. Pas besoin d’appli.'),
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (app.riders.isNotEmpty) ...[
                Text(tr('Qui roule ?'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                RiderChips(app: app),
                const SizedBox(height: 12),
              ],
              TrainerForWorkoutCard(app: app),
              const SizedBox(height: 12),
              FixedErgCard(app: app),
              const SizedBox(height: 16),
              _PlanCard(app: app, onStart: (w) => _start(context, w)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      can ? tr('Choisis ta séance') : tr('Les séances'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => FtpHelpDialog(app: app),
                    ),
                    icon: const Icon(Icons.help_outline_rounded, size: 18),
                    label: Text(tr('Test FTP ?')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final w in app.workouts)
                Opacity(
                  opacity: can ? 1 : 0.5,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: can ? () => _start(context, w) : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (can) ...[
                                  const Icon(Icons.play_circle_fill_rounded, color: Brand.orange, size: 30),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    w.title,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(clock(w.seconds), style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (!w.builtIn)
                                  IconButton(
                                    tooltip: tr('Modifier'),
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => WorkoutEditorPage(app: app, original: w),
                                      ),
                                    ),
                                  ),
                                if (!w.builtIn)
                                  IconButton(
                                    tooltip: tr('Supprimer'),
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    onPressed: () => app.deleteWorkout(w.name),
                                  )
                                else
                                  const SizedBox(width: 10),
                              ],
                            ),
                            if (w.subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, right: 8),
                                child: Text(
                                  w.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: WorkoutShape(workout: w),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutEditorPage(app: app))),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Créer une séance')),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.timer_outlined),
                title: Text(tr('Compte à rebours sonore')),
                subtitle: Text(tr('3 bips avant chaque changement de bloc, et la voix annonce les watts 10 s avant.')),
                value: app.workoutCountdown,
                onChanged: app.setWorkoutCountdown,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _import(context),
                icon: const Icon(Icons.file_open_rounded),
                label: Text(tr('Ajouter un fichier de séance ou un parcours')),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _importFromIntervals(context),
                icon: const Icon(Icons.cloud_download_rounded),
                label: Text(tr('Récupérer d’Intervals.icu')),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Formats lus : .zwo (Zwift, whatsonzwift.com), .erg et .mrc (TrainerRoad, Golden Cheetah), .fit (Garmin, TrainingPeaks, Intervals.icu) et .gpx (parcours Strava, Komoot, GPS…).',
                ),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              if (app.routes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(tr('Mes parcours'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final r in app.routes)
                  Opacity(
                    opacity: can ? 1 : 0.5,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.terrain_rounded, color: Brand.orange),
                        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          app.routeResumeAt(r) == null
                              ? r.subtitle
                              : '${r.subtitle}\n${tr('Arrêté au km {0}', [(app.routeResumeAt(r)! / 1000).toStringAsFixed(1).replaceAll('.', ',')])}',
                        ),
                        onTap: can ? () => _startRoute(context, r) : null,
                        trailing: IconButton(
                          tooltip: tr('Supprimer'),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => app.deleteRoute(r.name),
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Text(tr('Mes sorties'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              GroupCard(
                children: [
                  SettingRow(
                    icon: Icons.history_rounded,
                    color: Tones.red,
                    title: tr('Mes sorties'),
                    subtitle: tr('Durée, puissance et cardio de chaque sortie'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RidesPage.of(app),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Étape 1 de l'onglet Séances : le home trainer, connecté à ShiftLink et libre.
class TrainerForWorkoutCard extends StatelessWidget {
  final AppState app;
  const TrainerForWorkoutCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = app.proxy.trainer;
    final cs = Theme.of(context).colorScheme;
    final connected = t.isConnected;
    final busy = connected && app.proxy.appClient != null;
    final saved = app.savedTrainerName;
    final (Color color, IconData icon, String title, String? sub) = switch (t.state.value) {
      LinkState.connected when busy => (
        Tones.orange,
        Icons.warning_amber_rounded,
        tr('Une appli pilote déjà le home trainer'),
        tr('Ferme-la (ou débranche le trainer « ShiftLink » dedans) pour faire une séance ici.'),
      ),
      LinkState.connected => (Tones.green, Icons.check_circle_rounded, tr('Home trainer prêt'), t.name.value),
      LinkState.connecting => (Tones.blue, Icons.sync_rounded, tr('Connexion à {0}…', [t.name.value]), null),
      LinkState.disconnected => (
        Tones.grey,
        Icons.pedal_bike,
        tr('Connecte ton home trainer'),
        tr('Il ne doit pas être connecté à une autre appli en même temps.'),
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      if (sub != null) Text(sub, style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            if (t.state.value == LinkState.disconnected) ...[
              const SizedBox(height: 10),
              if (saved != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    if (await app.askPermissions()) await app.connectTrainerForWorkout();
                  },
                  icon: const Icon(Icons.bluetooth_connected_rounded),
                  label: Text(tr('Connecter {0}', [saved])),
                ),
              const SizedBox(height: 6),
              ValueListenableBuilder(
                valueListenable: t.scanning,
                builder: (_, scanning, _) => OutlinedButton.icon(
                  onPressed: scanning
                      ? null
                      : () async {
                          if (await app.askPermissions()) unawaited(t.scan());
                        },
                  icon: scanning
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching_rounded),
                  label: Text(scanning ? tr('Recherche en cours…') : tr('Chercher mon home trainer')),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: t.candidates,
                builder: (_, list, _) => Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 8),
                        leading: const Icon(Icons.pedal_bike),
                        title: Text(c.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => app.useTrainer(c),
                      ),
                  ],
                ),
              ),
            ],
            if (connected && !busy) ...[const SizedBox(height: 6), SpinDownButton(app: app)],
            if (connected && !busy && app.target.transport != Transport.proxy) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: t.disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(tr('Libérer le trainer pour {0}', [app.target.label])),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plus facile / plus dur pendant une séance : décale les watts.
class _IntensityButtons extends StatelessWidget {
  final AppState app;
  const _IntensityButtons({required this.app});

  @override
  Widget build(BuildContext context) {
    final step = app.ergButtonStep;
    final off = app.proxy.ergOffset.value;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: ShiftButton(up: false, onTap: () => app.proxy.ergAdjust(-step), height: 96)),
            const SizedBox(width: 12),
            Expanded(child: ShiftButton(up: true, onTap: () => app.proxy.ergAdjust(step), height: 96)),
          ],
        ),
        if (off != 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('{0}{1} W par rapport à la séance', [off > 0 ? '+' : '', off])),
          ),
      ],
    );
  }
}

/// Watts, cadence et cardio pendant la séance.
class _LiveMetrics extends StatelessWidget {
  final AppState app;
  const _LiveMetrics({required this.app});

  @override
  Widget build(BuildContext context) {
    final d = app.proxy.data.value;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget metric(String v, String unit) => Column(
      children: [
        Text(v, style: text.headlineSmall),
        Text(unit, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
    final bpm = app.heartRate.bpm.value;
    final z = app.hrZone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: metric('${d.power ?? '–'}', tr('watts'))),
                Expanded(child: metric('${d.cadence?.round() ?? '–'}', tr('tr/min'))),
                if (bpm != null)
                  Expanded(
                    child: z == null ? metric('$bpm', 'bpm') : HeartZoneMetric(bpm: bpm, zone: z),
                  ),
              ],
            ),
            if (z != null) ...[const SizedBox(height: 10), HeartZoneBar(zone: z)],
          ],
        ),
      ),
    );
  }
}

/// Séance en cours, sur l'écran Rouler.
/// Enregistrement de la sortie, dans l'onglet Séances.
class _RecordCard extends StatelessWidget {
  final AppState app;
  const _RecordCard({required this.app});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: RecordBar(app: app),
    ),
  );
}

/// Avant un parcours : on choisit d'où partir (début, reprise ou un km au choix).
/// Renvoie la distance de départ en mètres, ou null si on annule.
class RouteStartDialog extends StatefulWidget {
  final GpxRoute route;

  /// Là où on s'était arrêté la dernière fois (m), ou null.
  final double? resumeAt;
  const RouteStartDialog({super.key, required this.route, this.resumeAt});

  @override
  State<RouteStartDialog> createState() => _RouteStartDialogState();
}

class _RouteStartDialogState extends State<RouteStartDialog> {
  late double _from = widget.resumeAt ?? 0;

  static String _km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final scheme = Theme.of(context).colorScheme;
    // On peut partir jusqu'à 500 m avant l'arrivée, par pas de 100 m.
    final maxStart = ((r.length - 500) / 100).floor() * 100.0;
    final resume = widget.resumeAt;
    return AlertDialog(
      title: Text(r.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                '{0} km, {1} m de D+. Le trainer suivra la pente du parcours tant que tu pédales. Les vitesses marchent comme en simulation.',
                [_km(r.length), r.climbing.round()],
              ),
            ),
            if (maxStart >= 100) ...[
              const SizedBox(height: 16),
              Text(
                _from <= 0
                    ? tr('Départ : au début')
                    : tr('Départ : km {0} (reste {1} km)', [_km(_from), _km(r.length - _from)]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _from.clamp(0, maxStart),
                max: maxStart,
                divisions: (maxStart / 100).round(),
                label: tr('km {0}', [_km(_from)]),
                semanticFormatterCallback: (v) => tr('km {0}', [_km(v)]),
                onChanged: (v) => setState(() => _from = (v / 100).round() * 100.0),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (resume != null)
                    ChoiceChip(
                      label: Text(tr('Reprendre au km {0}', [_km(resume)])),
                      selected: _from == resume,
                      onSelected: (_) => setState(() => _from = resume),
                    ),
                  ChoiceChip(
                    label: Text(tr('Depuis le début')),
                    selected: _from <= 0,
                    onSelected: (_) => setState(() => _from = 0),
                  ),
                ],
              ),
              if (_from > 0) ...[
                const SizedBox(height: 8),
                Text(
                  tr('Le record du parcours ne compte que si tu pars du début.'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(context, _from), child: Text(tr('C’est parti'))),
      ],
    );
  }
}

/// Vitesses ShiftLink pendant un parcours : − vitesse +.
class RouteGears extends StatelessWidget {
  final AppState app;
  const RouteGears({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget button(bool up) => Material(
      shape: const CircleBorder(),
      color: up ? Brand.orange : cs.surfaceContainerHighest,
      child: RepeatInkWell(
        customBorder: const CircleBorder(),
        onFire: () => app.shift(up ? 1 : -1),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(up ? Icons.add_rounded : Icons.remove_rounded, size: 34, color: up ? Colors.white : cs.onSurface),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.proxy.gear]),
      builder: (context, _) {
        final g = app.proxy.gears;
        final infinite = g.config.infinite;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                button(false),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        infinite ? g.label() : tr('Vitesse {0} sur {1}', [g.gear, g.count]),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        infinite ? tr('Vitesses infinies') : g.label(g.gear),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                button(true),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pause / reprise d'une séance ou d'un parcours.
class _PauseButton extends StatelessWidget {
  final AppState app;
  final Color? color;
  const _PauseButton({required this.app, this.color});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: app.proxy.manualPause,
    builder: (context, paused, _) => IconButton(
      tooltip: paused ? tr('Reprendre') : tr('Pause'),
      color: color,
      icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
      onPressed: app.togglePause,
    ),
  );
}

/// Carte « Parcours en cours » : distance, pente, progression.
class RouteCard extends StatelessWidget {
  final AppState app;
  final RouteRun run;
  const RouteCard({super.key, required this.app, required this.run});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = run.route.length;
    final done = run.distance;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(gradient: Brand.gradient),
            child: Row(
              children: [
                const Icon(Icons.terrain_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    run.route.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                _PauseButton(app: app, color: Colors.white),
                IconButton(
                  tooltip: tr('Plein écran'),
                  color: Colors.white,
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteFullScreen(app: app))),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: app.proxy.stopRoute,
                  child: Text(tr('Arrêter')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${(done / 1000).toStringAsFixed(1).replaceAll('.', ',')} / ${(total / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(
                  app.proxy.manualPause.value
                      ? tr('En pause')
                      : tr('Pente {0}%', [run.grade.toStringAsFixed(1).replaceAll('.', ',')]),
                  style: TextStyle(
                    color: app.proxy.manualPause.value ? Tones.orange : cs.onSurfaceVariant,
                    fontWeight: app.proxy.manualPause.value ? FontWeight.w700 : null,
                  ),
                ),
                if (run.ghostGap != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        run.ghostGap! <= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 16,
                        color: run.ghostGap! <= 0 ? Tones.green : Tones.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('Fantôme : {0}{1} s', [run.ghostGap! <= 0 ? '−' : '+', run.ghostGap!.abs()]),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: run.ghostGap! <= 0 ? Tones.green : Tones.orange,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                if (run.route.hasTrace) _RouteMap(route: run.route, distance: run.distance),
                _ElevationProfile(route: run.route, distance: run.distance),
                const SizedBox(height: 8),
                _NextClimbChip(route: run.route, distance: run.distance),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: run.progress, minHeight: 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutCard extends StatelessWidget {
  final AppState app;

  /// Version grand format, pour l'onglet Séances.
  final bool big;
  const WorkoutCard({super.key, required this.app, this.big = false});

  @override
  Widget build(BuildContext context) {
    final run = app.proxy.workout.value;
    if (run == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final f = run.workout.intensityAt(run.elapsed) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center_rounded, color: intensityColor(f)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(run.workout.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                _PauseButton(app: app),
                TextButton(onPressed: app.proxy.stopWorkout, child: Text(tr('Arrêter'))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${run.watts} W',
                      style: TextStyle(
                        fontSize: big ? 64 : 40,
                        fontWeight: FontWeight.w800,
                        color: intensityColor(f),
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.proxy.manualPause.value
                          ? tr('En pause')
                          : run.paused
                          ? tr('Pédale pour reprendre')
                          : tr('Bloc {0} sur {1} · encore {2}', [run.step, run.steps, clock(run.stepSecondsLeft)]),
                      style: TextStyle(
                        color: run.paused ? Tones.orange : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (run.followsHeart) _HeartTarget(run: run, bpm: app.heartRate.bpm.value),
            if (run.cadenceTarget != null)
              _CadenceTarget(target: run.cadenceTarget!, now: app.proxy.data.value.cadence),
            if (run.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          run.message!.text,
                          style: TextStyle(fontSize: big ? 17 : 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!run.paused && run.step < run.steps && run.stepSecondsLeft <= 10)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: _NextStepBanner(
                  seconds: run.stepSecondsLeft,
                  watts: (run.workout.steps[run.step].from * app.ftp).round(),
                  intensity: run.workout.steps[run.step].from,
                ),
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: WorkoutShape(workout: run.workout, height: big ? 80 : 44, progress: run.progress),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Fin dans {0}', [clock(run.secondsLeft)]),
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            // Le piège de l'ERG : moins on pédale vite, plus le trainer serre.
            if (run.tooHard)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, color: Tones.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          'Trop dur ? Sur ton vrai vélo, mets le petit plateau (et un grand pignon si tu as une cassette) : le trainer peut alors descendre bas.',
                        ),
                        style: const TextStyle(color: Tones.orange, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              )
            // Pas ce conseil quand la séance demande elle-même une cadence basse.
            else if (!run.paused && (run.cadenceTarget ?? 90) >= 75 && (app.proxy.data.value.cadence ?? 90) < 70)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: Tones.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('Pédale plus vite : en séance, plus tu ralentis, plus le trainer serre.'),
                        style: const TextStyle(color: Tones.orange, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// « Cadence : 100 tr/min · tu es à 92 » : la cadence demandée par le bloc, verte quand on y est.
class _CadenceTarget extends StatelessWidget {
  final int target;
  final double? now;
  const _CadenceTarget({required this.target, this.now});

  @override
  Widget build(BuildContext context) {
    final rpm = now?.round();
    final ok = rpm != null && (rpm - target).abs() <= 5;
    final color = rpm == null || rpm < 20
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (ok ? Tones.green : Tones.orange);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Row(
        children: [
          Icon(Icons.rotate_right_rounded, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rpm == null || rpm < 20
                  ? tr('Cadence demandée : {0} tr/min', [target])
                  : ok
                  ? tr('Cadence demandée : {0} tr/min · c’est bon ({1})', [target, rpm])
                  : rpm < target
                  ? tr('Cadence demandée : {0} tr/min · plus vite ({1})', [target, rpm])
                  : tr('Cadence demandée : {0} tr/min · moins vite ({1})', [target, rpm]),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Prochain bloc dans 3 s : 250 W », en grand quand on approche.
class _NextStepBanner extends StatelessWidget {
  final int seconds;
  final int watts;
  final double intensity;
  const _NextStepBanner({required this.seconds, required this.watts, required this.intensity});

  @override
  Widget build(BuildContext context) {
    final c = intensityColor(intensity);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c, width: 2),
        ),
        child: Row(
          children: [
            Text(
              '$seconds',
              style: TextStyle(fontSize: seconds <= 3 ? 34 : 24, fontWeight: FontWeight.w800, color: c, height: 1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('Prochain bloc : {0} W', [watts]),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boîte de dialogue : saisie de l'ID d'athlète et de la clé API Intervals.icu.
class IntervalsIcuSetup extends StatefulWidget {
  final AppState app;
  const IntervalsIcuSetup({super.key, required this.app});

  @override
  State<IntervalsIcuSetup> createState() => _IntervalsIcuSetupState();
}

class _IntervalsIcuSetupState extends State<IntervalsIcuSetup> {
  late final _id = TextEditingController(text: widget.app.intervalsAthleteId);
  late final _key = TextEditingController(text: widget.app.intervalsApiKey);

  @override
  void dispose() {
    _id.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Connecter Intervals.icu')),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Ouvre intervals.icu/settings, section « Developer », copie ton ID d’athlète et crée une clé API. Rien ne quitte ton téléphone que pour aller chez Intervals.icu.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            decoration: InputDecoration(labelText: tr('ID d’athlète (commence par i)')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Clé API')),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Annuler'))),
      FilledButton(
        onPressed: () async {
          await widget.app.setIntervalsAthleteId(_id.text);
          await widget.app.setIntervalsApiKey(_key.text);
          if (context.mounted) Navigator.pop(context, true);
        },
        child: Text(tr('Garder')),
      ),
    ],
  );
}

/// Carte « Mon plan » : la séance du jour selon le plan actif.
class _PlanCard extends StatelessWidget {
  final AppState app;
  final void Function(Workout) onStart;
  const _PlanCard({required this.app, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final plan = app.activePlan;
    final cs = Theme.of(context).colorScheme;
    if (plan == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: () => _pickPlan(context),
          icon: const Icon(Icons.event_note_rounded),
          label: Text(tr('Suivre un plan d’entraînement')),
        ),
      );
    }
    final today = app.planWorkoutToday();
    final start = app.activePlanStart!;
    final day = DateTime.now().difference(DateTime(start.year, start.month, start.day)).inDays;
    final week = day ~/ 7 + 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_rounded, color: Brand.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text(
                  tr('Semaine {0} / {1}', [week.clamp(1, plan.totalWeeks), plan.totalWeeks]),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                IconButton(
                  tooltip: tr('Arrêter le plan'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: app.stopPlan,
                ),
              ],
            ),
            if (today != null) ...[
              const SizedBox(height: 4),
              Text(tr('Aujourd’hui : {0}', [today.title])),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: app.proxy.canRunAlone ? () => onStart(today) : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(tr('Lancer la séance du jour')),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                week > plan.totalWeeks ? tr('Plan terminé, bravo !') : tr('Repos aujourd’hui.'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickPlan(BuildContext context) async {
    final choice = await showDialog<TrainingPlan>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('Choisir un plan')),
        children: [
          for (final p in builtInPlans)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    tr('{0} · {1} semaines', [p.description, p.totalWeeks]),
                    style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice != null) await app.startPlan(choice);
  }
}

/// Dialogue de fin de test FTP : propose d'enregistrer la nouvelle FTP mesurée.
class FtpTestDialog extends StatelessWidget {
  final AppState app;
  final FtpTestResult result;
  const FtpTestDialog({super.key, required this.app, required this.result});

  @override
  Widget build(BuildContext context) {
    final cur = app.ftp;
    return AlertDialog(
      title: Text(tr('Test FTP terminé')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.kind == 'ramp' ? tr('Dernière minute × 0,75') : tr('Puissance moyenne des 20 min × 0,95')),
          const SizedBox(height: 12),
          Text(
            tr('Ta nouvelle FTP : {0} W', [result.ftp]),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(tr('Avant : {0} W', [cur]), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            app.ftpTestResult.value = null;
            Navigator.pop(context);
          },
          child: Text(tr('Ignorer')),
        ),
        FilledButton(
          onPressed: () async {
            await app.applyFtpTest(result.ftp);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(tr('Enregistrer')),
        ),
      ],
    );
  }
}

/// Profil d'altitude du parcours, avec le curseur de position et la couleur de la pente en cours.
class _ElevationProfile extends StatelessWidget {
  final GpxRoute route;
  final double distance;
  const _ElevationProfile({required this.route, required this.distance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54,
      child: CustomPaint(
        painter: _ProfilePainter(route, distance, cs.onSurface, cs.onSurfaceVariant),
        size: Size.infinite,
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  final GpxRoute route;
  final double distance;
  final Color ink;
  final Color dim;
  _ProfilePainter(this.route, this.distance, this.ink, this.dim);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.points.length < 2) return;
    final elevations = [for (final p in route.points) p.elevation];
    final lo = elevations.reduce((a, b) => a < b ? a : b);
    var hi = elevations.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 10) hi = lo + 10;
    final total = route.length;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < route.points.length; i++) {
      final p = route.points[i];
      final x = (p.distance / total) * size.width;
      final y = size.height - ((p.elevation - lo) / (hi - lo)) * (size.height - 6) - 2;
      i == 0 ? path.lineTo(x, y) : path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    final fill = Paint()..color = dim.withValues(alpha: 0.25);
    canvas.drawPath(path, fill);

    final line = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final profile = Path();
    for (var i = 0; i < route.points.length; i++) {
      final p = route.points[i];
      final x = (p.distance / total) * size.width;
      final y = size.height - ((p.elevation - lo) / (hi - lo)) * (size.height - 6) - 2;
      i == 0 ? profile.moveTo(x, y) : profile.lineTo(x, y);
    }
    canvas.drawPath(profile, line);

    final cx = (distance / total).clamp(0.0, 1.0) * size.width;
    final cy = size.height - ((route.elevationAt(distance) - lo) / (hi - lo)) * (size.height - 6) - 2;
    canvas.drawRect(Rect.fromLTWH(cx - 1, 0, 2, size.height), Paint()..color = Brand.orange.withValues(alpha: 0.5));
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = Brand.orange);
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.distance != distance || old.route != route;
}

/// « Montée ↗ 5,2% dans 240 m, sur 600 m » : résume la prochaine montée du parcours.
class _NextClimbChip extends StatelessWidget {
  final GpxRoute route;
  final double distance;
  const _NextClimbChip({required this.route, required this.distance});

  @override
  Widget build(BuildContext context) {
    final climb = route.nextClimb(distance);
    if (climb == null) return const SizedBox.shrink();
    final (ahead, length, grade) = climb;
    String m(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '${v.round()} m';
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Icon(Icons.trending_up_rounded, size: 18, color: _gradeColor(grade)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('Montée {0}% dans {1}, sur {2}', [grade.toStringAsFixed(1).replaceAll('.', ','), m(ahead), m(length)]),
              style: TextStyle(fontWeight: FontWeight.w600, color: _gradeColor(grade)),
            ),
          ),
        ],
      ),
    );
  }

  Color _gradeColor(double g) {
    if (g >= 10) return Tones.red;
    if (g >= 7) return Tones.orange;
    if (g >= 4) return Tones.yellow;
    return Tones.green;
  }
}

/// Explique comment faire un test FTP, avec un pas-à-pas pour chaque appli choisie.
class FtpHelpDialog extends StatelessWidget {
  final AppState app;
  const FtpHelpDialog({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = _stepsFor(app.target);
    return AlertDialog(
      title: Text(tr('Comment faire un test FTP ?')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Le test FTP mesure la puissance que tu peux tenir une heure à bloc. Résultat : des zones de puissance justes pour toi.',
              ),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(tr('Avec ShiftLink (sans appli)'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              tr(
                '• Dans Séances, choisis « Test FTP (rampe) » (~30 min) ou « Test FTP (20 min) » (~35 min).\n• À la fin, ShiftLink te propose ta nouvelle FTP, tu la gardes d’un bouton.',
              ),
            ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr('Avec {0}', [app.target.label]), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(steps),
            ],
            const SizedBox(height: 12),
            Text(
              tr('Chauffe toujours 10 à 15 min avant. Pas de test FTP si tu es fatigué ou malade.'),
              style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK')))],
    );
  }

  String _stepsFor(TargetApp t) {
    switch (t) {
      case TargetApp.zwift:
      case TargetApp.zwiftRide:
      case TargetApp.mywhooshProxy:
        return tr(
          '• Zwift : menu « Training » → « Workouts » → « FTP Builder » ou « FTP Tests » → « Ramp Test » (ou « FTP Test 20 min »).\n• À la fin, Zwift met à jour ta FTP toute seule. Vérifie dans Profile.',
        );
      case TargetApp.mywhoosh:
        return tr(
          '• MyWhoosh : menu « Workouts » → « FTP tests ». Le « Ramp Test » dure ~25 min.\n• À la fin, MyWhoosh enregistre ta FTP dans ton profil.',
        );
      case TargetApp.rouvy:
        return tr(
          '• Rouvy : « Workouts » → « FTP Test ».\n• Rouvy propose aussi une estimation après plusieurs sorties, dans « Settings » → « Profile ».',
        );
      case TargetApp.trainerroad:
        return tr(
          '• TrainerRoad : « Workouts » → tape « Ramp Test ».\n• TrainerRoad met ta FTP à jour tout seul après le test.',
        );
      case TargetApp.tpv:
        return tr('• TrainingPeaks Virtual : « Library » → « Tests » → « FTP Ramp ».');
      case TargetApp.biketerra:
      case TargetApp.biketerraObc:
        return tr('• Biketerra : « Workouts » → cherche « FTP » ou « Ramp ».');
      default:
        return '';
    }
  }
}

/// Carte 2D du parcours. S'affiche seulement s'il y a Internet (sinon on garde le profil d'altitude).
class _RouteMap extends StatefulWidget {
  final GpxRoute route;
  final double distance;
  const _RouteMap({required this.route, required this.distance});

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  bool? _online;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = Connectivity().onConnectivityChanged.listen((_) => _check());
  }

  Future<void> _check() async {
    try {
      final r = await Connectivity().checkConnectivity();
      final on = r.any((x) => x != ConnectivityResult.none);
      if (mounted && on != _online) setState(() => _online = on);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online != true) return const SizedBox.shrink();
    final pts = <LatLng>[
      for (final p in widget.route.points)
        if (p.lat != null && p.lon != null) LatLng(p.lat!, p.lon!),
    ];
    if (pts.length < 2) return const SizedBox.shrink();
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final here = widget.route.latLonAt(widget.distance);
    final hereLL = here == null ? null : LatLng(here.$1, here.$2);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 160,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
                padding: const EdgeInsets.all(20),
              ),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              backgroundColor: cs.surfaceContainerHighest,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.shiftlink',
                maxZoom: 19,
                errorTileCallback: (_, _, _) {},
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: pts,
                    color: Brand.orange,
                    strokeWidth: 4,
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              if (hereLL != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: hereLL,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Brand.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap')],
                alignment: AttributionAlignment.bottomLeft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vue plein écran d'un parcours en cours : carte zoomable, tous les chiffres, profil.
class RouteFullScreen extends StatelessWidget {
  final AppState app;
  const RouteFullScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<RouteRun?>(
          valueListenable: app.proxy.routeRun,
          builder: (_, run, _) => Text(run?.route.name ?? tr('Parcours')),
        ),
        actions: [
          _PauseButton(app: app),
          IconButton(
            tooltip: tr('Arrêter'),
            icon: const Icon(Icons.stop_circle_outlined),
            // Le parcours arrêté, le plein écran se ferme tout seul (plus bas) : un
            // second retour ici fermait aussi l'appli.
            onPressed: app.proxy.stopRoute,
          ),
        ],
      ),
      body: ValueListenableBuilder<RouteRun?>(
        valueListenable: app.proxy.routeRun,
        builder: (context, run, _) {
          if (run == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              Expanded(
                flex: 3,
                child: run.route.hasTrace
                    ? _InteractiveRouteMap(route: run.route, distance: run.distance)
                    : Center(child: Text(tr('Ce parcours n’a pas de trace GPS enregistrée.'))),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: _ElevationProfile(route: run.route, distance: run.distance),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _RouteBigStats(app: app, run: run),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: RouteGears(app: app),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Grille de chiffres en plein écran.
class _RouteBigStats extends StatelessWidget {
  final AppState app;
  final RouteRun run;
  const _RouteBigStats({required this.app, required this.run});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = app.proxy.data.value;
    final total = run.route.length;
    final done = run.distance;
    final remaining = (total - done).clamp(0, total);
    final elapsed = app.ride.elapsed.value.inSeconds;
    final avgKmh = elapsed > 0 ? (done / elapsed) * 3.6 : 0;
    final kmh = app.proxy.rideSpeedKmh ?? 0;
    // ETA à partir de la vitesse moyenne récente.
    final etaS = avgKmh > 0.1 ? (remaining / 1000) / avgKmh * 3600 : null;
    // Dénivelé fait/restant.
    var climbed = 0.0, remainingClimb = 0.0;
    double? lastEl;
    for (final p in run.route.points) {
      if (lastEl != null) {
        final dd = p.elevation - lastEl;
        if (dd > 0) {
          if (p.distance <= done) {
            climbed += dd;
          } else {
            remainingClimb += dd;
          }
        }
      }
      lastEl = p.elevation;
    }

    String km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');
    String mm(int s) {
      final h = s ~/ 3600, m = (s % 3600) ~/ 60, ss = s % 60;
      if (h > 0) return '$h:${m.toString().padLeft(2, '0')}';
      return '$m:${ss.toString().padLeft(2, '0')}';
    }

    Widget tile(String v, String unit) => Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(unit, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );

    final tiles = <Widget>[
      tile('${km(done)} / ${km(total)}', tr('km')),
      tile(mm(elapsed), tr('temps')),
      tile(kmh.toStringAsFixed(1).replaceAll('.', ','), tr('km/h')),
      tile(avgKmh.toStringAsFixed(1).replaceAll('.', ','), tr('moy. km/h')),
      tile('${climbed.round()} / ${remainingClimb.round()}', tr('D+ fait/reste')),
      tile(run.grade.toStringAsFixed(1).replaceAll('.', ','), tr('pente %')),
      tile(etaS == null ? '–' : mm(etaS.round()), tr('ETA')),
      tile('${d.power ?? '–'}', tr('watts')),
      tile('${d.cadence?.round() ?? '–'}', tr('tr/min')),
      if (app.heartRate.bpm.value != null) tile('${app.heartRate.bpm.value}', 'bpm'),
      if (run.ghostGap != null) tile('${run.ghostGap! <= 0 ? '−' : '+'}${run.ghostGap!.abs()} s', tr('fantôme')),
    ];
    return GridView.count(
      crossAxisCount: 3,
      childAspectRatio: 1.8,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

/// Carte interactive (pan + zoom) pour le plein écran. Marche sans réseau (simple fond uni + trace).
class _InteractiveRouteMap extends StatelessWidget {
  final GpxRoute route;
  final double distance;
  const _InteractiveRouteMap({required this.route, required this.distance});

  @override
  Widget build(BuildContext context) {
    final pts = <LatLng>[
      for (final p in route.points)
        if (p.lat != null && p.lon != null) LatLng(p.lat!, p.lon!),
    ];
    if (pts.length < 2) return const SizedBox.shrink();
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final here = route.latLonAt(distance);
    final hereLL = here == null ? null : LatLng(here.$1, here.$2);
    final cs = Theme.of(context).colorScheme;
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
          padding: const EdgeInsets.all(30),
        ),
        backgroundColor: cs.surfaceContainerHighest,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.shiftlink',
          maxZoom: 19,
          errorTileCallback: (_, _, _) {},
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: pts,
              color: Brand.orange,
              strokeWidth: 5,
              borderColor: Colors.white,
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        if (hereLL != null)
          MarkerLayer(
            markers: [
              Marker(
                point: hereLL,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    color: Brand.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('© OpenStreetMap')],
          alignment: AttributionAlignment.bottomLeft,
        ),
      ],
    );
  }
}

/// Kilos au dixième si besoin : « 9 » ou « 8,7 ».
String _kgText(double kg) {
  final tenth = (kg * 10).round() / 10;
  return tenth == tenth.roundToDouble() ? '${tenth.round()}' : tenth.toStringAsFixed(1).replaceAll('.', ',');
}


/// Séance au cardio : battements actuels et zone visée.
class _HeartTarget extends StatelessWidget {
  final WorkoutRun run;
  final int? bpm;
  const _HeartTarget({required this.run, required this.bpm});

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = run.hrTarget!;
    final b = bpm;
    final missing = run.noHeartRate || b == null;
    final color = missing
        ? Tones.orange
        : b > hi
        ? Tones.red
        : b < lo
        ? Tones.blue
        : Tones.green;
    final text = missing
        ? tr('Pas de cardio reçu : les watts restent fixes.')
        : b > hi
        ? tr('Cœur {0} bpm, visé {1} à {2} : ShiftLink baisse les watts.', [b, lo, hi])
        : b < lo
        ? tr('Cœur {0} bpm, visé {1} à {2} : ShiftLink monte les watts.', [b, lo, hi])
        : tr('Cœur {0} bpm, dans la zone ({1} à {2}).', [b, lo, hi]);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(Icons.favorite_rounded, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
