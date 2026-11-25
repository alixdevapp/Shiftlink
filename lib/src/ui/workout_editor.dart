// Créer ou modifier sa propre séance : des blocs (durée, % de la FTP), sans fichier.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../trainer/workout.dart';
import 'brand.dart';
import 'ride_extras.dart';
import 'widgets.dart';

/// Un bloc en cours d'édition.
class _Block {
  int seconds;
  int from; // % de la FTP
  int to;
  _Block(this.seconds, this.from, [int? to]) : to = to ?? from;
  bool get ramp => from != to;
  _Block copy() => _Block(seconds, from, to);
  WorkoutStep get step => WorkoutStep(seconds, from / 100, to / 100);
}

class WorkoutEditorPage extends StatefulWidget {
  final AppState app;

  /// Séance à modifier (null : nouvelle séance).
  final Workout? original;
  const WorkoutEditorPage({super.key, required this.app, this.original});

  @override
  State<WorkoutEditorPage> createState() => _WorkoutEditorPageState();
}

class _WorkoutEditorPageState extends State<WorkoutEditorPage> {
  late final TextEditingController _name;
  late final List<_Block> _blocks;

  int get _ftp => widget.app.ftp;

  @override
  void initState() {
    super.initState();
    final w = widget.original;
    _name = TextEditingController(text: w?.name ?? tr('Ma séance'));
    _blocks = w == null
        ? [_Block(600, 50, 75), _Block(300, 100), _Block(300, 55), _Block(300, 100), _Block(600, 60, 45)]
        : [for (final s in w.steps) _Block(s.seconds, (s.from * 100).round(), (s.to * 100).round())];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Workout get _workout => Workout(_name.text.trim().isEmpty ? tr('Ma séance') : _name.text.trim(), [
    for (final b in _blocks) b.step,
  ], description: tr('Créée dans ShiftLink'));

  int _watts(int percent) => (percent * _ftp / 100).round();

  Future<void> _save() async {
    if (_blocks.isEmpty) return;
    final w = _workout;
    final old = widget.original;
    if (old != null && old.name != w.name) await widget.app.deleteWorkout(old.name);
    final ok = await widget.app.addWorkout(w);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Trop de séances : supprimes-en une.'))));
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _addSeries() async {
    var count = 5, on = 180, off = 120, onPct = 110, offPct = 55;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Ajouter une série')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Stepper(
                label: tr('Répétitions'),
                value: '$count',
                onMinus: () => set(() => count = (count - 1).clamp(1, 30)),
                onPlus: () => set(() => count = (count + 1).clamp(1, 30)),
              ),
              _Stepper(
                label: tr('Effort'),
                value: '${clock(on)} · $onPct %',
                onMinus: () => set(() => on = (on - 15).clamp(15, 3600)),
                onPlus: () => set(() => on = (on + 15).clamp(15, 3600)),
              ),
              _Stepper(
                label: tr('Intensité de l’effort'),
                value: '$onPct % · ${_watts(onPct)} W',
                onMinus: () => set(() => onPct = (onPct - 5).clamp(30, 250)),
                onPlus: () => set(() => onPct = (onPct + 5).clamp(30, 250)),
              ),
              _Stepper(
                label: tr('Récupération'),
                value: clock(off),
                onMinus: () => set(() => off = (off - 15).clamp(15, 3600)),
                onPlus: () => set(() => off = (off + 15).clamp(15, 3600)),
              ),
              _Stepper(
                label: tr('Intensité de la récupération'),
                value: '$offPct % · ${_watts(offPct)} W',
                onMinus: () => set(() => offPct = (offPct - 5).clamp(30, 250)),
                onPlus: () => set(() => offPct = (offPct + 5).clamp(30, 250)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ajouter'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      for (var i = 0; i < count && _blocks.length + 2 <= Workout.maxSteps; i++) {
        _blocks.add(_Block(on, onPct));
        _blocks.add(_Block(off, offPct));
      }
    });
  }

  void _add(_Block b) {
    if (_blocks.length >= Workout.maxSteps) return;
    setState(() => _blocks.add(b));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = _blocks.isEmpty ? null : _workout;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.original == null ? tr('Nouvelle séance') : tr('Modifier la séance')),
        actions: [TextButton(onPressed: _blocks.isEmpty ? null : _save, child: Text(tr('Enregistrer')))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(labelText: tr('Nom de la séance'), border: const OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          if (w != null) ...[
            WorkoutShape(workout: w, height: 64),
            const SizedBox(height: 6),
            Text(
              tr('{0} · {1} blocs · FTP {2} W', [clock(w.seconds), _blocks.length, _ftp]),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < _blocks.length; i++) _blockCard(i),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.trending_up_rounded, size: 18),
                label: Text(tr('Échauffement')),
                onPressed: () => _add(_Block(600, 50, 75)),
              ),
              ActionChip(
                avatar: const Icon(Icons.horizontal_rule_rounded, size: 18),
                label: Text(tr('Palier')),
                onPressed: () => _add(_Block(300, 75)),
              ),
              ActionChip(
                avatar: const Icon(Icons.bolt_rounded, size: 18),
                label: Text(tr('Effort')),
                onPressed: () => _add(_Block(180, 105)),
              ),
              ActionChip(
                avatar: const Icon(Icons.self_improvement_rounded, size: 18),
                label: Text(tr('Récupération')),
                onPressed: () => _add(_Block(120, 50)),
              ),
              ActionChip(
                avatar: const Icon(Icons.repeat_rounded, size: 18),
                label: Text(tr('Série')),
                onPressed: _addSeries,
              ),
              ActionChip(
                avatar: const Icon(Icons.trending_down_rounded, size: 18),
                label: Text(tr('Retour au calme')),
                onPressed: () => _add(_Block(600, 60, 45)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _blocks.isEmpty ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(tr('Enregistrer la séance')),
          ),
        ],
      ),
    );
  }

  Widget _blockCard(int i) {
    final b = _blocks[i];
    final f = b.from / 100;
    void edit(void Function() change) => setState(change);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 28, color: intensityColor(f)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.ramp
                        ? tr('Bloc {0} · rampe {1} → {2} %', [i + 1, b.from, b.to])
                        : tr('Bloc {0} · {1} %', [i + 1, b.from]),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: tr('Monter'),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: i == 0 ? null : () => edit(() => _blocks.insert(i - 1, _blocks.removeAt(i))),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('Plus'),
                  onSelected: (v) => edit(() {
                    switch (v) {
                      case 'copy':
                        if (_blocks.length < Workout.maxSteps) _blocks.insert(i + 1, b.copy());
                      case 'ramp':
                        b.to = b.ramp ? b.from : (b.from + 20).clamp(30, 250);
                      case 'delete':
                        _blocks.removeAt(i);
                    }
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'copy', child: Text(tr('Dupliquer'))),
                    PopupMenuItem(value: 'ramp', child: Text(b.ramp ? tr('Faire un palier') : tr('Faire une rampe'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Supprimer'))),
                  ],
                ),
              ],
            ),
            _Stepper(
              label: tr('Durée'),
              value: clock(b.seconds),
              onMinus: () => edit(() => b.seconds = (b.seconds - (b.seconds > 300 ? 60 : 15)).clamp(15, 4 * 3600)),
              onPlus: () => edit(() => b.seconds = (b.seconds + (b.seconds >= 300 ? 60 : 15)).clamp(15, 4 * 3600)),
            ),
            _Stepper(
              label: b.ramp ? tr('Début') : tr('Intensité'),
              value: '${b.from} % · ${_watts(b.from)} W',
              onMinus: () => edit(() {
                final ramp = b.ramp;
                b.from = (b.from - 5).clamp(30, 250);
                if (!ramp) b.to = b.from;
              }),
              onPlus: () => edit(() {
                final ramp = b.ramp;
                b.from = (b.from + 5).clamp(30, 250);
                if (!ramp) b.to = b.from;
              }),
            ),
            if (b.ramp)
              _Stepper(
                label: tr('Fin'),
                value: '${b.to} % · ${_watts(b.to)} W',
                onMinus: () => edit(() => b.to = (b.to - 5).clamp(30, 250)),
                onPlus: () => edit(() => b.to = (b.to + 5).clamp(30, 250)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne « libellé  [−] valeur [+] ».
class _Stepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper({required this.label, required this.value, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton(tooltip: tr('Moins'), icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: onMinus),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: Brand.font),
        ),
      ),
      IconButton(tooltip: tr('Plus'), icon: const Icon(Icons.add_circle_outline_rounded), onPressed: onPlus),
    ],
  );
}

/// Carte « ERG à puissance fixe » de l'onglet Séances.
class FixedErgCard extends StatefulWidget {
  final AppState app;
  const FixedErgCard({super.key, required this.app});

  @override
  State<FixedErgCard> createState() => _FixedErgCardState();
}

class _FixedErgCardState extends State<FixedErgCard> {
  int? _watts;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final p = app.proxy;
    return ValueListenableBuilder<int?>(
      valueListenable: p.fixedErg,
      builder: (context, running, _) {
        final watts = running ?? _watts ?? (p.lastErgTarget ?? (app.ftp * 0.6).round());
        final can = p.canRunAlone;
        void change(int delta) {
          final next = (watts + delta).clamp(30, 1500);
          if (running != null) {
            p.setFixedErg(next);
          } else {
            setState(() => _watts = next);
          }
        }

        final cs = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: Brand.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('ERG à puissance fixe'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tr('Le trainer tient ces watts, que tu pédales vite ou lentement.'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: tr('Moins'),
                      onPressed: () => change(-10),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          '$watts W',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: running != null ? 44 : 32,
                            fontWeight: FontWeight.w800,
                            color: intensityColor(watts / app.ftp),
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: tr('Plus'),
                      onPressed: () => change(10),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                Center(
                  child: Text(
                    tr('{0} % de ta FTP', [(watts * 100 / app.ftp).round()]),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: running != null
                      ? OutlinedButton.icon(
                          onPressed: p.stopFixedErg,
                          icon: const Icon(Icons.stop_rounded),
                          label: Text(tr('Arrêter l’ERG')),
                        )
                      : FilledButton.icon(
                          onPressed: can
                              ? () {
                                  if (p.startFixedErg(watts)) setState(() {});
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(tr('Démarrer l’ERG')),
                        ),
                ),
                if (!can && running == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      tr('Connecte le home trainer à ShiftLink (et pas à une appli) pour démarrer.'),
                      style: const TextStyle(color: Tones.orange),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
