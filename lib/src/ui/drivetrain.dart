// Cassette vue de l'arrière, le pignon actif glisse à chaque changement de vitesse.
import 'dart:math';

import 'package:flutter/material.dart';

import 'brand.dart';

/// Cassette vue de derrière : le plus grand pignon (vitesse la plus facile) à
/// gauche, le plus petit à droite. Le pignon actif est en orange.
class DrivetrainView extends StatelessWidget {
  /// Nombre de pignons.
  final int count;

  /// Pignon actif, de 1 (le plus facile) à [count].
  final int current;

  /// Taille relative de chaque pignon (1 = le plus grand). Par défaut, régulière.
  final double Function(int)? size;

  final double height;

  const DrivetrainView({super.key, required this.count, required this.current, this.size, this.height = 132});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: current.toDouble()),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, pos, _) => DrivetrainPicture(count: count, position: pos, size: size, height: height),
    );
  }
}

/// Le dessin seul, pour une position quelconque (même entre deux pignons).
class DrivetrainPicture extends StatelessWidget {
  final int count;
  final double position;
  final double Function(int)? size;
  final double height;

  const DrivetrainPicture({super.key, required this.count, required this.position, this.size, this.height = 132});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = [for (var i = 1; i <= count; i++) size?.call(i) ?? 1 - 0.6 * (i - 1) / max(1, count - 1)];
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _DrivetrainPainter(
          sizes: sizes,
          position: position,
          idle: cs.surfaceContainerHighest,
          ink: cs.onSurface,
        ),
      ),
    );
  }
}

class _DrivetrainPainter extends CustomPainter {
  final List<double> sizes;
  final double position;
  final Color idle;
  final Color ink;

  _DrivetrainPainter({required this.sizes, required this.position, required this.idle, required this.ink});

  @override
  void paint(Canvas canvas, Size s) {
    final n = sizes.length;
    if (n == 0) return;
    final axleY = s.height / 2;
    final maxH = s.height * 0.9;
    const left = 12.0;
    final right = s.width - 12;
    final step = n == 1 ? 0.0 : (right - left) / (n - 1);
    final barW = (step * 0.55).clamp(3.0, 14.0);
    double xOf(double i) => left + (i - 1) * step;
    double hOf(double i) {
      final a = i.floor().clamp(1, n);
      final b = i.ceil().clamp(1, n);
      final t = i - i.floor();
      final sa = sizes[a - 1].clamp(0.2, 1.0);
      final sb = sizes[b - 1].clamp(0.2, 1.0);
      return maxH * (sa + (sb - sa) * t);
    }

    final active = position.round().clamp(1, n);

    // Pignons.
    for (var i = 1; i <= n; i++) {
      final h = hOf(i.toDouble());
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(xOf(i.toDouble()), axleY), width: barW, height: h),
        Radius.circular(barW / 2),
      );
      final on = i == active;
      canvas.drawRRect(
        r,
        Paint()
          ..shader = on ? Brand.gradient.createShader(r.outerRect) : null
          ..color = on ? Brand.orange : idle,
      );
    }

    // Moyeu.
    canvas.drawLine(
      Offset(left - 6, axleY),
      Offset(right + 6, axleY),
      Paint()
        ..color = ink.withValues(alpha: 0.25)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DrivetrainPainter old) =>
      old.position != position || old.sizes.length != sizes.length || old.idle != idle || old.ink != ink;
}
