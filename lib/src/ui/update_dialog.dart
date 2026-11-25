// Mise à jour depuis l'appli : téléchargement de l'APK de la release GitHub, puis
// installeur d'Android (qui garde les réglages et vérifie la signature).
import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../net/update_check.dart';

/// Propose puis lance la mise à jour vers [u].
Future<void> runUpdate(BuildContext context, UpdateInfo u) async {
  final progress = ValueNotifier<double?>(null);
  final messenger = ScaffoldMessenger.of(context);
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mise à jour vers ShiftLink {0}', [u.version])),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Téléchargement…')),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: v),
              if (v != null) ...[const SizedBox(height: 8), Text('${(v * 100).round()} %')],
            ],
          ),
        ),
      ),
    ).whenComplete(() => open = false),
  );
  final r = await downloadAndInstall(u, onProgress: (v) => progress.value = v);
  if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  final msg = switch (r) {
    UpdateResult.started => null,
    UpdateResult.openedInBrowser => null,
    UpdateResult.needsPermission => tr(
      'Autorise ShiftLink à installer des applis, puis touche à nouveau « Mettre à jour ».',
    ),
    UpdateResult.failed => tr('La mise à jour n’a pas pu être téléchargée. Vérifie ta connexion et réessaie.'),
  };
  if (msg != null) messenger.showSnackBar(SnackBar(duration: const Duration(seconds: 8), content: Text(msg)));
}
