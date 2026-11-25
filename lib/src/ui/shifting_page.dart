// Réglage des vitesses virtuelles ShiftLink : cassette, plateaux, sensation.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../trainer/gears.dart';
import 'brand.dart';
import 'trainer_tools.dart';
import 'widgets.dart';

class ShiftingPage extends StatefulWidget {
  final AppState app;
  const ShiftingPage({super.key, required this.app});

  @override
  State<ShiftingPage> createState() => _ShiftingPageState();
}

class _ShiftingPageState extends State<ShiftingPage> {
  AppState get app => widget.app;
  late ShiftingConfig c = app.shifting;

  Future<void> _set(ShiftingConfig next) async {
    setState(() => c = next);
    await app.setShifting(next);
  }

  /// Petite explication grise sous un réglage.
  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );

  Widget _section(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    ),
  );

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton.filledTonal(
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton.filledTonal(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
    ],
  );

  static Map<String, String> get _presetHelp => {
    'classic': tr('Polyvalent : des écarts réguliers, du très facile au très dur.'),
    'road12': tr('Comme un vélo de route récent, avec un petit plateau pour les cols.'),
    'road12_30': tr('Vélo de route récent, écarts serrés : idéal sur le plat.'),
    'road11': tr('Comme un vélo de route classique.'),
    'road11_30': tr('Vélo de route classique, un peu plus souple dans les bosses.'),
    'road11_32': tr('Vélo de route classique, avec un grand pignon pour les cols.'),
    'gravel': tr('Plus de vitesses faciles, pour les longues montées.'),
    'mtb': tr('Le plus de vitesses faciles, pour les pentes très raides.'),
  };

  String _controlHint() {
    final caps = app.proxy.trainer.caps.value;
    final used = tr(ShiftingConfig.controls[app.proxy.control] ?? '');
    final known = app.proxy.trainer.isConnected
        ? tr(' Ton trainer accepte : {0}. Utilisé : {1}.', [caps.describe(), used])
        : '';
    return tr(
      'Comment ShiftLink demande l’effort au trainer. Laisse « Auto » si tu ne sais pas. Pente : comme sur la route. Puissance : un nombre de watts pour chaque vitesse. Résistance : pour les trainers simples.{0}',
      [known],
    );
  }

  Future<void> _saveProfile() async {
    final ctl = TextEditingController(text: app.activeShiftProfile ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Nom du profil')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Montagne, sprint, VTT…')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await app.saveShiftProfile(name.trim());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final gears = VirtualGears(config: c);
    final preset = gearPresets.where((p) => p.id == c.presetId).firstOrNull;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Vitesses virtuelles'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('{0} vitesses, de très facile à très dur', [gears.count]),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(
                    tr('Chaque tour de pédale fait avancer de {0} à {1} m', [
                      gears.development(1).toStringAsFixed(1),
                      gears.development(gears.count).toStringAsFixed(1),
                    ]).replaceAll('.', ','),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 150, child: GearCurve(gears: gears)),
                  const SizedBox(height: 8),
                  Text(
                    tr('Le trait pointillé est la vitesse où le trainer reste tel que l’appli le règle.'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          _section(
            tr('Profils'),
            tr('Garde plusieurs réglages (« montagne », « sprint »…). Le dernier choisi est repris avec ce trainer.'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in app.shiftProfileNames)
                InputChip(
                  label: Text(name),
                  selected: name == app.activeShiftProfile,
                  onPressed: () async {
                    await app.loadShiftProfile(name);
                    setState(() => c = app.shifting);
                  },
                  onDeleted: () async {
                    await app.deleteShiftProfile(name);
                    setState(() {});
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(tr('Enregistrer…')),
                onPressed: _saveProfile,
              ),
            ],
          ),
          _section(tr('Ce que fait le trainer'), tr('Comment l’effort change à chaque vitesse.')),
          _ModeCards(
            selected: c.control,
            effective: app.proxy.active ? app.proxy.control : null,
            onSelected: (v) => _set(c.copyWith(control: v)),
          ),
          _section(tr('Type de vitesses'), tr('Choisis selon ton terrain. Tu peux changer quand tu veux.')),
          RadioGroup<String>(
            groupValue: c.custom ? 'custom' : c.presetId,
            onChanged: (id) {
              if (id == 'custom') {
                _set(
                  c.copyWith(
                    presetId: 'custom',
                    ratios: gears.allRatios,
                    smallRing: c.smallRing > 0 ? c.smallRing : 34,
                  ),
                );
              } else if (gearPresets.where((p) => p.id == id).firstOrNull case final p?) {
                _set(ShiftingConfig.fromPreset(p, c));
              }
            },
            child: Column(
              children: [
                for (final p in gearPresets)
                  RadioListTile<String>(
                    value: p.id,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_presetHelp[p.id] ?? ''),
                  ),
                RadioListTile<String>(
                  value: 'custom',
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Personnalisée'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('Tu règles chaque vitesse toi-même.')),
                ),
              ],
            ),
          ),
          if (c.custom) GearEditor(config: c, onChanged: _set),
          if (c.custom) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Double plateau')),
              subtitle: Text(
                tr('Petit plateau : {0} dents pour {1} (résistance × {2})', [
                  c.smallRing,
                  c.ring,
                  (c.smallRing / c.ring).toStringAsFixed(2).replaceAll('.', ','),
                ]),
              ),
              value: c.doubleRing,
              onChanged: (v) => _set(c.copyWith(doubleRing: v)),
            ),
            if (c.doubleRing)
              _stepper(tr('Petit plateau'), c.smallRing, 20, c.ring - 1, (v) => _set(c.copyWith(smallRing: v))),
          ],
          if (!c.custom && (preset?.smallRing ?? 0) > 0) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Double plateau')),
              subtitle: Text(tr('Une action « Changer de plateau » passe sur le petit plateau')),
              value: c.doubleRing,
              onChanged: (v) => _set(c.copyWith(doubleRing: v)),
            ),
            if (c.doubleRing)
              _stepper(tr('Petit plateau'), c.smallRing, 20, c.ring - 1, (v) => _set(c.copyWith(smallRing: v))),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Vitesses infinies')),
            subtitle: Text(tr('Chaque appui ajoute ou enlève 0,5 % de pente (5 W en ERG), sans jamais de butée.')),
            value: c.infinite,
            onChanged: (v) => _set(c.copyWith(infinite: v)),
          ),
          _section(tr('Sensation'), tr('Ce que tu ressens dans les jambes.')),
          Text(tr('Dureté des montées : {0} %', [(c.difficulty * 100).round()])),
          _help(tr('Plus bas, les côtes sont plus faciles. 100 % = comme en vrai.')),
          Slider(
            value: c.difficulty,
            min: 0.3,
            max: 1.5,
            divisions: 12,
            label: '${(c.difficulty * 100).round()} %',
            onChanged: (v) => setState(() => c = c.copyWith(difficulty: v)),
            onChangeEnd: (v) => _set(c.copyWith(difficulty: v)),
          ),
          Text(tr('Poids cycliste + vélo : {0} kg', [c.totalKg.round()])),
          _help(tr('Ton poids avec le vélo. Plus il est lourd, plus les côtes sont dures.')),
          Slider(
            value: c.totalKg,
            min: 45,
            max: 140,
            divisions: 95,
            label: '${c.totalKg.round()} kg',
            onChanged: (v) => setState(() => c = c.copyWith(totalKg: v)),
            onChangeEnd: (v) => _set(c.copyWith(totalKg: v)),
          ),
          _section(tr('À chaque vitesse')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Vibration')),
            subtitle: Text(tr('Le téléphone vibre à chaque vitesse, plus fort quand tu ne peux pas aller plus loin.')),
            value: c.vibrate,
            onChanged: (v) => _set(c.copyWith(vibrate: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Son')),
            subtitle: Text(tr('Un petit bip à chaque vitesse, un bip différent à la dernière.')),
            value: c.sound,
            onChanged: (v) => _set(c.copyWith(sound: v)),
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              shape: const Border(),
              title: Text(tr('Réglages avancés'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Pour les experts. Pas besoin d’y toucher pour rouler.')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!c.classic && !c.custom) ...[
                  _section(
                    tr('Tes pignons virtuels'),
                    tr('Le nombre de dents de chaque pignon. Plus il y a de dents, plus c’est facile.'),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final t in c.cogs) Chip(label: Text('$t'), visualDensity: VisualDensity.compact)],
                  ),
                  const SizedBox(height: 8),
                  _stepper(tr('Grand plateau'), c.ring, 20, 60, (v) => _set(c.copyWith(ring: v))),
                ],
                _section(
                  tr('Ton vélo sur le trainer'),
                  tr(
                    'La vitesse que tu laisses sur ton vrai vélo pendant la séance. Compte les dents de la roue dentée devant (plateau) et derrière (pignon).',
                  ),
                ),
                _stepper(tr('Plateau (devant)'), c.realRing, 20, 60, (v) => _set(c.copyWith(realRing: v))),
                _stepper(tr('Pignon (derrière)'), c.realCog, 10, 52, (v) => _set(c.copyWith(realCog: v))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Adoucir les changements de pente')),
                  subtitle: Text(tr('Évite les à-coups quand la pente change brusquement')),
                  value: c.smoothing,
                  onChanged: (v) => _set(c.copyWith(smoothing: v)),
                ),
                _section(tr('Pilotage du trainer'), _controlHint()),
                SegmentedButton<String>(
                  segments: [
                    for (final e in ShiftingConfig.controls.entries)
                      ButtonSegment(value: e.key, label: Text(tr(e.value))),
                  ],
                  selected: {c.control},
                  onSelectionChanged: (v) => _set(c.copyWith(control: v.first)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Filtre de cadence')),
                  subtitle: Text(tr('Évite les à-coups si ton trainer mesure mal ta vitesse de pédalage.')),
                  value: c.cadenceFilter,
                  onChanged: (v) => _set(c.copyWith(cadenceFilter: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Simple relais')),
                  subtitle: Text(
                    tr(
                      'ShiftLink ne change plus les vitesses : il transmet juste ton trainer à l’appli. Utile si ton trainer n’a que le Bluetooth et ton appli que le Wi-Fi.',
                    ),
                  ),
                  value: c.relay,
                  onChanged: (v) => _set(c.copyWith(relay: v)),
                ),
                _section(
                  tr('Séance à watts fixes (ERG)'),
                  tr(
                    'Quand l’appli impose des watts, « Intensité + » et « Intensité − » ajoutent ou retirent ce nombre de watts.',
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 W')),
                    ButtonSegment(value: 5, label: Text('5 W')),
                    ButtonSegment(value: 10, label: Text('10 W')),
                    ButtonSegment(value: 25, label: Text('25 W')),
                  ],
                  selected: {c.ergStep},
                  onSelectionChanged: (v) => _set(c.copyWith(ergStep: v.first)),
                ),
                _section(
                  tr('ERG sans appli'),
                  tr('Sans appli connectée, « Intensité + » démarre un ERG. Il part de :'),
                ),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'last', label: Text(tr('Dernière cible'))),
                    ButtonSegment(value: 'current', label: Text(tr('Ma puissance'))),
                  ],
                  selected: {c.ergStart},
                  onSelectionChanged: (v) => _set(c.copyWith(ergStart: v.first)),
                ),
                _section(
                  tr('Power Lock'),
                  tr('L’action « Power Lock » garde tes watts du moment, même quand la route monte. Un nouvel appui relâche.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Relâcher quand j’arrête de pédaler')),
                  subtitle: Text(tr('Tu ne repars pas contre un mur de résistance.')),
                  value: c.powerLockRelease,
                  onChanged: (v) => _set(c.copyWith(powerLockRelease: v)),
                ),
                const SizedBox(height: 8),
                StaircaseButton(app: widget.app),
              ],
            ),
          ),
          const SizedBox(height: 8),
          HintBox(
            text: tr(
              'Trop dur partout ? Baisse la dureté des montées. Pas assez de vitesses faciles ? Choisis Gravel ou VTT.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _set(const ShiftingConfig()),
            icon: const Icon(Icons.restart_alt),
            label: Text(tr('Revenir aux réglages par défaut')),
          ),
        ],
      ),
    );
  }
}

/// Développement de chaque vitesse, avec le braquet réel en pointillé.
class GearCurve extends StatelessWidget {
  final VirtualGears gears;
  const GearCurve({super.key, required this.gears});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _GearCurvePainter(gears, Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _GearCurvePainter extends CustomPainter {
  final VirtualGears g;
  final Color muted;
  _GearCurvePainter(this.g, this.muted);

  @override
  void paint(Canvas canvas, Size size) {
    final n = g.count;
    final maxDev = g.development(n) * 1.08;
    const labelH = 16.0;
    final h = size.height - labelH;
    final slot = size.width / n;
    final bar = slot * 0.62;
    final paint = Paint()..shader = Brand.gradient.createShader(Offset.zero & size);
    for (var i = 1; i <= n; i++) {
      final v = g.development(i);
      final top = h - h * v / maxDev;
      final x = slot * (i - 1) + (slot - bar) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, top, bar, h - top),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
      if (n <= 12 || i == 1 || i == n || i % 4 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(color: muted, fontSize: 11, fontFamily: Brand.font),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + bar / 2 - tp.width / 2, h + 3));
      }
    }
    final realY = h - h * g.realRatio * ShiftingConfig.wheelMeters / maxDev;
    final dash = Paint()
      ..color = muted
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, realY), Offset(x + 4, realY), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _GearCurvePainter old) => true;
}

/// Édition des vitesses une par une : touche une barre, glisse pour la régler.
class GearEditor extends StatefulWidget {
  final ShiftingConfig config;
  final ValueChanged<ShiftingConfig> onChanged;
  const GearEditor({super.key, required this.config, required this.onChanged});

  @override
  State<GearEditor> createState() => _GearEditorState();
}

class _GearEditorState extends State<GearEditor> {
  int selected = 0;
  double? _scale; // braquet maximal affiché, figé pendant un glissement
  double _drag = 0;

  List<double> get ratios => widget.config.ratios;

  void _setRatios(List<double> r) => widget.onChanged(widget.config.copyWith(ratios: r));

  void _nudge(int i, double delta) {
    final r = [...ratios];
    r[i] = double.parse((r[i] + delta).clamp(0.3, 7.0).toStringAsFixed(2));
    _setRatios(r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = ratios.length;
    final sel = selected.clamp(0, n - 1);
    final top = _scale ?? (ratios.reduce((a, b) => a > b ? a : b) * 1.15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            const h = 140.0;
            int indexAt(double dx) => (dx / (box.maxWidth / n)).floor().clamp(0, n - 1);
            return GestureDetector(
              onTapDown: (d) => setState(() => selected = indexAt(d.localPosition.dx)),
              onVerticalDragStart: (d) => setState(() {
                selected = indexAt(d.localPosition.dx);
                _scale = top;
                _drag = 0;
              }),
              onVerticalDragUpdate: (d) {
                _drag += -d.delta.dy / h * top;
                final steps = (_drag / 0.05).truncate();
                if (steps != 0) {
                  _drag -= steps * 0.05;
                  _nudge(selected, steps * 0.05);
                }
              },
              onVerticalDragEnd: (_) => setState(() => _scale = null),
              child: SizedBox(
                height: h,
                child: CustomPaint(size: Size.infinite, painter: _RatioPainter(ratios, sel, top, cs)),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          tr('Touche une barre puis glisse vers le haut ou le bas (pas de 0,05).'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Vitesse {0} : {1} · {2} m', [
                  sel + 1,
                  ratios[sel].toStringAsFixed(2).replaceAll('.', ','),
                  (ratios[sel] * ShiftingConfig.wheelMeters).toStringAsFixed(1).replaceAll('.', ','),
                ]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton.filledTonal(onPressed: () => _nudge(sel, -0.05), icon: const Icon(Icons.remove)),
            const SizedBox(width: 6),
            IconButton.filledTonal(onPressed: () => _nudge(sel, 0.05), icon: const Icon(Icons.add)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(tr('{0} vitesses', [n]))),
            TextButton.icon(
              onPressed: n > 1
                  ? () {
                      _setRatios([...ratios]..removeAt(sel));
                      setState(() => selected = (sel - 1).clamp(0, n - 2));
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              label: Text(tr('Retirer')),
            ),
            TextButton.icon(
              onPressed: n < ShiftingConfig.maxGears
                  ? () {
                      // Nouvelle vitesse juste après la sélection, à mi-chemin de la suivante.
                      final next = sel + 1 < n ? ratios[sel + 1] : ratios[sel] * 1.12;
                      final v = double.parse(((ratios[sel] + next) / 2).toStringAsFixed(2));
                      _setRatios([...ratios]..insert(sel + 1, v));
                      setState(() => selected = sel + 1);
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(tr('Ajouter')),
            ),
          ],
        ),
      ],
    );
  }
}

class _RatioPainter extends CustomPainter {
  final List<double> ratios;
  final int selected;
  final double top;
  final ColorScheme cs;
  _RatioPainter(this.ratios, this.selected, this.top, this.cs);

  @override
  void paint(Canvas canvas, Size size) {
    final n = ratios.length;
    const labelH = 16.0;
    final h = size.height - labelH;
    final slot = size.width / n;
    final bar = slot * 0.66;
    final grad = Paint()..shader = Brand.gradient.createShader(Offset.zero & size);
    for (var i = 0; i < n; i++) {
      final t = h - h * (ratios[i] / top).clamp(0.0, 1.0);
      final x = slot * i + (slot - bar) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, t, bar, h - t),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, i == selected ? (Paint()..color = cs.onSurface) : grad);
      if (n <= 12 || i == 0 || i == n - 1 || (i + 1) % 4 == 0 || i == selected) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: i == selected ? cs.onSurface : cs.onSurfaceVariant,
              fontSize: 11,
              fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
              fontFamily: Brand.font,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + bar / 2 - tp.width / 2, h + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RatioPainter old) => true;
}


/// Choix du mode en trois grandes cartes. « Auto » reste dans les réglages avancés.
class _ModeCards extends StatelessWidget {
  final String selected;
  final String? effective;
  final ValueChanged<String> onSelected;
  const _ModeCards({required this.selected, required this.effective, required this.onSelected});

  static const _modes = [
    ('power', Icons.gps_fixed_rounded, 'Puissance imposée', 'Des watts précis pour chaque vitesse'),
    ('grade', Icons.trending_up_rounded, 'Suit la pente', 'Comme sur la route'),
    ('resistance', Icons.horizontal_rule_rounded, 'Simple', 'Pour les trainers de base'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (id, icon, title, sub) in _modes)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Builder(
                builder: (context) {
                  final on = selected == id;
                  final auto = selected == 'auto' && effective == id;
                  return Semantics(
                    selected: on,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(id),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 128),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: on ? cs.primaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: on || auto ? cs.primary : Colors.transparent, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: on ? cs.primary : cs.onSurfaceVariant),
                            const SizedBox(height: 6),
                            Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              auto ? tr('Choisi par Auto') : tr(sub),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
