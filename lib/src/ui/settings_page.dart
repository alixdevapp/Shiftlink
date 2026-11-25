// Réglages : vitesses, affichage, aide, journal.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../net/update_check.dart';
import '../phone_steering.dart' show SteeringStatus;
import '../trainer/gears.dart';
import 'backup_page.dart';
import 'brand.dart';
import 'diagnostic_page.dart';
import 'help_pages.dart';
import 'problem_page.dart';
import 'ride_extras.dart';
import 'rides_page.dart';
import 'shifting_page.dart';
import 'tips_page.dart';
import 'trainer_tools.dart';
import 'whats_new.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  void _sheet(BuildContext context, String title, String body) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
          ],
        ),
      ),
    ),
  );

  Future<void> _checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String version;
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return;
    }
    final u = await app.checkForUpdate(version, now: true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          u == null ? tr('Tu as la dernière version ({0}).', [version]) : tr('ShiftLink {0} est sortie.', [u.version]),
        ),
        action: u == null
            ? null
            : SnackBarAction(label: tr('Télécharger'), onPressed: () => openLink(u.url)),
      ),
    );
  }

  Future<void> _addTile(BuildContext context) async {
    final r = await app.addQuickTile();
    if (!context.mounted) return;
    switch (r) {
      case 'added' || 'already':
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('La tuile ShiftLink est dans tes réglages rapides.'))));
      case 'refused':
        break;
      default:
        _sheet(
          context,
          tr('Ajouter la tuile'),
          tr(
            '1.  Glisse deux fois le doigt du haut de l’écran vers le bas.\n2.  Touche le crayon (Modifier).\n3.  Trouve la tuile ShiftLink et fais-la glisser avec les autres.\n\nEnsuite, un glissement et une touche suffisent pour ouvrir ShiftLink.',
          ),
        );
    }
  }

  Future<void> _stopBackground(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Ne plus rester actif ?')),
        content: Text(
          tr(
            'Android va ouvrir la liste des applis. Touche « Toutes les applis », choisis ShiftLink, puis « Optimiser ». Écran éteint, ShiftLink pourra alors s’endormir et lâcher la manette.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ouvrir les réglages'))),
        ],
      ),
    );
    if (ok == true) await app.openBackgroundSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.healthListenable]),
      builder: (context, _) {
        final preset = gearPresets.where((p) => p.id == app.shifting.presetId).firstOrNull;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SectionHeader(tr('Vitesses')),
            GroupCard(
              children: [
                SettingRow(
                  icon: Icons.tune_rounded,
                  color: Tones.orange,
                  title: tr('Vitesses virtuelles ShiftLink'),
                  subtitle: app.target.transport == Transport.proxy
                      ? (app.shifting.custom
                            ? tr('Personnalisées · {0} vitesses', [app.shifting.ratios.length])
                            : preset?.name)
                      : tr('Quand ShiftLink gère les vitesses (Zwift, MyWhoosh…)'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftingPage(app: app))),
                ),
              ],
            ),
            SectionHeader(tr('Mes réglages')),
            GroupCard(
              children: [
                SettingRow(
                  icon: Icons.people_alt_rounded,
                  color: Tones.blue,
                  title: tr('Cyclistes'),
                  subtitle: app.riders.isEmpty
                      ? tr('Un profil par personne : poids, FTP, cardio')
                      : app.riders.map((r) => r.name).join(', '),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RidersPage(app: app))),
                ),
                SettingRow(
                  icon: Icons.history_rounded,
                  color: Tones.red,
                  title: tr('Mes sorties'),
                  subtitle: tr('Durée, puissance et cardio de chaque sortie'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RidesPage.of(app))),
                ),
                SettingRow(
                  icon: Icons.ios_share_rounded,
                  color: Tones.teal,
                  title: tr('Sauvegarde et partage'),
                  subtitle: tr('Fichier ou QR code, sans compte'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupPage(app: app))),
                ),
              ],
            ),
            SectionHeader(tr('Automatique')),
            ValueListenableBuilder<bool?>(
              valueListenable: app.keepsRunning,
              builder: (context, ok, _) => GroupCard(
                children: [
                  SettingRow(
                    icon: Icons.battery_saver_rounded,
                    color: ok == false ? Tones.orange : Tones.green,
                    title: tr('Rester actif en arrière-plan'),
                    subtitle: ok == false
                        ? tr('Pas encore autorisé : Android peut endormir ShiftLink')
                        : tr('Autorisé : ShiftLink reste actif écran éteint'),
                    trailing: ok == false
                        ? FilledButton(onPressed: app.allowBackground, child: Text(tr('Autoriser')))
                        : TextButton(onPressed: () => _stopBackground(context), child: Text(tr('Désactiver'))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AutomationSettings(app: app),
            const SizedBox(height: 10),
            GroupCard(
              children: [
                SettingRow(
                  icon: Icons.block_rounded,
                  color: Tones.grey,
                  title: tr('Appareils ignorés'),
                  subtitle: app.ignoredDevices.isEmpty
                      ? tr('Aucun')
                      : tr('{0} appareil(s)', [app.ignoredDevices.length]),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => IgnoredDevicesPage(app: app))),
                ),
              ],
            ),
            SectionHeader(tr('Affichage')),
            GroupCard(
              children: [
                SettingRow(
                  icon: Icons.dark_mode_rounded,
                  color: Tones.blue,
                  title: tr('Thème'),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(value: ThemeMode.dark, label: Text(tr('Sombre'))),
                      ButtonSegment(value: ThemeMode.light, label: Text(tr('Clair'))),
                      ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto'))),
                    ],
                    selected: {app.themeMode},
                    onSelectionChanged: (v) => app.setThemeMode(v.first),
                  ),
                ),
                SettingRow(
                  icon: Icons.translate_rounded,
                  color: Tones.green,
                  title: tr('Langue'),
                  trailing: DropdownButton<String>(
                    value: app.language,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      DropdownMenuItem(value: 'auto', child: Text(tr('Auto'))),
                      for (final MapEntry(:key, :value) in languageNames.entries)
                        DropdownMenuItem(value: key, child: Text(value)),
                    ],
                    onChanged: (v) {
                      if (v != null) app.setAppLanguage(v);
                    },
                  ),
                ),
                SettingRow(
                  icon: Icons.dashboard_customize_rounded,
                  color: Tones.orange,
                  title: tr('Chiffres pendant la sortie'),
                  subtitle: app.rideMetrics.map(rideMetricLabel).join(' · '),
                  onTap: () => pickRideMetrics(context, app),
                ),
                SettingRow.toggle(
                  icon: Icons.picture_in_picture_alt_rounded,
                  color: Tones.pink,
                  title: tr('Fenêtre par-dessus l’appli'),
                  subtitle: tr('Vitesse et watts dans une petite fenêtre déplaçable'),
                  value: app.hudEnabled,
                  onChanged: app.setHud,
                ),
                if (app.hudEnabled)
                  SettingRow(
                    icon: Icons.tune_rounded,
                    color: Tones.pink,
                    title: tr('Dans la fenêtre'),
                    subtitle: [
                      for (final f in app.hudFields) hudFieldLabel(f),
                      if (app.hudButtons) tr('boutons − et +'),
                    ].join(' · '),
                    onTap: () => pickHudFields(context, app),
                  ),
                SettingRow.toggle(
                  icon: Icons.record_voice_over_rounded,
                  color: Tones.purple,
                  title: tr('Voix'),
                  subtitle: tr('Pile faible, manette déconnectée, et ta vitesse quand ShiftLink pilote le trainer'),
                  value: app.voice,
                  onChanged: app.setVoice,
                ),
                SettingRow(
                  icon: Icons.view_module_rounded,
                  color: Tones.teal,
                  title: tr('Tuile dans les réglages rapides'),
                  subtitle: tr('Ouvre ShiftLink en glissant le doigt depuis le haut de l’écran'),
                  onTap: () => _addTile(context),
                ),
              ],
            ),
            if (app.hudEnabled && !app.taps.enabled.value) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: app.taps.openSettings,
                icon: const Icon(Icons.accessibility_new_rounded),
                label: Text(tr('Activer l’accessibilité ShiftLink')),
              ),
            ],
            SectionHeader(tr('Aide')),
            GroupCard(
              children: [
                SettingRow(
                  icon: Icons.health_and_safety_rounded,
                  color: Tones.green,
                  title: tr('Ça ne marche pas ?'),
                  subtitle: tr('Diagnostic complet, avec la solution en un geste'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagnosticPage(app: app))),
                ),
                SettingRow(
                  icon: Icons.support_agent_rounded,
                  color: Tones.orange,
                  title: tr('Envoyer mon problème'),
                  subtitle: tr('Un texte prêt à partager, rien ne part sans toi'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProblemPage(app: app))),
                ),
                SettingRow(
                  icon: Icons.checklist_rounded,
                  color: Tones.blue,
                  title: tr('Compatible avec'),
                  subtitle: tr('Manettes, home trainers, applis et capteurs, avec recherche'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompatibilityPage())),
                ),
                SettingRow(
                  icon: Icons.menu_book_rounded,
                  color: Tones.pink,
                  title: tr('Mots'),
                  subtitle: tr('ERG, cadence, braquet… expliqués simplement'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WordsPage())),
                ),
                SettingRow(
                  icon: Icons.lightbulb_rounded,
                  color: Tones.yellow,
                  title: tr('Conseils Zwift, Shimano, SRAM'),
                  subtitle: tr('Réveiller et régler ta manette'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TipsPage(app: app))),
                ),
                SettingRow(
                  icon: Icons.replay_rounded,
                  color: Tones.purple,
                  title: tr('Refaire la configuration pas à pas'),
                  onTap: app.restartOnboarding,
                ),
                SettingRow(
                  icon: Icons.new_releases_rounded,
                  color: Tones.green,
                  title: tr('Quoi de neuf'),
                  onTap: () => showWhatsNew(context),
                ),
                if (updateRepo.isNotEmpty) ...[
                  SettingRow.toggle(
                    icon: Icons.system_update_rounded,
                    color: Tones.blue,
                    title: tr('Prévenir des nouvelles versions'),
                    subtitle: tr('ShiftLink regarde une fois par jour sur GitHub. Rien d’autre ne part.'),
                    value: app.checkUpdates,
                    onChanged: app.setCheckUpdates,
                  ),
                  SettingRow(
                    icon: Icons.refresh_rounded,
                    color: Tones.blue,
                    title: tr('Chercher une mise à jour'),
                    onTap: () => _checkNow(context),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: Column(
                children: [
                  const ShiftLinkLogo(size: 44),
                  const SizedBox(height: 8),
                  const Text('ShiftLink', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) => Text(
                      snap.hasData ? 'Version ${snap.data!.version}' : '',
                      style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Angle du guidon en direct, seuil et remise à zéro.
class SteeringTuner extends StatelessWidget {
  final AppState app;
  const SteeringTuner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = app.steeringThreshold;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<SteeringStatus>(
              valueListenable: app.steeringStatus,
              builder: (context, st, _) => switch (st) {
                SteeringStatus.noGyro => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr(
                      'Ce téléphone ne donne pas de mesure de rotation (pas de gyroscope ?) : la direction ne peut pas marcher avec lui.',
                    ),
                    style: const TextStyle(color: Tones.red, fontWeight: FontWeight.w600),
                  ),
                ),
                SteeringStatus.starting => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Garde le guidon droit un instant…')),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
            ValueListenableBuilder<double>(
              valueListenable: app.steeringAngle,
              builder: (context, a, _) {
                final side = a > t ? tr('à gauche') : (a < -t ? tr('à droite') : tr('tout droit'));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Guidon : {0}° {1}', [a.abs().round(), side]),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 14,
                      child: CustomPaint(size: Size.infinite, painter: _AnglePainter(a, t, scheme)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(tr('Seuil')),
                Expanded(
                  child: Slider(
                    value: t,
                    min: 3,
                    max: 25,
                    divisions: 22,
                    label: '${t.round()}°',
                    onChanged: app.setSteeringThreshold,
                  ),
                ),
                Text('${t.round()}°'),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: app.recenterSteering,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(tr('Guidon droit : remettre à zéro')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnglePainter extends CustomPainter {
  final double angle, threshold;
  final ColorScheme scheme;
  _AnglePainter(this.angle, this.threshold, this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    const range = 45.0;
    final mid = size.width / 2;
    double x(double deg) => mid - deg.clamp(-range, range) / range * mid; // gauche = positif
    final track = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7));
    canvas.drawRRect(track, Paint()..color = scheme.surfaceContainerHighest);
    final zone = Rect.fromLTRB(x(threshold), 0, x(-threshold), size.height);
    canvas.drawRect(zone, Paint()..color = scheme.outlineVariant.withValues(alpha: 0.6));
    final active = angle.abs() > threshold;
    final bar = Rect.fromLTRB(min(mid, x(angle)), 2, max(mid, x(angle)), size.height - 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(5)),
      Paint()..color = active ? scheme.primary : scheme.outline,
    );
    canvas.drawLine(
      Offset(mid, 0),
      Offset(mid, size.height),
      Paint()
        ..color = scheme.onSurface
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_AnglePainter old) => old.angle != angle || old.threshold != threshold;
}
