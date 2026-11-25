// ShiftLink : passe les vitesses virtuelles de ton appli d'entraînement avec
// une manette Bluetooth. Licence GPL-3.0.
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/app_state.dart';
import 'src/i18n.dart';
import 'src/ui/brand.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/onboarding.dart';
import 'src/ui/play_dialogs.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(ShiftLinkApp(app: AppState()));
}

class ShiftLinkApp extends StatefulWidget {
  final AppState app;
  final ThemeMode? themeMode;
  const ShiftLinkApp({super.key, required this.app, this.themeMode});

  @override
  State<ShiftLinkApp> createState() => _ShiftLinkAppState();
}

class _ShiftLinkAppState extends State<ShiftLinkApp> {
  AppState get app => widget.app;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (!app.demo) WakelockPlus.enable();
    appLanguage.addListener(_rebuildAll);
    app.init();
    app.taps.onStillOff = () => explainRestrictedSetting(
      _navigator.currentContext,
      openAppInfo: app.taps.openAppInfo,
      openSettings: app.taps.openSettings,
    );
    app.explainBackground = () => explainBackgroundSettings(_navigator.currentContext);
  }

  /// Nouvelle langue : tous les écrans se redessinent, sans perdre la page ouverte.
  void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    if (mounted) (context as Element).visitChildren(mark);
  }

  @override
  void dispose() {
    appLanguage.removeListener(_rebuildAll);
    app.dispose();
    if (!app.demo) WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'ShiftLink',
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: shiftLinkTheme(Brightness.light),
        darkTheme: shiftLinkTheme(Brightness.dark),
        themeMode: widget.themeMode ?? app.themeMode,
        home: WithForegroundTask(
          child: Builder(
            builder: (context) {
              if (app.prefs == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
              if (!app.onboarded) {
                return OnboardingPage(app: app, initialStep: app.onboardingStep, key: const ValueKey('onboarding'));
              }
              return HomeShell(app: app);
            },
          ),
        ),
      ),
    );
  }
}
