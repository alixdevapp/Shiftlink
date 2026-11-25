// Assistant de configuration au premier lancement, en 4 étapes :
// 1. ton appli, 2. ta manette (avec test des boutons), 3. connexion à l'appli, 4. résumé.
// Chaque étape dit pourquoi ça bloque, et l'assistant reprend là où on s'est arrêté.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../controller_manager.dart' show ConnectedController, LinkState;
import '../controllers/registry.dart';
import '../i18n.dart';
import '../installed_apps.dart';
import 'brand.dart';
import 'connection_setup.dart';
import 'learn_controller_page.dart';
import 'widgets.dart';

class OnboardingPage extends StatefulWidget {
  final AppState app;
  final int initialStep;
  const OnboardingPage({super.key, required this.app, this.initialStep = 0});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _steps = 4;

  /// Au bout de combien de temps sans manette on propose les causes possibles.
  static const _helpAfter = Duration(seconds: 25);

  late int _step = widget.initialStep.clamp(0, _steps - 1);
  bool? _permissionsOk;
  final Map<TargetApp, bool> _installed = {};

  /// Boutons de la manette déjà essayés pendant le test.
  final Set<String> _tested = {};
  DateTime? _searchSince;
  Timer? _tick;

  /// Dernière action au moment d'arriver sur le résumé (pour l'essai final).
  FiredAction? _firedAtDone;

  bool _appWasOk = false;
  bool _autoAdvancing = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.buttonActivity.addListener(_onButton);
    app.healthListenable.addListener(_onHealth);
    for (final t in TargetApp.pickable) {
      InstalledApps.has(t).then((v) {
        if (mounted) setState(() => _installed[t] = v);
      });
    }
    unawaited(_onEnter());
  }

  @override
  void dispose() {
    app.buttonActivity.removeListener(_onButton);
    app.healthListenable.removeListener(_onHealth);
    _tick?.cancel();
    super.dispose();
  }

  void _onButton() {
    final a = app.buttonActivity.value;
    if (a == null || !a.down || _step != 1) return;
    if (mounted) setState(() => _tested.add(a.buttonId));
  }

  /// Étape 3 : dès que l'appli est connectée, on passe tout seul au résumé.
  void _onHealth() {
    if (_step != 2 || !mounted) return;
    final ok = app.appHealth == Health.ok;
    if (ok && !_appWasOk && !_autoAdvancing) {
      _autoAdvancing = true;
      Future.delayed(const Duration(milliseconds: 1800), () {
        _autoAdvancing = false;
        if (mounted && _step == 2 && app.appHealth == Health.ok) _next();
      });
    }
    _appWasOk = ok;
  }

  void _go(int step) {
    setState(() => _step = step);
    app.onboardingStep = step;
    unawaited(_onEnter());
  }

  Future<void> _next() async {
    if (_step == _steps - 1) {
      await app.finishOnboarding();
      return;
    }
    final from = _step;
    _go(_step + 1);
    // On démarre la liaison avec l'appli sans bloquer l'écran : un réseau ou un
    // Bluetooth qui tarde ne doit pas empêcher d'avancer.
    if (from == 0) {
      try {
        await app.setTarget(app.target).timeout(const Duration(seconds: 10));
      } catch (e) {
        app.log('Liaison avec ${app.target.label} : $e');
      }
    }
  }

  void _back() {
    if (_step > 0) {
      _go(_step - 1);
    } else if (app.onboardingReplay) {
      unawaited(app.quitOnboarding());
    }
  }

  Future<void> _onEnter() async {
    _tick?.cancel();
    if (_step == 1) {
      // Manettes mises en veille : on les réveille pour pouvoir les tester.
      if (app.controllers.asleep.value) unawaited(app.controllers.wake());
      final ok = await app.permissionsGranted();
      if (!mounted) return;
      setState(() => _permissionsOk = ok);
      if (ok) _search();
    }
    if (_step == 2) {
      _appWasOk = app.appHealth == Health.ok;
      await app.startKeepAlive();
    }
    if (_step == 3) _firedAtDone = app.lastFired.value;
  }

  void _search() {
    _searchSince = DateTime.now();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (!app.controllers.controllers.value.any((c) => c.state.value == LinkState.connected)) {
      unawaited(app.controllers.scan());
    }
  }

  Future<void> _askPermissions() async {
    final ok = await app.askPermissions();
    if (!mounted) return;
    setState(() => _permissionsOk = ok);
    if (ok) _search();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (title, body) = switch (_step) {
      0 => (tr('Sur quelle appli roules-tu ?'), _chooseApp()),
      1 => (tr('Ta manette'), _controller()),
      2 => (tr('Connexion à {0}', [app.target.label]), _connection()),
      _ => (tr('Résumé'), _done()),
    };
    return PopScope(
      // Bouton retour d'Android : étape précédente, ou quitter si l'assistant a été relancé.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _step > 0 || app.onboardingReplay ? _back : null,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: tr('Retour'),
                    ),
                    Expanded(
                      child: _StepBar(step: _step, count: _steps),
                    ),
                    const SizedBox(width: 12),
                    Text(tr('Étape {0} sur {1}', [_step + 1, _steps]), style: text.labelMedium),
                    if (app.onboardingReplay)
                      IconButton(
                        onPressed: app.quitOnboarding,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: tr('Quitter'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    body,
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                // Hors du focus : une manette vue comme clavier ou manette de jeu par Android
                // ne doit pas « valider » ces boutons à la place d'un doigt.
                child: ExcludeFocus(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([app.healthListenable, app]),
                    builder: (context, _) => _bottomBar(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    const big = Size(150, 52);
    switch (_step) {
      case 1:
        final tested = _tested.isNotEmpty;
        return Row(
          children: [
            if (!tested) TextButton(onPressed: _next, child: Text(tr('Passer'))),
            const Spacer(),
            FilledButton(
              onPressed: tested ? _next : null,
              style: FilledButton.styleFrom(minimumSize: big),
              child: Text(tr('Continuer')),
            ),
          ],
        );
      case 2:
        // Un seul bouton : « Plus tard » tant que l'appli attend, « Continuer » une fois connectée.
        final ok = app.appHealth == Health.ok;
        return Row(
          children: [
            const Spacer(),
            if (ok)
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(minimumSize: big),
                child: Text(tr('Continuer')),
              )
            else
              FilledButton.tonal(
                onPressed: _next,
                style: FilledButton.styleFrom(minimumSize: big),
                child: Text(tr('Plus tard')),
              ),
          ],
        );
      case 3:
        final allOk = _missing().isEmpty;
        return Row(
          children: [
            const Spacer(),
            FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: big),
              child: Text(allOk ? tr('Terminé, on roule !') : tr('Je finirai plus tard')),
            ),
          ],
        );
      default:
        return Row(
          children: [
            const Spacer(),
            FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: big),
              child: Text(tr('Continuer')),
            ),
          ],
        );
    }
  }

  // ---------- Étape 1 : l'appli ----------

  Widget _chooseApp() {
    final cs = Theme.of(context).colorScheme;
    // Les applis présentes sur le téléphone d'abord.
    final apps = [...TargetApp.pickable]
      ..sort((a, b) => (_installed[b] == true ? 1 : 0) - (_installed[a] == true ? 1 : 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ShiftLinkLogo(size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('4 petites étapes, environ 2 minutes. Gratuit, sans pub et sans compte.'),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        RadioGroup<TargetApp>(
          groupValue: app.target.base,
          onChanged: (v) async {
            if (v == null || v == app.target.base) return;
            await app.prefs?.setString('target', v.name);
            setState(() {});
          },
          child: Column(
            children: [
              for (final t in apps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: t == app.target.base ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: RadioListTile<TargetApp>(
                      value: t,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      secondary: TargetAppIcon(t),
                      title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(t.description), InstalledBadge(t)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Étape 2 : la manette ----------

  Widget _controller() {
    return ListenableBuilder(
      listenable: Listenable.merge([app.healthListenable, app.buttonActivity]),
      builder: (context, _) {
        if (_permissionsOk == false) {
          return _Problem(
            icon: Icons.bluetooth_disabled,
            title: tr('Autorisation Bluetooth manquante'),
            text: tr('Sans « Appareils à proximité », ShiftLink ne peut pas trouver ta manette.'),
            action: tr('Autoriser'),
            onAction: _askPermissions,
          );
        }
        if (_permissionsOk == true && !app.bluetoothOn && !app.controllers.scanning.value) {
          return _Problem(
            icon: Icons.bluetooth_disabled,
            title: tr('Le Bluetooth est éteint'),
            text: tr('Allume-le pour que ShiftLink trouve ta manette.'),
            action: tr('Allumer le Bluetooth'),
            onAction: () async {
              await app.turnOnBluetooth();
              _search();
            },
          );
        }
        final list = app.controllers.controllers.value;
        final connected = list.where((c) => c.state.value == LinkState.connected).toList();
        final scanning = app.controllers.scanning.value;
        final waited = _searchSince != null && DateTime.now().difference(_searchSince!) > _helpAfter;
        final stuck = connected.isEmpty && (waited || (!scanning && app.controllers.lastScanEmpty.value));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (connected.isEmpty) ...[
              _WakeUp(searching: scanning || list.isNotEmpty),
              for (final c in list)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StatusLine(health: Health.waiting, text: tr('Connexion à {0}…', [c.name])),
                ),
              if (stuck) ...[
                const SizedBox(height: 16),
                _Causes(
                  onRetry: _search,
                  scanning: scanning,
                  onLearn: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnControllerPage(app: app))),
                ),
              ],
            ] else ...[
              for (final c in connected) ...[
                StatusLine(health: Health.ok, text: '${c.name} · ${c.driver.label}'),
                const SizedBox(height: 12),
                _ButtonTest(controller: c, tested: _tested, pressed: app.buttonActivity.value),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Manettes reconnues')),
              children: [
                for (final s in supportedControllers) Align(alignment: Alignment.centerLeft, child: Text('• ${tr(s)}')),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('Pas de manette ? Touche « Passer » : les gros boutons à l’écran marchent aussi.')),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ---------- Étape 3 : connexion à l'appli ----------

  Widget _connection() {
    return ListenableBuilder(
      listenable: Listenable.merge([app.healthListenable, app]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (app.appHealth == Health.ok) ...[
            _Success(text: tr('{0} est connecté ! On passe au résumé…', [app.target.label])),
            const SizedBox(height: 16),
          ],
          ConnectionSetup(app: app),
        ],
      ),
    );
  }

  // ---------- Étape 4 : résumé ----------

  bool get _usesTrainer => app.target.transport == Transport.proxy;

  /// Ce qui n'est pas encore prêt (pour le texte et le bouton final).
  List<String> _missing() => [
    if (app.controllerHealth != Health.ok) tr('la manette'),
    if (_usesTrainer && !app.proxy.trainer.isConnected) tr('le home trainer'),
    if (app.appHealth != Health.ok) app.target.label,
  ];

  Widget _done() {
    return ListenableBuilder(
      listenable: Listenable.merge([app.healthListenable, app]),
      builder: (context, _) {
        final missing = _missing();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(
              icon: Icons.gamepad_outlined,
              title: tr('Manette'),
              subtitle: app.controllerHealth == Health.ok
                  ? tr('Connectée')
                  : tr('Pas encore : les boutons à l’écran marchent en attendant'),
              health: app.controllerHealth == Health.ok ? Health.ok : Health.waiting,
              onTap: app.controllerHealth == Health.ok ? null : () => _go(1),
            ),
            const SizedBox(height: 8),
            if (_usesTrainer) ...[
              StatusPill(
                icon: Icons.directions_bike,
                title: tr('Home trainer'),
                subtitle: app.proxy.trainer.isConnected ? tr('Connecté') : tr('En attente'),
                health: app.proxy.trainer.isConnected ? Health.ok : Health.waiting,
                onTap: app.proxy.trainer.isConnected ? null : () => _go(2),
              ),
              const SizedBox(height: 8),
            ],
            StatusPill(
              icon: Icons.sports_esports_outlined,
              title: app.target.label,
              subtitle: app.appHealth == Health.ok ? tr('Connecté') : tr('En attente'),
              health: app.appHealth == Health.ok ? Health.ok : Health.waiting,
              onTap: app.appHealth == Health.ok ? null : () => _go(2),
            ),
            const SizedBox(height: 16),
            if (missing.isEmpty) ...[
              if (app.controllerHealth == Health.ok) ...[_tryIt(), const SizedBox(height: 16)],
              Text(
                tr(
                  'Pendant la séance, ShiftLink affiche ta vitesse en grand. Tu peux passer sur ton appli : ShiftLink reste actif en arrière-plan.',
                ),
              ),
            ] else ...[
              HintBox(
                icon: Icons.schedule,
                text: tr('Il te reste : {0}. Tu retrouveras ces étapes sur l’accueil, et tu peux déjà rouler.', [
                  missing.join(', '),
                ]),
              ),
              const SizedBox(height: 8),
              Text(tr('Touche une ligne en attente pour la finir maintenant.')),
            ],
            const SizedBox(height: 8),
            Text(tr('Tu peux refaire cette configuration à tout moment depuis les réglages.')),
          ],
        );
      },
    );
  }

  /// Essai en direct : un appui sur la manette doit déclencher une vitesse.
  Widget _tryIt() {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: app.lastFired,
      builder: (context, f, _) {
        final ok = f != null && f != _firedAtDone;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ok ? Brand.green.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ok ? Brand.green : Colors.transparent, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.touch_app_rounded, size: 32, color: ok ? Brand.green : null),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ok
                      ? tr('Ça marche : « {0} » envoyé à {1}. Regarde si la vitesse change dans l’appli.', [
                          f.action.label,
                          app.target.label,
                        ])
                      : tr('Essaie : appuie sur + de ta manette.'),
                  style: TextStyle(fontSize: 15.5, fontWeight: ok ? FontWeight.w700 : FontWeight.w500, height: 1.3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Barre de progression en segments : une case par étape.
class _StepBar extends StatelessWidget {
  final int step;
  final int count;
  const _StepBar({required this.step, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
              decoration: BoxDecoration(
                color: i <= step ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

/// Grande carte animée : « Appuie maintenant sur un bouton de ta manette ».
class _WakeUp extends StatefulWidget {
  final bool searching;
  const _WakeUp({required this.searching});

  @override
  State<_WakeUp> createState() => _WakeUpState();
}

class _WakeUpState extends State<_WakeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.1).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Icon(Icons.touch_app_rounded, size: 64, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Text(
            tr('Appuie maintenant sur un bouton de ta manette'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            widget.searching
                ? tr('Ça la réveille. ShiftLink la cherche…')
                : tr('Ça la réveille. Puis touche « Chercher encore ».'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
          if (widget.searching) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
        ],
      ),
    );
  }
}

/// Les causes possibles quand on ne trouve pas la manette, avec « Chercher encore ».
class _Causes extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onLearn;
  final bool scanning;
  const _Causes({required this.onRetry, required this.onLearn, required this.scanning});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Toujours rien ? Vérifie :'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          line(Icons.bedtime_outlined, tr('Ta manette dort : appuie sur un de ses boutons.')),
          line(
            Icons.link_off,
            tr('Elle est déjà connectée à une autre appli (BikeControl, Zwift…) : ferme cette appli.'),
          ),
          line(Icons.battery_alert, tr('Sa pile est faible : change-la ou recharge-la.')),
          line(Icons.social_distance, tr('Elle est loin : rapproche-la du téléphone.')),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: scanning ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(scanning ? tr('Recherche en cours…') : tr('Chercher encore')),
          ),
          TextButton.icon(
            onPressed: onLearn,
            icon: const Icon(Icons.school_rounded),
            label: Text(tr('Ma manette n’est pas dans la liste')),
          ),
        ],
      ),
    );
  }
}

/// Test visuel : chaque bouton de la manette s'allume quand on appuie, et garde un ✓.
class _ButtonTest extends StatelessWidget {
  final ConnectedController controller;
  final Set<String> tested;
  final ButtonActivity? pressed;
  const _ButtonTest({required this.controller, required this.tested, required this.pressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final driver = controller.driver;
    final ok = tested.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? Brand.green.withValues(alpha: 0.12) : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ok ? Brand.green : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.touch_app, size: 28, color: ok ? Brand.green : null),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok ? tr('Bien reçu ! Ta manette fonctionne.') : tr('Test : appuie sur + ou − de ta manette.'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in driver.buttons)
                _ButtonChip(
                  label: b.label,
                  lit:
                      pressed != null &&
                      pressed!.down &&
                      pressed!.driver.typeId == driver.typeId &&
                      pressed!.buttonId == b.id,
                  done: tested.contains(b.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ButtonChip extends StatelessWidget {
  final String label;
  final bool lit;
  final bool done;
  const _ButtonChip({required this.label, required this.lit, required this.done});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: lit ? Brand.yellow : (done ? Brand.green.withValues(alpha: 0.2) : cs.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lit ? Brand.yellow : (done ? Brand.green : cs.outlineVariant), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done && !lit) ...[const Icon(Icons.check, size: 16, color: Brand.green), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: lit ? Colors.black : null),
          ),
        ],
      ),
    );
  }
}

/// Un blocage expliqué, avec le bouton qui le corrige.
class _Problem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Problem({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.onErrorContainer, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: cs.onErrorContainer)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  final String text;
  const _Success({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Brand.green.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Brand.green, width: 1.5),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: Brand.green, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ],
    ),
  );
}
