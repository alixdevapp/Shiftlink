# ShiftLink

ShiftLink passe les **vitesses virtuelles** de ton appli d'entraînement avec une
manette Bluetooth, quel que soit le home trainer.

Le home trainer reste connecté directement à l'appli, qui gère la résistance et
les vitesses virtuelles. ShiftLink lit les boutons de la manette et transmet
« vitesse + / − » à l'appli :

| Appli | Comment |
|---|---|
| MyWhoosh | Connexion « Link » (Wi-Fi local, TCP 21587, même protocole que l'app MyWhoosh Link) |
| Rouvy | Clavier Bluetooth : `.` et `,` (activer les « Virtual Shifting Controls ») |
| TrainingPeaks Virtual | Clavier Bluetooth : `+` et `−` du pavé numérique |
| Biketerra | Clavier Bluetooth : `W` et `S` |
| Autres applis avec raccourcis clavier | Clavier Bluetooth, touches personnalisées |
| Applis compatibles OpenBikeControl | Protocole ouvert, découverte automatique sur le Wi-Fi (TCP 36867) |
| Zwift et applis sans vitesses virtuelles | Mode « Vitesses virtuelles ShiftLink » (voir plus bas) |

En mode clavier, le téléphone se présente comme un clavier Bluetooth (profil HID,
Android 9 ou plus) à l'ordinateur ou la tablette où tourne l'appli.

## Installer l'APK

ShiftLink n'est pas sur le Play Store : l'APK se télécharge depuis la page
**Releases** de ce dépôt.

1. Sur le téléphone Android (8 ou plus), ouvre la dernière release et touche
   `ShiftLink-x.y.z.apk` pour le télécharger.
2. Ouvre le fichier téléchargé. Si Android le demande, autorise ton navigateur
   (ou ton gestionnaire de fichiers) à **installer des applis inconnues**, puis
   touche **Installer**.
3. Si Play Protect affiche « Appli non reconnue », touche **Plus de détails >
   Installer quand même**. C'est normal pour une appli hors Play Store.
4. Lance ShiftLink : l'assistant de démarrage te guide pour le reste.

### Autoriser les paramètres restreints (Android 13 et plus)

Pour toucher l'écran à ta place, lire les télécommandes Bluetooth ou les
touches de volume, ShiftLink utilise un **service d'accessibilité**. Sur une
appli installée hors Play Store, Android grise ce service et affiche
« Paramètre restreint ». Pour le débloquer, une seule fois :

1. Essaie d'activer ShiftLink dans **Paramètres > Accessibilité > Applis
   installées** : Android refuse et affiche « Paramètre restreint ». C'est cette
   tentative qui débloque l'étape suivante.
2. Va dans **Paramètres > Applis > ShiftLink**.
3. Touche le menu **⋮** en haut à droite, puis **Autoriser les paramètres
   restreints**, et confirme avec ton code ou ton empreinte.
4. Reviens dans **Paramètres > Accessibilité > ShiftLink** et active le service.

ShiftLink t'y guide depuis l'assistant et depuis Réglages > Ça ne marche pas ?
Le service d'accessibilité n'est utile que pour les touches à l'écran et les
télécommandes : les manettes Bluetooth, le clavier Bluetooth, MyWhoosh Link et
OpenBikeControl marchent sans lui.

Les noms de menus varient un peu selon la marque (Samsung, Xiaomi…). Si le
menu ⋮ n'apparaît pas, refais l'étape 1 puis réessaie.

### Mettre à jour

Télécharge le nouvel APK et installe-le par-dessus : les réglages sont gardés.
Les APK des releases sont tous signés avec la même clé. Une version compilée
par quelqu'un d'autre ne s'installe pas par-dessus (il faut d'abord
désinstaller, ce qui efface les réglages ; fais une sauvegarde avant dans
Réglages > Sauvegarde et partage).

### Vérifier le fichier (facultatif)

Chaque release donne l'empreinte SHA-256 de l'APK. Sur un ordinateur :
`sha256sum ShiftLink-x.y.z.apk` (Linux/macOS) ou
`certutil -hashfile ShiftLink-x.y.z.apk SHA256` (Windows).

## Vitesses virtuelles ShiftLink (Zwift…)

ShiftLink se connecte lui-même au home trainer (FTMS, Bluetooth) et se présente à
l'appli comme un trainer Wi-Fi (protocole Wahoo Direct Connect, TCP 36866, mDNS
`_wahoo-fitness-tnp._tcp`). Quand l'appli demande une pente, ShiftLink l'ajuste
selon la vitesse engagée avant de l'envoyer au trainer :

- pente + roulement multipliés par le rapport k de la vitesse ;
- coefficient aérodynamique multiplié par k³, vent divisé par k.

24 vitesses, du rapport ×0,5 au rapport ×2. En mode ERG, la puissance passe
telle quelle et les vitesses n'ont pas d'effet.

## Manettes reconnues

| Manette | Remarque |
|---|---|
| ThinkRider VS200 | |
| CYCPLUS BC2 | |
| Zwift Click (1re génération) | |
| Zwift Click v2 | Réglage « Click v2 : côté droit seul » : rien à faire dans Zwift (+ = plus dur, B = plus facile). Sinon, la connecter 30 s dans l'appli Zwift chaque jour pour avoir les deux côtés |
| Zwift Play (firmware 2) | Chaque poignée se connecte seule (bêta) |
| Zwift Play | Gauche = vitesse −, droite = vitesse + (bouton latéral ou palette) |
| Zwift Ride et Ride V2 | Connexion à la poignée gauche, qui relaie la droite. La Ride V2 (firmware 1.3 et plus) doit être déverrouillée dans l'appli Zwift : ShiftLink le dit quand elle est verrouillée |
| WHEELTOP EDS (OX, TX) | Bêta. Dérailleur arrière éteint. Interrupteur sur R = vitesses, sur T = deux boutons de plus |
| Elite Square | Leviers de vitesses gauche et droit |
| Shimano Di2 | Boutons réglés en canaux D-Fly dans E-TUBE : canaux 1/3 = +, 2/4 = − |
| SRAM AXS | Un appui = +, double appui = − |
| Wahoo KICKR Bike, Bike Shift, Bike Pro | Boutons droits = +, gauches = − |
| Tacx NEO Bike (Smart, Plus) | Bêta. Firmware 4.5 et plus. Chaque changement de vitesse sur les manettes = + ou −, boutons gauche / droit = tourner. Relier aussi le vélo comme home trainer |
| Elite Sterzo Smart | Direction : tourner le guidon fait tourner le coureur (maintien gauche / droite) |
| Elite Rizer | Bêta. Direction comme le Sterzo, et l'avant du vélo suit la pente de l'appli ; la pente qu'il rapporte s'affiche, un refus est noté dans le journal |
| Wahoo KICKR Climb | Bêta, dans Appareils > Accessoires : l'avant du vélo suit la pente de l'appli (−10 à +19 %) |
| Ce téléphone au guidon | Réglages > Tourner avec ce téléphone. Marche dans n'importe quelle position du téléphone |

Sans manette, les gros boutons + et − de l'écran marchent aussi.

## Utilisation

Au premier lancement, un assistant en 6 étapes guide la configuration : choix de
l'appli, autorisations, recherche et test de la manette, connexion à l'appli.
Il peut être relancé depuis les réglages.

Pendant la séance, l'écran principal montre si tout est prêt, la vitesse en cours
(mode Zwift / proxy) ou le dernier changement, et l'état de chaque appareil.

Pour MyWhoosh : le téléphone et l'appareil MyWhoosh doivent être sur le même Wi-Fi
(pas de réseau invité ni d'isolation des clients), et l'app « MyWhoosh Link » doit
être fermée (elle utilise le même port). Dans MyWhoosh, choisir la connexion « Link ».

ShiftLink peut tourner sur le même appareil que l'appli : une notification
« ShiftLink est actif » le garde en vie en arrière-plan.

Captures et icônes : `flutter test test_screens --update-goldens` (dans `test_screens/out`).

## Boutons personnalisables

Appareils > (ta manette) : chaque bouton peut faire une action différente
au clic, au double clic et à l'appui long (vitesses, direction, demi-tour, caméra,
intensité ERG, musique, volume, retour Android…). Les actions proposées dépendent de
l'appli choisie. Le réglage est enregistré par appli. Un bandeau affiche en direct le
bouton appuyé et l'action déclenchée.

Combinaisons : deux boutons appuyés ensemble déclenchent leur propre action (par
exemple + et − ensemble pour changer de plateau). Les délais du double clic et de
l'appui long se règlent au même endroit.

Sur le même téléphone, ShiftLink touche les boutons de l'appli à l'écran : positions
par défaut pour Rouvy, TPV et MyWhoosh, réglables action par action, et « Montrer les
cibles » pour vérifier.

## Vitesses virtuelles réglables (mode Zwift / trainer ShiftLink)

Réglages > Vitesses virtuelles (ou l'icône de réglage sur la carte des vitesses) :
transmission (24 vitesses régulières, route 2×12 et 2×11, gravel 1×12, VTT 1×12),
plateaux, double plateau avec l'action « Changer de plateau », braquet réel engagé sur
le trainer, effet des pentes, poids, lissage des pentes, pas de l'intensité en ERG
(actions « Intensité + / − »), vibration et son à chaque vitesse.

Depuis la 1.9 :
- transmission personnalisée : de 1 à 30 vitesses, chaque braquet réglable au doigt (pas de 0,05) ;
- profils nommés (« Montagne », « Sprint »…), repris automatiquement avec le même trainer ;
- pilotage du trainer : pente, puissance cible (watts calculés pour la vitesse à ta cadence)
  ou résistance simple ; « Auto » choisit selon ce que le trainer annonce ;
- filtre de cadence, mode « simple relais » sans vitesses ;
- l'appli peut se connecter en Wi-Fi (DIRCON) ou en Bluetooth (ShiftLink se présente comme
  un home trainer FTMS) ;
- « MyWhoosh avec les vitesses ShiftLink » à la place de MyShift.

Testé le 6 novembre 2026 : ThinkRider VS200 + MyWhoosh en OpenBikeControl, ça marche.

MyWhoosh (mode normal) se connecte en OpenBikeControl (icône guidon de l'écran des
connexions) ou, sur les anciennes versions, en Link.

## Télécommandes, affichage, diagnostic

- Réglages > Télécommandes : les télécommandes Bluetooth, manettes de jeu et claviers
  appairés au téléphone servent de manette (par défaut, volume / croix haut-bas =
  vitesses). Leurs touches passent par le service d'accessibilité.
- Affichage par-dessus l'appli : petite fenêtre déplaçable (vitesse, watts, cadence,
  ERG ou dernière action).
- Réglages > Ça ne marche pas ? : vérifie Bluetooth, autorisations, manette, Wi-Fi,
  trainer, appli et arrière-plan, et propose la correction.
- Langue : français, anglais, allemand, espagnol, italien ou polonais (Réglages > Affichage > Langue ; « Auto » suit le
  téléphone). Chaque langue a son fichier `lib/src/i18n_xx.dart`, avec le texte
  français comme clé. Le journal reste en français.
- Accessibilité : la vitesse est annoncée par le lecteur d'écran à chaque changement,
  et les écrans sont vérifiés avec un texte agrandi à 160 %.

## Capteurs et sorties (2.x)

- Ceinture cardio Bluetooth : le pouls s'affiche, s'enregistre et part vers l'appli
  quand ShiftLink gère les vitesses.
- Ventilateur Wahoo KICKR Headwind (bêta) : à la main (actions « Ventilateur + / − »),
  selon ta vitesse, ta puissance ou ton cardio (celui du ventilateur, ou la ceinture
  reliée à ShiftLink), avec un réglage « démarre à / à fond à ».
- Enregistrer la sortie : fichier .fit (puissance, cadence, vitesse, cardio, distance)
  à envoyer sur Strava, Garmin Connect ou intervals.icu.
- Applis connectées (Réglages > Automatique > Applis connectées) : Garmin Connect
  et Intervals.icu (clé API). Strava se connecte dans MyWhoosh. Garmin Connect : chaque sortie enregistrée
  part toute seule sur Garmin Connect, et un .fit venu de MyWhoosh peut y être envoyé à
  la main. Le fichier est d'abord réparé : moyennes de puissance, de cardio et de
  cadence ajoutées, température retirée. La connexion reprend
  celle de l'appli Garmin Connect mobile, comme
  [python-garminconnect](https://github.com/cyberjunky/python-garminconnect) (MIT) : page
  de connexion de Garmin dans l'appli, ticket échangé contre un jeton gardé sur le
  téléphone. Ce n'est pas une API officielle : Garmin peut la changer.
- Compte MyWhoosh (même page) : ShiftLink récupère tes sorties et leur .fit d'origine
  chez MyWhoosh, puis envoie les nouvelles sur Garmin Connect à l'ouverture de l'appli
  (les plus anciennes, à la main depuis « Mes sorties MyWhoosh »). Le mot de passe ne
  sert qu'à la connexion ; seule la session est gardée sur le téléphone. API privée de
  l'appli MyWhoosh, non officielle : elle peut changer.
- Réglages > Sauvegarde et partage : fichier, QR code ou texte à copier, sans compte.
  Les appareils appairés restent sur le téléphone.

## Nouveautés 2.3

- Home trainers : en plus du FTMS, les anciens Tacx et autres trainers **FE-C** en Bluetooth
  (commandes traduites en pages ANT+ FE-C) et les trainers **Wi-Fi** (client DIRCON,
  découverte `_wahoo-fitness-tnp._tcp`).
- Capteurs **cadence** (CSC) et **puissance** (Cycling Power) : la cadence sert aux vitesses,
  les watts du capteur peuvent remplacer ceux du trainer vers l'appli.
- **Test de résistance** (10 s facile, 10 s dur) dans la connexion au trainer.
- **ERG sans appli** (départ à la dernière cible ou à ta puissance) et **séance escalier**.
- Manettes : « Ce n'est pas la mienne » (appareil ignoré pour toujours), **mise en veille**
  5 min après la fin de séance, **vibration des manettes de jeu** à chaque vitesse.
- **Enregistrement automatique** des sorties, envoi à **Health Connect**, intent
  `app.shiftlink.ACTION` pour Tasker / MacroDroid (extras : action, button, gesture, device).
- Android 8 minimum (Health Connect).

## Nouveautés 2.7 (idées reprises de QZ / qdomyos-zwift)

- **Cyclistes** : un profil par personne (prénom, poids, FTP, cardio max, profil de vitesses
  facultatif), choisi d'un appui en haut de l'écran Rouler. Le poids règle les vitesses virtuelles.
- **Séances sans appli** : le trainer suit une séance en ERG (watts = % de la FTP du cycliste).
  Trois séances fournies (balade, pyramide, 30/30) et import des fichiers Zwift **.zwo**
  (SteadyState, Warmup, Cooldown, Ramp, IntervalsT, FreeRide, MaxEffort). Le chrono attend quand
  on ne pédale pas ; les boutons Intensité ± restent actifs ; l'appli qui reprend la main arrête la séance.
- **Zones cardio** (60/70/80/90 % du cardio max) en couleur pendant la sortie.
- **Watts estimés** d'après la vitesse et le poids quand le trainer n'envoie pas de puissance
  (aussi transmis à l'appli).
- **Chiffres affichés** au choix (watts, cadence, pente/cible, cardio, vitesse ; 4 au plus).
- Applis qui gèrent leurs vitesses : la cassette dessine **un pignon par vitesse de l'appli**
  (MyWhoosh 30, Zwift/Rouvy et autres 24 ; réglable d'un appui).
- Direction au téléphone : le zéro est pris au bout de 1,5 s même si le guidon vibre ; message si le
  téléphone n'a pas de gyroscope ; la carte « Téléphone au guidon » ne s'ajoute plus en haut de la liste.

## Nouveautés 2.10

- **Carte et dénivelé dans le .fit** : une sortie sur un parcours GPX garde sa position et son altitude
  (sortie « virtuelle »), donc Strava et Intervals.icu montrent la carte et le D+.
- **Reprendre un parcours** là où on s'est arrêté, ou partir du km de son choix. Le record (fantôme)
  ne compte que pour un parcours fait depuis le début.
- **Un tour par bloc de séance** dans le .fit (watts, cardio et cadence moyens de chaque intervalle).
- **Fichiers .zwo** : la cadence demandée (`Cadence`, `CadenceResting`) et les messages (`textevent`)
  s'affichent pendant la séance et sont lus par la voix.
- **Calibration (spin down)** du home trainer, pour les trainers FTMS qui l'annoncent.
- **Jusqu'à 200 parcours** (un fichier chacun dans le dossier de l'appli, plus dans les préférences),
  et les fichiers GPX jusqu'à 4 Mo sont acceptés. Les parcours ne font pas partie de la sauvegarde des réglages.

## Sécurité

- Les serveurs réseau (OpenBikeControl, Link, trainer Wi-Fi) n'acceptent que les
  appareils du réseau local, jamais une adresse Internet.
- Le trainer Bluetooth n'accepte qu'une appli à la fois et rejette les commandes
  mal formées. La puissance demandée est bornée à 2000 W.
- Le fichier de codes du Sterzo est vérifié par son empreinte SHA-256.
- Pas de compte, pas de pistage, pas de sauvegarde cloud des réglages, pas de trafic
  HTTP en clair.

## Compiler

```
flutter test
flutter build apk --release
```

Pour signer avec la clé ShiftLink (indispensable pour que les mises à jour
s'installent par-dessus l'ancienne version), placer `android/key.properties` :

```
storePassword=…
keyPassword=…
keyAlias=shiftlink
storeFile=/chemin/vers/shiftlink.jks
```

## Licence et sources

ShiftLink est publié sous GPL-3.0 (voir `LICENSE`). Son code est écrit pour
ShiftLink.

Les protocoles des appareils (identifiants Bluetooth, forme des trames, messages
réseau) sont des faits imposés par le matériel et les applis : ShiftLink les applique
tels quels pour que ça marche. Sources publiques utilisées :

- Zwift Click et Play : [ajchellew/zwiftplay](https://github.com/ajchellew/zwiftplay) ;
  Zwift Ride et Click v2 : [Makinolo, « Zwift Ride protocol »](https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/) ;
- Zwift Ride V2, WHEELTOP EDS, Elite Rizer, CYCPLUS T7, Tacx NEO Bike : descriptions publiques des protocoles par
  [OpenBikeControl](https://github.com/OpenBikeControl/bikecontrol) (faits de protocole seulement, aucun code repris) ;
- KICKR Climb : relevé au sniffer de [Redback Operations](https://github.com/Redback-Operations/redback-smartbike-iot) (GPL-3.0) ;
- Elite Sterzo : [pycycling](https://github.com/zacharyedwardbull/pycycling) (MIT), dont
  le fichier de codes de réponse est téléchargé au premier usage ;
- OpenBikeControl : [openbikecontrol.org](https://openbikecontrol.org), protocole ouvert ;
- raccourcis clavier : aides des applis (Rouvy, Zwift…) ;
- les autres appareils (ThinkRider, CYCPLUS, Elite Square, Shimano Di2, SRAM AXS,
  Wahoo KICKR Bike, Headwind, MyWhoosh Link) : identifiants et formats de trames
  connus publiquement, appliqués dans un code écrit pour ShiftLink.

ShiftLink est un projet indépendant. Il n'est affilié ni à MyWhoosh, ni à Zwift, ni à
BikeControl / OpenBikeControl, ni aux fabricants des manettes.
