// « Envoyer mon problème » : un résumé lisible de l'état de ShiftLink.
// Rien n'est envoyé tout seul : la personne voit le texte et choisit à qui le partager.
import 'dart:io';

import 'app_state.dart';
import 'controller_manager.dart' show LinkState;

/// Une ligne de vérification (titre, bon / à corriger / à surveiller, détail).
typedef ReportCheck = ({String title, bool? ok, String detail});

/// Construit le texte du rapport. [version] : version de ShiftLink ; [what] : ce que la personne a écrit.
String buildProblemReport(
  AppState app, {
  required String version,
  String what = '',
  List<ReportCheck> checks = const [],
  int maxLogs = 80,
}) {
  final b = StringBuffer()
    ..writeln('ShiftLink $version')
    ..writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
    ..writeln();
  if (what.trim().isNotEmpty) {
    b
      ..writeln('Problème :')
      ..writeln(what.trim())
      ..writeln();
  }
  b
    ..writeln('Appli : ${app.target.name} (${app.target.transport.name}${app.sameDevice ? ', même téléphone' : ''})')
    ..writeln('Appli connectée : ${app.appHealth.name}');
  final list = app.controllers.controllers.value;
  if (list.isEmpty) b.writeln('Manette : aucune');
  for (final c in list) {
    b.writeln(
      'Manette : ${c.name} · ${c.driver.typeId} · ${c.state.value.name}'
      '${c.battery.value != null ? ' · pile ${c.battery.value} %' : ''}'
      '${c.firmware != null ? ' · firmware ${c.firmware}' : ''}'
      '${c.rssi != null ? ' · signal ${c.rssi} dBm' : ''}',
    );
  }
  final t = app.proxy.trainer;
  if (t.name.value != null) {
    b.writeln(
      'Home trainer : ${t.name.value} · ${t.state.value == LinkState.connected ? 'connecté' : t.state.value.name}',
    );
  }
  b.writeln('Changements de vitesse : ${app.shifts}');
  if (checks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Diagnostic :');
    for (final c in checks) {
      b.writeln(
        '${switch (c.ok) {
          true => '✓',
          false => '✗',
          null => '!',
        }} ${c.title} : ${c.detail}',
      );
    }
  }
  final logs = app.logs.take(maxLogs).toList();
  if (logs.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Journal (le plus récent en haut) :');
    logs.forEach(b.writeln);
  }
  return b.toString().trimRight();
}
