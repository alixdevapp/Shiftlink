// Écran de séance : état, vitesse en grand, gros boutons.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../controller_manager.dart' show LinkState;
import '../i18n.dart';
import '../trainer/proxy.dart' show TrainerMode;
import '../voice.dart' show BatteryAlert;
import 'brand.dart';
import 'buttons_page.dart';
import 'connection_setup.dart';
import 'devices_page.dart' show NoControllerCard;
import 'drivetrain.dart';
import 'ride_extras.dart';
import 'rides_page.dart';
import 'shifting_page.dart';
import 'widgets.dart';

class RidePage extends StatelessWidget {
  final AppState app;

  /// Ouvre l'onglet Appareils (pour finir la connexion).
  final VoidCallback onOpenDevices;
  const RidePage({super.key, required this.app, required this.onOpenDevices});

  String _appHint(AppState app) => switch (app.target.transport) {
    Transport.link => tr('Dans MyWhoosh, touche l’icône OpenBikeControl de l’écran des connexions.'),
    Transport.obc => tr('Dans ton appli, ajoute la manette OpenBikeControl « ShiftLink ».'),
    Transport.zwiftRide => tr('Dans Zwift, appaire la manette Zwift Ride « ShiftLink ».'),
    Transport.keyboard =>
      app.sameDevice
          ? (app.taps.enabled.value
                ? tr('Règle la position des boutons + et − de ton appli.')
                : tr('Active ShiftLink dans les réglages d’accessibilité.'))
          : tr('Connecte le clavier ShiftLink à ton ordinateur ou ta tablette.'),
    Transport.proxy =>
      app.proxy.trainer.isConnected
          ? tr('Dans {0}, appaire le trainer « ShiftLink ».', [
              app.target == TargetApp.zwift
                  ? 'Zwift'
                  : (app.target == TargetApp.mywhooshProxy
                        ? 'MyWhoosh'
                        : (app.target == TargetApp.incyclist ? 'Incyclist' : tr('ton appli'))),
            ])
          : tr('Choisis ton home trainer.'),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.healthListenable, app]),
      builder: (context, _) {
        final isProxy = app.target.transport == Transport.proxy;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _ReadyCard(app: app, hint: _appHint(app), onTap: onOpenDevices),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool?>(
              valueListenable: app.keepsRunning,
              builder: (context, ok, _) => ok == false
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BackgroundCard(app: app),
                    )
                  : const SizedBox.shrink(),
            ),
            if (app.batteryAlert.value case final alert?) ...[
              _BatteryAlertCard(alert: alert, onClose: () => app.batteryAlert.value = null),
              const SizedBox(height: 12),
            ],
            if (app.ftpTestResult.value case final r?) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_rounded, color: Brand.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Test FTP : {0} W', [r.ftp]), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(tr('Avant : {0} W', [app.ftp]), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () => app.ftpTestResult.value = null, child: Text(tr('Plus tard'))),
                      FilledButton(onPressed: () => app.applyFtpTest(r.ftp), child: Text(tr('Garder'))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (app.controllers.controllers.value.isEmpty && app.controllers.lastScanEmpty.value) ...[
              NoControllerCard(app: app, showSearch: true),
              const SizedBox(height: 12),
            ],
            if (app.riders.isNotEmpty) ...[RiderChips(app: app), const SizedBox(height: 8)],
            if (isProxy) ...[
              if (app.proxy.workout.value != null) ...[WorkoutCard(app: app), const SizedBox(height: 12)],
              _GearCard(app: app),
            ] else
              _ShiftCard(app: app),
            const SizedBox(height: 12),
            _DeviceStrip(app: app, onTap: onOpenDevices),
          ],
        );
      },
    );
  }
}

/// « Prêt à rouler » (bandeau discret) ou ce qu'il reste à faire (carte).
class _ReadyCard extends StatelessWidget {
  final AppState app;
  final String hint;
  final VoidCallback onTap;
  const _ReadyCard({required this.app, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = app.appHealth == Health.ok;
    final ctrlOk = app.controllerHealth == Health.ok;
    if (ready) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
            decoration: BoxDecoration(
              color: Brand.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Pulse(color: Brand.green),
                const SizedBox(width: 8),
                Text(
                  ctrlOk ? tr('Prêt · {0}', [app.target.label]) : tr('Prêt · boutons à l’écran'),
                  style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final proxy = app.target.transport == Transport.proxy;
    final trainerOk = app.proxy.trainer.isConnected;
    final steps = <(String, bool, String)>[
      (
        tr('Manette'),
        ctrlOk,
        ctrlOk
            ? tr('Connectée')
            : (app.controllers.scanning.value
                  ? tr('Appuie sur un bouton de ta manette')
                  : tr('Facultatif : les boutons de l’écran marchent aussi')),
      ),
      if (proxy) (tr('Home trainer'), trainerOk, trainerOk ? tr('Connecté') : tr('Choisis ton home trainer')),
      (app.target.label, false, hint),
    ];
    final left = steps.where((s) => !s.$2).length;
    return Material(
      color: Brand.yellow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Pulse(color: Brand.yellow),
                const SizedBox(width: 10),
                Text(
                  left <= 1 ? tr('Encore une étape') : tr('Encore {0} étapes', [left]),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (name, ok, detail) in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: ok ? Brand.green : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: appLanguage.value == 'fr' ? '$name : ' : '$name: ',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: detail,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 14, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showSetup(context),
                    icon: const Icon(Icons.help_outline_rounded),
                    label: Text(tr('Me montrer comment')),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onTap, child: Text(tr('Appareils'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Les étapes de connexion de l'appli, sans quitter l'écran.
  void _showSetup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListenableBuilder(
          listenable: Listenable.merge([app.healthListenable, app]),
          builder: (c, _) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(tr('Connexion à {0}', [app.target.label]), style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              ConnectionSetup(app: app),
            ],
          ),
        ),
      ),
    );
  }
}

/// Point lumineux qui « respire ».
class _Pulse extends StatefulWidget {
  final Color color;
  const _Pulse({required this.color});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.6),
            blurRadius: 4 + 6 * _c.value,
            spreadRadius: 1 * _c.value,
          ),
        ],
      ),
    ),
  );
}

/// Carte héro du mode « vitesses ShiftLink » : vitesse, barres, mesures.
class _GearCard extends StatelessWidget {
  final AppState app;
  const _GearCard({required this.app});

  /// Un chiffre de l'écran Rouler ; null s'il n'y a rien à montrer (pas de ceinture cardio).
  static Widget? _metric(String m, AppState app) {
    final p = app.proxy;
    final d = p.data.value;
    switch (m) {
      case 'power':
        return _Metric('${d.power ?? '–'}', p.estimatedPower.value ? tr('watts (estimés)') : tr('watts'));
      case 'cadence':
        return _Metric('${d.cadence?.round() ?? '–'}', tr('tr/min'));
      case 'speed':
        final kmh = p.rideSpeedKmh;
        return _Metric(kmh == null ? '–' : kmh.toStringAsFixed(1).replaceAll('.', ','), 'km/h');
      case 'hr':
        final bpm = app.heartRate.bpm.value;
        if (bpm == null) return null;
        final z = app.hrZone;
        return z == null ? _Metric('$bpm', 'bpm') : HeartZoneMetric(bpm: bpm, zone: z);
      case 'grade':
        if (p.powerLock.value case final w?) return _Metric('$w', tr('Power Lock W'));
        if (p.mode == TrainerMode.erg) {
          return _Metric(
            '${p.ergTarget ?? '–'}',
            p.ergOffset.value == 0
                ? tr('cible W')
                : tr('cible ({0}{1} W)', [p.ergOffset.value > 0 ? '+' : '', p.ergOffset.value]),
          );
        }
        final grade = p.appGrade.value;
        return _Metric(grade == null ? '–' : '${grade.toStringAsFixed(1)}%', tr('pente'));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = app.proxy;
    final g = p.gear.value;
    final infinite = p.gears.config.infinite;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(gradient: Brand.gradient),
            child: Row(
              children: [
                const Icon(Icons.settings_input_antenna, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Vitesses virtuelles ShiftLink'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: tr('Régler les vitesses'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftingPage(app: app))),
                  icon: const Icon(Icons.tune, color: Colors.white),
                ),
                // Interrupteur SIM / ERG : un appui passe de l'un à l'autre.
                Semantics(
                  button: true,
                  label: p.mode == TrainerMode.erg ? tr('Passer en SIM') : tr('Passer en ERG'),
                  child: Tooltip(
                    message: p.mode == TrainerMode.erg
                        ? tr('ERG : le trainer tient des watts. Touche pour revenir en SIM.')
                        : tr('SIM : le trainer suit les côtes et tes vitesses. Touche pour passer en ERG.'),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      // Toujours actif : un refus s'explique à l'écran.
                      onTap: app.toggleErg,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (label, on) in [('SIM', p.mode != TrainerMode.erg), ('ERG', p.mode == TrainerMode.erg)])
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: on ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: on ? Brand.orange : Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _RoundShift(up: false, onTap: () => app.shift(-1)),
                    Expanded(
                      child: Column(
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              infinite ? p.gears.label() : '$g',
                              semanticsLabel: infinite
                                  ? tr('Pente ajoutée {0}', [p.gears.label()])
                                  : tr('Vitesse {0} sur {1}', [g, p.gears.count]),
                              style: TextStyle(
                                fontSize: infinite ? 64 : 104,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                letterSpacing: -2,
                              ),
                            ),
                          ),
                          Text(
                            infinite
                                ? tr('Vitesses infinies : 0,5 % de pente par appui')
                                : [
                                    tr('vitesse {0} sur {1}', [g, p.gears.count]),
                                    p.gears.label(g),
                                    tr('{0} m par tour', [p.gears.development(g).toStringAsFixed(1).replaceAll('.', ',')]),
                                    if (p.simPower.value case final w? when p.mode == TrainerMode.simulation) tr('{0} W', [w]),
                                  ].join(' · '),
                            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    _RoundShift(up: true, onTap: () => app.shift(1)),
                  ],
                ),
                if (!infinite) ...[
                  const SizedBox(height: 16),
                  ExcludeSemantics(
                    child: DrivetrainView(
                      count: p.gears.count,
                      current: g,
                      size: (i) => p.gears.ratio(1) / p.gears.ratio(i),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(tr('Plus facile'), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(tr('Plus dur'), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
                if (p.mode == TrainerMode.erg && (p.powerLock.value ?? p.ergTarget) != null) ...[
                  const SizedBox(height: 12),
                  _ErgStrip(app: app),
                ],
                if (app.shiftProfileNames.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ProfileRow(app: app),
                ],
                const SizedBox(height: 10),
                // Décale toutes les vitesses d'un coup, sans changer de vitesse.
                Row(
                  children: [
                    IconButton.outlined(
                      tooltip: tr('Tout plus facile'),
                      onPressed: () => app.shiftAll(-1),
                      icon: const Icon(Icons.keyboard_double_arrow_down_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            tr('Toutes les vitesses'),
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            p.gears.offset == 0 ? '0' : '${p.gears.offset > 0 ? '+' : ''}${p.gears.offset}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: tr('Tout plus dur'),
                      onPressed: () => app.shiftAll(1),
                      icon: const Icon(Icons.keyboard_double_arrow_up_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Power Lock : garde les watts du moment, quelle que soit la route.
                ValueListenableBuilder<int?>(
                  valueListenable: p.powerLock,
                  builder: (context, lock, _) => SizedBox(
                    width: double.infinity,
                    child: lock == null
                        ? OutlinedButton.icon(
                            onPressed: app.togglePowerLock,
                            icon: const Icon(Icons.lock_open_rounded),
                            label: Text(tr('Power Lock : garder mes watts')),
                          )
                        : FilledButton.icon(
                            onPressed: app.togglePowerLock,
                            icon: const Icon(Icons.lock_rounded),
                            label: Text(tr('Power Lock {0} W : relâcher', [lock])),
                          ),
                  ),
                ),
                const Divider(height: 28),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onLongPress: () => pickRideMetrics(context, app),
                  child: Row(
                    children: [
                      for (final m in app.rideMetrics)
                        if (_metric(m, app) case final w?) Expanded(child: w),
                      IconButton(
                        tooltip: tr('Chiffres pendant la sortie'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => pickRideMetrics(context, app),
                        icon: Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (app.hrZone case final z? when app.rideMetrics.contains('hr')) ...[
                  const SizedBox(height: 8),
                  HeartZoneBar(zone: z),
                ],
                if (app.target.transport == Transport.proxy && p.mode != TrainerMode.erg) ...[
                  const SizedBox(height: 4),
                  _AutoShiftRow(app: app),
                ],
                const SizedBox(height: 12),
                RecordBar(app: app),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Interrupteur « Boîte auto » : ShiftLink change les vitesses pour garder une cadence cible.
class _AutoShiftRow extends StatelessWidget {
  final AppState app;
  const _AutoShiftRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.autorenew_rounded, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Boîte auto'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                tr('Garde une cadence de {0} à {1} tr/min', [app.autoShiftLowCad, app.autoShiftHighCad]),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Switch(value: app.autoShift, onChanged: app.setAutoShift),
      ],
    );
  }
}

class _RoundShift extends StatelessWidget {
  final bool up;
  final VoidCallback onTap;
  const _RoundShift({required this.up, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      shape: const CircleBorder(),
      color: up ? Brand.orange : cs.surfaceContainerHigh,
      child: RepeatInkWell(
        customBorder: const CircleBorder(),
        onFire: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(up ? Icons.add_rounded : Icons.remove_rounded, size: 40, color: up ? Colors.white : cs.onSurface),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String unit;
  const _Metric(this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value, style: text.headlineSmall),
        Text(unit, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Carte héro quand l'appli gère elle-même les vitesses.
class _ShiftCard extends StatelessWidget {
  final AppState app;
  const _ShiftCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final d = app.lastDelta;
    final up = d != null && d > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 0.9,
            colors: [
              Brand.orange.withValues(alpha: dark ? 0.16 : 0.10),
              Colors.transparent,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
        child: Column(
          children: [
            Semantics(
              button: true,
              label: tr('{0} vitesses dans {1}', [app.appGearCount, app.target.label]),
              child: GestureDetector(
                onTap: () => pickAppGearCount(context, app),
                child: ExcludeSemantics(
                  child: DrivetrainView(
                    count: app.appGearCount,
                    current: app.displayCog.clamp(1, app.appGearCount),
                    height: 150,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(tr('Facile'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Text(
                      tr('Le numéro de vitesse s’affiche dans {0}', [app.target.label]),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(tr('Dur'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Text(
                d != null
                    ? (up ? tr('Plus dur') : tr('Plus facile'))
                    : (app.controllerHealth == Health.ok ? tr('Appuie sur ta manette') : tr('Touche + ou − ici')),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                InfoChip(tr('{0} changement{1}', [app.shifts, app.shifts > 1 ? 's' : '']), icon: Icons.bolt_rounded),
                if (app.hrZone case final z?)
                  InfoChip('${app.heartRate.bpm.value} bpm · ${z.label}', icon: Icons.favorite_rounded, color: z.color),
                InfoChip(
                  tr('{0} vitesses dans {1}', [app.appGearCount, app.target.label]),
                  icon: Icons.settings_rounded,
                  onTap: () => pickAppGearCount(context, app),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: ShiftButton(up: false, onTap: () => app.shift(-1), height: 110)),
                const SizedBox(width: 12),
                Expanded(child: ShiftButton(up: true, onTap: () => app.shift(1), height: 110)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Manettes, trainer et appli, en pastilles.
class _DeviceStrip extends StatelessWidget {
  final AppState app;
  final VoidCallback onTap;
  const _DeviceStrip({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final controllers = app.controllers.controllers.value;
    final t = app.proxy.trainer;
    final tiles = <Widget>[
      for (final c in controllers)
        _DeviceTile(
          icon: c.driver.typeId == 'phoneSteering' ? Icons.smartphone_rounded : Icons.gamepad_rounded,
          title: c.name,
          subtitle: c.battery.value != null ? '${c.driver.label} · ${c.battery.value} %' : c.driver.label,
          health: c.state.value == LinkState.connected ? Health.ok : Health.waiting,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ButtonsPage(app: app, controller: c),
            ),
          ),
        ),
      if (controllers.isEmpty)
        _DeviceTile(
          icon: Icons.gamepad_rounded,
          title: tr('Manette'),
          subtitle: app.controllers.scanning.value
              ? tr('Appuie sur un bouton de ta manette')
              : (app.controllers.lastScanEmpty.value
                    ? tr('Introuvable · touche pour de l’aide')
                    : tr('Aucune · boutons à l’écran')),
          health: app.controllerHealth,
          onTap: onTap,
        ),
      if (app.target.transport == Transport.proxy)
        _DeviceTile(
          icon: Icons.pedal_bike_rounded,
          title: t.name.value ?? tr('Home trainer'),
          subtitle: t.isConnected ? tr('Home trainer') : tr('Non connecté'),
          health: switch (t.state.value) {
            LinkState.connected => Health.ok,
            LinkState.connecting => Health.waiting,
            LinkState.disconnected => Health.off,
          },
          onTap: onTap,
        ),
      _DeviceTile(
        icon: Icons.sports_esports_rounded,
        leading: TargetAppIcon(app.target),
        title: app.target.label,
        subtitle: app.appHealth == Health.ok ? tr('Connectée') : tr('En attente'),
        health: app.appHealth,
        onTap: onTap,
      ),
    ];
    return GroupCard(children: tiles);
  }
}

class _DeviceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Health health;
  final VoidCallback onTap;
  const _DeviceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.health,
    required this.onTap,
    this.leading,
  });

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final color = healthColor(context, health);
    return SettingRow(
      leading: leading,
      icon: icon,
      color: health == Health.ok ? Tones.green : (health == Health.waiting ? Tones.yellow : Tones.grey),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Enregistrer la sortie : bouton, durée et distance, puis partage du fichier.
class RecordBar extends StatelessWidget {
  final AppState app;
  const RecordBar({super.key, required this.app});

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0
        ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _stop(BuildContext context) async {
    final file = await app.finishRide();
    if (!context.mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Sortie trop courte (moins d’une minute) : rien d’enregistré.'))));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Sortie enregistrée')),
        content: Text(
          tr(
            '{0} · {1} km\n\nEnvoie le fichier .fit sur Strava, Garmin Connect ou intervals.icu. Si ton appli enregistre déjà la sortie, inutile de l’envoyer deux fois.',
            [_clock(app.ride.elapsed.value), (app.ride.distance.value / 1000).toStringAsFixed(1).replaceAll('.', ',')],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fermer'))),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(c);
              SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: tr('Sortie ShiftLink')));
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(tr('Partager')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([app.ride.elapsed, app.ride.recording, app.lastAutoRide, app.lastAutoSend]),
      builder: (context, _) {
        final elapsed = app.ride.elapsed.value;
        final on = app.ride.recording.value;
        final saved = app.lastAutoRide.value;
        if (!on && saved != null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_rounded, color: Tones.green),
              title: Text(tr('Sortie enregistrée')),
              subtitle: Text(
                [saved.path.split('/').last, ?app.lastAutoSend.value].join('\n'),
              ),
              trailing: IconButton(
                tooltip: tr('Partager'),
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () {
                  app.lastAutoRide.value = null;
                  app.lastAutoSend.value = null;
                  SharePlus.instance.share(ShareParams(files: [XFile(saved.path)], subject: tr('Sortie ShiftLink')));
                },
              ),
            ),
          );
        }
        if (!on) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: app.ride.start,
                  icon: const Icon(Icons.fiber_manual_record_rounded, color: Tones.red),
                  label: Text(tr('Enregistrer la sortie')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: tr('Mes sorties'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RidesPage.of(app),
                  ),
                ),
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          );
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(color: Tones.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Tones.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_clock(elapsed)} · ${(app.ride.distance.value / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _stop(context),
                icon: const Icon(Icons.stop_rounded),
                label: Text(tr('Arrêter')),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// « Pile faible » : prévient avant que la manette s'éteigne en pleine sortie.
/// Android peut endormir ShiftLink : un bandeau avec le bouton pour l'autoriser en arrière-plan.
class BackgroundCard extends StatelessWidget {
  final AppState app;
  const BackgroundCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_saver_rounded, color: cs.onTertiaryContainer, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('Laisse ShiftLink actif en arrière-plan'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onTertiaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Sinon Android peut l’endormir pendant la séance, et tes boutons ne répondent plus.'),
            style: TextStyle(color: cs.onTertiaryContainer),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: app.allowBackground, child: Text(tr('Autoriser'))),
        ],
      ),
    );
  }
}

class _BatteryAlertCard extends StatelessWidget {
  final BatteryAlert alert;
  final VoidCallback onClose;
  const _BatteryAlertCard({required this.alert, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(Icons.battery_alert_rounded, color: cs.onErrorContainer, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Pile faible : {0} %', [alert.level]),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onErrorContainer),
                ),
                Text(
                  tr('{0} : change la pile ou recharge-la bientôt.', [alert.name]),
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Fermer'),
            onPressed: onClose,
            icon: Icon(Icons.close, color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }
}


/// ERG sur l'écran Rouler : watts tenus, − / +, et curseur pour l'ERG fixe.
class _ErgStrip extends StatelessWidget {
  final AppState app;
  const _ErgStrip({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = app.proxy;
    final lock = p.powerLock.value;
    final watts = lock ?? p.ergTarget ?? 0;
    final fixed = p.fixedErg.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Brand.orange, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  lock != null ? 'LOCK' : 'ERG',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: tr('Moins de watts'),
                onPressed: () => app.nudgeErg(-1),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  '$watts W',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filled(
                tooltip: tr('Plus de watts'),
                onPressed: () => app.nudgeErg(1),
                icon: const Icon(Icons.add),
              ),
              const Spacer(),
            ],
          ),
          if (fixed != null)
            Slider(
              value: fixed.clamp(50, 600).toDouble(),
              min: 50,
              max: 600,
              divisions: 110,
              label: '$fixed W',
              onChanged: (v) => app.setFixedErgWatts(v.round()),
            ),
        ],
      ),
    );
  }
}

/// Profil de vitesses en un geste : liste, et accès à la gestion.
class _ProfileRow extends StatelessWidget {
  final AppState app;
  const _ProfileRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final names = app.shiftProfileNames;
    final active = names.contains(app.activeShiftProfile) ? app.activeShiftProfile : null;
    return Row(
      children: [
        const Icon(Icons.bookmark_outline, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: active,
            hint: Text(tr('Profil de vitesses')),
            underline: const SizedBox.shrink(),
            items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))],
            onChanged: (n) {
              if (n != null) app.loadShiftProfile(n);
            },
          ),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftingPage(app: app))),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: Text(tr('Gérer')),
        ),
      ],
    );
  }
}
