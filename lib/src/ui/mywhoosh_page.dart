// Ton compte MyWhoosh dans ShiftLink : connexion, et liste de tes sorties à envoyer sur Garmin Connect.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../net/mywhoosh_account.dart';
import '../net/send_target.dart';
import 'widgets.dart';

/// Demande l'e-mail et le mot de passe MyWhoosh, puis connecte le compte. Renvoie true si c'est bon.
Future<bool> connectMyWhoosh(BuildContext context, AppState app) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => _MyWhooshLogin(app: app));
  return ok == true;
}

class _MyWhooshLogin extends StatefulWidget {
  final AppState app;
  const _MyWhooshLogin({required this.app});

  @override
  State<_MyWhooshLogin> createState() => _MyWhooshLoginState();
}

class _MyWhooshLoginState extends State<_MyWhooshLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.connectMyWhoosh(_email.text, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Connecter MyWhoosh')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Le compte avec lequel tu roules sur MyWhoosh. Ton mot de passe part seulement chez MyWhoosh et n’est pas gardé : ShiftLink garde la session sur ce téléphone pour récupérer tes sorties.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: tr('E-mail')),
            enabled: !_busy,
          ),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: tr('Mot de passe'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            enabled: !_busy,
            onSubmitted: (_) => _go(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Tones.red)),
            ),
          const SizedBox(height: 10),
          Text(
            tr('MyWhoosh n’a pas d’accès officiel pour les autres applis : ShiftLink utilise celui de l’appli MyWhoosh, qui peut changer.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(tr('Annuler'))),
      FilledButton(
        onPressed: _busy ? null : _go,
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(tr('Connecter')),
      ),
    ],
  );
}

/// Tes sorties MyWhoosh, avec un bouton pour envoyer chacune sur Garmin Connect.
class MyWhooshRidesPage extends StatefulWidget {
  final AppState app;
  const MyWhooshRidesPage({super.key, required this.app});

  @override
  State<MyWhooshRidesPage> createState() => _MyWhooshRidesPageState();
}

class _MyWhooshRidesPageState extends State<MyWhooshRidesPage> {
  List<MyWhooshActivity>? _rides;
  String? _error;
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rides = null;
      _error = null;
    });
    try {
      final list = await widget.app.myWhooshActivities();
      if (mounted) setState(() => _rides = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send(MyWhooshActivity a) async {
    final messenger = ScaffoldMessenger.of(context);
    final app = widget.app;
    final targets = app.connectedTargets;
    if (targets.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Connecte d’abord une appli (Garmin Connect, Intervals.icu).'))));
      return;
    }
    // Vers les applis où elle n'est pas encore partie (ou toutes, si elle est déjà partout).
    final done = app.myWhooshSentTo(a);
    final missing = targets.where((t) => !done.contains(t)).toList();
    setState(() => _sending.add(a.id));
    try {
      final res = await app.sendMyWhooshTo(a, missing.isEmpty ? targets : missing);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [
              for (final MapEntry(:key, :value) in res.entries)
                value is SendStatus ? AppState.sendStatusText(key, value) : '${key.label} : $value',
            ].join('\n'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('MyWhoosh : {0}', ['$e']))));
    } finally {
      if (mounted) setState(() => _sending.remove(a.id));
    }
  }

  static String _date(DateTime? t) {
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} · ${two(t.hour)}h${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final rides = _rides;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mes sorties MyWhoosh')),
        actions: [IconButton(tooltip: tr('Actualiser'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _error != null
          ? Center(
              child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center)),
            )
          : rides == null
          ? const Center(child: CircularProgressIndicator())
          : rides.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(tr('Pas encore de sortie sur ton compte MyWhoosh.'), textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final a in rides)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(Icons.directions_bike_rounded),
                      title: Text(
                        a.name.isEmpty ? tr('Sortie MyWhoosh') : a.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          _date(a.start),
                          if (!a.downloadable) tr('Pas de fichier chez MyWhoosh'),
                          if (widget.app.myWhooshSentTo(a).isNotEmpty)
                            tr('Déjà envoyée sur {0}', [widget.app.myWhooshSentTo(a).map((t) => t.label).join(', ')]),
                        ].where((x) => x.isNotEmpty).join('\n'),
                      ),
                      trailing: _sending.contains(a.id)
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              tooltip: tr('Envoyer vers une appli connectée'),
                              icon: Icon(
                                widget.app.myWhooshSentTo(a).isNotEmpty ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                                color: widget.app.myWhooshSentTo(a).isNotEmpty ? Tones.green : null,
                              ),
                              onPressed: a.downloadable ? () => _send(a) : null,
                            ),
                    ),
                  ),
              ],
            ),
    );
  }
}
