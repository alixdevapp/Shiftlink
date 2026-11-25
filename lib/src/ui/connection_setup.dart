// Réglage de la connexion à l'appli choisie (assistant et réglages).
import 'dart:async';

import 'package:flutter/material.dart';

import '../actions.dart';
import '../app_state.dart';
import '../controller_manager.dart' show LinkState;
import '../i18n.dart';
import '../installed_apps.dart';
import '../outputs/hid_keyboard.dart';
import '../outputs/screen_taps.dart';
import '../trainer/trainer_client.dart' show TrainerClient, TrainerKind;
import 'hint_pictures.dart';
import 'trainer_tools.dart';
import 'widgets.dart';

class ConnectionSetup extends StatelessWidget {
  final AppState app;
  const ConnectionSetup({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.healthListenable, app]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstallAppPrompt(target: app.target),
          switch (app.target.transport) {
            Transport.link => _LinkSetup(app),
            Transport.obc => _ObcSetup(app),
            Transport.zwiftRide => _ZwiftRideSetup(app),
            Transport.keyboard => KeyboardSetup(app: app),
            Transport.proxy => TrainerSetup(app: app),
          },
        ],
      ),
    );
  }
}

/// L'appli choisie n'est pas sur ce téléphone : on propose de l'installer depuis le Play Store.
class InstallAppPrompt extends StatelessWidget {
  final TargetApp target;
  const InstallAppPrompt({super.key, required this.target});

  @override
  Widget build(BuildContext context) {
    final name = InstalledApps.searchName(target);
    if (name == null) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: InstalledApps.has(target),
      builder: (context, snap) {
        if (snap.data != false) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.download_rounded, color: Tones.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('{0} n’est pas installée sur ce téléphone. Tu veux l’installer ?', [target.label]),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => InstalledApps.open(name),
                    icon: const Icon(Icons.shop_rounded),
                    label: Text(tr('Installer {0}', [target.label])),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinkSetup extends StatelessWidget {
  final AppState app;
  const _LinkSetup(this.app);

  @override
  Widget build(BuildContext context) {
    final viaObc = app.obc.connectedApp.value != null;
    final connected = viaObc || app.link.isConnected.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusLine(
          health: app.appHealth,
          text: connected
              ? tr('MyWhoosh est connecté {0}', [viaObc ? '(OpenBikeControl)' : '(Link)'])
              : tr('En attente de MyWhoosh…'),
        ),
        const SizedBox(height: 8),
        StepLine(
          1,
          tr('Connecte ton home trainer à MyWhoosh comme d’habitude et active ses vitesses virtuelles (MyShift).'),
        ),
        StepLine(
          2,
          tr(
            'Dans MyWhoosh, ouvre l’écran des connexions et touche l’icône en forme de guidon, en haut à droite (« OpenBikeControl », la langue commune des manettes), puis « Oui ».',
          ),
        ),
        const SizedBox(height: 8),
        const ConnectionsScreenPicture(),
        const ConfirmPicture(),
        HintBox(text: tr('Ancienne version de MyWhoosh : choisis plutôt « Link » (et ferme l’app « MyWhoosh Link »).')),
        const SizedBox(height: 8),
        HintBox(text: tr('Le téléphone et l’appareil MyWhoosh doivent être sur le même Wi-Fi, sans réseau invité.')),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('Ensuite : régler l’écart entre deux vitesses')),
          children: [
            HintBox(
              text: tr(
                'Écart entre deux vitesses : dans MyWhoosh, Réglages > Équipement > « Gear step size ». Plus le chiffre est petit, plus chaque vitesse change doucement. 32 est un bon début.',
              ),
            ),
            const SizedBox(height: 8),
            const GearStepPicture(),
          ],
        ),
      ],
    );
  }
}

class _ObcSetup extends StatelessWidget {
  final AppState app;
  const _ObcSetup(this.app);

  @override
  Widget build(BuildContext context) {
    final appName = app.obc.connectedApp.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepLine(1, tr('Mets le téléphone et l’appareil de l’appli sur le même Wi-Fi, ou laisse le Bluetooth allumé.')),
        StepLine(2, tr('Dans l’appli, cherche une manette OpenBikeControl : « ShiftLink » apparaît tout seul.')),
        if (app.target == TargetApp.incyclistObc)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr(
                'Il faut une version d’Incyclist qui gère OpenBikeControl. Sinon, choisis « ShiftLink gère les vitesses ».',
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (app.target == TargetApp.biketerraObc)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Biketerra se connecte en Bluetooth seulement : laisse le Bluetooth du téléphone allumé, près de l’ordinateur.'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        StatusLine(
          health: app.appHealth,
          text: appName != null ? tr('Connecté à {0}', [appName]) : tr('En attente de l’appli…'),
        ),
      ],
    );
  }
}

/// Zwift : ShiftLink se présente comme une manette Zwift Ride (bêta).
class _ZwiftRideSetup extends StatelessWidget {
  final AppState app;
  const _ZwiftRideSetup(this.app);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepLine(1, tr('Dans Zwift, appaire ton home trainer comme d’habitude : c’est Zwift qui fait les vitesses.')),
        StepLine(2, tr('Dans « Manettes » de l’écran d’appairage, choisis la Zwift Ride qui apparaît (c’est ShiftLink).')),
        StepLine(3, tr('Éteins une vraie Zwift Ride ou Click à proximité : Zwift prendrait la mauvaise.')),
        const SizedBox(height: 8),
        HintBox(
          text: tr(
            'Bêta : si Zwift ne voit pas la manette, reviens à « ShiftLink fait les vitesses » ou utilise le clavier Bluetooth.',
          ),
        ),
        const SizedBox(height: 12),
        StatusLine(
          health: app.appHealth,
          text: app.zwiftRide.isConnected ? tr('Connecté à {0}', ['Zwift']) : tr('En attente de l’appli…'),
        ),
      ],
    );
  }
}

/// Appairage du clavier Bluetooth.
class KeyboardSetup extends StatefulWidget {
  final AppState app;
  const KeyboardSetup({super.key, required this.app});

  @override
  State<KeyboardSetup> createState() => _KeyboardSetupState();
}

class _KeyboardSetupState extends State<KeyboardSetup> {
  bool? _supported;
  List<HostDevice> _hosts = [];

  AppState get app => widget.app;
  HidKeyboard get kb => app.keyboard;

  @override
  void initState() {
    super.initState();
    kb.isSupported().then((v) {
      if (mounted) setState(() => _supported = v);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    if (app.demo) {
      setState(() => _hosts = [const HostDevice('00:11', 'PC-Salon'), HostDevice('00:12', tr('iPad de Alex'))]);
      return;
    }
    try {
      await kb.start();
      final hosts = await kb.bondedDevices();
      if (mounted) setState(() => _hosts = hosts);
    } catch (_) {}
  }

  String _prefFor(ShiftAction a) => switch (a) {
    ShiftAction.shiftUp => 'kbUp',
    ShiftAction.shiftDown => 'kbDown',
    _ => 'kb.${a.name}',
  };

  Widget _keyDropdown(ShiftAction a, HidKey? value) => Row(
    children: [
      Icon(a.icon, size: 20),
      const SizedBox(width: 8),
      Expanded(flex: 3, child: Text(a.label)),
      Expanded(
        flex: 2,
        child: DropdownButton<String>(
          isExpanded: true,
          value: value?.label ?? '',
          items: [
            const DropdownMenuItem(value: '', child: Text('—')),
            for (final k in HidKeys.all) DropdownMenuItem(value: k.label, child: Text(k.label)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            if (v.isEmpty) {
              await app.prefs?.remove(_prefFor(a));
            } else {
              await app.prefs?.setString(_prefFor(a), v);
            }
            setState(() {});
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Où tourne ton appli ?')),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.smartphone), label: Text(tr('Ce téléphone'))),
              ButtonSegment(value: false, icon: const Icon(Icons.devices), label: Text(tr('Autre appareil'))),
            ],
            selected: {app.sameDevice},
            showSelectedIcon: false,
            onSelectionChanged: (v) async {
              await app.setSameDevice(v.first);
              if (!v.first) unawaited(_refresh());
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 16),
        if (app.sameDevice) SameDeviceSetup(app: app) else _remote(context),
      ],
    );
  }

  Widget _remote(BuildContext context) {
    if (_supported == false) {
      return HintBox(
        icon: Icons.error_outline,
        text: tr(
          'Ce téléphone ne peut pas servir de clavier Bluetooth (Android 9 minimum). Choisis une autre méthode, ou les boutons à l’écran.',
        ),
      );
    }
    final presetId = app.prefs?.getString('kbPreset') ?? 'rouvy';
    final preset = keyPresetFor(presetId, app.prefs);
    final host = kb.connectedHost.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (presetId == 'custom')
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            title: Text(tr('Touches de ton appli')),
            subtitle: Text(tr('Choisis la touche de chaque action. « — » = pas de touche.')),
            children: [for (final a in keyboardActions) _keyDropdown(a, preset.keys[a])],
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr('Touches envoyées : {0}.', [
                [for (final e in preset.keys.entries) '${e.key.label} « ${e.value.label} »'].join(', '),
              ]),
            ),
          ),
        if (app.target == TargetApp.rouvy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HintBox(text: tr('Dans Rouvy, active les « Virtual Shifting Controls » dans les réglages.')),
          ),
        StepLine(1, tr('Touche « Rendre visible » ci-dessous.')),
        StepLine(
          2,
          tr(
            'Sur l’ordinateur ou la tablette de l’appli, ajoute un appareil Bluetooth : choisis « ShiftLink » ou le nom de ce téléphone.',
          ),
        ),
        StepLine(3, tr('Reviens ici et touche cet appareil dans la liste.')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () async {
                try {
                  await kb.start();
                  await kb.makeDiscoverable();
                } catch (e) {
                  app.log(tr('Impossible de rendre le téléphone visible ({0})', [e]));
                }
              },
              icon: const Icon(Icons.visibility),
              label: Text(tr('Rendre visible')),
            ),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: Text(tr('Actualiser'))),
          ],
        ),
        const SizedBox(height: 8),
        for (final h in _hosts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              h.name == host ? Icons.check_circle : Icons.computer,
              color: h.name == host ? healthColor(context, Health.ok) : null,
            ),
            title: Text(h.name),
            subtitle: h.name == host ? Text(tr('Connecté')) : null,
            onTap: () async {
              await app.prefs?.setString('kbHost', h.address);
              app.log(tr('Connexion du clavier à {0}…', [h.name]));
              try {
                await kb.start(address: h.address);
              } catch (e) {
                app.log(tr('Clavier Bluetooth : {0}', [e]));
              }
            },
          ),
        const SizedBox(height: 8),
        StatusLine(
          health: app.appHealth,
          text: host != null
              ? tr('Clavier connecté à {0}', [host])
              : tr('Pas encore connecté à un ordinateur ou une tablette'),
        ),
      ],
    );
  }
}

/// Choix du home trainer et appairage dans l'appli (vitesses ShiftLink).
/// Appli sur ce téléphone : ShiftLink touche les boutons à l'écran.
class SameDeviceSetup extends StatelessWidget {
  final AppState app;
  const SameDeviceSetup({super.key, required this.app});

  /// Actions à placer à l'écran : vitesses + celles des boutons réglés.
  List<ShiftAction> _actions() {
    final drivers = [for (final c in app.controllers.controllers.value) c.driver];
    final used = app.prefs == null ? <ShiftAction>{} : app.keymap.usedActions(drivers);
    return [
      ShiftAction.shiftUp,
      ShiftAction.shiftDown,
      for (final a in ShiftAction.values)
        if (a != ShiftAction.shiftUp && a != ShiftAction.shiftDown && used.contains(a) && isTappable(a)) a,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.taps.enabled,
        app.taps.revision,
        app.taps.calibrating,
        app.controllers.controllers,
      ]),
      builder: (context, _) {
        final taps = app.taps;
        final on = taps.enabled.value;
        final target = app.target.name;
        final positions = taps.positionsFor(target);
        final actions = _actions();
        final missing = [
          for (final a in actions)
            if (!positions.containsKey(a)) a,
        ];
        Future<void> calibrate(List<ShiftAction> list) async {
          if (!await taps.calibrate(target, list)) app.log(tr('Impossible d’afficher la bulle de réglage'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('ShiftLink touche lui-même les boutons de ton appli quand tu appuies sur ta manette.')),
            const SizedBox(height: 12),
            StepLine(1, tr('Active « ShiftLink : vitesses à l’écran » dans les réglages d’accessibilité.')),
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 8),
              child: on
                  ? StatusLine(health: Health.ok, text: tr('Accessibilité activée'))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: taps.openSettings,
                          icon: const Icon(Icons.accessibility_new),
                          label: Text(tr('Ouvrir l’accessibilité')),
                        ),
                        TextButton(onPressed: taps.openAppInfo, child: Text(tr('Infos de l’appli'))),
                      ],
                    ),
            ),
            if (!on)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HintBox(
                  text: tr(
                    'Android affiche « Paramètre restreint » ? Touche « Infos de l’appli », puis le menu ⋮ en haut à droite, « Autoriser les paramètres restreints », et réessaie.',
                  ),
                ),
              ),
            StepLine(2, tr('Ouvre ton appli, lance une sortie, puis reviens ici.')),
            StepLine(
              3,
              tr(
                'Touche « Régler les positions », puis la bulle orange en haut de l’écran, puis chaque bouton de l’appli dans l’ordre demandé.',
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Column(
                children: [
                  for (final a in actions)
                    ListTile(
                      dense: true,
                      leading: Icon(a.icon),
                      title: Text(a.label),
                      subtitle: Text(switch ((positions[a], taps.isCalibrated(target, a))) {
                        (null, _) => tr('À régler'),
                        (_, true) => tr('Réglée'),
                        _ => tr('Position par défaut, à vérifier'),
                      }),
                      trailing: IconButton(
                        tooltip: tr('Régler cette position'),
                        icon: Icon(
                          Icons.ads_click,
                          color: positions[a] == null ? healthColor(context, Health.waiting) : null,
                        ),
                        onPressed: on ? () => calibrate([a]) : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (taps.calibrating.value)
                  OutlinedButton.icon(
                    onPressed: taps.cancelCalibration,
                    icon: const Icon(Icons.close),
                    label: Text(tr('Annuler le réglage')),
                  )
                else
                  FilledButton.icon(
                    onPressed: on ? () => calibrate(missing.isEmpty ? actions : missing) : null,
                    icon: const Icon(Icons.ads_click),
                    label: Text(missing.isEmpty ? tr('Tout régler à nouveau') : tr('Régler les positions')),
                  ),
                OutlinedButton.icon(
                  onPressed: on && positions.isNotEmpty ? () => taps.showTargets(target) : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(tr('Montrer les cibles')),
                ),
                if (actions.any((a) => taps.isCalibrated(target, a)))
                  TextButton(onPressed: () => taps.resetPositions(target), child: Text(tr('Positions par défaut'))),
              ],
            ),
            const SizedBox(height: 12),
            StatusLine(
              health: app.appHealth,
              text: app.tapsReady
                  ? tr('Prêt : ShiftLink touchera les boutons de l’appli')
                  : tr('Positions des vitesses à régler'),
            ),
            const SizedBox(height: 8),
            HintBox(
              text: tr(
                '« Montrer les cibles » affiche des ronds orange par-dessus ton appli pendant 6 secondes : vérifie qu’ils tombent bien sur les boutons. Garde le téléphone dans le même sens qu’au réglage.',
              ),
            ),
            if (app.target == TargetApp.rouvy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: HintBox(
                  text: tr('Dans Rouvy, active les « Virtual Shifting Controls » pour afficher les boutons + et −.'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class TrainerSetup extends StatelessWidget {
  final AppState app;
  const TrainerSetup({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final proxy = app.proxy;
    final t = proxy.trainer;
    final appName = switch (app.target) {
      TargetApp.zwift => 'Zwift',
      TargetApp.mywhooshProxy => 'MyWhoosh',
      TargetApp.incyclist => 'Incyclist',
      _ => tr('l’appli'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepLine(1, tr('Déconnecte ton home trainer des autres applis (Zwift, MyWhoosh…), puis choisis-le ici.')),
        const SizedBox(height: 4),
        StatusLine(
          health: switch (t.state.value) {
            LinkState.connected => Health.ok,
            LinkState.connecting => Health.waiting,
            LinkState.disconnected => Health.off,
          },
          text: switch (t.state.value) {
            LinkState.connected => tr('Home trainer : {0}', [t.name.value]),
            LinkState.connecting => tr('Connexion à {0}…', [t.name.value]),
            LinkState.disconnected => tr('Aucun home trainer connecté'),
          },
          trailing: ValueListenableBuilder(
            valueListenable: t.scanning,
            builder: (_, scanning, _) => scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () async {
                      if (await app.askPermissions()) unawaited(t.scan());
                    },
                    child: Text(tr('Chercher')),
                  ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: t.candidates,
          builder: (_, list, _) => Column(
            children: [
              for (final c in list)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 8),
                  leading: Icon(c.kind == TrainerKind.wifi ? Icons.wifi_rounded : Icons.pedal_bike),
                  title: Text(c.name),
                  subtitle: switch (c.kind) {
                    _ when TrainerClient.hasTwin(c, list) => Text(
                      c.kind == TrainerKind.wifi
                          ? tr('Même trainer, en Wi-Fi : choisis l’un des deux')
                          : tr('Même trainer, en Bluetooth : choisis l’un des deux'),
                    ),
                    TrainerKind.fec => Text(tr('Ancien protocole Tacx (FE-C)')),
                    TrainerKind.wahoo => Text(tr('Ancien protocole Wahoo (KICKR, Hammer…)')),
                    _ => null,
                  },
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await app.prefs?.setString('trainerId', c.id);
                    await app.prefs?.setString('trainerName', c.name);
                    t.candidates.value = const [];
                    await t.disconnect();
                    unawaited(t.connectCandidate(c));
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        StepLine(
          2,
          tr(
            'Dans {0}, appaire le trainer « ShiftLink » (en Wi-Fi) ou le nom de ce téléphone (en Bluetooth) pour la puissance et la résistance, et la cadence.',
            [appName],
          ),
        ),
        if (app.target == TargetApp.incyclist)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Dans Incyclist, désactive les vitesses virtuelles : ShiftLink s’en occupe.'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 4),
        StatusLine(
          health: proxy.appClient != null ? Health.ok : Health.waiting,
          text: proxy.appClient != null
              ? tr('{0} est connecté ({1})', [appName, proxy.server.client.value != null ? 'Wi-Fi' : 'Bluetooth'])
              : tr('En attente de {0}…', [appName]),
        ),
        const SizedBox(height: 12),
        HintBox(
          text: tr(
            'ShiftLink fait lui-même les vitesses virtuelles, réglables dans « Vitesses virtuelles ». Dans l’appli, laisse ses propres vitesses virtuelles désactivées. En ERG, les boutons changent les watts.',
          ),
        ),
        const SizedBox(height: 8),
        ResistanceTestButton(app: app),
        SpinDownButton(app: app),
      ],
    );
  }
}
