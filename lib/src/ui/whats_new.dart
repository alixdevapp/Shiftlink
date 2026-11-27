// « Quoi de neuf » : montré une fois après une mise à jour de ShiftLink.
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../net/update_check.dart';

/// Nouveautés par version, la plus récente en premier.
List<(String, List<(IconData, String)>)> whatsNew() => [
  (
    '2.23',
    [
      (Icons.sports_esports_rounded, tr('Zwift Play et Zwift Ride : chaque palette a deux boutons, vers l’intérieur et vers l’extérieur, à régler chacun. Tes réglages actuels valent pour les deux.')),
      (Icons.lock_rounded, tr('Elite Rizer verrouillé (LED rouge) : ShiftLink l’affiche sous le Rizer et ne note plus un refus par seconde dans le journal.')),
      (Icons.apps_rounded, tr('PedalCraft, suffer.online, Kardiacs, Sueur et TrainerKit sont reconnus par leur nom en OpenBikeControl.')),
    ],
  ),
  (
    '2.22',
    [
      (Icons.system_update_rounded, tr('ShiftLink se met à jour tout seul : quand une nouvelle version sort, touche « Mettre à jour » et Android l’installe en gardant tes réglages.')),
      (Icons.apps_rounded, tr('Everycol a sa propre ligne dans la liste des applis (OpenBikeControl en Bluetooth).')),
      (Icons.keyboard_rounded, tr('Clavier Bluetooth : chaque touche reste appuyée 50 ms, pour les jeux sur ordinateur qui ratent les appuis trop courts.')),
    ],
  ),
  (
    '2.21',
    [
      (
        Icons.hub_rounded,
        tr('Applis connectées : tes sorties (ShiftLink et MyWhoosh) partent sur Garmin Connect et Intervals.icu. Réglages › Automatique › Applis connectées.'),
      ),
    ],
  ),
  (
    '2.19',
    [
      (
        Icons.sync_rounded,
        tr('Connecte ton compte MyWhoosh : tes nouvelles sorties partent toutes seules sur Garmin Connect. Réglages › Automatique › Garmin Connect.'),
      ),
    ],
  ),
  (
    '2.18',
    [
      (
        Icons.watch_rounded,
        tr('Garmin Connect : envoie tes sorties ShiftLink tout seul, ou un .fit de MyWhoosh (moyennes réparées). Réglages › Automatique.'),
      ),
    ],
  ),
  (
    '2.17.1',
    [
      (
        Icons.lock_rounded,
        tr('Le bouton SIM / ERG et Power Lock disent pourquoi ils ne s’activent pas : pédaler d’abord, trainer à connecter, ou séance ERG de l’appli.'),
      ),
    ],
  ),
  (
    '2.17',
    [
      (Icons.pedal_bike_rounded, tr('Tacx NEO Bike (bêta) : ses manettes et ses deux boutons pilotent ShiftLink.')),
      (
        Icons.air_rounded,
        tr('Ventilateur Headwind : il peut suivre ta ceinture cardio reliée à ShiftLink, et tu règles où il démarre et où il est à fond.'),
      ),
      (Icons.terrain_rounded, tr('Elite Rizer : sa pente réelle s’affiche, et une pente refusée est notée dans le journal.')),
    ],
  ),
  (
    '2.16',
    [
      (Icons.gamepad_rounded, tr('Manettes du vélo CYCPLUS T7 (bêta) : dissocie-les d’abord du vélo dans l’appli CYCPLUS.')),
      (Icons.apps_rounded, tr('Rampida a sa propre ligne dans la liste des applis.')),
    ],
  ),
  (
    '2.15',
    [
      (Icons.air_rounded, tr('Ventilateur Headwind : nouveau mode « Suit ta puissance ».')),
      (Icons.credit_card_off_rounded, tr('Les lecteurs de cartes Square ne sont plus pris pour une manette Elite Square.')),
    ],
  ),
  (
    '2.14',
    [
      (Icons.bluetooth_rounded, tr('Biketerra : choisis le clavier ou OpenBikeControl en Bluetooth.')),
      (Icons.label_rounded, tr('Le vrai nom de ton appli OpenBikeControl s’affiche : Warp, Tour du Pain, Vieta…')),
      (Icons.wifi_rounded, tr('Un trainer Elite vu en Bluetooth et en Wi-Fi est signalé comme le même.')),
    ],
  ),
  (
    '2.13',
    [
      (
        Icons.monitor_heart_rounded,
        tr('Séances au cardio : les watts suivent ton cœur pour rester en endurance ou en récupération.'),
      ),
      if (updateRepo.isNotEmpty)
        (
          Icons.system_update_rounded,
          tr('ShiftLink peut te prévenir quand une nouvelle version sort (Réglages > Aide).'),
        ),
    ],
  ),
  (
    '2.12',
    [
      (
        Icons.pedal_bike_rounded,
        tr('Chaque cycliste a son poids de vélo : un VTT de 14 kg ou un vélo de route de 7 kg change les côtes.'),
      ),
    ],
  ),
  (
    '2.11',
    [
      (Icons.lock_outline_rounded, tr('Power Lock : garde tes watts même quand la route monte.')),
      (Icons.bluetooth_rounded, tr('OpenBikeControl en Bluetooth : Grimpa, Ride Cave, Velotoss et 12 autres applis.')),
      (Icons.sports_esports_rounded, tr('Zwift : ShiftLink peut se faire passer pour une manette Zwift Ride (bêta).')),
      (Icons.speed_rounded, tr('Vitesse et distance calculées avec ta puissance, la pente et ton poids.')),
      (Icons.devices_other_rounded, tr('Anciens Wahoo KICKR et Saris Hammer, Magene Onelap Key, Di2 plus fiable.')),
      (
        Icons.dashboard_customize_rounded,
        tr(
          'Écran Rouler : SIM ou ERG d’un appui, profil de vitesses, fenêtre flottante avec boutons − et +. Et le chinois.',
        ),
      ),
    ],
  ),
  (
    '2.10',
    [
      (Icons.map_rounded, tr('Tes parcours arrivent avec leur carte et leur dénivelé dans Strava et Intervals.icu.')),
      (Icons.restart_alt_rounded, tr('Reprends un parcours là où tu t’es arrêté, ou pars du km que tu veux.')),
      (Icons.flag_rounded, tr('Séances : un tour par bloc dans le fichier de la sortie, pour voir chaque intervalle.')),
      (
        Icons.chat_bubble_outline_rounded,
        tr('Fichiers .zwo : la cadence demandée et les messages du coach s’affichent et sont lus à voix haute.'),
      ),
      (Icons.tune_rounded, tr('Calibre ton home trainer depuis ShiftLink, s’il le permet.')),
      (Icons.terrain_rounded, tr('Jusqu’à 200 parcours, et les gros fichiers GPX passent.')),
    ],
  ),
  (
    '2.9',
    [
      (Icons.pause_circle_rounded, tr('Bouton pause pendant les séances et les parcours.')),
      (
        Icons.all_inclusive_rounded,
        tr('Vitesses infinies, et « Tout plus dur / Tout plus facile » sur l’écran Rouler.'),
      ),
      (Icons.child_care_rounded, tr('Mode enfant par cycliste : pente et watts plafonnés.')),
      (
        Icons.trending_up_rounded,
        tr('Test FTP en rampe : il s’arrête tout seul quand tu lâches et enregistre ta FTP.'),
      ),
      (Icons.vibration_rounded, tr('Les Zwift Play et Ride vibrent à chaque vitesse.')),
      (
        Icons.verified_rounded,
        tr(
          'Plus fiable : manette coupée en plein appui, vrai clavier Bluetooth, mise en veille, bouton Arrêter dans la notification.',
        ),
      ),
    ],
  ),
  (
    '2.8',
    [
      (Icons.edit_note_rounded, tr('Crée tes propres séances : blocs, rampes et séries.')),
      (Icons.lock_clock_rounded, tr('ERG fixe : une puissance constante, quelle que soit ta cadence.')),
      (Icons.insights_rounded, tr('Statistiques : meilleurs efforts, courbe de puissance, forme et fatigue.')),
      (Icons.timer_rounded, tr('Compte à rebours : 3 bips et une annonce avant chaque changement de bloc.')),
      (Icons.cloud_upload_rounded, tr('Envoie tes sorties sur Intervals.icu.')),
      (Icons.directions_bike_rounded, tr('Compatible avec Incyclist.')),
    ],
  ),
  (
    '2.7',
    [
      (
        Icons.people_alt_rounded,
        tr('Cyclistes : un profil par personne (poids, FTP, cardio), choisi d’un appui sur l’écran Rouler.'),
      ),
      (
        Icons.fitness_center_rounded,
        tr('Nouvel onglet Séances : le trainer règle les watts tout seul, sans appli. Ajoute tes fichiers Zwift .zwo.'),
      ),
      (Icons.touch_app_rounded, tr('Reste appuyé sur + ou − : les vitesses défilent.')),
      (Icons.close_rounded, tr('Pouvoir quitter « Refaire la configuration » à tout moment.')),
      (Icons.exposure_rounded, tr('En séance, + et − changent les watts.')),
      (Icons.favorite_rounded, tr('Zones cardio en couleur pendant la sortie.')),
      (Icons.bolt_rounded, tr('Watts estimés quand le home trainer ne les mesure pas.')),
      (Icons.dashboard_customize_rounded, tr('Choisis les chiffres affichés pendant la sortie.')),
      (Icons.settings_rounded, tr('La cassette a un pignon par vitesse de ton appli (30 pour MyWhoosh, 24 sinon).')),
      (Icons.screen_rotation_alt_rounded, tr('Tourner avec ce téléphone : marche aussi quand le guidon vibre.')),
    ],
  ),
  (
    '2.6',
    [
      (
        Icons.record_voice_over_rounded,
        tr(
          'Une voix prévient si la manette se déconnecte ou n’a plus de pile, et annonce ta vitesse quand ShiftLink pilote le trainer. Tu peux la couper dans Réglages.',
        ),
      ),
      (Icons.battery_alert_rounded, tr('ShiftLink te prévient quand la pile de la manette devient faible.')),
      (
        Icons.support_agent_rounded,
        tr('« Envoyer mon problème » : un texte prêt à partager, seulement si tu le veux.'),
      ),
      (Icons.view_module_rounded, tr('Une tuile ShiftLink dans les réglages rapides d’Android.')),
      (Icons.system_update_rounded, tr('Un bouton pour mettre à jour ta manette dans l’appli de sa marque.')),
    ],
  ),
  ('2.5', [(Icons.school_rounded, tr('ShiftLink apprend les boutons d’une manette qu’il ne connaît pas.'))]),
  ('2.4', [(Icons.history_rounded, tr('Mes sorties, Compatible avec, Mots, TrainerRoad, néerlandais et portugais.'))]),
];

/// Ouvre la feuille des nouveautés. [onlyLatest] : seulement la dernière version.
Future<void> showWhatsNew(BuildContext context, {bool onlyLatest = false}) {
  final list = onlyLatest ? whatsNew().take(1).toList() : whatsNew();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Quoi de neuf'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            for (final (version, items) in list) ...[
              const SizedBox(height: 14),
              Text(
                tr('Version {0}', [version]),
                style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary),
              ),
              for (final (icon, text) in items)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Super !'))),
          ],
        ),
      ),
    ),
  );
}
