// « Mes sorties » : l'historique des sorties enregistrées, avec partage et suppression.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../net/send_target.dart';
import '../ride/ride_history.dart';
import '../ride/ride_recorder.dart';
import 'stats_page.dart';
import 'widgets.dart';

class RidesPage extends StatefulWidget {
  /// Pour les captures et les tests : sorties affichées sans lire le disque.
  final List<RideSummary>? demo;

  /// FTP du cycliste, pour la charge des sorties sans FTP notée.
  final int ftp;

  /// Applis connectées où l'on peut envoyer une sortie (vide : aucune).
  final List<SendTarget> targets;
  final Future<SendStatus> Function(SendTarget target, File fit)? send;
  const RidesPage({super.key, this.demo, this.ftp = 200, this.targets = const [], this.send});

  /// Avec les applis connectées de ShiftLink.
  factory RidesPage.of(AppState app) => RidesPage(ftp: app.ftp, targets: app.connectedTargets, send: app.sendRideTo);

  @override
  State<RidesPage> createState() => _RidesPageState();
}

class _RidesPageState extends State<RidesPage> {
  List<RideSummary>? _rides;
  RideHistory? _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.demo != null) {
      setState(() => _rides = widget.demo);
      return;
    }
    _history ??= RideHistory(await RideRecorder.directory());
    final list = await _history!.list();
    if (mounted) setState(() => _rides = list);
    // Statistiques des anciennes sorties : calculées une fois, en arrière-plan.
    final withStats = await _history!.withStats(list, widget.ftp);
    if (mounted) setState(() => _rides = withStats);
  }

  static String clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h h ${two(d.inMinutes % 60)}' : '${d.inMinutes} min';
  }

  static String date(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} · ${two(t.hour)}h${two(t.minute)}';
  }

  Future<void> _delete(RideSummary r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Supprimer cette sortie ?')),
        content: Text(tr('Le fichier .fit sera effacé du téléphone. Les copies déjà envoyées ailleurs restent.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Supprimer'))),
        ],
      ),
    );
    if (ok != true) return;
    await _history?.delete(r);
    await _load();
  }

  Future<void> _send(RideSummary r) async {
    final targets = widget.targets;
    var chosen = targets;
    if (targets.length > 1) {
      final pick = await showModalBottomSheet<List<SendTarget>>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(tr('Envoyer la sortie sur…'), style: const TextStyle(fontWeight: FontWeight.w700))),
              for (final t in targets)
                ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: Text(t.label), onTap: () => Navigator.pop(c, [t])),
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: Text(tr('Toutes les applis connectées')),
                onTap: () => Navigator.pop(c, targets),
              ),
            ],
          ),
        ),
      );
      if (pick == null) return;
      chosen = pick;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(tr('Envoi en cours…'))));
    final lines = <String>[];
    for (final t in chosen) {
      try {
        lines.add(AppState.sendStatusText(t, await widget.send!(t, File(r.fitPath))));
      } catch (e) {
        lines.add('${t.label} : $e');
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(lines.join('\n'))));
  }

  @override
  Widget build(BuildContext context) {
    final rides = _rides;
    final total = rides?.fold<Duration>(Duration.zero, (a, r) => a + r.duration) ?? Duration.zero;
    final km = rides?.fold<double>(0, (a, r) => a + r.distance) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mes sorties'))),
      body: rides == null
          ? const Center(child: CircularProgressIndicator())
          : rides.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    'Pas encore de sortie. Touche « Enregistrer la sortie » sur l’écran Rouler, ou active l’enregistrement automatique.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Big(value: '${rides.length}', label: tr('sorties')),
                        _Big(value: clock(total), label: tr('en tout')),
                        _Big(value: (km / 1000).toStringAsFixed(0), label: 'km'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StatsPage(rides: rides, ftp: widget.ftp),
                    ),
                  ),
                  icon: const Icon(Icons.insights_rounded),
                  label: Text(tr('Statistiques : courbe de puissance, forme')),
                ),
                const SizedBox(height: 8),
                for (final r in rides)
                  _RideCard(
                    ride: r,
                    onDelete: () => _delete(r),
                    onUpload: widget.send == null || widget.targets.isEmpty ? null : () => _send(r),
                  ),
              ],
            ),
    );
  }
}

class _Big extends StatelessWidget {
  final String value;
  final String label;
  const _Big({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _RideCard extends StatelessWidget {
  final RideSummary ride;
  final VoidCallback onDelete;
  final VoidCallback? onUpload;
  const _RideCard({required this.ride, required this.onDelete, this.onUpload});

  @override
  Widget build(BuildContext context) {
    final r = ride;
    final known = r.duration > Duration.zero;
    Widget stat(IconData icon, Color color, String text) => Padding(
      padding: const EdgeInsets.only(right: 14, top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(text),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _RidesPageState.date(r.start),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (!known)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(tr('Sortie d’une ancienne version : pas de résumé')),
                    ),
                  if (known)
                    Wrap(
                      children: [
                        stat(Icons.timer_outlined, Tones.blue, _RidesPageState.clock(r.duration)),
                        if (r.distance > 0)
                          stat(
                            Icons.route_outlined,
                            Tones.teal,
                            '${(r.distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
                          ),
                        if (r.avgPower != null)
                          stat(Icons.bolt_rounded, Tones.orange, tr('{0} W moy. · {1} max', [r.avgPower, r.maxPower])),
                        if (r.avgHeartRate != null)
                          stat(Icons.favorite_rounded, Tones.red, tr('{0} bpm moy.', [r.avgHeartRate])),
                        if (r.avgCadence != null) stat(Icons.autorenew_rounded, Tones.purple, '${r.avgCadence} tr/min'),
                        if (r.load != null)
                          stat(Icons.local_fire_department_rounded, Tones.red, tr('Charge {0}', [r.load!.round()])),
                      ],
                    ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: tr('Partager'),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: File(r.fitPath).existsSync()
                      ? () => SharePlus.instance.share(
                          ShareParams(files: [XFile(r.fitPath)], subject: tr('Sortie ShiftLink')),
                        )
                      : null,
                ),
                if (onUpload != null)
                  IconButton(
                    tooltip: tr('Envoyer vers une appli connectée'),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    onPressed: File(r.fitPath).existsSync() ? onUpload : null,
                  ),
                IconButton(
                  tooltip: tr('Supprimer'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
