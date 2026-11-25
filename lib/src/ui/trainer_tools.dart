// Nouveaux outils 2.3 : capteurs de cadence et de puissance, test de résistance,
// séance « escalier », appareils ignorés et options de fin de séance.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../controller_manager.dart';
import '../i18n.dart';
import '../sensors/bike_sensor.dart';
import '../trainer/ftms.dart';
import '../trainer/proxy.dart';
import 'connected_apps_page.dart' show ConnectedAppsPage;
import 'devices_page.dart' show pickSensor;
import 'widgets.dart';

/// Capteur de cadence ou de puissance : connecté (valeur en direct) ou à ajouter.
class BikeSensorCard extends StatelessWidget {
  final AppState app;
  final BikeSensor sensor;
  const BikeSensorCard({super.key, required this.app, required this.sensor});

  bool get _power => sensor.kind == SensorKind.power;

  Future<void> _pick(BuildContext context) async {
    if (!await app.askPermissions()) return;
    unawaited(sensor.scan());
    if (!context.mounted) return;
    final picked = await pickSensor(
      context,
      title: _power ? tr('Capteur de puissance') : tr('Capteur de cadence'),
      tip: tr('Fais tourner les pédales pour le réveiller.'),
      icon: _power ? Icons.bolt_rounded : Icons.autorenew_rounded,
      candidates: sensor.candidates,
      scanning: sensor.scanning,
      rescan: sensor.scan,
      notFound: tr('S’il est connecté à un compteur ou une montre, déconnecte-le d’abord.'),
    );
    if (picked != null) await app.useSensor(sensor, picked);
  }

  @override
  Widget build(BuildContext context) {
    final name = sensor.name.value;
    final icon = _power ? Icons.bolt_rounded : Icons.autorenew_rounded;
    if (name == null) {
      return GroupCard(
        children: [
          SettingRow(
            icon: icon,
            color: Tones.orange,
            title: _power ? tr('Ajouter un capteur de puissance') : tr('Ajouter un capteur de cadence'),
            subtitle: _power
                ? tr('Tes vrais watts (pédales, manivelle) à la place de ceux du trainer')
                : tr('Des vitesses plus justes si ton trainer mesure mal la cadence'),
            onTap: () => _pick(context),
          ),
        ],
      );
    }
    final cad = sensor.cadence.value;
    final value = _power
        ? [
            if (sensor.power.value != null) '${sensor.power.value} W',
            if (cad != null) tr('{0} tr/min', [cad.round()]),
          ].join(' · ')
        : (cad != null ? tr('{0} tr/min', [cad.round()]) : '');
    return GroupCard(
      children: [
        SettingRow(
          icon: icon,
          color: sensor.isConnected ? Tones.orange : Tones.grey,
          title: name,
          subtitle: sensor.isConnected ? (value.isEmpty ? tr('Connecté') : value) : tr('Connexion…'),
          trailing: IconButton(
            tooltip: tr('Oublier ce capteur'),
            onPressed: () => app.forgetSensor(sensor),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        if (_power)
          SettingRow.toggle(
            icon: Icons.swap_horiz_rounded,
            color: Tones.grey,
            title: tr('Envoyer ces watts à l’appli'),
            subtitle: tr('Sinon, l’appli garde les watts du trainer'),
            value: app.sensorPower,
            onChanged: app.setSensorPower,
          ),
      ],
    );
  }
}

/// « Est-ce que mon trainer réagit ? » : 10 s facile, 10 s dur.
class ResistanceTestButton extends StatelessWidget {
  final AppState app;
  const ResistanceTestButton({super.key, required this.app});

  Future<void> _run(BuildContext context) async {
    final step = ValueNotifier<(int, int)>((1, 10));
    final done = Completer<ResistanceTestResult>();
    unawaited(
      app.proxy
          .resistanceTest(progress: (s, left) => step.value = (s, left))
          .then(
            done.complete,
            onError: (_) {
              done.complete(const ResistanceTestResult(ResistanceTestOutcome.noTrainer));
            },
          ),
    );
    final result = await showDialog<ResistanceTestResult>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        done.future.then((r) {
          if (c.mounted) Navigator.of(c).pop(r);
        });
        return AlertDialog(
          title: Text(tr('Test de résistance')),
          content: ValueListenableBuilder(
            valueListenable: step,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v.$1 == 1 ? tr('Pédale tranquillement… c’est facile.') : tr('Garde la même cadence… ça durcit !'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text('${v.$2}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800)),
                Text(tr('Étape {0} sur 2', [v.$1])),
              ],
            ),
          ),
        );
      },
    );
    step.dispose();
    if (result == null || !context.mounted) return;
    final (title, body) = switch (result.outcome) {
      ResistanceTestOutcome.ok => (
        tr('Ton trainer réagit bien'),
        tr('{0} W en facile, {1} W en dur. Les vitesses vont marcher.', [result.easyWatts, result.hardWatts]),
      ),
      ResistanceTestOutcome.noChange => (
        tr('Ton trainer ne durcit pas'),
        tr(
          '{0} W en facile, {1} W en dur. Ferme les autres applis qui pilotent le trainer, puis dans « Vitesses virtuelles », essaie le pilotage « Résistance ».',
          [result.easyWatts, result.hardWatts],
        ),
      ),
      ResistanceTestOutcome.noPedaling => (tr('Pas de watts reçus'), tr('Pédale pendant tout le test, puis réessaie.')),
      ResistanceTestOutcome.noTrainer => (tr('Pas de home trainer'), tr('Connecte d’abord ton home trainer.')),
    };
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('OK')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: app.proxy.active ? () => _run(context) : null,
    icon: const Icon(Icons.speed_rounded),
    label: Text(tr('Tester la résistance (20 s)')),
  );
}

/// Calibrer le home trainer (« spin down ») : on accélère, on lâche, le trainer mesure
/// son frottement. Proposé seulement par les trainers qui l'annoncent.
class SpinDownButton extends StatelessWidget {
  final AppState app;
  const SpinDownButton({super.key, required this.app});

  Future<void> _run(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Calibrer le home trainer')),
        content: Text(
          tr(
            'Pour des watts plus justes. Roule d’abord 10 minutes pour chauffer le trainer. Ensuite : tu accélères jusqu’à la vitesse demandée, puis tu arrêtes de pédaler et tu laisses la roue ralentir toute seule, sans freiner.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Commencer'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    if (!await app.proxy.startCalibration()) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => SpinDownDialog(app: app),
    );
    await app.proxy.endCalibration();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      app.proxy.trainer.caps,
      app.proxy.trainer.state,
      app.proxy.workout,
      app.proxy.routeRun,
      app.proxy.fixedErg,
    ]),
    builder: (context, _) {
      final p = app.proxy;
      if (!p.active) return const SizedBox.shrink();
      if (!p.trainer.caps.value.spinDown) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr('Calibration : ce home trainer ne la propose pas ici. Utilise l’appli de sa marque.'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: p.canCalibrate ? () => _run(context) : null,
            icon: const Icon(Icons.tune_rounded),
            label: Text(tr('Calibrer le home trainer')),
          ),
          if (!p.canCalibrate)
            Text(
              tr('Possible quand le home trainer est connecté et qu’aucune appli ne le pilote.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
        ],
      );
    },
  );
}

/// Suivi de la calibration : accélère, lâche, résultat.
class SpinDownDialog extends StatelessWidget {
  final AppState app;
  const SpinDownDialog({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = app.proxy.trainer;
    return ListenableBuilder(
      listenable: Listenable.merge([t.spinDown, t.state, app.proxy.data]),
      builder: (context, _) {
        final lost = !t.isConnected;
        final s = t.spinDown.value;
        final phase = lost ? SpinDownPhase.failed : (s?.phase ?? SpinDownPhase.failed);
        final kmh = app.proxy.data.value.speedKmh;
        final target = s?.targetKmh;
        final (IconData icon, String title, String body) = switch (phase) {
          SpinDownPhase.starting => (Icons.hourglass_top_rounded, tr('Un instant…'), tr('Le home trainer se prépare.')),
          SpinDownPhase.speedUp => (
            Icons.trending_up_rounded,
            tr('Accélère !'),
            target == null
                ? tr('Pédale de plus en plus vite, jusqu’à ce que le trainer te dise d’arrêter.')
                : tr('Monte jusqu’à {0} km/h.', [target.round()]),
          ),
          SpinDownPhase.coast => (
            Icons.do_not_touch_rounded,
            tr('Arrête de pédaler'),
            tr('Laisse la roue ralentir toute seule. Ne freine pas.'),
          ),
          SpinDownPhase.success => (
            Icons.check_circle_rounded,
            tr('Calibration réussie'),
            tr('Ton home trainer est réglé. Refais-la de temps en temps, ou si tu le déplaces.'),
          ),
          SpinDownPhase.refused => (
            Icons.block_rounded,
            tr('Le home trainer a refusé'),
            tr('Ferme les autres applis reliées au trainer, puis réessaie. Sinon, utilise l’appli de sa marque.'),
          ),
          SpinDownPhase.failed => (
            Icons.error_outline_rounded,
            tr('Calibration ratée'),
            lost
                ? tr('Le home trainer s’est déconnecté.')
                : tr('Réessaie : accélère bien jusqu’à la vitesse demandée, puis ne pédale plus du tout.'),
          ),
        };
        final done = lost || (s?.finished ?? true);
        final moving = phase == SpinDownPhase.speedUp || phase == SpinDownPhase.coast;
        return AlertDialog(
          title: Text(tr('Calibrer le home trainer')),
          content: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center),
                if (moving && kmh != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    tr('{0} km/h', [kmh.toStringAsFixed(1).replaceAll('.', ',')]),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                  ),
                  if (phase == SpinDownPhase.speedUp && target != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: (kmh / target).clamp(0.0, 1.0), minHeight: 8),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            done
                ? FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK')))
                : TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Arrêter'))),
          ],
        );
      },
    );
  }
}

/// Séance « escalier » : la puissance monte par paliers, sans appli.
class StaircaseButton extends StatelessWidget {
  final AppState app;
  const StaircaseButton({super.key, required this.app});

  Future<void> _start(BuildContext context) async {
    var start = app.ergStartWatts.clamp(50, 400);
    var step = 20;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Séance escalier')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('5 marches de 2 minutes. La puissance monte à chaque marche.')),
              const SizedBox(height: 12),
              Text(tr('Départ : {0} W', [start])),
              Slider(
                value: start.toDouble(),
                min: 50,
                max: 400,
                divisions: 35,
                onChanged: (v) => set(() => start = v.round()),
              ),
              Text(tr('Chaque marche : +{0} W', [step])),
              Slider(
                value: step.toDouble(),
                min: 5,
                max: 50,
                divisions: 9,
                onChanged: (v) => set(() => step = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('C’est parti'))),
          ],
        ),
      ),
    );
    if (ok == true) app.proxy.startStaircase(startWatts: start, stepWatts: step);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StaircaseState?>(
    valueListenable: app.proxy.staircase,
    builder: (context, st, _) {
      if (st != null) {
        final m = st.secondsLeft ~/ 60, s = (st.secondsLeft % 60).toString().padLeft(2, '0');
        return Card(
          child: ListTile(
            leading: const Icon(Icons.stairs_rounded),
            title: Text(tr('Marche {0} sur {1} · {2} W', [st.step, st.steps, st.watts])),
            subtitle: Text(tr('Encore {0}', ['$m:$s'])),
            trailing: TextButton(onPressed: app.proxy.stopStaircase, child: Text(tr('Arrêter'))),
          ),
        );
      }
      final can = app.proxy.active && app.proxy.appClient == null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: can ? () => _start(context) : null,
            icon: const Icon(Icons.stairs_rounded),
            label: Text(tr('Séance escalier')),
          ),
          if (!can)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Possible quand le home trainer est connecté et qu’aucune appli ne le pilote.'),
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      );
    },
  );
}

/// Bouton « × » d'une manette : l'oublier pour cette fois, ou pour toujours.
Future<void> forgetOrIgnore(BuildContext context, AppState app, ConnectedController c) async {
  if (!c.isBluetooth) return app.forgetController(c);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link_off_rounded),
            title: Text(tr('Déconnecter')),
            subtitle: Text(tr('Elle reviendra à la prochaine recherche')),
            onTap: () => Navigator.pop(s, 'forget'),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(tr('Ce n’est pas la mienne')),
            subtitle: Text(tr('ShiftLink ne s’y connectera plus jamais')),
            onTap: () => Navigator.pop(s, 'ignore'),
          ),
        ],
      ),
    ),
  );
  if (choice == 'forget') await app.forgetController(c);
  if (choice == 'ignore') await app.ignoreController(c);
}

/// Réglages de fin de séance, des manettes et des automatismes.
class AutomationSettings extends StatelessWidget {
  final AppState app;
  const AutomationSettings({super.key, required this.app});

  @override
  Widget build(BuildContext context) => GroupCard(
    children: [
      SettingRow.toggle(
        icon: Icons.fiber_manual_record_rounded,
        color: Tones.red,
        title: tr('Enregistrer mes sorties tout seul'),
        subtitle: tr('Dès que tu pédales, quand ShiftLink pilote le trainer'),
        value: app.autoRecord,
        onChanged: app.setAutoRecord,
      ),
      SettingRow.toggle(
        icon: Icons.favorite_border_rounded,
        color: Tones.pink,
        title: tr('Envoyer à Health Connect'),
        subtitle: app.healthConnectAvailable
            ? tr('Chaque sortie enregistrée va aussi dans Health Connect')
            : tr('Health Connect n’est pas installée sur ce téléphone'),
        value: app.healthConnect,
        onChanged: app.setHealthConnect,
        enabled: app.healthConnectAvailable,
      ),
      SettingRow(
        icon: Icons.hub_rounded,
        color: Tones.blue,
        title: tr('Applis connectées'),
        subtitle: app.connectedTargets.isEmpty
            ? tr('Garmin Connect, Intervals.icu, et tes sorties MyWhoosh')
            : app.connectedTargets.map((t) => t.label).join(', '),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConnectedAppsPage(app: app))),
      ),
      SettingRow.toggle(
        icon: Icons.battery_saver_rounded,
        color: Tones.green,
        title: tr('Éteindre les manettes après la séance'),
        subtitle: tr('5 minutes après la déconnexion de l’appli, pour leurs piles'),
        value: app.autoSleep,
        onChanged: app.setAutoSleep,
      ),
      SettingRow.toggle(
        icon: Icons.vibration_rounded,
        color: Tones.purple,
        title: tr('Vibration des manettes'),
        subtitle: tr('Manettes de jeu, Zwift Play et Zwift Ride : elles vibrent à chaque vitesse, plus fort en butée'),
        value: app.rumble,
        onChanged: app.setRumble,
      ),
      SettingRow(
        icon: Icons.autorenew_rounded,
        color: Tones.teal,
        title: tr('Cadence cible de la boîte auto'),
        subtitle: tr('De {0} à {1} tr/min', [app.autoShiftLowCad, app.autoShiftHighCad]),
        onTap: () => showDialog<void>(
          context: context,
          builder: (c) => AutoShiftCadenceDialog(app: app),
        ),
      ),
    ],
  );
}

/// Choisit la zone de cadence que vise la boîte auto.
class AutoShiftCadenceDialog extends StatefulWidget {
  final AppState app;
  const AutoShiftCadenceDialog({super.key, required this.app});

  @override
  State<AutoShiftCadenceDialog> createState() => _AutoShiftCadenceDialogState();
}

class _AutoShiftCadenceDialogState extends State<AutoShiftCadenceDialog> {
  late RangeValues _v = RangeValues(widget.app.autoShiftLowCad.toDouble(), widget.app.autoShiftHighCad.toDouble());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Cadence cible')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(
            'ShiftLink passe + d’une vitesse si tu dépasses {0} tr/min, et − d’une vitesse si tu descends sous {1} tr/min.',
            [_v.end.round(), _v.start.round()],
          ),
        ),
        const SizedBox(height: 12),
        RangeSlider(
          values: _v,
          min: 50,
          max: 120,
          divisions: 70,
          labels: RangeLabels('${_v.start.round()}', '${_v.end.round()}'),
          onChanged: (x) => setState(() => _v = RangeValues(x.start, x.end.clamp(x.start + 5, 120))),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
      FilledButton(
        onPressed: () async {
          await widget.app.setAutoShiftLowCad(_v.start.round());
          await widget.app.setAutoShiftHighCad(_v.end.round());
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Garder')),
      ),
    ],
  );
}

/// Liste des appareils ignorés, à remettre si on s'est trompé.
class IgnoredDevicesPage extends StatelessWidget {
  final AppState app;
  const IgnoredDevicesPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Appareils ignorés'))),
    body: ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.ignoredDevices.entries.toList();
        if (list.isEmpty) return Center(child: Text(tr('Aucun appareil ignoré.')));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: Text(e.value),
                  subtitle: Text(e.key),
                  trailing: TextButton(onPressed: () => app.unignore(e.key), child: Text(tr('Remettre'))),
                ),
              ),
          ],
        );
      },
    ),
  );
}
