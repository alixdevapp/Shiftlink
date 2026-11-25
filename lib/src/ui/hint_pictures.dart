// Petits dessins « où toucher » pour guider les réglages dans l'appli d'entraînement.
// Ce sont des schémas simplifiés dessinés par ShiftLink, pas des captures d'écran.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'brand.dart';

/// Un écran schématique, avec une flèche jaune vers l'élément à toucher.
class HintPicture extends StatelessWidget {
  final String caption;
  final Widget screen;
  final double height;
  const HintPicture({super.key, required this.caption, required this.screen, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: screen,
          ),
          const SizedBox(height: 6),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Halo jaune autour de l'élément à toucher.
class _Target extends StatelessWidget {
  final Widget child;
  const _Target({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Brand.yellow, width: 3),
    ),
    child: child,
  );
}

Widget _bar(BuildContext context, double width) => Container(
  width: width,
  height: 10,
  margin: const EdgeInsets.symmetric(vertical: 5),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.outlineVariant,
    borderRadius: BorderRadius.circular(5),
  ),
);

/// Icône OpenBikeControl telle qu'on la voit dans MyWhoosh : un guidon de route
/// avec des ondes Wi-Fi au-dessus. Dessinée ici, pas copiée.
class ObcIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const ObcIcon({super.key, this.size = 28, this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _ObcPainter(color ?? IconTheme.of(context).color ?? Colors.black));
}

class _ObcPainter extends CustomPainter {
  final Color color;
  _ObcPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Ondes Wi-Fi : un point et deux arcs, centrés en haut.
    final c = Offset(w * 0.5, w * 0.5);
    for (final r in [0.17, 0.32]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: w * r), -math.pi * 0.78, math.pi * 0.56, false, p);
    }
    canvas.drawCircle(c, w * 0.05, Paint()..color = color);
    // Cintre de route vu de face : barre droite et deux « drops » recourbés vers l'intérieur.
    final y = w * 0.64;
    final path = Path()
      ..moveTo(w * 0.24, y)
      ..lineTo(w * 0.76, y)
      ..cubicTo(w * 0.92, y, w * 0.92, y + w * 0.22, w * 0.76, y + w * 0.22)
      ..moveTo(w * 0.24, y)
      ..cubicTo(w * 0.08, y, w * 0.08, y + w * 0.22, w * 0.24, y + w * 0.22);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ObcPainter old) => old.color != color;
}

/// Étape 2 MyWhoosh : l'icône OpenBikeControl, en haut à droite de l'écran des connexions.
class ConnectionsScreenPicture extends StatelessWidget {
  const ConnectionsScreenPicture({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const blue = Color(0xFF3355CC);
    Widget round(Widget child, {Color? bg, double left = 5, double top = 4}) => Container(
      width: 30,
      height: 30,
      margin: EdgeInsets.only(left: left, top: top),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg ?? cs.surface, shape: BoxShape.circle),
      child: child,
    );
    return HintPicture(
      height: 180,
      caption: tr(
        'Écran des connexions de MyWhoosh (schéma) : touche l’icône guidon avec le Wi-Fi, juste à droite de « BLE ».',
      ),
      screen: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Connexions'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            // La barre d'icônes de MyWhoosh, de gauche à droite.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                round(
                  Text(
                    'ANT+',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                  ),
                ),
                round(const Icon(Icons.lan_outlined, size: 16, color: Colors.white), bg: blue),
                round(Icon(Icons.directions_bike, size: 16, color: cs.onSurfaceVariant)),
                round(const Icon(Icons.bluetooth, size: 16, color: Colors.white), bg: blue),
                // L'icône à toucher, avec la flèche et « ici » centrés juste en dessous.
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Brand.yellow, width: 3),
                        ),
                        child: round(
                          const ObcIcon(size: 22, color: Color(0xFF223355)),
                          bg: Colors.white,
                          left: 0,
                          top: 0,
                        ),
                      ),
                      const Icon(Icons.north_rounded, size: 30, color: Brand.yellow, shadows: [Shadow(blurRadius: 4)]),
                      Text(tr('ici'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                round(Icon(Icons.cleaning_services_outlined, size: 16, color: cs.onSurfaceVariant)),
                round(Icon(Icons.settings, size: 16, color: cs.onSurfaceVariant)),
              ],
            ),
            Row(
              children: [
                for (final c in [blue, cs.outlineVariant])
                  Expanded(
                    child: Container(
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Étape 2 MyWhoosh (suite) : la question « Oui / Non ».
class ConfirmPicture extends StatelessWidget {
  const ConfirmPicture({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HintPicture(
      caption: tr('MyWhoosh a trouvé ShiftLink (« OpenBikeControl Instance Found ») : touche « Oui » (« Yes »).'),
      screen: Center(
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Brand.yellow,
                    child: Text(
                      '?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('OpenBikeControl', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              _bar(context, 150),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(tr('Non'), style: TextStyle(color: cs.onSurfaceVariant)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Brand.yellow, width: 3),
                    ),
                    child: Text(
                      tr('Oui'),
                      style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Réglage « Gear step size » : un curseur, plus petit = plus doux.
class GearStepPicture extends StatelessWidget {
  const GearStepPicture({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HintPicture(
      caption: tr('Réglages > Équipement > « Gear step size » : 32 est un bon début.'),
      screen: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Équipement'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Gear step size'),
            Row(
              children: [
                Text(tr('doux'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 8), color: cs.outlineVariant),
                      Align(
                        alignment: const Alignment(-0.3, 0),
                        child: _Target(child: CircleAvatar(radius: 9, backgroundColor: cs.primary)),
                      ),
                    ],
                  ),
                ),
                Text(tr('fort'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                const SizedBox(width: 8),
                const Text('32', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
