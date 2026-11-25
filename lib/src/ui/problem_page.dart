// « Envoyer mon problème » : tu écris ce qui ne va pas, tu vois tout le texte, tu choisis à qui l'envoyer.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../problem_report.dart';
import '../support_mail.dart';
import 'diagnostic_page.dart';
import 'widgets.dart';

class ProblemPage extends StatefulWidget {
  final AppState app;
  const ProblemPage({super.key, required this.app});

  @override
  State<ProblemPage> createState() => _ProblemPageState();
}

class _ProblemPageState extends State<ProblemPage> {
  final _what = TextEditingController();
  String _version = '';
  List<ReportCheck> _checks = const [];
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _what.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    var v = '';
    try {
      v = widget.app.demo ? '2.6.8' : (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    final checks = await runChecks(widget.app);
    if (!mounted) return;
    setState(() {
      _version = v;
      _checks = [for (final c in checks) (title: c.title, ok: c.ok, detail: c.detail)];
    });
  }

  @override
  void dispose() {
    _what.dispose();
    super.dispose();
  }

  String get _report => buildProblemReport(widget.app, version: _version, what: _what.text, checks: _checks);

  Future<void> _share() => SharePlus.instance.share(ShareParams(text: _report, subject: tr('Problème ShiftLink')));

  /// Ouvre l'appli mail, adresse, sujet et texte déjà remplis. Sans appli mail : le partage classique.
  Future<void> _mail() async {
    // Journal raccourci : un lien mailto trop long est coupé par certaines applis mail.
    final body = buildProblemReport(widget.app, version: _version, what: _what.text, checks: _checks, maxLogs: 40);
    final ok = await openSupportMail('${tr('Problème ShiftLink')} $_version', body);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('Aucune appli mail trouvée. Choisis à qui l’envoyer.'))));
    await _share();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Envoyer mon problème'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          HintBox(
            icon: Icons.lock_outline,
            text: tr(
              'Rien ne part tout seul. Tu lis le texte, puis tu choisis à qui l’envoyer : mail, WhatsApp, Messages… Il contient l’état de ShiftLink et son journal, pas tes sorties ni tes contacts.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _what,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Qu’est-ce qui ne marche pas ?'),
              hintText: tr('Exemple : le bouton + ne fait rien dans MyWhoosh'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _version.isEmpty && !widget.app.demo ? null : _mail,
            icon: const Icon(Icons.mail_rounded),
            label: Text(tr('Envoyer à l’équipe ShiftLink')),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(supportEmail, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _version.isEmpty && !widget.app.demo ? null : _share,
            icon: const Icon(Icons.share_rounded),
            label: Text(tr('Choisir à qui l’envoyer')),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showText = !_showText),
            icon: Icon(_showText ? Icons.expand_less : Icons.expand_more),
            label: Text(_showText ? tr('Cacher le texte') : tr('Voir tout le texte')),
          ),
          if (_showText)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(_report, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
