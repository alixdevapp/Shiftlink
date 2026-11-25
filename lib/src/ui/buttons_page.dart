// Réglage des boutons d'une manette : une action par geste, combinaisons de
// deux boutons, délais des gestes et test en direct.
import 'package:flutter/material.dart';

import '../actions.dart';
import '../app_state.dart';
import '../controller_manager.dart';
import '../controllers/driver.dart';
import '../gestures.dart';
import '../i18n.dart';
import 'brand.dart';

class ButtonsPage extends StatefulWidget {
  final AppState app;
  final ConnectedController controller;
  const ButtonsPage({super.key, required this.app, required this.controller});

  @override
  State<ButtonsPage> createState() => _ButtonsPageState();
}

class _ButtonsPageState extends State<ButtonsPage> {
  AppState get app => widget.app;
  ControllerDriver get driver => widget.controller.driver;

  /// Boutons sans action affichés quand même (appuyés ou choisis dans « Autres boutons »).
  final Set<String> _revealed = {};
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    app.buttonActivity.addListener(_onActivity);
  }

  @override
  void dispose() {
    app.buttonActivity.removeListener(_onActivity);
    super.dispose();
  }

  /// Un appui sur la vraie manette ouvre la carte de ce bouton.
  void _onActivity() {
    final act = app.buttonActivity.value;
    if (act == null || !act.down || act.driver.typeId != driver.typeId) return;
    if (!_isUsed(act.buttonId) && _revealed.add(act.buttonId)) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[act.buttonId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.3);
      }
    });
  }

  List<Gesture> get _gestures => [Gesture.click, Gesture.double, if (driver.reportsRelease) Gesture.long];

  bool _isUsed(String id) => _gestures.any((g) => app.keymap.actionFor(driver, id, g) != null);

  Future<void> _choose(ControllerButton b, Gesture g) async {
    final picked = await _pickAction('${b.label} · ${g.label}', app.keymap.actionFor(driver, b.id, g));
    if (picked == null) return;
    await app.keymap.set(driver, b.id, g, picked.$1);
    setState(() {});
  }

  Future<void> _chooseCombo(String a, String b) async {
    final title = '${driver.labelOf(a)} + ${driver.labelOf(b)}';
    final picked = await _pickAction(title, app.keymap.comboFor(driver, a, b));
    if (picked == null) return;
    await app.keymap.setCombo(driver, a, b, picked.$1);
    setState(() {});
  }

  Future<void> _addCombo() async {
    final pair = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (c) => _ComboPicker(buttons: driver.buttons),
    );
    if (pair != null) await _chooseCombo(pair.$1, pair.$2);
  }

  /// Choix d'une action. Renvoie null si on ferme sans choisir, (null,) pour « Rien ».
  Future<(ShiftAction?,)?> _pickAction(String title, ShiftAction? current) {
    final supported = app.supportedActions;
    return showModalBottomSheet<(ShiftAction?,)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(c).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(tr('Rien')),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, (null,)),
            ),
            for (final group in ActionGroup.values)
              if (ShiftAction.values.any((a) => a.group == group && supported.contains(a))) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    group.label.toUpperCase(),
                    style: Theme.of(c).textTheme.labelMedium?.copyWith(letterSpacing: 1.2),
                  ),
                ),
                for (final a in ShiftAction.values)
                  if (a.group == group && supported.contains(a))
                    ListTile(
                      leading: Icon(a.icon),
                      title: Text(a.label),
                      subtitle: a.isPhone ? Text(tr('Demande l’accessibilité ShiftLink')) : null,
                      trailing: a == current ? const Icon(Icons.check, color: Brand.orange) : null,
                      onTap: () => Navigator.pop(c, (a,)),
                    ),
              ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shown = [
      for (final b in driver.buttons)
        if (_isUsed(b.id) || _revealed.contains(b.id)) b,
    ];
    final hidden = driver.buttons.where((b) => !shown.contains(b)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.controller.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(tr('Réglage pour {0} · {1}', [app.target.label, driver.label]), style: text.bodyMedium),
          const SizedBox(height: 12),
          _LiveBanner(app: app, driver: driver),
          const SizedBox(height: 12),
          if (!driver.reportsRelease)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(tr('Cette manette ne signale pas quand on relâche un bouton : pas d’appui long.')),
            ),
          Text(
            tr('Appuie sur un bouton de ta manette pour le régler.'),
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder(
            valueListenable: app.buttonActivity,
            builder: (context, act, _) => Column(
              children: [
                for (final b in shown)
                  _ButtonCard(
                    key: _keys.putIfAbsent(b.id, GlobalKey.new),
                    button: b,
                    pressed: act != null && act.down && act.driver.typeId == driver.typeId && act.buttonId == b.id,
                    rows: [
                      for (final g in _gestures)
                        if (g == Gesture.click || app.keymap.actionFor(driver, b.id, g) != null)
                          _GestureRow(
                            gesture: g,
                            action: app.keymap.actionFor(driver, b.id, g),
                            onTap: () => _choose(b, g),
                          ),
                    ],
                    extra: [
                      for (final g in _gestures)
                        if (g != Gesture.click && app.keymap.actionFor(driver, b.id, g) == null)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(g.label),
                            onPressed: () => _choose(b, g),
                          ),
                    ],
                  ),
              ],
            ),
          ),
          if (hidden.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                shape: const Border(),
                title: Text(tr('Autres boutons ({0})', [hidden.length])),
                subtitle: Text(tr('Sans action pour le moment')),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedAlignment: Alignment.centerLeft,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in hidden)
                        ActionChip(label: Text(b.label), onPressed: () => setState(() => _revealed.add(b.id))),
                    ],
                  ),
                ],
              ),
            ),
          if (driver.reportsRelease && driver.buttons.length > 1) ...[
            const SizedBox(height: 8),
            _CombosCard(
              combos: app.keymap.combos(driver),
              labelOf: driver.labelOf,
              onEdit: (id) {
                final ids = GestureEngine.comboParts(id);
                _chooseCombo(ids[0], ids[1]);
              },
              onAdd: _addCombo,
            ),
          ],
          const SizedBox(height: 8),
          _TimingsCard(app: app, showLong: driver.reportsRelease),
          const SizedBox(height: 8),
          Text(
            tr(
              'Astuce : un double clic ou une combinaison retarde le clic simple de ce bouton jusqu’au relâchement. Les vitesses se répètent si tu gardes le bouton appuyé.',
            ),
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (app.keymap.isCustom(driver))
            OutlinedButton.icon(
              onPressed: () async {
                await app.keymap.reset(driver);
                setState(() {});
              },
              icon: const Icon(Icons.restart_alt),
              label: Text(tr('Revenir aux réglages par défaut')),
            ),
        ],
      ),
    );
  }
}

/// Dernière action déclenchée, pour tester sans quitter l'écran.
class _LiveBanner extends StatelessWidget {
  final AppState app;
  final ControllerDriver driver;
  const _LiveBanner({required this.app, required this.driver});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: app.lastFired,
      builder: (context, f, _) {
        final mine = f != null && f.driver.typeId == driver.typeId;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: mine ? Brand.gradient : null,
            color: mine ? null : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(mine ? f.action.icon : Icons.touch_app, color: mine ? Colors.white : null, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mine
                      ? tr('{0}\n{1} sur « {2} »', [f.action.label, f.gesture.label, f.buttonLabel])
                      : tr('Appuie sur un bouton de ta manette : il s’allume ci-dessous et l’action s’affiche ici.'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
                    color: mine ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ButtonCard extends StatelessWidget {
  final ControllerButton button;
  final bool pressed;
  final List<Widget> rows;
  final List<Widget> extra;
  const _ButtonCard({
    super.key,
    required this.button,
    required this.pressed,
    required this.rows,
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pressed ? Brand.orange : Colors.transparent, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.radio_button_checked,
                size: 18,
                color: pressed ? Brand.orange : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: 8),
              Text(button.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ...rows,
          if (extra.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Wrap(spacing: 8, runSpacing: 4, children: extra),
            ),
        ],
      ),
    );
  }
}

class _GestureRow extends StatelessWidget {
  final Gesture gesture;
  final ShiftAction? action;
  final VoidCallback onTap;
  const _GestureRow({required this.gesture, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(gesture.label, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: Row(
                children: [
                  if (action != null) ...[Icon(action!.icon, size: 18), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      action?.label ?? tr('Rien'),
                      style: TextStyle(
                        fontWeight: action != null ? FontWeight.w600 : FontWeight.w400,
                        color: action != null ? null : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Combinaisons de deux boutons appuyés ensemble.
class _CombosCard extends StatelessWidget {
  final Map<String, ShiftAction> combos;
  final String Function(String) labelOf;
  final void Function(String comboId) onEdit;
  final VoidCallback onAdd;
  const _CombosCard({required this.combos, required this.labelOf, required this.onEdit, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.join_inner, size: 18),
              const SizedBox(width: 8),
              Text(tr('Combinaisons'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('Deux boutons appuyés en même temps déclenchent une action à part.'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          for (final e in combos.entries)
            InkWell(
              key: ValueKey('combo-${e.key}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => onEdit(e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        GestureEngine.comboParts(e.key).map(labelOf).join(' + '),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    Icon(e.value.icon, size: 18),
                    const SizedBox(width: 6),
                    Text(e.value.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(tr('Ajouter une combinaison'))),
        ],
      ),
    );
  }
}

/// Choix des deux boutons d'une combinaison.
class _ComboPicker extends StatefulWidget {
  final List<ControllerButton> buttons;
  const _ComboPicker({required this.buttons});

  @override
  State<_ComboPicker> createState() => _ComboPickerState();
}

class _ComboPickerState extends State<_ComboPicker> {
  final List<String> _picked = [];

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id)) {
      if (_picked.length == 2) _picked.removeAt(0);
      _picked.add(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Choisis deux boutons'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in widget.buttons)
                FilterChip(label: Text(b.label), selected: _picked.contains(b.id), onSelected: (_) => _toggle(b.id)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _picked.length == 2 ? () => Navigator.pop(context, (_picked[0], _picked[1])) : null,
              child: Text(tr('Choisir l’action')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Délais du double clic et de l'appui long.
class _TimingsCard extends StatelessWidget {
  final AppState app;
  final bool showLong;
  const _TimingsCard({required this.app, required this.showLong});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Container(
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tr('Délais des gestes'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            _TimingSlider(
              label: tr('Double clic'),
              hint: tr('Le temps pour appuyer deux fois. Plus court, le clic simple réagit plus vite.'),
              value: app.doubleClickMs,
              min: 150,
              max: 600,
              onChanged: (v) => app.setGestureTimings(doubleClick: v),
            ),
            if (showLong)
              _TimingSlider(
                label: tr('Appui long'),
                hint: tr('Combien de temps tu gardes le bouton appuyé.'),
                value: app.longPressMs,
                min: 300,
                max: 1200,
                onChanged: (v) => app.setGestureTimings(longPress: v),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimingSlider extends StatelessWidget {
  final String label;
  final String hint;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _TimingSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${(v / 1000).toStringAsFixed(2).replaceAll('.', ',')} s'),
            ],
          ),
          Text(hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          Slider(
            value: v.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ 50,
            label: '$v ms',
            onChanged: (x) => onChanged(x.round()),
          ),
        ],
      ),
    );
  }
}
