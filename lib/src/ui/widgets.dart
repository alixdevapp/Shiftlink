// Petits composants partagés par les écrans.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../installed_apps.dart';

Color healthColor(BuildContext context, Health h) => switch (h) {
  Health.ok => const Color(0xFF2E9E5B),
  Health.waiting => const Color(0xFFE0A000),
  Health.off => Theme.of(context).colorScheme.outline,
};

/// Voyant rond + libellé.
class StatusPill extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Health health;
  final VoidCallback? onTap;

  const StatusPill({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.health,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = healthColor(context, health);
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 26, color: cs.onSurfaceVariant),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surfaceContainerHigh, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gros bouton de changement de vitesse.
class ShiftButton extends StatelessWidget {
  final bool up;
  final VoidCallback onTap;
  final double height;

  const ShiftButton({super.key, required this.up, required this.onTap, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: up ? cs.primary : cs.secondaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: RepeatInkWell(
        borderRadius: BorderRadius.circular(24),
        onFire: onTap,
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                up ? Icons.add_rounded : Icons.remove_rounded,
                size: 56,
                color: up ? cs.onPrimary : cs.onSecondaryContainer,
              ),
              Text(
                up ? tr('Plus dur') : tr('Plus facile'),
                style: TextStyle(color: up ? cs.onPrimary : cs.onSecondaryContainer, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton qui agit dès l'appui et se répète tant qu'on reste appuyé
/// (vitesses qui défilent à la volée).
class RepeatInkWell extends StatefulWidget {
  final VoidCallback onFire;
  final Widget child;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;

  /// Délai avant la première répétition, puis intervalle entre deux répétitions.
  static const firstDelay = Duration(milliseconds: 400);
  static const every = Duration(milliseconds: 200);

  const RepeatInkWell({super.key, required this.onFire, required this.child, this.borderRadius, this.customBorder});

  @override
  State<RepeatInkWell> createState() => _RepeatInkWellState();
}

class _RepeatInkWellState extends State<RepeatInkWell> {
  Timer? _timer;
  bool _firedOnDown = false;

  void _down() {
    _stop();
    _firedOnDown = true;
    widget.onFire();
    _timer = Timer(RepeatInkWell.firstDelay, () {
      _timer = Timer.periodic(RepeatInkWell.every, (_) => widget.onFire());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: widget.borderRadius,
    customBorder: widget.customBorder,
    onTapDown: (_) => _down(),
    onTapUp: (_) => _stop(),
    onTapCancel: _stop,
    // Tap sans appui physique (lecteur d'écran) : une seule vitesse.
    onTap: () {
      if (!_firedOnDown) widget.onFire();
      _firedOnDown = false;
    },
    child: widget.child,
  );
}

/// Encadré d'aide.
class HintBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const HintBox({super.key, this.icon = Icons.info_outline, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }
}

/// Une étape numérotée d'instructions.
class StepLine extends StatelessWidget {
  final int n;
  final String text;
  const StepLine(this.n, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Ligne d'état d'une connexion (utilisée dans l'assistant et les réglages).
class StatusLine extends StatelessWidget {
  final Health health;
  final String text;
  final Widget? trailing;
  const StatusLine({super.key, required this.health, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (health == Health.waiting)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: healthColor(context, health)),
            )
          else
            Icon(
              health == Health.ok ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: healthColor(context, health),
            ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Titre de section discret, en petites capitales.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Carte qui regroupe des lignes, séparées par un trait fin.
class GroupCard extends StatelessWidget {
  final List<Widget> children;
  const GroupCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: cs.outlineVariant.withValues(alpha: 0.4)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Pastille d'icône colorée, comme dans les réglages des téléphones.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile(this.icon, this.color, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.3)),
    child: Icon(icon, color: Colors.white, size: size * 0.58),
  );
}

/// Ligne de réglage : icône colorée, titre, sous-titre, élément à droite.
class SettingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Remplace la pastille d'icône (icône d'une appli, par exemple).
  final Widget? leading;

  /// false : ligne grisée et inactive (option indisponible sur ce téléphone).
  final bool enabled;
  const SettingRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.leading,
    this.enabled = true,
  });

  /// Variante avec interrupteur.
  factory SettingRow.toggle({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) => SettingRow(
    icon: icon,
    color: color,
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
    onTap: enabled ? () => onChanged(!value) : null,
    enabled: enabled,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            leading ?? IconTile(icon, color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant, height: 1.3)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                (onTap != null ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant) : const SizedBox()),
          ],
        ),
      ),
    );
    return enabled ? row : Opacity(opacity: 0.45, child: row);
  }
}

/// Petite étiquette arrondie (batterie, firmware, signal…).
class InfoChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  const InfoChip(this.label, {super.key, this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = _chip(context);
    if (onTap == null) return chip;
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: chip);
  }

  Widget _chip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
          ),
          if (onTap != null) ...[const SizedBox(width: 2), Icon(Icons.edit_rounded, size: 12, color: fg)],
        ],
      ),
    );
  }
}

/// Couleurs des pastilles d'icônes.
class Tones {
  static const orange = Color(0xFFFF6A2B);
  static const blue = Color(0xFF3B82F6);
  static const green = Color(0xFF22A45D);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const teal = Color(0xFF14B8A6);
  static const grey = Color(0xFF6B7280);
  static const red = Color(0xFFEF4444);
  static const yellow = Color(0xFFF2A900);
}

/// Pastille de l'appli d'entraînement : sa première lettre, en grand.
class TargetAppIcon extends StatelessWidget {
  final TargetApp target;
  final double size;
  const TargetAppIcon(this.target, {super.key, this.size = 36});

  /// Lettre affichée : M, Z, R, T, B, O… et « + » pour une autre appli.
  String get letter => switch (target) {
    TargetApp.keyboard || TargetApp.proxyOther => '+',
    TargetApp.obc => 'O',
    TargetApp.trainerroad => 'TR',
    _ => target.label.characters.first.toUpperCase(),
  };

  /// Couleur de marque connue, utilisée tant que l'icône de l'appli installée n'a pas été lue.
  Color get color => switch (target) {
    TargetApp.mywhoosh || TargetApp.mywhooshProxy => Tones.blue,
    TargetApp.zwift || TargetApp.zwiftRide => const Color(0xFFFC6719),
    TargetApp.rouvy => Tones.red,
    TargetApp.tpv => const Color(0xFF1A7ED7),
    TargetApp.biketerra || TargetApp.biketerraObc => Tones.green,
    TargetApp.obc => Tones.teal,
    TargetApp.trainerroad => const Color(0xFFDA2128),
    TargetApp.incyclist || TargetApp.incyclistObc => const Color(0xFF2E7D32),
    _ => Tones.grey,
  };

  @override
  Widget build(BuildContext context) {
    final knownIcon = InstalledApps.knownIconOf(target);
    return FutureBuilder<Uint8List?>(
      future: InstalledApps.iconOf(target, size: (size * 2.5).round()),
      initialData: knownIcon,
      builder: (context, iconSnap) {
        final bytes = iconSnap.data;
        if (bytes != null && bytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: Image.memory(bytes, width: size, height: size, gaplessPlayback: true),
          );
        }
        return FutureBuilder<int?>(
          future: InstalledApps.colorOf(target),
          initialData: InstalledApps.knownColorOf(target),
          builder: (context, snap) => _tile(snap.data == null ? color : _readable(Color(snap.data!))),
        );
      },
    );
  }

  /// Assombrit une couleur trop claire pour que la lettre blanche reste lisible.
  static Color _readable(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.lightness > 0.55 ? hsl.withLightness(0.5).toColor() : c;
  }

  Widget _tile(Color color) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.3)),
    child: Text(
      letter,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * (letter.length > 1 ? 0.42 : 0.58),
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

/// « Sur ce téléphone » quand l'appli est installée ici.
class InstalledBadge extends StatelessWidget {
  final TargetApp target;
  const InstalledBadge(this.target, {super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: InstalledApps.has(target),
    builder: (context, snap) => snap.data == true
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.phone_android_rounded, size: 15, color: Tones.green),
                const SizedBox(width: 4),
                Text(
                  tr('Sur ce téléphone'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Tones.green),
                ),
              ],
            ),
          )
        : const SizedBox.shrink(),
  );
}
