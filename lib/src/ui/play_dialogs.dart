// Écrans d'explication exigés par Google Play avant d'ouvrir certains réglages d'Android.
import 'package:flutter/material.dart';

import '../i18n.dart';

/// Explique à quoi sert l'accessibilité et demande l'accord, avant d'ouvrir ses réglages.
/// Vrai seulement si la personne touche « J'accepte ».
Future<bool> askAccessibilityConsent(BuildContext? context) async {
  if (context == null || !context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.accessibility_new_rounded),
      title: Text(tr('ShiftLink utilise l’accessibilité')),
      content: SingleChildScrollView(
        child: Text(
          tr(
            'ShiftLink utilise le service d’accessibilité d’Android pour une seule chose : toucher à ta place les boutons + et − de ton appli d’entraînement quand elle est ouverte sur ce téléphone, et recevoir les touches de ta télécommande Bluetooth.\n\nShiftLink ne lit pas le contenu de l’écran : il retient seulement quelle appli est au premier plan. Rien n’est enregistré ni envoyé.\n\nTu peux le désactiver à tout moment dans les réglages d’accessibilité d’Android.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Non merci'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('J’accepte'))),
      ],
    ),
  );
  return ok ?? false;
}

/// Dit quoi toucher dans la liste d'Android avant de l'ouvrir. Vrai si la personne continue.
Future<bool> explainBackgroundSettings(BuildContext? context) async {
  if (context == null || !context.mounted) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Rester actif en arrière-plan')),
      content: Text(
        tr(
          'Android va ouvrir la liste des applis. Touche « Toutes les applis », choisis ShiftLink, puis « Ne pas optimiser ». Écran éteint, ShiftLink gardera alors la manette connectée.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ouvrir les réglages'))),
      ],
    ),
  );
  return ok ?? false;
}

/// Au retour des réglages, l'accessibilité n'est pas activée : Android l'a sans doute bloquée
/// (« Paramètre restreint », pour les applis installées hors Play Store). On explique comment débloquer.
Future<void> explainRestrictedSetting(
  BuildContext? context, {
  required Future<void> Function() openAppInfo,
  required Future<void> Function() openSettings,
}) async {
  if (context == null || !context.mounted) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(tr('Android a refusé l’accès ?')),
      content: SingleChildScrollView(
        child: Text(
          tr(
            'Si Android affiche « Paramètre restreint », c’est normal pour une appli installée hors Play Store. Pour débloquer :\n\n1. Touche « Infos de l’appli » ci-dessous.\n2. Touche le menu ⋮ en haut à droite, puis « Autoriser les paramètres restreints ».\n3. Reviens et touche « Réessayer » pour activer ShiftLink.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Plus tard'))),
        TextButton(onPressed: () => Navigator.pop(c, 'retry'), child: Text(tr('Réessayer'))),
        FilledButton(onPressed: () => Navigator.pop(c, 'info'), child: Text(tr('Infos de l’appli'))),
      ],
    ),
  );
  if (choice == 'info') await openAppInfo();
  if (choice == 'retry') await openSettings();
}
