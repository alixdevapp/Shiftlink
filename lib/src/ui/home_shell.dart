// Navigation principale : Rouler, Séances, Appareils, Réglages.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_state.dart';
import '../i18n.dart';
import 'brand.dart';
import 'devices_page.dart';
import 'ride_extras.dart' show WorkoutsTab;
import 'ride_page.dart';
import 'settings_page.dart';
import 'update_dialog.dart';
import 'whats_new.dart';

class HomeShell extends StatefulWidget {
  final AppState app;
  final int initialTab;
  const HomeShell({super.key, required this.app, this.initialTab = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _whatsNew());
    widget.app.onNotice = _notice;
  }

  /// Message court en bas de l'écran (refus de Power Lock, verrou relâché…).
  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
  }

  @override
  void dispose() {
    if (widget.app.onNotice == _notice) widget.app.onNotice = null;
    super.dispose();
  }

  Future<void> _whatsNew() async {
    if (widget.app.demo) return;
    String version;
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (widget.app.shouldShowWhatsNew(version)) await showWhatsNew(context, onlyLatest: true);
    final u = await widget.app.checkForUpdate(version);
    if (u == null || !mounted || widget.app.update.value == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: Text(tr('ShiftLink {0} est sortie.', [u.version])),
        action: SnackBarAction(
          label: tr('Mettre à jour'),
          onPressed: () => runUpdate(context, u),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: switch (tab) {
          0 => const BrandHeader(size: 32),
          1 => Text(tr('Séances')),
          2 => Text(tr('Appareils')),
          _ => Text(tr('Réglages')),
        },
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: [
            RidePage(app: app, onOpenDevices: () => setState(() => tab = 2)),
            WorkoutsTab(app: app),
            DevicesPage(app: app),
            SettingsPage(app: app),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.pedal_bike_outlined),
            selectedIcon: const Icon(Icons.pedal_bike),
            label: tr('Rouler'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            selectedIcon: const Icon(Icons.fitness_center),
            label: tr('Séances'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bluetooth_outlined),
            selectedIcon: const Icon(Icons.bluetooth),
            label: tr('Appareils'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('Réglages'),
          ),
        ],
      ),
    );
  }
}
