// « Ma manette n'est pas dans la liste » : ShiftLink apprend ses boutons.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_state.dart';
import '../controllers/driver.dart';
import '../controllers/learned_driver.dart';
import '../controllers/registry.dart';
import '../i18n.dart';
import '../support_mail.dart';
import 'brand.dart';
import 'widgets.dart';

enum _Step { pick, connecting, quiet, button, done }

class LearnControllerPage extends StatefulWidget {
  final AppState app;
  const LearnControllerPage({super.key, required this.app});

  @override
  State<LearnControllerPage> createState() => _LearnControllerPageState();
}

class _LearnControllerPageState extends State<LearnControllerPage> {
  _Step _step = _Step.pick;
  final Map<String, ScanResult> _found = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  BluetoothDevice? _device;
  ScanResult? _picked;
  LearnedProfile? _profile;
  final List<Subscription> _subs = [];
  final List<StreamSubscription<List<int>>> _listen = [];
  final ControllerLearner _learner = ControllerLearner();
  String? _error;
  int _quietLeft = 3;
  Timer? _timer;

  AppState get app => widget.app;

  /// Caractéristiques standard (batterie, cardio, home trainer…) : ce ne sont pas des boutons.
  static bool _standard(Guid g) {
    final s = g.str128.toLowerCase();
    if (!s.endsWith('-0000-1000-8000-00805f9b34fb') || !s.startsWith('0000')) return false;
    final short = int.parse(s.substring(4, 8), radix: 16);
    return short >= 0x2A00 && short <= 0x2BFF && short != 0x2A4D;
  }

  String get _nextLabel => switch (_learner.buttons.length) {
    0 => tr('Bouton +'),
    1 => tr('Bouton −'),
    final n => tr('Bouton {0}', [n + 1]),
  };

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_scanSub?.cancel());
    for (final l in _listen) {
      unawaited(l.cancel());
    }
    if (_step != _Step.done) unawaited(FlutterBluePlus.stopScan());
    if (_step != _Step.done) unawaited(_device?.disconnect());
    super.dispose();
  }

  Future<void> _scan() async {
    if (app.demo) return;
    if (!await app.askPermissions()) return;
    _found.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        final id = r.device.remoteId.str;
        if (name.isEmpty) continue;
        if (identify(r) != null) continue; // déjà reconnue d'office
        if (app.controllers.controllers.value.any((c) => c.device.remoteId.str == id)) continue;
        _found[id] = r;
      }
      if (mounted) setState(() {});
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    } catch (_) {}
  }

  Future<void> _pick(ScanResult r) async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _step = _Step.connecting;
      _device = r.device;
      _picked = r;
      _error = null;
    });
    try {
      await r.device.connect(timeout: const Duration(seconds: 15));
      try {
        await r.device.requestMtu(247);
      } catch (_) {}
      final services = await r.device.discoverServices();
      for (final s in services) {
        for (final c in s.characteristics) {
          if (!(c.properties.notify || c.properties.indicate) || _standard(c.uuid)) continue;
          try {
            final l = c.onValueReceived.listen((v) {
              _learner.add(c.uuid.str128, v);
              if (mounted) setState(() {});
            });
            _listen.add(l);
            await c.setNotifyValue(true);
            _subs.add(Subscription(s.uuid, c.uuid));
          } catch (_) {}
        }
      }
      if (_subs.isEmpty) {
        setState(() {
          _step = _Step.pick;
          _error = tr('Cet appareil n’envoie rien que ShiftLink puisse écouter. Ce n’est sans doute pas une manette.');
        });
        await r.device.disconnect();
        unawaited(_scan());
        return;
      }
      _startQuiet();
    } catch (e) {
      setState(() {
        _step = _Step.pick;
        _error = tr('Connexion impossible. Rapproche la manette, appuie sur un bouton et réessaie.');
      });
      unawaited(_scan());
    }
  }

  void _startQuiet() {
    _learner.startQuiet();
    setState(() {
      _step = _Step.quiet;
      _quietLeft = 3;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _quietLeft--);
      if (_quietLeft <= 0) {
        t.cancel();
        _learner.endQuiet();
        _learner.startButton();
        setState(() => _step = _Step.button);
      }
    });
  }

  void _validateButton() {
    final n = _learner.buttons.length;
    final why = _learner.finishButton('b${n + 1}', _nextLabel);
    setState(() {
      _error = switch (why) {
        null => null,
        'nothing' => tr('Rien reçu. Appuie bien 3 fois sur le bouton, puis touche « C’est fait ».'),
        'few' => tr('Pas assez d’appuis reçus. Appuie 3 fois, sans te presser.'),
        'same' => tr('Ce bouton envoie la même chose qu’un bouton déjà appris. Essaie un autre bouton.'),
        _ => tr(
          'La manette envoie des choses différentes à chaque appui. Réessaie, en appuyant 3 fois sur le même bouton.',
        ),
      };
    });
    _learner.startButton();
  }

  Future<void> _finish() async {
    final d = _device!;
    final name = d.platformName.isNotEmpty ? d.platformName : tr('Ma manette');
    final profile = _learner.profile(name, _subs);
    for (final l in _listen) {
      await l.cancel();
    }
    _listen.clear();
    try {
      await d.disconnect();
    } catch (_) {}
    await app.adoptLearned(d, profile);
    setState(() {
      _profile = profile;
      _step = _Step.done;
    });
  }

  /// Ce qu'il faut à l'équipe pour reconnaître cette manette d'office : nom, annonce Bluetooth, boutons appris.
  Future<void> _sendModel() async {
    var version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    final r = _picked;
    final p = _profile;
    final a = r?.advertisementData;
    String hex(List<int> v) => v.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final b = StringBuffer()
      ..writeln('ShiftLink $version')
      ..writeln()
      ..writeln('Nom : ${p?.name ?? _device?.platformName ?? '?'}');
    if (a != null) {
      if (a.advName.isNotEmpty) b.writeln('Nom annoncé : ${a.advName}');
      if (a.serviceUuids.isNotEmpty) b.writeln('Services annoncés : ${a.serviceUuids.map((g) => g.str128).join(', ')}');
      a.manufacturerData.forEach(
        (id, v) => b.writeln('Fabricant 0x${id.toRadixString(16).padLeft(4, '0')} : ${hex(v)}'),
      );
    }
    if (p != null) {
      b
        ..writeln('Boutons appris : ${p.buttons.length}')
        ..writeln()
        ..writeln('Profil :')
        ..writeln(jsonEncode(p.toJson()));
    }
    final subject = tr('Manette à reconnaître : {0}', [p?.name ?? '?']);
    if (await openSupportMail(subject, b.toString())) return;
    await shareForSupport(subject, b.toString());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Apprendre ma manette'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_error != null) ...[HintBox(icon: Icons.error_outline, text: _error!), const SizedBox(height: 12)],
          ...switch (_step) {
            _Step.pick => _pickView(text),
            _Step.connecting => [
              const SizedBox(height: 40),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(child: Text(tr('Connexion…'))),
            ],
            _Step.quiet => [
              const SizedBox(height: 24),
              Center(child: Icon(Icons.pan_tool_rounded, size: 72, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 16),
              Text(
                tr('Ne touche à rien pendant {0} s', [_quietLeft]),
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(tr('ShiftLink écoute ce que la manette envoie toute seule.'), textAlign: TextAlign.center),
            ],
            _Step.button => _buttonView(text),
            _Step.done => [
              const SizedBox(height: 24),
              const Icon(Icons.check_circle_rounded, size: 80, color: Brand.green),
              const SizedBox(height: 12),
              Text(
                tr('C’est appris !'),
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Ta manette est dans la liste. Le premier bouton passe à la vitesse plus dure, le deuxième à la plus facile. Tu peux tout changer dans « Régler les boutons ».',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Terminé'))),
              const SizedBox(height: 24),
              HintBox(
                icon: Icons.mail_outline_rounded,
                text: tr(
                  'Envoie le nom de ta manette à l’équipe ShiftLink : elle pourra être reconnue d’office dans une prochaine version, sans rien apprendre.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _sendModel,
                icon: const Icon(Icons.mail_rounded),
                label: Text(tr('Envoyer le nom de ma manette')),
              ),
            ],
          },
        ],
      ),
    );
  }

  List<Widget> _pickView(TextTheme text) {
    final list = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return [
      Text(
        tr('Ta manette n’est pas reconnue ? ShiftLink peut apprendre ses boutons.'),
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      StepLine(1, tr('Allume ta manette et appuie sur un bouton pour la réveiller.')),
      StepLine(2, tr('Choisis-la ci-dessous : la plus proche est en haut.')),
      StepLine(3, tr('Appuie 3 fois sur chaque bouton quand ShiftLink te le demande.')),
      const SizedBox(height: 12),
      for (final r in list)
        Card(
          child: ListTile(
            leading: const Icon(Icons.bluetooth_rounded),
            title: Text(r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName),
            subtitle: Text(
              r.rssi > -60
                  ? tr('Tout près')
                  : r.rssi > -80
                  ? tr('Proche')
                  : tr('Loin'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pick(r),
          ),
        ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Recherche des appareils Bluetooth…'))),
            ],
          ),
        ),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh), label: Text(tr('Chercher encore'))),
      const SizedBox(height: 8),
      HintBox(
        text: tr(
          'Shimano et SRAM : utilise plutôt la manette déjà reconnue, pour ne pas faire bouger tes vrais dérailleurs.',
        ),
      ),
    ];
  }

  List<Widget> _buttonView(TextTheme text) {
    final cs = Theme.of(context).colorScheme;
    final got = _learner.captured;
    return [
      for (final b in _learner.buttons)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: StatusLine(health: Health.ok, text: tr('{0} appris', [b.label])),
        ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Text(
              tr('Appuie 3 fois sur le {0}', [_nextLabel]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 8),
            Text(
              got == 0 ? tr('ShiftLink écoute…') : tr('Reçu : {0}', [got]),
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: got == 0 ? null : _validateButton, child: Text(tr('C’est fait'))),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_learner.buttons.isNotEmpty)
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() {
                _learner.undo();
                _learner.startButton();
              }),
              child: Text(tr('Refaire le dernier')),
            ),
            const Spacer(),
            FilledButton.tonal(onPressed: _finish, child: Text(tr('Terminer'))),
          ],
        ),
    ];
  }
}
