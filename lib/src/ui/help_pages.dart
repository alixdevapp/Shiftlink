// Aide : « Compatible avec » (avec recherche) et « Mots » (petit lexique avec synonymes).
import 'package:flutter/material.dart';

import '../app_state.dart' show TargetApp;
import '../controllers/registry.dart';
import '../i18n.dart';
import 'widgets.dart';

/// Une ligne cherchable : titre, détail, et rubrique.
typedef HelpItem = ({String section, String title, String detail});

/// Recherche sans accents ni majuscules : « velo » trouve « Vélo ».
String _fold(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Page avec une barre de recherche et des rubriques repliées en cartes.
class _SearchList extends StatefulWidget {
  final String title;
  final String hint;
  final List<HelpItem> items;
  final IconData Function(String section) iconOf;
  const _SearchList({required this.title, required this.hint, required this.items, required this.iconOf});

  @override
  State<_SearchList> createState() => _SearchListState();
}

class _SearchListState extends State<_SearchList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _fold(_q.trim());
    final shown = widget.items
        .where((i) => q.isEmpty || _fold('${i.title} ${i.detail} ${i.section}').contains(q))
        .toList();
    final sections = <String>[];
    for (final i in shown) {
      if (!sections.contains(i.section)) sections.add(i.section);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.hint,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text(
                tr(
                  'Rien trouvé pour « {0} ». Si ton appareil parle Bluetooth FTMS, il y a de bonnes chances qu’il marche quand même.',
                  [_q],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          for (final s in sections) ...[
            SectionHeader(s),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final i in shown.where((i) => i.section == s))
                    ListTile(
                      leading: Icon(widget.iconOf(s), color: cs.primary),
                      title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: i.detail.isEmpty ? null : Text(i.detail),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tout ce qui marche avec ShiftLink : manettes, home trainers, applis, capteurs.
class CompatibilityPage extends StatelessWidget {
  const CompatibilityPage({super.key});

  /// Applis qui parlent OpenBikeControl (en plus de celles de la liste des applis).
  static const obcApps = [
    'Strappo',
    'Grimpa',
    'Ride Cave',
    'Velotoss',
    'icTrainer',
    'Auuki',
    'VoxVelo',
    'VeloWorkout',
    'Pedalparty',
    'VeloPopuli',
    'Vieta',
    'DirtWatts',
    'WattLog.pro',
    'REZVIVO',
    'OpenRadlr',
    'zwoTrainer',
  ];

  static List<HelpItem> items() {
    final ctrl = tr('Manettes');
    final ht = tr('Home trainers');
    final apps = tr('Applis d’entraînement');
    final sensors = tr('Capteurs et services');
    return [
      for (final s in supportedControllers) (section: ctrl, title: tr(s), detail: ''),
      (
        section: ht,
        title: tr('Tout home trainer Bluetooth « FTMS »'),
        detail: tr('La langue commune de la plupart des home trainers récents.'),
      ),
      for (final b in [
        'Wahoo KICKR, KICKR Core, KICKR Move',
        'Tacx Neo, Flux, Flow (Garmin)',
        'Elite Suito, Direto, Justo',
        'Zwift Hub',
        'Saris H3',
        'JetBlack Volt',
        'ThinkRider',
        'Van Rysel (Decathlon) D100, D500',
        'Magene T300, T600',
      ])
        (section: ht, title: b, detail: tr('En Bluetooth FTMS')),
      (
        section: ht,
        title: tr('Anciens Tacx et Elite (ANT+ FE-C par Bluetooth)'),
        detail: tr('ShiftLink traduit leurs messages tout seul.'),
      ),
      (
        section: ht,
        title: tr('Anciens Wahoo KICKR, KICKR Snap, Saris Hammer et H2 (bêta)'),
        detail: tr('Avant FTMS : ShiftLink parle leur ancien protocole Wahoo.'),
      ),
      (
        section: ht,
        title: tr('Wahoo KICKR en Wi-Fi ou câble (Direct Connect)'),
        detail: tr('Trouvé tout seul s’il est sur le même réseau que le téléphone.'),
      ),
      for (final t in TargetApp.pickable) (section: apps, title: t.label, detail: t.description),
      for (final a in obcApps)
        (section: apps, title: a, detail: tr('Avec la manette OpenBikeControl « ShiftLink », en Wi-Fi ou en Bluetooth')),
      (
        section: apps,
        title: 'FulGaz, Tacx Training',
        detail: tr('Avec le mode relais : ShiftLink se place entre le trainer et l’appli'),
      ),
      (
        section: sensors,
        title: tr('Ceinture cardio Bluetooth'),
        detail: tr('Polar, Garmin HRM, Wahoo TICKR, montres qui diffusent le cardio…'),
      ),
      (
        section: sensors,
        title: tr('Capteur de cadence Bluetooth'),
        detail: tr('Pour les home trainers qui n’envoient pas la cadence.'),
      ),
      (
        section: sensors,
        title: tr('Capteur de puissance Bluetooth'),
        detail: tr('Pédales ou manivelle : plus précis que le home trainer.'),
      ),
      (section: sensors, title: 'Health Connect', detail: tr('Tes sorties arrivent dans Santé Connect (Android).')),
      (section: sensors, title: tr('Fichier .fit'), detail: tr('Pour Strava, Garmin Connect, intervals.icu…')),
    ];
  }

  @override
  Widget build(BuildContext context) => _SearchList(
    title: tr('Compatible avec'),
    hint: tr('Cherche ton matériel ou ton appli'),
    items: items(),
    iconOf: (s) => s == tr('Manettes')
        ? Icons.gamepad_rounded
        : s == tr('Home trainers')
        ? Icons.pedal_bike_rounded
        : s == tr('Applis d’entraînement')
        ? Icons.sports_esports_rounded
        : Icons.sensors_rounded,
  );
}

/// Petit lexique : chaque mot, ses synonymes, et une explication simple.
class WordsPage extends StatelessWidget {
  const WordsPage({super.key});

  /// (mot, synonymes, explication)
  static List<(String, String, String)> words() => [
    (
      tr('Home trainer'),
      tr('HT, rouleau, smart trainer'),
      tr('Le support qui tient ton vélo à la maison et freine la roue pour faire comme une vraie route.'),
    ),
    (
      tr('Manette'),
      tr('contrôleur, commande, télécommande, shifter'),
      tr('Les boutons sur ton guidon. Tu appuies, la vitesse change.'),
    ),
    (
      tr('Vitesses virtuelles'),
      tr('virtual shifting, MyShift'),
      tr('Tu changes de vitesse dans l’appli, sans toucher à la chaîne du vélo.'),
    ),
    (
      tr('Braquet'),
      tr('vitesse, rapport, développement, gear'),
      tr('La combinaison plateau et pignon. Grand braquet = dur, petit braquet = facile.'),
    ),
    (tr('Plateau'), tr('chainring'), tr('La grande roue dentée devant, près des pédales.')),
    (tr('Pignon'), tr('cassette, sprocket'), tr('Les petites roues dentées sur la roue arrière.')),
    (
      tr('Cadence'),
      tr('tr/min, RPM, moulinage'),
      tr('Combien de tours de pédales tu fais en une minute. 80 à 95, c’est confortable.'),
    ),
    (tr('Puissance'), tr('watts, W, power'), tr('La force que tu mets dans les pédales, à chaque instant.')),
    (
      tr('FTP'),
      tr('seuil, puissance au seuil'),
      tr('La puissance que tu peux tenir environ une heure. Elle sert à régler les séances.'),
    ),
    (
      tr('Mode ERG'),
      tr('puissance imposée, ERG'),
      tr(
        'Le home trainer règle la résistance tout seul pour que tu pédales à la puissance demandée, quelle que soit ta vitesse.',
      ),
    ),
    (
      tr('Mode simulation'),
      tr('SIM, pente, mode parcours'),
      tr('Le home trainer devient plus dur dans les montées et plus facile dans les descentes.'),
    ),
    (tr('Résistance'), tr('niveau, freinage'), tr('À quel point le home trainer freine la roue.')),
    (tr('Fréquence cardiaque'), tr('FC, cardio, BPM, HR'), tr('Combien de fois ton cœur bat en une minute.')),
    (tr('Ceinture cardio'), tr('capteur cardio, HRM'), tr('La sangle sur la poitrine qui mesure ton cœur.')),
    (tr('Appairer'), tr('associer, connecter, pairing'), tr('Relier deux appareils en Bluetooth la première fois.')),
    (
      tr('Bluetooth'),
      tr('BLE, Bluetooth Low Energy'),
      tr('La liaison sans fil entre le téléphone, la manette et le home trainer.'),
    ),
    (tr('ANT+'), tr('ANT'), tr('Une autre liaison sans fil, surtout sur les compteurs et les anciens home trainers.')),
    (tr('FTMS'), tr('Fitness Machine Service'), tr('La langue Bluetooth commune des home trainers récents.')),
    (tr('FE-C'), tr('ANT+ FE-C'), tr('La langue des home trainers Tacx et Elite plus anciens.')),
    (
      tr('OpenBikeControl'),
      tr('OBC, l’icône guidon'),
      tr('La langue commune des manettes. MyWhoosh la comprend : c’est l’icône guidon avec le Wi-Fi.'),
    ),
    (
      tr('Direct Connect'),
      tr('DIRCON, Wi-Fi, câble'),
      tr('Brancher un Wahoo KICKR par le réseau au lieu du Bluetooth.'),
    ),
    (
      tr('Mode relais'),
      tr('proxy, pont'),
      tr('ShiftLink se place entre ton home trainer et l’appli, pour ajouter les vitesses virtuelles.'),
    ),
    (
      tr('Fichier .fit'),
      tr('activité, sortie'),
      tr('Le fichier de ta sortie, à envoyer sur Strava ou Garmin Connect.'),
    ),
    (tr('Direction'), tr('steering, tourner'), tr('Tourner à gauche ou à droite dans les applis qui le permettent.')),
  ];

  @override
  Widget build(BuildContext context) => _SearchList(
    title: tr('Mots'),
    hint: tr('Cherche un mot'),
    items: [
      for (final (w, syn, def) in words())
        (section: _fold(w).substring(0, 1).toUpperCase(), title: w, detail: '$def\n${tr('Aussi appelé : {0}', [syn])}'),
    ]..sort((a, b) => _fold(a.title).compareTo(_fold(b.title))),
    iconOf: (_) => Icons.menu_book_rounded,
  );
}
