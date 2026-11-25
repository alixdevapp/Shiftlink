// Statistiques : meilleurs efforts, courbe de puissance, forme et fatigue.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../ride/power_stats.dart';
import '../ride/ride_history.dart';
import 'widgets.dart';

/// Libellé court d'une durée d'effort : « 5 s », « 1 min », « 20 min ».
String effortLabel(int seconds) => seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min';

class StatsPage extends StatelessWidget {
  final List<RideSummary> rides;
  final int ftp;

  /// Jour de référence (pour les captures et les tests).
  final DateTime? today;
  const StatsPage({super.key, required this.rides, required this.ftp, this.today});

  static const recentDays = 42;

  Map<int, int> _best(Iterable<RideSummary> list) {
    final out = <int, int>{};
    for (final r in list) {
      for (final e in r.bests.entries) {
        if (e.value > (out[e.key] ?? 0)) out[e.key] = e.value;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final allTime = _best(rides);
    final recent = _best(rides.where((r) => now.difference(r.start).inDays < recentDays));
    final loads = {
      for (final r in rides)
        if (r.load != null) r.start: r.load!,
    };
    final curve = fitnessCurve(loads, until: now);
    final last90 = curve.length > 90 ? curve.sublist(curve.length - 90) : curve;
    final todayFit = curve.isEmpty ? null : curve.last;
    final ftpGuess = allTime[1200] == null ? null : (allTime[1200]! * 0.95).round();
    final muted = TextStyle(color: cs.onSurfaceVariant);

    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Statistiques'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (allTime.isEmpty && loads.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text(
                tr(
                  'Pas encore de puissance enregistrée. Enregistre une sortie avec un home trainer qui mesure les watts.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (allTime.isNotEmpty) ...[
            title(tr('Meilleurs efforts')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(child: SizedBox()),
                        Expanded(
                          child: Text(tr('Record'), textAlign: TextAlign.end, style: muted),
                        ),
                        Expanded(
                          child: Text(tr('6 semaines'), textAlign: TextAlign.end, style: muted),
                        ),
                      ],
                    ),
                    for (final d in bestEffortDurations)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(effortLabel(d), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: Text(
                                allTime[d] == null ? '–' : '${allTime[d]} W',
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                recent[d] == null ? '–' : '${recent[d]} W',
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (ftpGuess != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('FTP estimée d’après ton record sur 20 min : {0} W (ta FTP : {1} W).', [ftpGuess, ftp]),
                  style: muted,
                ),
              ),
            title(tr('Courbe de puissance')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                child: Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _PowerCurvePainter(
                          allTime: allTime,
                          recent: recent,
                          grid: cs.outlineVariant,
                          text: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      children: [
                        _Legend(color: Tones.orange, label: tr('Record')),
                        _Legend(color: Tones.blue, label: tr('6 semaines')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (todayFit != null) ...[
            title(tr('Forme et fatigue')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Figure(value: todayFit.fitness.round(), label: tr('Forme'), color: Tones.blue),
                        _Figure(value: todayFit.fatigue.round(), label: tr('Fatigue'), color: Tones.orange),
                        _Figure(value: todayFit.freshness.round(), label: tr('Fraîcheur'), color: Tones.teal),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 150,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _FitnessPainter(last90, grid: cs.outlineVariant),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_advice(todayFit.freshness), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        'Forme : ta charge moyenne des 6 dernières semaines. Fatigue : celle des 7 derniers jours. Fraîcheur = forme − fatigue. Calculé avec ta FTP, à partir des sorties enregistrées avec la puissance.',
                      ),
                      style: muted.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _advice(double tsb) {
    if (tsb > 15) return tr('Très reposé : bon moment pour un test ou une grosse sortie.');
    if (tsb > 0) return tr('Frais : prêt pour une séance intense.');
    if (tsb > -20) return tr('Charge normale : tu progresses.');
    return tr('Grosse fatigue : prévois du repos ou une séance facile.');
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 4, color: color),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}

class _Figure extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _Figure({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// Courbe puissance / durée (axe des durées en échelle logarithmique).
class _PowerCurvePainter extends CustomPainter {
  final Map<int, int> allTime;
  final Map<int, int> recent;
  final Color grid;
  final Color text;
  _PowerCurvePainter({required this.allTime, required this.recent, required this.grid, required this.text});

  static const _left = 40.0, _bottom = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final maxW = [...allTime.values, ...recent.values, 100].reduce(math.max) * 1.1;
    final w = size.width - _left, h = size.height - _bottom;
    final lo = math.log(bestEffortDurations.first), hi = math.log(bestEffortDurations.last);
    double x(int d) => _left + (math.log(d) - lo) / (hi - lo) * w;
    double y(num watts) => h - watts / maxW * h;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void label(String s, Offset at, {bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: text, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(center ? tp.width / 2 : tp.width + 4, tp.height / 2));
    }

    final step = maxW > 600 ? 200 : 100;
    for (var v = 0; v < maxW; v += step) {
      canvas.drawLine(Offset(_left, y(v)), Offset(size.width, y(v)), gridPaint);
      label('$v', Offset(_left, y(v)));
    }
    for (final d in bestEffortDurations) {
      label(effortLabel(d), Offset(x(d), size.height - 8), center: true);
    }
    void series(Map<int, int> m, Color c) {
      final pts = [
        for (final d in bestEffortDurations)
          if (m[d] != null) Offset(x(d), y(m[d]!)),
      ];
      if (pts.isEmpty) return;
      final line = Paint()
        ..color = c
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawPath(Path()..addPolygon(pts, false), line);
      for (final p in pts) {
        canvas.drawCircle(p, 4, Paint()..color = c);
      }
    }

    series(recent, Tones.blue);
    series(allTime, Tones.orange);
  }

  @override
  bool shouldRepaint(covariant _PowerCurvePainter old) => old.allTime != allTime || old.recent != recent;
}

/// Forme (bleu), fatigue (orange) et fraîcheur (barres) sur les derniers jours.
class _FitnessPainter extends CustomPainter {
  final List<FitnessDay> days;
  final Color grid;
  _FitnessPainter(this.days, {required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final top = [for (final d in days) math.max(d.fitness, d.fatigue)].reduce(math.max).clamp(10.0, 1e9) * 1.1;
    final mid = size.height * 0.75; // zéro de la fraîcheur
    double x(int i) => days.length == 1 ? size.width / 2 : i / (days.length - 1) * size.width;
    double y(double v) => mid - v / top * mid;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = grid);
    final barW = math.max(1.0, size.width / days.length - 1);
    for (var i = 0; i < days.length; i++) {
      final f = days[i].freshness.clamp(-top / 3, top);
      canvas.drawRect(
        Rect.fromLTRB(x(i) - barW / 2, math.min(mid, y(f)), x(i) + barW / 2, math.max(mid, y(f))),
        Paint()..color = Tones.teal.withValues(alpha: 0.35),
      );
    }
    void line(double Function(FitnessDay) v, Color c) {
      final path = Path();
      for (var i = 0; i < days.length; i++) {
        final p = Offset(x(i), y(v(days[i])));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }

    line((d) => d.fatigue, Tones.orange);
    line((d) => d.fitness, Tones.blue);
  }

  @override
  bool shouldRepaint(covariant _FitnessPainter old) => old.days != days;
}
