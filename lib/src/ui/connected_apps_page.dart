// « Applis connectées » : Garmin Connect et Intervals.icu (où partent tes sorties),
// et ton compte MyWhoosh (d'où ShiftLink récupère tes sorties).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../net/garmin_connect.dart';
import '../net/send_target.dart';
import '../ride/fit_fixer.dart';
import 'garmin_login_page.dart';
import 'mywhoosh_page.dart';
import 'ride_extras.dart' show IntervalsIcuSetup;
import 'widgets.dart';

/// Connexion à Garmin depuis n'importe quel écran. Renvoie true si c'est bon.
Future<bool> connectGarmin(BuildContext context, AppState app) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Connecter Garmin Connect')),
      content: Text(
        tr(
          'La page de connexion de Garmin va s’ouvrir. ShiftLink ne voit pas ton mot de passe : il garde seulement le jeton que Garmin lui donne, sur ce téléphone.\n\nGarmin n’offre pas d’accès officiel aux petites applis : ShiftLink passe par la connexion de l’appli Garmin Connect. Garmin peut la changer ou la bloquer à tout moment.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Continuer'))),
      ],
    ),
  );
  if (ok != true) return false;
  var flow = GarminLoginFlow.mobile;
  for (var attempt = 0; attempt < 2; attempt++) {
    final got = await nav.push<(String, GarminLoginFlow)>(
      MaterialPageRoute(builder: (_) => GarminLoginPage(flow: flow)),
    );
    if (got == null) return false;
    final (ticket, used) = got;
    try {
      await app.connectGarmin(ticket, used);
      messenger.showSnackBar(SnackBar(content: Text(tr('Garmin Connect est connecté.'))));
      return true;
    } catch (e) {
      if (attempt == 1 || !context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(tr('Garmin Connect : {0}', ['$e']))));
        return false;
      }
      // Ticket refusé : on rouvre l'autre page de connexion de Garmin.
      messenger.showSnackBar(SnackBar(content: Text(tr('Garmin a refusé, on essaie l’autre connexion…'))));
      flow = used == GarminLoginFlow.mobile ? GarminLoginFlow.portal : GarminLoginFlow.mobile;
    }
  }
  return false;
}

Future<bool> connectIntervals(BuildContext context, AppState app) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => IntervalsIcuSetup(app: app));
  return ok == true && app.intervalsReady;
}

Future<void> disconnectIntervals(AppState app) async {
  await app.setIntervalsApiKey('');
}

Future<bool> connectTarget(BuildContext context, AppState app, SendTarget t) => switch (t) {
  SendTarget.garmin => connectGarmin(context, app),
  SendTarget.intervals => connectIntervals(context, app),
};

Future<void> disconnectTarget(AppState app, SendTarget t) => switch (t) {
  SendTarget.garmin => app.disconnectGarmin(),
  SendTarget.intervals => disconnectIntervals(app),
};

/// Envoie un .fit choisi dans les fichiers du téléphone vers toutes les applis connectées.
Future<void> sendFitFile(BuildContext context, AppState app) async {
  final messenger = ScaffoldMessenger.of(context);
  final targets = app.connectedTargets;
  if (targets.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Connecte d’abord une appli (Garmin Connect, Intervals.icu).'))));
    return;
  }
  final picked = await FilePicker.pickFiles();
  if (picked.isEmpty) return;
  final file = picked.first.xFile;
  if (!file.name.toLowerCase().endsWith('.fit')) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Choisis un fichier .fit.'))));
    return;
  }
  if (await file.length() > 50 * 1024 * 1024) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Fichier trop volumineux.'))));
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text(tr('Envoi en cours…'))));
  final bytes = await file.readAsBytes();
  final lines = <String>[];
  for (final t in targets) {
    try {
      lines.add(AppState.sendStatusText(t, await app.sendFitTo(t, bytes, file.name)));
    } on FitFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Fichier illisible : {0}', [tr(e.message)]))));
      return;
    } catch (e) {
      lines.add('${t.label} : $e');
    }
  }
  messenger.showSnackBar(SnackBar(content: Text(lines.join('\n'))));
}

class ConnectedAppsPage extends StatelessWidget {
  final AppState app;
  const ConnectedAppsPage({super.key, required this.app});

  static const _icons = {
    SendTarget.garmin: Icons.watch_rounded,
    SendTarget.intervals: Icons.insights_rounded,
  };

  List<Widget> _target(BuildContext context, SendTarget t) {
    final on = app.targetConnected(t);
    return [
      SectionHeader(t.label),
      GroupCard(
        children: [
          SettingRow(
            icon: _icons[t]!,
            color: on ? Tones.green : Tones.blue,
            title: on ? tr('Connecté') : tr('Pas connecté'),
            subtitle: switch (t) {
              SendTarget.garmin => tr('Connexion de l’appli Garmin Connect (pas d’API officielle)'),
              SendTarget.intervals => tr('API officielle, avec ta clé API Intervals.icu'),
            },
            trailing: on
                ? TextButton(onPressed: () => disconnectTarget(app, t), child: Text(tr('Déconnecter')))
                : FilledButton(onPressed: () => connectTarget(context, app, t), child: Text(tr('Connecter'))),
          ),
          SettingRow.toggle(
            icon: Icons.cloud_upload_rounded,
            color: Tones.teal,
            title: tr('Envoyer mes sorties tout seul'),
            subtitle: tr('Sorties enregistrées par ShiftLink et nouvelles sorties MyWhoosh'),
            value: app.targetAuto(t),
            onChanged: (v) => app.setTargetAuto(t, v),
            enabled: on,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(tr('Applis connectées'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final t in SendTarget.values) ..._target(context, t),
          SectionHeader(tr('Sorties MyWhoosh')),
          GroupCard(
            children: [
              SettingRow(
                icon: Icons.directions_bike_rounded,
                color: app.myWhooshConnected ? Tones.green : Tones.orange,
                title: app.myWhooshConnected ? tr('Compte MyWhoosh connecté') : tr('Compte MyWhoosh pas connecté'),
                subtitle: app.myWhooshConnected
                    ? tr('ShiftLink récupère tes sorties chez MyWhoosh')
                    : tr('Pour récupérer tes sorties directement chez MyWhoosh'),
                trailing: app.myWhooshConnected
                    ? TextButton(onPressed: app.disconnectMyWhoosh, child: Text(tr('Déconnecter')))
                    : FilledButton(onPressed: () => connectMyWhoosh(context, app), child: Text(tr('Connecter'))),
              ),
              SettingRow.toggle(
                icon: Icons.sync_rounded,
                color: Tones.teal,
                title: tr('Envoyer mes sorties MyWhoosh tout seul'),
                subtitle: tr('À l’ouverture de ShiftLink, vers les applis en envoi automatique'),
                value: app.myWhooshAuto && app.myWhooshConnected,
                onChanged: app.setMyWhooshAuto,
                enabled: app.myWhooshConnected,
              ),
              SettingRow(
                icon: Icons.list_alt_rounded,
                color: Tones.blue,
                title: tr('Mes sorties MyWhoosh'),
                subtitle: tr('Choisis une sortie à envoyer'),
                enabled: app.myWhooshConnected,
                onTap: app.myWhooshConnected
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyWhooshRidesPage(app: app)))
                    : null,
              ),
            ],
          ),
          ValueListenableBuilder<String?>(
            valueListenable: app.lastMyWhooshSync,
            builder: (context, v, _) => v == null
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.fromLTRB(8, 10, 8, 0), child: Text(v)),
          ),
          SectionHeader(tr('Fichier')),
          GroupCard(
            children: [
              SettingRow(
                icon: Icons.upload_file_rounded,
                color: Tones.orange,
                title: tr('Envoyer un fichier .fit'),
                subtitle: tr('Vers toutes les applis connectées : moyennes ajoutées, température retirée'),
                onTap: () => sendFitFile(context, app),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr(
                'Strava : connecte-le directement dans MyWhoosh (Profil › Connections), qui y envoie tes sorties. Polar Flow et Suunto n’acceptent pas encore les envois de ShiftLink : partage le .fit depuis Mes sorties.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}
