// « Ça ne marche pas ? » : vérifie chaque maillon et dit quoi faire.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../controller_manager.dart' show LinkState;
import '../i18n.dart';
import 'problem_page.dart';
import 'widgets.dart';

class Check {
  final String title;

  /// true = bon, false = à corriger, null = à surveiller.
  final bool? ok;
  final String detail;
  final String? fixLabel;
  final Future<void> Function()? fix;
  const Check(this.title, this.ok, this.detail, {this.fixLabel, this.fix});
}

/// Liste des vérifications pour l'état actuel.
Future<List<Check>> runChecks(AppState app) async {
  final demo = app.demo;
  final bt = demo ? BluetoothAdapterState.on : FlutterBluePlus.adapterStateNow;
  final perms = demo || await Permission.bluetoothConnect.isGranted;
  final service = demo || await FlutterForegroundTask.isRunningService;
  final battery = demo || await FlutterForegroundTask.isIgnoringBatteryOptimizations;
  final t = app.target;
  final network = t.transport != Transport.keyboard;
  final private = app.ips
      .where((ip) => ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.'))
      .toList();
  final controllers = app.controllers.controllers.value;
  final connected = controllers.where((c) => c.state.value == LinkState.connected).toList();

  return [
    Check(
      'Bluetooth',
      bt == BluetoothAdapterState.on,
      bt == BluetoothAdapterState.on
          ? tr('Activé')
          : tr('Le Bluetooth du téléphone est coupé. Android demande de l’allumer toi-même dans ses réglages.'),
      fixLabel: tr('Ouvrir les réglages'),
      fix: () async {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        await app.taps.openBluetoothSettings();
      },
    ),
    Check(
      tr('Autorisations'),
      perms,
      perms
          ? tr('Appareils à proximité : autorisé')
          : tr('ShiftLink n’a pas le droit de chercher les appareils Bluetooth.'),
      fixLabel: tr('Autoriser'),
      fix: () async => app.askPermissions(),
    ),
    Check(
      tr('Manette'),
      connected.isNotEmpty ? true : (controllers.isEmpty ? false : null),
      connected.isNotEmpty
          ? connected.map((c) => c.name).join(', ')
          : controllers.isEmpty
          ? tr(
              'Aucune manette. Allume-la et appuie sur un bouton. Une manette Zwift ne se connecte qu’à une app à la fois : ferme Zwift Companion.',
            )
          : tr('Trouvée, connexion en cours…'),
      fixLabel: tr('Chercher'),
      fix: () async {
        if (await app.askPermissions()) await app.controllers.scan();
      },
    ),
    if (network)
      Check(
        'Wi-Fi',
        private.isNotEmpty,
        private.isNotEmpty
            ? tr(
                'Connecté au Wi-Fi. L’appli doit être sur le même réseau (pas un réseau invité, pas d’isolation des appareils).',
              )
            : tr('Le téléphone n’a pas d’adresse Wi-Fi locale. Connecte-le au Wi-Fi de la maison.'),
      ),
    if (t.transport == Transport.proxy)
      Check(
        tr('Home trainer'),
        app.proxy.trainer.isConnected,
        app.proxy.trainer.isConnected
            ? (app.proxy.trainer.name.value ?? tr('Connecté'))
            : tr(
                'Pas connecté. Réglages > Connexion : choisis ton trainer. Ferme les autres applis qui s’y connectent.',
              ),
      ),
    if (t.transport == Transport.keyboard && app.sameDevice) ...[
      Check(
        tr('Accessibilité'),
        app.taps.enabled.value,
        app.taps.enabled.value ? tr('Activée') : tr('ShiftLink ne peut pas toucher l’écran sans l’accessibilité.'),
        fixLabel: tr('Ouvrir'),
        fix: app.taps.openSettings,
      ),
      Check(
        tr('Positions des boutons'),
        app.tapsReady,
        app.tapsReady ? tr('Réglées') : tr('Règle les positions + et − dans Réglages > Connexion.'),
      ),
    ] else if (t.transport == Transport.keyboard)
      Check(
        tr('Clavier Bluetooth'),
        app.keyboard.connectedHost.value != null,
        app.keyboard.connectedHost.value != null
            ? tr('Connecté à {0}', [app.keyboard.connectedHost.value])
            : tr(
                'Pas connecté. Appaire « ShiftLink » depuis l’ordinateur ou la tablette, puis choisis-le dans la liste.',
              ),
      ),
    Check(
      t.label,
      switch (app.appHealth) {
        Health.ok => true,
        Health.waiting => null,
        Health.off => false,
      },
      switch (app.appHealth) {
        Health.ok => tr('Connecté'),
        Health.waiting => switch (t.transport) {
          Transport.link => tr(
            'ShiftLink attend MyWhoosh. Dans MyWhoosh, choisis la connexion « Link » et ferme l’app MyWhoosh Link.',
          ),
          Transport.obc => tr(
            'ShiftLink attend l’appli. Ajoute la manette OpenBikeControl « ShiftLink » dans ses réglages.',
          ),
          Transport.proxy => tr('ShiftLink attend l’appli. Dans {0}, appaire le trainer « ShiftLink » (Wi-Fi).', [
            t.label,
          ]),
          Transport.zwiftRide => tr('ShiftLink attend Zwift. Dans Zwift, appaire la manette Zwift Ride « ShiftLink ».'),
          Transport.keyboard => tr('En attente.'),
        },
        Health.off => tr('Pas démarré : refais l’étape « Connexion ».'),
      },
    ),
    Check(
      tr('Arrière-plan'),
      service && battery ? true : null,
      service
          ? (battery
                ? tr('ShiftLink reste actif écran éteint ou derrière l’appli.')
                : tr('Android peut endormir ShiftLink pour économiser la batterie.'))
          : tr(
              'La notification « ShiftLink est actif » n’est pas affichée : ShiftLink peut s’arrêter en arrière-plan.',
            ),
      fixLabel: battery ? null : tr('Ne pas optimiser'),
      fix: battery ? null : app.allowBackground,
    ),
  ];
}

class DiagnosticPage extends StatefulWidget {
  final AppState app;
  const DiagnosticPage({super.key, required this.app});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  List<Check>? _checks;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final c = await runChecks(widget.app);
    if (mounted) setState(() => _checks = c);
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks;
    final bad = checks?.where((c) => c.ok == false).length ?? 0;
    final warn = checks?.where((c) => c.ok == null).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Diagnostic')),
        actions: [IconButton(tooltip: tr('Relancer'), onPressed: _run, icon: const Icon(Icons.refresh))],
      ),
      body: checks == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                StatusPill(
                  icon: bad == 0 ? Icons.check_circle_outline : Icons.build_outlined,
                  title: bad == 0 && warn == 0
                      ? tr('Tout est bon')
                      : bad > 0
                      ? tr('{0} point{1} à corriger', [bad, bad > 1 ? 's' : ''])
                      : tr('{0} point{1} à surveiller', [warn, warn > 1 ? 's' : '']),
                  subtitle: tr('Vérifié dans l’ordre : du téléphone jusqu’à l’appli'),
                  health: bad > 0 ? Health.off : (warn > 0 ? Health.waiting : Health.ok),
                ),
                const SizedBox(height: 12),
                for (final c in checks)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              switch (c.ok) {
                                true => Icons.check_circle,
                                false => Icons.cancel,
                                null => Icons.error,
                              },
                              color: healthColor(context, switch (c.ok) {
                                true => Health.ok,
                                false => Health.off,
                                null => Health.waiting,
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(c.detail),
                              ],
                            ),
                          ),
                          if (c.ok != true && c.fix != null && c.fixLabel != null)
                            TextButton(
                              onPressed: () async {
                                await c.fix!();
                                await Future.delayed(const Duration(milliseconds: 500));
                                unawaited(_run());
                              },
                              child: Text(c.fixLabel!),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProblemPage(app: widget.app))),
                  icon: const Icon(Icons.support_agent_rounded),
                  label: Text(tr('Toujours bloqué ? Envoyer mon problème')),
                ),
              ],
            ),
    );
  }
}
