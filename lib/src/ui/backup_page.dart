// Sauvegarde et partage des réglages : fichier, QR code, presse-papiers.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../settings_transfer.dart';
import 'widgets.dart';

class BackupPage extends StatelessWidget {
  final AppState app;
  const BackupPage({super.key, required this.app});

  /// Au-delà, le QR code devient trop dense pour être lu par un téléphone.
  static const qrMaxLength = 2000;

  String get _json => SettingsTransfer.export(app.prefs!);

  Future<void> _shareFile(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/shiftlink-reglages.json');
    await file.writeAsString(_json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: tr('Réglages ShiftLink'),
      ),
    );
  }

  void _showQr(BuildContext context) {
    final code = SettingsTransfer.compact(_json);
    final fits = code.length <= qrMaxLength;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Réglages en QR code')),
        content: SizedBox(
          width: 280,
          child: fits
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(data: code, size: 256),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('Sur l’autre téléphone : Réglages > Sauvegarde et partage > Scanner un QR code.')),
                  ],
                )
              : Text(tr('Tes réglages sont trop nombreux pour un QR code. Partage plutôt le fichier.')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fermer')))],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: SettingsTransfer.compact(_json)));
    if (context.mounted) _toast(context, tr('Réglages copiés. Colle-les dans un message ou sur l’autre téléphone.'));
  }

  Future<void> _importFile(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !context.mounted) return;
    final file = picked.first.xFile;
    if (await file.length() > SettingsTransfer.maxBytes) {
      if (context.mounted) _toast(context, tr('Fichier trop volumineux.'));
      return;
    }
    final text = await file.readAsString();
    if (context.mounted) await _import(context, text);
  }

  Future<void> _paste(BuildContext context) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!context.mounted) return;
    if (text == null || text.isEmpty) return _toast(context, tr('Le presse-papiers est vide.'));
    await _import(context, text);
  }

  Future<void> _scan(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (code != null && context.mounted) await _import(context, code);
  }

  /// Vérifie, demande confirmation, puis applique.
  Future<void> _import(BuildContext context, String text) async {
    final Map<String, Object> settings;
    try {
      settings = SettingsTransfer.parse(text);
    } on FormatException catch (e) {
      return _toast(context, tr(e.message));
    } catch (_) {
      return _toast(context, tr('Ce n’est pas un fichier de réglages ShiftLink.'));
    }
    if (settings.isEmpty) return _toast(context, tr('Aucun réglage à importer.'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Importer ces réglages ?')),
        content: Text(
          tr(
            '{0} réglages : appli, boutons, vitesses, profils… Ils remplacent les tiens. Les appareils appairés à ce téléphone ne changent pas.',
            [settings.length],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Importer'))),
        ],
      ),
    );
    if (ok != true) return;
    final n = await SettingsTransfer.apply(app.prefs!, settings);
    await app.reloadSettings();
    app.log(tr('Réglages importés ({0})', [n]));
    if (context.mounted) _toast(context, tr('Réglages importés.'));
  }

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sauvegarde et partage'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              tr(
                'Pour passer tes réglages (appli choisie, boutons, vitesses, profils…) d’un téléphone à un autre, ou en garder une copie. Sans compte : tout reste entre tes mains.',
              ),
            ),
          ),
          SectionHeader(tr('Envoyer mes réglages')),
          GroupCard(
            children: [
              SettingRow(
                icon: Icons.ios_share_rounded,
                color: Tones.orange,
                title: tr('Envoyer par message ou e-mail'),
                subtitle: tr('Fichier .json à joindre à un message, mettre sur Drive, etc.'),
                onTap: () => _shareFile(context),
              ),
              SettingRow(
                icon: Icons.qr_code_2_rounded,
                color: Tones.blue,
                title: tr('Afficher un QR code'),
                subtitle: tr('Scanne-le avec l’autre téléphone, c’est transféré.'),
                onTap: () => _showQr(context),
              ),
              SettingRow(
                icon: Icons.copy_rounded,
                color: Tones.grey,
                title: tr('Copier dans le presse-papiers'),
                subtitle: tr('Puis colle-le dans un message, une note, un chat.'),
                onTap: () => _copy(context),
              ),
            ],
          ),
          SectionHeader(tr('Recevoir des réglages')),
          GroupCard(
            children: [
              SettingRow(
                icon: Icons.file_open_rounded,
                color: Tones.green,
                title: tr('Ouvrir un fichier reçu'),
                subtitle: tr('Fichier .json de ShiftLink (depuis un message, Drive, Téléchargements…)'),
                onTap: () => _importFile(context),
              ),
              SettingRow(
                icon: Icons.qr_code_scanner_rounded,
                color: Tones.purple,
                title: tr('Scanner un QR code'),
                subtitle: tr('Affiché sur l’autre téléphone, dans cette même page.'),
                onTap: () => _scan(context),
              ),
              SettingRow(
                icon: Icons.content_paste_rounded,
                color: Tones.grey,
                title: tr('Coller depuis le presse-papiers'),
                subtitle: tr('Un texte « Copier » envoyé par un ami, par message.'),
                onTap: () => _paste(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HintBox(
            text: tr(
              'Ce qui est partagé : appli choisie, boutons, combinaisons, vitesses, profils, affichage. Ce qui reste sur ce téléphone : manettes et trainer appairés, positions des boutons à l’écran.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Scanner les réglages'))),
      body: MobileScanner(
        onDetect: (capture) {
          final code = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull;
          if (_done || code == null || !code.startsWith(SettingsTransfer.compactPrefix)) return;
          _done = true;
          Navigator.pop(context, code);
        },
      ),
    );
  }
}
