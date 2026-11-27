// Appareils : appli d'entraînement, manettes, home trainer, téléphone au guidon.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../controller_manager.dart';
import '../controllers/steering_drivers.dart' show EliteRizerDriver;
import '../i18n.dart';
import '../installed_apps.dart';
import '../sensors/headwind.dart';
import '../sensors/heart_rate.dart';
import 'brand.dart';
import 'buttons_page.dart';
import 'connection_setup.dart';
import 'diagnostic_page.dart';
import 'learn_controller_page.dart';
import 'settings_page.dart' show SteeringTuner;
import 'trainer_tools.dart';
import 'widgets.dart';

/// Choix de l'appli d'entraînement dans une feuille.
Future<void> pickTarget(BuildContext context, AppState app) async {
  final t = await showModalBottomSheet<TargetApp>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                tr('Avec quelle appli tu roules ?'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            for (final t in TargetApp.pickable)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: t == app.target.base
                      ? Brand.orange.withValues(alpha: 0.12)
                      : Theme.of(c).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: TargetAppIcon(t),
                    title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(t.description), InstalledBadge(t)],
                    ),
                    trailing: t == app.target.base ? const Icon(Icons.check_circle, color: Brand.orange) : null,
                    onTap: () => Navigator.pop(c, t),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  // Même appli : on garde la variante déjà choisie.
  if (t != null && t != app.target.base) await app.setTarget(t);
}

class DevicesPage extends StatelessWidget {
  final AppState app;
  const DevicesPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.healthListenable]),
      builder: (context, _) {
        // Le téléphone au guidon a sa propre section « Direction », plus bas : l'ajouter ici
        // ferait sauter la page au moment où on active le réglage.
        final controllers = app.controllers.controllers.value.where((c) => c != app.phoneController).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SectionHeader(tr('Appli d’entraînement')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TargetAppIcon(app.target, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.target.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              if (app.target.alternative == null)
                                Text(
                                  app.target.description,
                                  style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant, height: 1.3),
                                ),
                            ],
                          ),
                        ),
                        TextButton(onPressed: () => pickTarget(context, app), child: Text(tr('Changer'))),
                      ],
                    ),
                    if (app.target.alternative case final alt?) ...[
                      const SizedBox(height: 12),
                      if (app.target.transport == Transport.proxy || alt.transport == Transport.proxy)
                        _GearsSource(app: app)
                      else
                        _LinkChoice(app: app),
                    ],
                    const SizedBox(height: 14),
                    _CollapsibleSetup(app: app),
                  ],
                ),
              ),
            ),
            SectionHeader(
              tr('Manettes'),
              trailing: app.controllers.scanning.value
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            for (final c in controllers) ...[_ControllerCard(app: app, c: c), const SizedBox(height: 10)],
            if (controllers.isEmpty) NoControllerCard(app: app),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: app.controllers.scanning.value
                  ? null
                  : () async {
                      if (await app.askPermissions()) unawaited(app.controllers.scan());
                    },
              icon: const Icon(Icons.bluetooth_searching_rounded),
              label: Text(
                app.controllers.scanning.value
                    ? tr('Recherche en cours…')
                    : (app.controllers.lastScanEmpty.value ? tr('Chercher à nouveau') : tr('Chercher une manette')),
              ),
            ),
            if (controllers.isNotEmpty)
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnControllerPage(app: app))),
                icon: const Icon(Icons.school_rounded),
                label: Text(tr('Ma manette n’est pas dans la liste')),
              ),
            const SizedBox(height: 12),
            GroupCard(
              children: [
                SettingRow.toggle(
                  icon: Icons.keyboard_rounded,
                  color: Tones.purple,
                  title: tr('Télécommandes et claviers'),
                  subtitle: tr('Télécommandes Bluetooth, manettes de jeu, claviers appairés au téléphone'),
                  value: app.captureKeys,
                  onChanged: app.setCaptureKeys,
                ),
                SettingRow.toggle(
                  icon: Icons.swap_vert_rounded,
                  color: Tones.grey,
                  title: tr('Inverser + et −'),
                  subtitle: tr('Si ta manette passe les vitesses à l’envers'),
                  value: app.invert,
                  onChanged: (v) => app.invert = v,
                ),
                SettingRow.toggle(
                  icon: Icons.ads_click_rounded,
                  color: Tones.orange,
                  title: tr('Zwift Click v2 : côté droit seul'),
                  subtitle: tr('Plus besoin de la déverrouiller dans Zwift chaque jour. + plus dur, B plus facile.'),
                  value: app.clickV2RightOnly,
                  onChanged: app.setClickV2RightOnly,
                ),
              ],
            ),
            if (app.captureKeys && !app.taps.enabled.value) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: app.taps.openSettings,
                icon: const Icon(Icons.accessibility_new_rounded),
                label: Text(tr('Activer l’accessibilité ShiftLink')),
              ),
            ],
            SectionHeader(tr('Capteurs')),
            _HeartRateCard(app: app),
            const SizedBox(height: 10),
            BikeSensorCard(app: app, sensor: app.cadenceSensor),
            const SizedBox(height: 10),
            BikeSensorCard(app: app, sensor: app.powerSensor),
            const SizedBox(height: 10),
            _FanCard(app: app),
            const SizedBox(height: 10),
            _ClimbCard(app: app),
            SectionHeader(tr('Direction')),
            GroupCard(
              children: [
                SettingRow.toggle(
                  icon: Icons.screen_rotation_alt_rounded,
                  color: Tones.teal,
                  title: tr('Tourner avec ce téléphone'),
                  subtitle: tr('Fixé au guidon, il fait tourner ton coureur. Bêta.'),
                  value: app.phoneSteering,
                  onChanged: app.setPhoneSteering,
                ),
                if (app.phoneController case final phone?)
                  SettingRow(
                    icon: Icons.touch_app_rounded,
                    color: Tones.orange,
                    title: tr('Actions de la direction'),
                    subtitle: tr('Ce que font « à gauche » et « à droite »'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ButtonsPage(app: app, controller: phone),
                      ),
                    ),
                  ),
              ],
            ),
            if (app.phoneSteering) ...[const SizedBox(height: 10), SteeringTuner(app: app)],
          ],
        );
      },
    );
  }
}

class _ControllerCard extends StatelessWidget {
  final AppState app;
  final ConnectedController c;
  const _ControllerCard({required this.app, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = c.state.value == LinkState.connected;
    final battery = c.battery.value;
    final rssi = c.rssi;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ButtonsPage(app: app, controller: c),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(
                    c.driver.typeId == 'phoneSteering'
                        ? Icons.smartphone_rounded
                        : (c.driver.typeId.startsWith('keys.') ? Icons.keyboard_rounded : Icons.gamepad_rounded),
                    connected ? Tones.green : Tones.grey,
                    size: 44,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(c.driver.label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Oublier'),
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: () => forgetOrIgnore(context, app, c),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (c.asleep)
                    InfoChip(tr('En veille'), icon: Icons.bedtime_rounded)
                  else
                    switch (c.state.value) {
                      LinkState.connected => InfoChip(tr('Connectée'), icon: Icons.circle, color: Tones.green),
                      LinkState.connecting => InfoChip(tr('Connexion…'), icon: Icons.circle, color: Tones.yellow),
                      LinkState.disconnected => InfoChip(tr('Reconnexion…'), icon: Icons.circle, color: Tones.yellow),
                    },
                  if (battery != null)
                    InfoChip(
                      '$battery %',
                      icon: battery > 60
                          ? Icons.battery_full_rounded
                          : (battery > 25 ? Icons.battery_4_bar_rounded : Icons.battery_1_bar_rounded),
                      color: battery > 25 ? null : Tones.red,
                    ),
                  if (rssi != null)
                    InfoChip(
                      rssi > -70 ? tr('Bon signal') : (rssi > -85 ? tr('Signal moyen') : tr('Signal faible')),
                      icon: Icons.network_cell_rounded,
                    ),
                  if (c.firmware != null) InfoChip('FW ${c.firmware}', icon: Icons.memory_rounded),
                ],
              ),
              if (InstalledApps.updaterFor(c.driver.typeId) case final updater?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                    onPressed: () => InstalledApps.open(updater),
                    icon: const Icon(Icons.system_update_rounded, size: 18),
                    label: Text(tr('Mettre à jour dans {0}', [updater])),
                  ),
                ),
              if (c.problem != null && c.state.value != LinkState.connected) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    c.problem!,
                    style: const TextStyle(fontSize: 13, color: Tones.red, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
              ],
              if (c.driver.hint != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(c.driver.hint!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.3)),
                ),
              ],
              if (c.driver case final EliteRizerDriver rizer)
                ValueListenableBuilder<bool>(
                  valueListenable: rizer.locked,
                  builder: (_, locked, _) => !locked
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 8, right: 8),
                          child: Text(
                            tr('Verrouillé (LED rouge) : déverrouille le Rizer pour qu’il suive la pente.'),
                            style: const TextStyle(fontSize: 13, color: Tones.red, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                ),
              if (c.driver case final EliteRizerDriver rizer)
                ValueListenableBuilder<double?>(
                  valueListenable: rizer.reportedGrade,
                  builder: (_, g, _) => g == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            tr('Pente du Rizer : {0} %', [g.toStringAsFixed(1)]),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    tr('Régler les boutons'),
                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.primary),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Étapes de connexion, repliées une fois l'appli connectée.
class _CollapsibleSetup extends StatefulWidget {
  final AppState app;
  const _CollapsibleSetup({required this.app});

  @override
  State<_CollapsibleSetup> createState() => _CollapsibleSetupState();
}

class _CollapsibleSetupState extends State<_CollapsibleSetup> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.appHealth != Health.ok || open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConnectionSetup(app: app),
          if (open)
            TextButton.icon(
              onPressed: () => setState(() => open = false),
              icon: const Icon(Icons.expand_less_rounded),
              label: Text(tr('Masquer les étapes')),
            ),
        ],
      );
    }
    return Row(
      children: [
        InfoChip(tr('Connectée'), icon: Icons.check_circle_rounded, color: Tones.green),
        const Spacer(),
        TextButton.icon(
          onPressed: () => setState(() => open = true),
          icon: const Icon(Icons.expand_more_rounded),
          label: Text(tr('Voir les étapes')),
        ),
      ],
    );
  }
}

/// Qui calcule les vitesses : l'appli d'entraînement ou ShiftLink.
class _GearsSource extends StatelessWidget {
  final AppState app;
  const _GearsSource({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = app.target;
    final shiftLink = t.transport == Transport.proxy;
    final appGears = shiftLink ? t.alternative! : t;
    final ownGears = shiftLink ? t : t.alternative!;
    final keyboard = appGears == TargetApp.keyboard;
    final name = keyboard ? tr('ton appli') : appGears.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr('Qui gère les vitesses ?'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        _SourceOption(
          selected: !shiftLink,
          icon: Icons.sports_esports_rounded,
          title: keyboard
              ? tr('Ton appli, avec ses raccourcis clavier')
              : tr('{0} gère les vitesses', [appGears.label]),
          subtitle: keyboard
              ? tr('Ta manette envoie les touches de vitesse de l’appli.')
              : tr('Ta manette envoie + et −, et {0} change de vitesse. Le plus simple.', [name]),
          onTap: () => app.setTarget(appGears),
        ),
        const SizedBox(height: 8),
        _SourceOption(
          selected: shiftLink,
          icon: Icons.settings_suggest_rounded,
          title: tr('ShiftLink gère les vitesses'),
          subtitle: tr(
            'ShiftLink règle ton home trainer : nombre de vitesses, double plateau, profils. Dans {0}, choisis le trainer « ShiftLink ».',
            [name],
          ),
          onTap: () => app.setTarget(ownGears),
        ),
      ],
    );
  }
}

/// L'appli fait les vitesses de deux façons : clavier Bluetooth ou OpenBikeControl.
class _LinkChoice extends StatelessWidget {
  final AppState app;
  const _LinkChoice({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = app.target;
    final keyboard = t.transport == Transport.keyboard ? t : t.alternative!;
    final obc = t.transport == Transport.obc ? t : t.alternative!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            tr('Comment relier ShiftLink à {0} ?', [t.label]),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        _SourceOption(
          selected: t == keyboard,
          icon: Icons.keyboard_rounded,
          title: tr('Clavier Bluetooth'),
          subtitle: tr('ShiftLink tape les raccourcis de {0}. Marche partout.', [t.label]),
          onTap: () => app.setTarget(keyboard),
        ),
        const SizedBox(height: 8),
        _SourceOption(
          selected: t == obc,
          icon: Icons.bluetooth_rounded,
          title: tr('OpenBikeControl'),
          subtitle: tr(
            'Dans {0}, ajoute la manette « ShiftLink ». Les vitesses arrivent sans passer par le clavier.',
            [t.label],
          ),
          onTap: () => app.setTarget(obc),
        ),
      ],
    );
  }
}

class _SourceOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SourceOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? Brand.orange.withValues(alpha: 0.12) : cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? Brand.orange : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? Brand.orange : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13.5, height: 1.3, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Brand.orange : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aucune manette : comment la réveiller, puis les causes probables.
class NoControllerCard extends StatelessWidget {
  final AppState app;

  /// Affiche aussi le bouton « Chercher à nouveau » (écran Rouler).
  final bool showSearch;
  const NoControllerCard({super.key, required this.app, this.showSearch = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: app.controllers.lastScanEmpty,
      builder: (context, notFound, _) {
        final scanning = app.controllers.scanning.value;
        final title = scanning
            ? tr('Réveille ta manette')
            : (notFound ? tr('Aucune manette trouvée') : tr('Pas encore de manette'));
        final tips = scanning
            ? [
                (Icons.touch_app_rounded, tr('Appuie sur un bouton de ta manette : elle se réveille et apparaît ici.')),
                (
                  Icons.bluetooth_rounded,
                  tr('Zwift Click, Play, Ride : le voyant clignote en bleu quand elle est prête.'),
                ),
                (Icons.directions_bike_rounded, tr('Elite Sterzo : tourne un peu le guidon.')),
              ]
            : notFound
            ? [
                (
                  Icons.link_off_rounded,
                  tr(
                    'Elle est peut-être encore connectée à une autre appli (Zwift Companion, MyWhoosh, BikeControl). Ferme-la, puis cherche à nouveau.',
                  ),
                ),
                (Icons.touch_app_rounded, tr('Elle dort : appuie sur un bouton juste avant de lancer la recherche.')),
                (Icons.battery_alert_rounded, tr('Sa pile est peut-être faible.')),
                (Icons.health_and_safety_rounded, tr('Le diagnostic vérifie le Bluetooth et les autorisations.')),
              ]
            : [
                (Icons.bluetooth_searching_rounded, tr('Lance la recherche, puis appuie sur un bouton de ta manette.')),
                (Icons.ads_click_rounded, tr('Sans manette, les gros boutons de l’écran Rouler marchent aussi.')),
              ];
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(
                      notFound && !scanning ? Icons.search_off_rounded : Icons.gamepad_rounded,
                      notFound && !scanning ? Tones.yellow : Tones.orange,
                    ),
                    const SizedBox(width: 12),
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final (icon, tip) in tips)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tip, style: const TextStyle(height: 1.3))),
                      ],
                    ),
                  ),
                if (showSearch && !scanning)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        if (await app.askPermissions()) unawaited(app.controllers.scan());
                      },
                      icon: const Icon(Icons.bluetooth_searching_rounded),
                      label: Text(tr('Chercher à nouveau')),
                    ),
                  ),
                if (notFound && !scanning)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagnosticPage(app: app))),
                      icon: const Icon(Icons.health_and_safety_rounded),
                      label: Text(tr('Lancer le diagnostic')),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnControllerPage(app: app))),
                    icon: const Icon(Icons.school_rounded),
                    label: Text(tr('Ma manette n’est pas dans la liste')),
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

/// Ceinture cardio : connectée (avec le pouls en direct) ou à ajouter.
class _HeartRateCard extends StatelessWidget {
  final AppState app;
  const _HeartRateCard({required this.app});

  Future<void> _pick(BuildContext context) async {
    if (!await app.askPermissions()) return;
    final hr = app.heartRate;
    unawaited(hr.scan());
    if (!context.mounted) return;
    final picked = await pickSensor(
      context,
      title: tr('Ceinture cardio'),
      tip: tr('Porte-la, électrodes mouillées : elle n’émet que sur la peau.'),
      icon: Icons.favorite_rounded,
      candidates: hr.candidates,
      scanning: hr.scanning,
      rescan: hr.scan,
      notFound: tr('Si elle est connectée à une montre, l’appairage peut être exclusif.'),
    );
    if (picked != null) await app.useHeartRate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hr = app.heartRate;
    final name = hr.name.value;
    if (name == null) {
      return GroupCard(
        children: [
          SettingRow(
            icon: Icons.favorite_rounded,
            color: Tones.red,
            title: tr('Ajouter une ceinture cardio'),
            subtitle: tr(
              'Ton pouls à l’écran, dans la sortie enregistrée et envoyé à l’appli quand ShiftLink gère les vitesses',
            ),
            onTap: () => _pick(context),
          ),
        ],
      );
    }
    final bpm = hr.bpm.value;
    return GroupCard(
      children: [
        SettingRow(
          icon: Icons.favorite_rounded,
          color: hr.isConnected ? Tones.red : Tones.grey,
          title: name,
          subtitle: hr.isConnected ? (bpm != null ? '$bpm bpm' : tr('Connectée')) : tr('Connexion…'),
          trailing: IconButton(
            tooltip: tr('Oublier cette ceinture'),
            onPressed: app.forgetHeartRate,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}

/// Liste des capteurs trouvés, dans une feuille.
Future<SensorCandidate?> pickSensor(
  BuildContext context, {
  required String title,
  required String tip,
  required IconData icon,
  required ValueNotifier<List<SensorCandidate>> candidates,
  required ValueNotifier<bool> scanning,
  required Future<void> Function() rescan,
  required String notFound,
}) => showModalBottomSheet<SensorCandidate>(
  context: context,
  showDragHandle: true,
  builder: (c) => ListenableBuilder(
    listenable: Listenable.merge([candidates, scanning]),
    builder: (c, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tip),
            const SizedBox(height: 12),
            for (final s in candidates.value)
              ListTile(leading: Icon(icon), title: Text(s.name), onTap: () => Navigator.pop(c, s)),
            if (scanning.value)
              ListTile(
                leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text(tr('Recherche…')),
              )
            else if (candidates.value.isEmpty)
              ListTile(
                leading: const Icon(Icons.search_off_rounded),
                title: Text(tr('Rien trouvé')),
                subtitle: Text(notFound),
                trailing: TextButton(onPressed: rescan, child: Text(tr('Réessayer'))),
              ),
          ],
        ),
      ),
    ),
  ),
);

/// Ventilateur Wahoo KICKR Headwind : mode et puissance du vent.
class _FanCard extends StatelessWidget {
  final AppState app;
  const _FanCard({required this.app});

  Future<void> _pick(BuildContext context) async {
    if (!await app.askPermissions()) return;
    final fan = app.fan;
    unawaited(fan.scan());
    if (!context.mounted) return;
    final picked = await pickSensor(
      context,
      title: tr('Ventilateur'),
      tip: tr('Allume ton KICKR Headwind et ferme l’appli Wahoo.'),
      icon: Icons.air_rounded,
      candidates: fan.candidates,
      scanning: fan.scanning,
      rescan: fan.scan,
      notFound: tr('Il ne doit pas être connecté à une autre appli.'),
    );
    if (picked != null) await app.useFan(picked);
  }

  @override
  Widget build(BuildContext context) {
    final fan = app.fan;
    final name = fan.name.value;
    final cs = Theme.of(context).colorScheme;
    if (name == null) {
      return GroupCard(
        children: [
          SettingRow(
            icon: Icons.air_rounded,
            color: Tones.blue,
            title: tr('Ajouter un ventilateur'),
            subtitle: tr('Wahoo KICKR Headwind (bêta)'),
            onTap: () => _pick(context),
          ),
        ],
      );
    }
    final mode = app.fanMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingRow(
              icon: Icons.air_rounded,
              color: fan.isConnected ? Tones.blue : Tones.grey,
              title: name,
              subtitle: fan.isConnected ? tr('Vent à {0} %', [fan.level.value]) : tr('Connexion…'),
              trailing: IconButton(
                tooltip: tr('Oublier ce ventilateur'),
                onPressed: app.forgetFan,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioGroup<FanMode>(
                    groupValue: mode,
                    onChanged: (m) {
                      if (m != null) app.setFanMode(m);
                    },
                    child: Column(
                      children: [
                        for (final m in FanMode.values)
                          RadioListTile<FanMode>(
                            value: m,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(m.description, style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  if (mode == FanMode.manual)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final l in Headwind.steps)
                          ChoiceChip(
                            label: Text(l == 0 ? tr('Arrêt') : '$l %'),
                            selected: fan.level.value == l,
                            onSelected: fan.isConnected ? (_) => fan.setLevel(l) : null,
                          ),
                      ],
                    ),
                  if (mode.hasRamp) _FanRamp(app: app, mode: mode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rampe du ventilateur : où il démarre, où il est à fond, et la mesure en direct.
class _FanRamp extends StatelessWidget {
  final AppState app;
  final FanMode mode;
  const _FanRamp({required this.app, required this.mode});

  @override
  Widget build(BuildContext context) {
    final hr = mode == FanMode.heartRateStrap;
    final (start, full) = app.fanRamp(mode);
    final (lo, hi, gap, div) = hr ? (60.0, 210.0, 10.0, 30) : (0.0, 800.0, 50.0, 80);
    final unit = hr ? 'bpm' : 'W';
    final values = RangeValues(start.toDouble().clamp(lo, hi), full.toDouble().clamp(lo, hi));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Démarre à {0}, à fond à {1}', ['$start $unit', '$full $unit']),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        RangeSlider(
          values: values,
          min: lo,
          max: hi,
          divisions: div,
          labels: RangeLabels('${values.start.round()} $unit', '${values.end.round()} $unit'),
          onChanged: (v) {
            if (v.end - v.start < gap) return;
            app.setFanRamp(mode, v.start.round(), v.end.round());
          },
        ),
        ValueListenableBuilder<int?>(
          valueListenable: app.fanInput,
          builder: (_, v, _) => Text(
            v == null
                ? (hr ? tr('En attente de ta ceinture cardio…') : tr('En attente de ta puissance…'))
                : tr('Maintenant : {0} → vent à {1} %', ['$v $unit', app.fan.level.value]),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Wahoo KICKR Climb : l'avant du vélo suit la pente de l'appli.
class _ClimbCard extends StatelessWidget {
  final AppState app;
  const _ClimbCard({required this.app});

  Future<void> _pick(BuildContext context) async {
    if (!await app.askPermissions()) return;
    final climb = app.climb;
    unawaited(climb.scan());
    if (!context.mounted) return;
    final picked = await pickSensor(
      context,
      title: tr('Pente réelle'),
      tip: tr('Allume ton KICKR Climb. S’il est appairé à ton KICKR, éteins le KICKR ou ferme l’appli Wahoo.'),
      icon: Icons.terrain_rounded,
      candidates: climb.candidates,
      scanning: climb.scanning,
      rescan: climb.scan,
      notFound: tr('Il ne doit pas être connecté à une autre appli.'),
    );
    if (picked != null) await app.useClimb(picked);
  }

  @override
  Widget build(BuildContext context) {
    final climb = app.climb;
    final name = climb.name.value;
    if (name == null) {
      return GroupCard(
        children: [
          SettingRow(
            icon: Icons.terrain_rounded,
            color: Tones.teal,
            title: tr('Ajouter un KICKR Climb'),
            subtitle: tr('L’avant du vélo suit la pente (bêta)'),
            onTap: () => _pick(context),
          ),
        ],
      );
    }
    final g = climb.grade.value;
    return GroupCard(
      children: [
        SettingRow(
          icon: Icons.terrain_rounded,
          color: climb.isConnected ? Tones.teal : Tones.grey,
          title: name,
          subtitle: !climb.isConnected
              ? tr('Connexion…')
              : (g == null ? tr('En attente d’une pente de l’appli') : tr('Pente {0} %', [g.toStringAsFixed(1)])),
          trailing: IconButton(
            tooltip: tr('Oublier ce KICKR Climb'),
            onPressed: app.forgetClimb,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}
