// Identité visuelle de ShiftLink : couleurs, thème, logo.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class Brand {
  static const orange = Color(0xFFFF5A1F);
  static const orangeDeep = Color(0xFFE23D00);
  static const amber = Color(0xFFFFA62B);
  static const ink = Color(0xFF14161C);
  static const inkSoft = Color(0xFF232733);
  static const green = Color(0xFF22A45D);
  static const yellow = Color(0xFFF2A900);

  static const lightBg = Color(0xFFF3F4F6);
  static const darkBg = Color(0xFF0E1015);
  static const darkCard = Color(0xFF1A1D24);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [amber, orange, orangeDeep],
    stops: [0, 0.55, 1],
  );

  static const font = 'Barlow';
}

ThemeData shiftLinkTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brand.orange,
        brightness: b,
        primary: Brand.orange,
        onPrimary: Colors.white,
        surface: dark ? Brand.darkBg : Brand.lightBg,
      ).copyWith(
        surfaceContainerLowest: dark ? const Color(0xFF14171D) : Colors.white,
        surfaceContainerLow: dark ? Brand.darkCard : Colors.white,
        surfaceContainer: dark ? Brand.darkCard : Colors.white,
        surfaceContainerHigh: dark ? const Color(0xFF242833) : const Color(0xFFEDEEF1),
        secondaryContainer: dark ? const Color(0xFF2A2F3B) : const Color(0xFFE4E6EB),
        onSecondaryContainer: dark ? Colors.white : Brand.ink,
      );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: Brand.font, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: Brand.font,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: Brand.font, fontWeight: FontWeight.w700, fontSize: 16),
        minimumSize: const Size(48, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: Brand.font, fontWeight: FontWeight.w600, fontSize: 15),
        minimumSize: const Size(48, 46),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15),
    ),
  );
}

/// Logo : un plateau stylisé avec deux chevrons (monter / descendre).
class ShiftLinkLogo extends StatelessWidget {
  final double size;

  /// Sans fond (pour l'icône adaptative Android ou un fond déjà coloré).
  final bool foregroundOnly;
  const ShiftLinkLogo({super.key, this.size = 40, this.foregroundOnly = false});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: LogoPainter(foregroundOnly: foregroundOnly),
  );
}

class LogoPainter extends CustomPainter {
  final bool foregroundOnly;

  /// Échelle du dessin dans le carré (l'icône adaptative a besoin de marges).
  final double scale;
  LogoPainter({this.foregroundOnly = false, this.scale = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    if (!foregroundOnly) {
      final r = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.23));
      canvas.drawRRect(r, Paint()..shader = Brand.gradient.createShader(rect));
      // Léger reflet en haut.
      canvas.save();
      canvas.clipRRect(r);
      canvas.drawCircle(Offset(s * 0.2, -s * 0.15), s * 0.75, Paint()..color = Colors.white.withValues(alpha: 0.10));
      canvas.restore();
    }
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(scale);
    const c = Offset.zero;
    final white = Paint()..color = Colors.white;

    // Plateau : anneau denté.
    const teeth = 18;
    final outer = s * 0.36;
    final inner = s * 0.30;
    final path = Path();
    for (var i = 0; i < teeth * 2; i++) {
      final a0 = i * math.pi / teeth - math.pi / 2;
      final a1 = (i + 1) * math.pi / teeth - math.pi / 2;
      final rad = i.isEven ? outer : inner;
      final p0 = Offset(math.cos(a0) * rad, math.sin(a0) * rad);
      final p1 = Offset(math.cos(a1) * rad, math.sin(a1) * rad);
      if (i == 0) {
        path.moveTo(p0.dx, p0.dy);
      } else {
        path.lineTo(p0.dx, p0.dy);
      }
      path.lineTo(p1.dx, p1.dy);
    }
    path.close();
    final ring = Path.combine(
      PathOperation.difference,
      path,
      Path()..addOval(Rect.fromCircle(center: c, radius: s * 0.235)),
    );
    canvas.drawPath(ring, white);

    // Chevrons haut / bas au centre.
    final chevron = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s * 0.11;
    final h = s * 0.065;
    final gap = s * 0.09;
    canvas.drawPath(
      Path()
        ..moveTo(-w, -gap + h / 2)
        ..lineTo(0, -gap - h / 2)
        ..lineTo(w, -gap + h / 2),
      chevron,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-w, gap - h / 2)
        ..lineTo(0, gap + h / 2)
        ..lineTo(w, gap - h / 2),
      chevron..color = Colors.white.withValues(alpha: 0.75),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) => old.foregroundOnly != foregroundOnly || old.scale != scale;
}

/// Logo + nom.
class BrandHeader extends StatelessWidget {
  final double size;
  const BrandHeader({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ShiftLinkLogo(size: size),
      const SizedBox(width: 10),
      Text.rich(
        const TextSpan(
          children: [
            TextSpan(text: 'Shift'),
            TextSpan(
              text: 'Link',
              style: TextStyle(color: Brand.orange),
            ),
          ],
        ),
        style: TextStyle(
          fontFamily: Brand.font,
          fontSize: size * 0.68,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    ],
  );
}
