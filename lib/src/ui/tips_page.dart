// Conseils par marque (Zwift, Shimano, SRAM) : une carte colorée par marque,
// des étapes numérotées et de petits schémas, plutôt qu'un long texte.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';

class TipsPage extends StatelessWidget {
  final AppState app;
  const TipsPage({super.key, required this.app});

  static const zwiftColor = Color(0xFFFC6719);
  static const shimanoColor = Color(0xFF1F6FD1);
  static const sramColor = Color(0xFFD7262C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Conseils'))),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _BrandCard(
              color: zwiftColor,
              icon: Icons.sports_esports_rounded,
              title: tr('Manettes Zwift'),
              subtitle: tr('Click, Play, Ride'),
              steps: [
                tr('Ferme Zwift et Zwift Companion : la manette ne parle qu’à une appli à la fois.'),
                tr('Appuie sur un bouton pour la réveiller.'),
                tr('Zwift Play et Ride : allume les deux poignées.'),
              ],
              extra: _Highlight(
                color: zwiftColor,
                icon: Icons.ads_click_rounded,
                title: tr('Click v2 : côté droit seul'),
                text: tr('Plus besoin de la déverrouiller dans Zwift chaque jour. + plus dur, B plus facile.'),
                trailing: Switch(value: app.clickV2RightOnly, onChanged: app.setClickV2RightOnly),
              ),
            ),
            const SizedBox(height: 14),
            _BrandCard(
              color: shimanoColor,
              icon: Icons.settings_input_component_rounded,
              title: tr('Shimano Di2'),
              subtitle: tr('Réglage dans l’appli E-TUBE'),
              steps: [
                tr('Ouvre E-TUBE et choisis les boutons que tu veux utiliser.'),
                tr('Mets-les sur les canaux D-Fly :'),
              ],
              extra: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (ch, up) in [(1, true), (2, false), (3, true), (4, false)])
                    _ChannelChip(channel: ch, up: up, color: shimanoColor),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _BrandCard(
              color: sramColor,
              icon: Icons.bolt_rounded,
              title: tr('SRAM AXS'),
              subtitle: tr('Réglage dans l’appli AXS'),
              steps: [tr('Dans l’appli AXS, désactive la fonction du bouton que tu veux utiliser.')],
              extra: Row(
                children: [
                  Expanded(
                    child: _PressBox(presses: 1, label: tr('Plus dur'), up: true, color: sramColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PressBox(presses: 2, label: tr('Plus facile'), up: false, color: sramColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'une marque : bandeau coloré, étapes numérotées, puis un schéma.
class _BrandCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> steps;
  final Widget? extra;
  const _BrandCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.steps,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!]),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(color: color, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(steps[i], style: const TextStyle(fontSize: 15, height: 1.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (extra != null) ...[const SizedBox(height: 4), extra!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Encadré mis en avant, avec un interrupteur.
class _Highlight extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final Widget trailing;
  const _Highlight({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

/// Canal D-Fly : son numéro et ce qu'il fait.
class _ChannelChip extends StatelessWidget {
  final int channel;
  final bool up;
  final Color color;
  const _ChannelChip({required this.channel, required this.up, required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('Canal {0} : {1}', [channel, up ? tr('Plus dur') : tr('Plus facile')]),
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: up ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: up ? Colors.white : color,
            child: Text(
              '$channel',
              style: TextStyle(color: up ? color : Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
          Icon(up ? Icons.add_rounded : Icons.remove_rounded, color: up ? Colors.white : color, size: 22),
        ],
      ),
    ),
  );
}

/// « 1 appui = plus dur », « 2 appuis = plus facile ».
class _PressBox extends StatelessWidget {
  final int presses;
  final String label;
  final bool up;
  final Color color;
  const _PressBox({required this.presses, required this.label, required this.up, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: up ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < presses; i++) Icon(Icons.touch_app_rounded, color: up ? Colors.white : color, size: 28),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          presses == 1 ? tr('1 appui') : tr('2 appuis'),
          style: TextStyle(color: up ? Colors.white : color, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        Text(label, style: TextStyle(color: up ? Colors.white : color)),
      ],
    ),
  );
}
