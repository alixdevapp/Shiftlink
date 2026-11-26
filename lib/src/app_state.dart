// État central de ShiftLink : connexions, appli choisie, journal.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show BluetoothAdapterState, BluetoothDevice, FlutterBluePlus;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'actions.dart';
import 'controller_manager.dart';
import 'controllers/driver.dart';
import 'controllers/key_input.dart';
import 'controllers/learned_driver.dart';
import 'controllers/registry.dart' as registry;
import 'controllers/simple_drivers.dart';
import 'controllers/steering_drivers.dart';
import 'gestures.dart';
import 'i18n.dart';
import 'keymap.dart';
import 'net/garmin_connect.dart';
import 'net/intervals_icu.dart';
import 'net/mywhoosh_account.dart';
import 'net/send_target.dart';
import 'net/update_check.dart';
import 'outputs/hid_keyboard.dart';
import 'outputs/obc_server.dart';
import 'outputs/screen_taps.dart';
import 'outputs/zwift_ride_emulator.dart';
import 'phone_steering.dart';
import 'ride/fit_fixer.dart';
import 'ride/health_connect.dart';
import 'ride/ride_history.dart';
import 'ride/ride_recorder.dart';
import 'riders.dart';
import 'sensors/bike_sensor.dart';
import 'sensors/headwind.dart';
import 'sensors/heart_rate.dart';
import 'sensors/incline.dart';
import 'trainer/ftms.dart' show BikeData;
import 'trainer/gears.dart';
import 'trainer/proxy.dart';
import 'trainer/route.dart';
import 'trainer/trainer_client.dart' show TrainerCandidate;
import 'trainer/workout.dart';
import 'training_plans.dart';
import 'voice.dart';
import 'whoosh_link.dart';

/// Comment ShiftLink transmet les vitesses à l'appli.
enum Transport { link, keyboard, proxy, obc, zwiftRide }

/// Applis proposées dans l'assistant.
enum TargetApp {
  mywhoosh('MyWhoosh', 'Vitesses virtuelles de MyWhoosh, connexion OpenBikeControl (ou Link) en Wi-Fi', Transport.link),
  mywhooshProxy(
    'MyWhoosh',
    'ShiftLink pilote ton trainer : tes vitesses, ton double plateau, tes profils',
    Transport.proxy,
  ),
  zwift('Zwift', 'ShiftLink pilote ton trainer et fait les vitesses virtuelles', Transport.proxy),
  zwiftRide(
    'Zwift',
    'Vitesses virtuelles de Zwift. ShiftLink se présente comme une manette Zwift Ride : vitesses, direction, power-up, menu (bêta)',
    Transport.zwiftRide,
  ),
  rouvy('Rouvy', 'Vitesses virtuelles de Rouvy, ShiftLink sert de clavier Bluetooth', Transport.keyboard, 'rouvy'),
  tpv('TrainingPeaks Virtual', 'ShiftLink sert de clavier Bluetooth', Transport.keyboard, 'tpv'),
  biketerra('Biketerra', 'ShiftLink sert de clavier Bluetooth', Transport.keyboard, 'biketerra'),
  biketerraObc(
    'Biketerra',
    'Vitesses virtuelles de Biketerra, connexion OpenBikeControl en Bluetooth',
    Transport.obc,
  ),
  trainerroad(
    'TrainerRoad',
    'ShiftLink pilote ton trainer : en ERG tes boutons changent les watts, sinon tes vitesses virtuelles',
    Transport.proxy,
  ),
  incyclist('Incyclist', 'ShiftLink pilote ton trainer et fait les vitesses virtuelles', Transport.proxy),
  incyclistObc(
    'Incyclist',
    'Vitesses virtuelles d’Incyclist, connexion OpenBikeControl en Wi-Fi (version récente d’Incyclist)',
    Transport.obc,
  ),
  rampida('Rampida', 'Vitesses virtuelles de Rampida, connexion OpenBikeControl', Transport.obc),
  everycol('Everycol', 'Monde virtuel dans Chrome ou Edge sur ordinateur, connexion OpenBikeControl en Bluetooth', Transport.obc),
  obc(
    'Appli OpenBikeControl',
    'Grimpa, icTrainer, Auuki, Ride Cave, Velotoss… en Wi-Fi ou en Bluetooth',
    Transport.obc,
  ),
  keyboard('Autre appli', 'Toute appli qui a des raccourcis clavier pour les vitesses', Transport.keyboard, 'custom'),
  proxyOther(
    'Autre appli',
    'FulGaz, Tacx Training, Gradient ou appli sans vitesses virtuelles : ShiftLink pilote ton trainer',
    Transport.proxy,
  );

  final String _label;
  String get label => tr(_label);
  final String _description;
  String get description => tr(_description);
  final Transport transport;
  final String? keyPreset;
  const TargetApp(this._label, this._description, this.transport, [this.keyPreset]);

  /// Les applis à choisir, une ligne chacune. Les variantes se règlent ensuite.
  static List<TargetApp> get pickable => values.where((t) => t.base == t).toList();

  /// L'appli de la liste dont c'est une variante (ou elle-même).
  TargetApp get base => switch (this) {
    mywhooshProxy => mywhoosh,
    incyclistObc => incyclist,
    biketerraObc => biketerra,
    proxyOther => keyboard,
    zwiftRide => zwift,
    _ => this,
  };

  /// L'autre façon d'utiliser la même appli : vitesses de l'appli ou de ShiftLink.
  TargetApp? get alternative => switch (this) {
    mywhoosh => mywhooshProxy,
    mywhooshProxy => mywhoosh,
    incyclist => incyclistObc,
    incyclistObc => incyclist,
    biketerra => biketerraObc,
    biketerraObc => biketerra,
    keyboard => proxyOther,
    proxyOther => keyboard,
    zwift => zwiftRide,
    zwiftRide => zwift,
    _ => null,
  };
}

/// État d'une connexion, pour les voyants.
enum Health { ok, waiting, off }

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());

/// Le service ne fait rien lui-même : il garde l'app en vie quand l'appli
/// d'entraînement est au premier plan sur le même appareil.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  /// Bouton « Arrêter » de la notification : c'est l'appli qui s'arrête.
  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

/// Bouton de la notification qui arrête ShiftLink.
List<NotificationButton> get _notificationButtons => [NotificationButton(id: 'stop', text: tr('Arrêter'))];

class AppState extends ChangeNotifier {
  final bool demo;
  SharedPreferences? prefs;

  final List<String> logs = [];
  late final WhooshLinkServer link = WhooshLinkServer(log: log);
  late final ObcServer obc = ObcServer(log: log);
  late final ZwiftRideEmulator zwiftRide = ZwiftRideEmulator(log: log)..onHaptic = relayHaptic;
  late final HidKeyboard keyboard = HidKeyboard(log: log);
  late final ScreenTaps taps = ScreenTaps(log: log);
  AppLifecycleListener? _lifecycle;
  late final VirtualShiftingProxy proxy = VirtualShiftingProxy(log: log);
  late final ControllerManager controllers = ControllerManager(onButton: _onButton, log: log);
  late final HeartRateMonitor heartRate = HeartRateMonitor(log: log);
  late final Headwind fan = Headwind(log: log);

  /// Wahoo KICKR Climb : l'avant du vélo suit la pente de l'appli.
  late final KickrClimb climb = KickrClimb(log: log);
  Timer? _inclineTimer;
  late final BikeSensor cadenceSensor = BikeSensor(SensorKind.cadence, log: log);
  late final BikeSensor powerSensor = BikeSensor(SensorKind.power, log: log);

  /// Capteur de cadence ou de puissance choisi, gardé pour le reconnecter au démarrage.
  Future<void> useSensor(BikeSensor s, SensorCandidate c) async {
    final k = s.kind.name;
    await prefs?.setString('$k.id', c.device.remoteId.str);
    await prefs?.setString('$k.name', c.name);
    await s.connect(c.device, c.name);
    notifyListeners();
  }

  Future<void> forgetSensor(BikeSensor s) async {
    await prefs?.remove('${s.kind.name}.id');
    await prefs?.remove('${s.kind.name}.name');
    await s.disconnect();
    notifyListeners();
  }

  /// La puissance du capteur remplace celle du trainer (envoyée à l'appli).
  bool get sensorPower => prefs?.getBool('sensorPower') ?? true;
  Future<void> setSensorPower(bool v) async {
    await prefs?.setBool('sensorPower', v);
    notifyListeners();
  }

  double? _externalCadence() {
    if (cadenceSensor.isConnected && cadenceSensor.fresh && cadenceSensor.cadence.value != null) {
      return cadenceSensor.cadence.value;
    }
    if (powerSensor.isConnected && powerSensor.fresh) return powerSensor.cadence.value;
    return null;
  }

  int? _externalPower() => sensorPower && powerSensor.isConnected && powerSensor.fresh ? powerSensor.power.value : null;

  FanMode get fanMode =>
      FanMode.values.where((m) => m.name == prefs?.getString('fanMode')).firstOrNull ?? FanMode.manual;

  Future<void> setFanMode(FanMode m) async {
    await prefs?.setString('fanMode', m.name);
    if (m == FanMode.heartRate) await fan.followHeartRate();
    if (m == FanMode.manual) await fan.setLevel(fan.level.value);
    fanInput.value = null;
    _fanWatts.clear();
    notifyListeners();
    if (m.hasRamp) _driveFan();
  }

  Future<void> useFan(SensorCandidate c) async {
    await prefs?.setString('fanId', c.device.remoteId.str);
    await prefs?.setString('fanName', c.name);
    await fan.connect(c.device, c.name);
  }

  Future<void> forgetFan() async {
    await prefs?.remove('fanId');
    await prefs?.remove('fanName');
    await fan.disconnect();
    notifyListeners();
  }

  Future<void> useClimb(SensorCandidate c) async {
    await prefs?.setString('climbId', c.device.remoteId.str);
    await prefs?.setString('climbName', c.name);
    _ensureInclineTimer();
    await climb.connect(c.device, c.name);
    notifyListeners();
  }

  Future<void> forgetClimb() async {
    await prefs?.remove('climbId');
    await prefs?.remove('climbName');
    await climb.disconnect();
    notifyListeners();
  }

  void _ensureInclineTimer() => _inclineTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _driveIncline());

  /// Une fois par seconde : la pente de l'appli part vers le KICKR Climb et l'Elite Rizer.
  void _driveIncline() {
    final grade = proxy.appGrade.value;
    unawaited(climb.follow(grade));
    for (final c in controllers.controllers.value) {
      final d = c.driver;
      if (d is EliteRizerDriver && c.state.value == LinkState.connected) {
        unawaited(
          d.follow(grade).then((_) {
            final refused = d.lastRefusal;
            if (refused != null) {
              d.lastRefusal = null;
              log('Elite Rizer : $refused');
            }
          }),
        );
      }
    }
  }

  /// Modes « suit ta vitesse » (un palier par tranche de 10 km/h environ) et
  /// Mode « suit ta puissance » : moyenne sur ~5 s pour ne pas changer de palier à chaque coup de pédale.
  void _driveFan() {
    if (!fan.isConnected) return;
    final int target;
    switch (fanMode) {
      case FanMode.speed:
        final kmh = proxy.rideSpeedKmh;
        if (kmh == null) return;
        target = Headwind.forSpeed(kmh);
      case FanMode.power:
        final w = proxy.data.value.power;
        if (w == null) return;
        _fanWatts.add(w);
        if (_fanWatts.length > 5) _fanWatts.removeAt(0);
        final avg = _fanWatts.reduce((a, b) => a + b) ~/ _fanWatts.length;
        fanInput.value = avg;
        final (start, full) = fanRamp(FanMode.power);
        target = Headwind.nextRampLevel(Headwind.rampPercent(avg, start, full), fan.level.value);
      case FanMode.heartRateStrap:
        final bpm = heartRate.bpm.value ?? proxy.data.value.heartRate;
        fanInput.value = bpm;
        if (bpm == null || bpm <= 0) return;
        final (start, full) = fanRamp(FanMode.heartRateStrap);
        target = Headwind.nextRampLevel(Headwind.rampPercent(bpm, start, full), fan.level.value);
      default:
        return;
    }
    if (target != fan.level.value) unawaited(fan.setLevel(target));
  }

  final List<int> _fanWatts = [];

  /// Mesure suivie par le ventilateur (watts moyens ou bpm), pour l'affichage.
  final ValueNotifier<int?> fanInput = ValueNotifier(null);

  /// Rampe du ventilateur : (démarre à, à fond à), en watts ou en bpm.
  (int, int) fanRamp(FanMode m) => switch (m) {
    FanMode.heartRateStrap => (prefs?.getInt('fanHrStart') ?? 100, prefs?.getInt('fanHrFull') ?? 170),
    _ => (prefs?.getInt('fanPowerStart') ?? 30, prefs?.getInt('fanPowerFull') ?? (ftp * 0.95).round()),
  };

  Future<void> setFanRamp(FanMode m, int start, int full) async {
    final hr = m == FanMode.heartRateStrap;
    await prefs?.setInt(hr ? 'fanHrStart' : 'fanPowerStart', start);
    await prefs?.setInt(hr ? 'fanHrFull' : 'fanPowerFull', full);
    notifyListeners();
    _driveFan();
  }

  /// Enregistrement de la sortie : données du trainer et cardio.
  late final RideRecorder ride = RideRecorder(
    read: () {
      final d = proxy.data.value;
      return (
        power: d.power,
        cadence: d.cadence?.round(),
        heartRate: heartRate.bpm.value ?? d.heartRate,
        speedKmh: proxy.rideSpeedKmh,
      );
    },
    ftp: () => ftp,
    // Sur un parcours : la position et l'altitude vont dans le .fit (carte et dénivelé).
    position: () {
      final run = proxy.routeRun.value;
      if (run == null) return null;
      final ll = run.route.latLonAt(run.distance);
      return (lat: ll?.$1, lon: ll?.$2, altitude: run.route.elevationAt(run.distance));
    },
  );

  /// Ceinture cardio choisie, gardée pour la reconnecter au démarrage.
  Future<void> useHeartRate(SensorCandidate c) async {
    await prefs?.setString('hrId', c.device.remoteId.str);
    await prefs?.setString('hrName', c.name);
    await heartRate.connect(c.device, c.name);
  }

  Future<void> forgetHeartRate() async {
    await prefs?.remove('hrId');
    await prefs?.remove('hrName');
    await heartRate.disconnect();
    notifyListeners();
  }

  /// Voix : annonce la vitesse (quand ShiftLink la connaît) et les alertes.
  bool get voice => prefs?.getBool('voice') ?? true;
  Future<void> setVoice(bool v) async {
    await prefs?.setBool('voice', v);
    notifyListeners();
    if (v) unawaited(_voice.say(tr('La voix est activée')));
  }

  final Voice _voice = Voice();
  final BatteryWatch _batteryWatch = BatteryWatch();

  /// Dernière alerte de pile faible, affichée sur l'écran Rouler jusqu'à ce qu'on la ferme.
  final ValueNotifier<BatteryAlert?> batteryAlert = ValueNotifier(null);

  /// Android laisse ShiftLink actif en arrière-plan (pas d'optimisation de batterie). null : pas encore vérifié.
  final ValueNotifier<bool?> keepsRunning = ValueNotifier(null);

  Future<void> refreshKeepsRunning() async {
    if (demo || !Platform.isAndroid) {
      keepsRunning.value = true;
      return;
    }
    try {
      keepsRunning.value = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {}
  }

  /// Ouvre la question d'Android « Autoriser ShiftLink en arrière-plan ? ».
  /// Rend la main à Android : ouvre la liste des applis où l'on remet ShiftLink en « Optimiser ».
  Future<void> openBackgroundSettings() async {
    try {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {}
  }

  /// Explique quoi toucher avant d'ouvrir la liste des réglages batterie.
  /// Rend faux si la personne annule.
  Future<bool> Function()? explainBackground;

  /// Ouvre la liste d'Android où l'on met ShiftLink en « Ne pas optimiser ».
  /// (Google Play refuse la demande directe REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.)
  Future<void> allowBackground() async {
    final explain = explainBackground;
    if (explain != null && !await explain()) return;
    try {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {}
    await refreshKeepsRunning();
  }

  final Set<ConnectedController> _watched = {};

  void _say(String text) {
    if (voice && !demo) unawaited(_voice.say(text));
  }

  /// Compte à rebours sonore avant chaque changement de bloc d'une séance.
  bool get workoutCountdown => prefs?.getBool('workoutCountdown') ?? true;
  Future<void> setWorkoutCountdown(bool v) async {
    await prefs?.setBool('workoutCountdown', v);
    notifyListeners();
  }

  /// Dernière seconde déjà signalée (bloc, secondes restantes), pour ne bipper qu'une fois.
  (int, int)? _lastCountdown;

  /// 10 s avant un bloc : la voix annonce ses watts. À 3, 2, 1 : un bip ; au départ : un bip long.
  void _workoutCountdownTick() {
    final r = proxy.workout.value;
    if (r == null || r.paused || !workoutCountdown || demo) return;
    final key = (r.step, r.stepSecondsLeft);
    if (key == _lastCountdown) return;
    final previous = _lastCountdown;
    _lastCountdown = key;
    if (previous != null && previous.$1 != r.step) unawaited(_tone('go'));
    if (r.step >= r.steps) return;
    final left = r.stepSecondsLeft;
    if (left >= 1 && left <= 3) unawaited(_tone('count'));
    if (left == 10 && voice) {
      final next = r.workout.steps[r.step];
      _say(tr('Dans 10 secondes : {0} watts', [(next.from * ftp).round()]));
    }
  }

  /// Dernier bloc annoncé à la voix, pour éviter de le redire chaque seconde.
  int _lastAnnouncedStep = 0;
  void _announceWorkoutStep() {
    _workoutCountdownTick();
    final r = proxy.workout.value;
    if (r == null) {
      _lastAnnouncedStep = 0;
      _lastCountdown = null;
      _lastSpokenMessage = null;
      return;
    }
    if (!voice || demo) return;
    if (r.step != _lastAnnouncedStep) {
      _lastAnnouncedStep = r.step;
      final s = r.workout.steps[r.step - 1];
      final w = (s.from * ftp).round();
      _say(
        s.cadence == null
            ? tr('{0} watts pendant {1} secondes', [w, s.seconds])
            : tr('{0} watts pendant {1} secondes, à {2} tours par minute', [w, s.seconds, s.cadence]),
      );
    }
    // Messages de coaching de la séance : lus une fois chacun.
    final m = r.message;
    if (m != null && m.at != _lastSpokenMessage) {
      _lastSpokenMessage = m.at;
      _say(m.text);
    }
  }

  /// Un tour dans le .fit à chaque bloc de séance (et au début / à la fin de la séance).
  int? _lastSpokenMessage;
  int _lapStep = 0;
  void _lapOnWorkoutStep() {
    final step = proxy.workout.value?.step ?? 0;
    if (step == _lapStep) return;
    _lapStep = step;
    ride.markLap();
  }

  /// Dernier test FTP terminé, à proposer à la personne.
  final ValueNotifier<FtpTestResult?> ftpTestResult = ValueNotifier(null);

  void _onFinishedWorkout() {
    final w = proxy.finishedWorkout.value;
    if (w == null) return;
    _say(tr('Séance terminée, bravo !'));
    if (w.ftpTest != null) {
      final log = proxy.lastPowerLog;
      if (log.length >= 60) {
        int newFtp;
        if (w.ftpTest == 'ramp') {
          final last = log.sublist(log.length - 60);
          final avg = last.reduce((a, b) => a + b) / last.length;
          newFtp = (avg * 0.75).round();
        } else {
          // 20min : moyenne de la plus grosse fenêtre de 20 min continues.
          var best = 0.0;
          const win = 20 * 60;
          if (log.length >= win) {
            var sum = log.take(win).fold<int>(0, (a, b) => a + b);
            best = sum / win;
            for (var i = win; i < log.length; i++) {
              sum += log[i] - log[i - win];
              final avg = sum / win;
              if (avg > best) best = avg;
            }
          } else {
            best = log.reduce((a, b) => a + b) / log.length;
          }
          newFtp = (best * 0.95).round();
        }
        ftpTestResult.value = FtpTestResult(newFtp, w.ftpTest!);
      }
    }
  }

  /// Applique la nouvelle FTP mesurée au cycliste actif (ou à l'appli s'il n'y en a pas).
  Future<void> applyFtpTest(int newFtp) async {
    final r = rider;
    if (r != null) {
      await saveRider(r.copyWith(ftp: newFtp), replacing: r.name);
    } else {
      // Sans cycliste : la FTP de l'appli.
      await prefs?.setInt('ftp', newFtp);
    }
    ftpTestResult.value = null;
    notifyListeners();
  }

  /// Rafraîchit le widget écran d'accueil avec les totaux de la semaine en cours.
  Future<void> refreshWeeklyWidget() async {
    if (demo || !Platform.isAndroid) return;
    try {
      final dir = await RideRecorder.directory();
      final list = await RideHistory(dir).list();
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      var seconds = 0, rides = 0;
      var meters = 0.0;
      for (final r in list) {
        if (r.start.isBefore(monday)) break;
        rides++;
        seconds += r.duration.inSeconds;
        meters += r.distance;
      }
      final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
      final duration = h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}min';
      final km = (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');
      await HomeWidget.saveWidgetData('weeklyDuration', duration);
      await HomeWidget.saveWidgetData('weeklyKm', km);
      await HomeWidget.saveWidgetData('weeklyRides', rides);
      await HomeWidget.updateWidget(name: 'WeeklyWidget', androidName: 'WeeklyWidget');
    } catch (_) {}
  }

  /// Suit la pile et la connexion de chaque nouvelle manette.
  void _watchControllers() {
    for (final c in controllers.controllers.value) {
      if (!_watched.add(c)) continue;
      void onBattery() {
        final level = c.battery.value;
        if (level == null) return;
        final t = _batteryWatch.check(c.device.remoteId.str, level);
        if (t == null) return;
        log('Pile faible : ${c.name} ($level %)');
        batteryAlert.value = BatteryAlert(c.name, level);
        _say(tr('Pile de la manette faible : {0} %', [level]));
        if (!demo && Platform.isAndroid) {
          unawaited(
            FlutterForegroundTask.updateService(
              notificationTitle: tr('Pile de la manette faible'),
              notificationText: tr('{0} : {1} %. Pense à la changer ou à la recharger.', [c.name, level]),
              notificationButtons: _notificationButtons,
            ),
          );
        }
      }

      var last = c.state.value;
      void onState() {
        final now = c.state.value;
        // Partie (coupure, veille, oubli) en plein appui : le relâchement n'arrivera
        // plus. On arrête les répétitions et on relâche les actions maintenues.
        if (now != LinkState.connected) _engines.remove(c.device.remoteId.str)?.releaseAll();
        if (last == LinkState.connected && now == LinkState.disconnected && !c.asleep && !c.forgotten) {
          _say(tr('Manette déconnectée'));
          _lostAt[c] = DateTime.now();
        } else if (now == LinkState.connected && _lostAt.remove(c) != null) {
          _say(tr('Manette reconnectée'));
        }
        last = now;
      }

      c.battery.addListener(onBattery);
      c.state.addListener(onState);
      onBattery();
    }
    _watched.removeWhere((c) => !controllers.controllers.value.contains(c));
  }

  final Map<ConnectedController, DateTime> _lostAt = {};

  /// Nouveautés : à montrer une fois si ShiftLink vient d'être mis à jour (pas à la première installation).
  // ------- Nouvelle version de ShiftLink --------
  /// Prévenir quand une nouvelle version sort (une requête à GitHub à chaque ouverture).
  bool get checkUpdates => updateRepo.isNotEmpty && (prefs?.getBool('checkUpdates') ?? true);
  Future<void> setCheckUpdates(bool v) async {
    await prefs?.setBool('checkUpdates', v);
    notifyListeners();
  }

  /// Nouvelle version trouvée (et pas encore écartée).
  final ValueNotifier<UpdateInfo?> update = ValueNotifier(null);

  /// Cherche une nouvelle version : à chaque ouverture de l'appli (si activé), ou tout de suite avec [now].
  Future<UpdateInfo?> checkForUpdate(String current, {bool now = false}) async {
    if (demo || updateRepo.isEmpty || current.isEmpty) return null;
    if (!now && !checkUpdates) return null;
    final u = await fetchUpdate(current);
    if (u != null) log('Nouvelle version de ShiftLink : ${u.version}');
    update.value = u == null || (!now && prefs?.getString('skippedVersion') == u.version) ? null : u;
    return u;
  }

  /// « Plus tard » : ne plus proposer cette version-là.
  Future<void> skipUpdate() async {
    final u = update.value;
    if (u != null) await prefs?.setString('skippedVersion', u.version);
    update.value = null;
  }

  bool shouldShowWhatsNew(String version) {
    final seen = prefs?.getString('seenVersion');
    if (seen == version) return false;
    unawaited(prefs?.setString('seenVersion', version));
    return onboarded && version.isNotEmpty;
  }

  static const _tile = MethodChannel('shiftlink/tile');

  /// Demande à Android d'ajouter la tuile ShiftLink. 'added', 'already', 'refused' ou 'manual'.
  Future<String> addQuickTile() async {
    if (demo || !Platform.isAndroid) return 'manual';
    try {
      return await _tile.invokeMethod<String>('add') ?? 'manual';
    } catch (_) {
      return 'manual';
    }
  }

  /// Coupe les manettes 5 min après la fin de la séance (appli déconnectée), pour leurs piles.
  /// Boîte auto : ShiftLink change les vitesses pour te garder autour d'une cadence cible.
  /// Ne marche que quand ShiftLink pilote le trainer (Transport.proxy, hors ERG).
  bool get autoShift => prefs?.getBool('autoShift') ?? false;
  Future<void> setAutoShift(bool v) async {
    await prefs?.setBool('autoShift', v);
    _autoHigh = 0;
    _autoLow = 0;
    notifyListeners();
  }

  int get autoShiftLowCad => prefs?.getInt('autoShiftLow') ?? 85;
  Future<void> setAutoShiftLowCad(int v) async {
    final x = v.clamp(50, 110);
    await prefs?.setInt('autoShiftLow', x);
    if (x >= autoShiftHighCad) await prefs?.setInt('autoShiftHigh', (x + 5).clamp(60, 130));
    notifyListeners();
  }

  int get autoShiftHighCad => prefs?.getInt('autoShiftHigh') ?? 95;
  Future<void> setAutoShiftHighCad(int v) async {
    final x = v.clamp(60, 130);
    await prefs?.setInt('autoShiftHigh', x);
    if (x <= autoShiftLowCad) await prefs?.setInt('autoShiftLow', (x - 5).clamp(50, 110));
    notifyListeners();
  }

  DateTime _autoPauseUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _autoHigh = 0;
  int _autoLow = 0;
  DateTime? _autoLastTick;

  void _autoShiftTick() {
    if (!autoShift) {
      _autoHigh = 0;
      _autoLow = 0;
      return;
    }
    // Seulement quand ShiftLink pilote le trainer et n'est pas en ERG (watts imposés).
    if (target.transport != Transport.proxy || !proxy.active || proxy.mode == TrainerMode.erg) {
      _autoHigh = 0;
      _autoLow = 0;
      return;
    }
    if (DateTime.now().isBefore(_autoPauseUntil)) {
      _autoHigh = 0;
      _autoLow = 0;
      return;
    }
    final c = proxy.data.value.cadence;
    if (c == null || c < 30) {
      _autoHigh = 0;
      _autoLow = 0;
      return;
    }
    final now = DateTime.now();
    final dt = _autoLastTick == null ? 1 : now.difference(_autoLastTick!).inSeconds.clamp(0, 3);
    _autoLastTick = now;
    final dtS = dt == 0 ? 1 : dt;
    if (c >= autoShiftHighCad) {
      _autoHigh += dtS;
      _autoLow = 0;
      if (_autoHigh >= 2) {
        _autoHigh = 0;
        _autoShift(1);
      }
    } else if (c <= autoShiftLowCad) {
      _autoLow += dtS;
      _autoHigh = 0;
      if (_autoLow >= 2) {
        _autoLow = 0;
        _autoShift(-1);
      }
    } else {
      _autoHigh = 0;
      _autoLow = 0;
    }
  }

  void _autoShift(int delta) {
    final g = proxy.gears.gear;
    final count = proxy.gears.count;
    if (delta > 0 && g >= count) return;
    if (delta < 0 && g <= 1) return;
    log('Boîte auto : ${delta > 0 ? '+1' : '−1'}');
    shift(delta, fromAuto: true);
  }

  bool get autoSleep => prefs?.getBool('autoSleep') ?? true;
  Future<void> setAutoSleep(bool v) async {
    await prefs?.setBool('autoSleep', v);
    notifyListeners();
  }

  static const sleepAfter = Duration(minutes: 5);
  bool _appWasOk = false;
  DateTime? _appOffSince;
  Timer? _watchdog;

  void _checkSleep() {
    final ok = appHealth == Health.ok;
    if (ok) {
      _appWasOk = true;
      _appOffSince = null;
      if (controllers.asleep.value) {
        log('Appli reconnectée : on réveille les manettes');
        unawaited(controllers.wake());
      }
      return;
    }
    // Pendant l'assistant, on a besoin des manettes : pas de veille.
    if (!autoSleep || controllers.asleep.value || !onboarded) return;
    final since = _appOffSince ??= DateTime.now();
    if (!controllers.controllers.value.any((c) => c.state.value == LinkState.connected && c.isBluetooth)) return;
    if (_appWasOk) {
      if (DateTime.now().difference(since) < sleepAfter) return;
      log('Séance terminée : manettes déconnectées pour économiser leurs piles');
    } else {
      // L'appli d'entraînement n'est jamais venue : veille après un long moment sans appui.
      final lastPress = _lastPressAt ?? since;
      final quiet = DateTime.now().difference(lastPress.isAfter(since) ? lastPress : since);
      if (quiet < idleSleepAfter) return;
      log('Aucun appui depuis ${idleSleepAfter.inMinutes} min : manettes en veille pour économiser leurs piles');
    }
    unawaited(controllers.sleep());
  }

  /// Veille quand l'appli d'entraînement ne s'est jamais connectée et que personne n'appuie.
  static const idleSleepAfter = Duration(minutes: 10);
  DateTime? _lastPressAt;
  ConnectedController? _lastPressed;

  /// Zwift Click v2 : côté droit seul, sans déverrouillage dans Zwift.
  bool get clickV2RightOnly => prefs?.getBool('clickV2RightOnly') ?? false;
  Future<void> setClickV2RightOnly(bool v) async {
    await prefs?.setBool('clickV2RightOnly', v);
    registry.clickV2RightOnly = v;
    // On repart de zéro avec les Click v2 déjà connectées, puis on cherche à nouveau.
    for (final c in List.of(controllers.controllers.value)) {
      if (c.driver.typeId.startsWith('zwiftClickV2')) await controllers.forget(c);
    }
    notifyListeners();
    unawaited(controllers.scan());
  }

  /// Appareils à ne plus jamais connecter (manette du voisin…).
  Map<String, String> get ignoredDevices => controllers.ignored;

  Future<void> ignoreController(ConnectedController c) async {
    controllers.ignored[c.device.remoteId.str] = c.name;
    await _saveIgnored();
    await controllers.forget(c);
    notifyListeners();
  }

  Future<void> unignore(String id) async {
    controllers.ignored.remove(id);
    await _saveIgnored();
    notifyListeners();
  }

  /// Manettes apprises (« Ma manette n'est pas dans la liste »).
  Future<void> adoptLearned(BluetoothDevice device, LearnedProfile p) async {
    controllers.adopt(device, p);
    await _saveLearned();
  }

  Future<void> forgetLearned(String id) async {
    controllers.learned.remove(id);
    await _saveLearned();
  }

  Future<void> _saveLearned() async =>
      prefs?.setString('learned', jsonEncode({for (final e in controllers.learned.entries) e.key: e.value.toJson()}));

  void _loadLearned() {
    try {
      final m = (jsonDecode(prefs?.getString('learned') ?? '{}') as Map).cast<String, Object?>();
      for (final e in m.entries) {
        controllers.learned[e.key] = LearnedProfile.fromJson((e.value as Map).cast());
      }
    } catch (_) {}
  }

  Future<void> _saveIgnored() async => prefs?.setString('ignored', jsonEncode(controllers.ignored));

  void _loadIgnored() {
    try {
      final m = (jsonDecode(prefs?.getString('ignored') ?? '{}') as Map).cast<String, String>();
      controllers.ignored
        ..clear()
        ..addAll(m);
    } catch (_) {}
  }

  /// Les manettes de jeu vibrent à chaque vitesse.
  bool get rumble => prefs?.getBool('rumble') ?? true;
  Future<void> setRumble(bool v) async {
    await prefs?.setBool('rumble', v);
    notifyListeners();
  }

  String? _lastKeyDevice;
  DateTime _lastKeyAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Enregistre la sortie tout seul dès que tu pédales (ShiftLink pilote le trainer).
  bool get autoRecord => prefs?.getBool('autoRecord') ?? true;
  Future<void> setAutoRecord(bool v) async {
    await prefs?.setBool('autoRecord', v);
    notifyListeners();
  }

  /// Envoie les sorties enregistrées à Health Connect.
  bool get healthConnect => healthConnectAvailable && (prefs?.getBool('healthConnect') ?? false);

  /// Health Connect est installée sur le téléphone (sinon la ligne est grisée).
  bool healthConnectAvailable = true;
  Future<void> refreshHealthConnect() async {
    final v = await _health.isAvailable();
    if (v == healthConnectAvailable) return;
    healthConnectAvailable = v;
    notifyListeners();
  }

  Future<void> setHealthConnect(bool v) async {
    if (v && !await _health.requestAccess()) {
      log('Health Connect : accès refusé ou appli absente');
      return;
    }
    await prefs?.setBool('healthConnect', v);
    notifyListeners();
  }

  final HealthConnect _health = HealthConnect();
  DateTime? _pedalSince;
  DateTime? _idleSince;
  bool _autoRecording = false;

  /// Dernière sortie enregistrée automatiquement (pour la proposer au partage).
  final ValueNotifier<File?> lastAutoRide = ValueNotifier(null);

  void _autoRide() {
    if (demo) return;
    final d = proxy.data.value;
    final pedaling = (d.power ?? 0) > 20 || (d.cadence ?? 0) > 30;
    final now = DateTime.now();
    if (!ride.recording.value) {
      // Séance, parcours ou ERG lancés dans ShiftLink : enregistrés aussi, quelle que soit l'appli choisie.
      final alone = proxy.workout.value != null || proxy.routeRun.value != null || proxy.fixedErg.value != null;
      if (!autoRecord || (target.transport != Transport.proxy && !alone) || !proxy.active || !pedaling) {
        _pedalSince = null;
        return;
      }
      final since = _pedalSince ??= now;
      if (now.difference(since).inSeconds >= 20) {
        _autoRecording = true;
        _idleSince = null;
        ride.start();
        log('Tu pédales : sortie enregistrée automatiquement');
      }
      return;
    }
    if (!_autoRecording) return;
    if (pedaling && proxy.active) {
      _idleSince = null;
      return;
    }
    final idle = _idleSince ??= now;
    if (now.difference(idle).inMinutes >= 3) unawaited(finishRide());
  }

  /// Arrête la sortie, l'enregistre et l'envoie à Health Connect si activé.
  Future<File?> finishRide() async {
    final wasAuto = _autoRecording;
    _autoRecording = false;
    _pedalSince = null;
    final samples = [...ride.samples];
    final file = await ride.stop();
    if (file == null) return null;
    if (wasAuto) lastAutoRide.value = file;
    log('Sortie enregistrée : ${file.path.split('/').last}');
    if (healthConnect) {
      final ok = await _health.saveRide(samples, ride.distance.value);
      log(ok ? 'Sortie envoyée à Health Connect' : 'Health Connect : envoi impossible');
    }
    final auto = [for (final t in SendTarget.values) if (targetAuto(t)) t];
    lastAutoSend.value = auto.isEmpty ? null : tr('Envoi sur {0}…', [auto.map((t) => t.label).join(', ')]);
    if (auto.isNotEmpty) unawaited(_autoSend(file, auto));
    unawaited(refreshWeeklyWidget());
    return file;
  }

  int shifts = 0;
  int? lastDelta;

  /// Pignon affiché par l'animation quand l'appli calcule elle-même les vitesses :
  /// indicatif, il suit les changements sans connaître la vraie vitesse.
  int displayCog = 12;

  /// Nombre de vitesses de l'appli quand elle les calcule elle-même (un pignon dessiné par vitesse).
  int get appGearCount => prefs?.getInt('appGears.${target.base.name}') ?? defaultAppGears(target);

  static int defaultAppGears(TargetApp t) => switch (t.base) {
    TargetApp.mywhoosh => 30, // MyShift : 30 vitesses
    _ => 24, // Zwift et la plupart des applis : 24
  };

  Future<void> setAppGearCount(int n) async {
    final v = n.clamp(minAppGears, maxAppGears);
    await prefs?.setInt('appGears.${target.base.name}', v);
    displayCog = (v + 1) ~/ 2;
    notifyListeners();
  }

  static const minAppGears = 8;
  static const maxAppGears = 34;
  DateTime? lastShiftAt;
  List<String> ips = [];

  /// Appelé à chaque appui sur la manette (pour l'assistant).
  final ValueNotifier<int> controllerPresses = ValueNotifier(0);

  /// Dernier bouton appuyé ou relâché (pour l'écran des boutons).
  final ValueNotifier<ButtonActivity?> buttonActivity = ValueNotifier(null);

  /// Dernière action déclenchée par un bouton.
  final ValueNotifier<FiredAction?> lastFired = ValueNotifier(null);

  final Map<String, GestureEngine> _engines = {};
  Keymap? _keymap;

  /// Réglage des boutons pour l'appli choisie.
  Keymap get keymap {
    final k = _keymap;
    if (k != null && k.target == target.name) return k;
    return _keymap = Keymap(prefs!, target.name);
  }

  AppState({this.demo = false});

  /// Thème choisi (sombre par défaut : plus lisible pendant l'effort).
  ThemeMode get themeMode => switch (prefs?.getString('theme')) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  Future<void> setThemeMode(ThemeMode m) async {
    await prefs?.setString('theme', m.name);
    notifyListeners();
  }

  /// Langue choisie : 'auto' (celle du téléphone), 'fr' ou 'en'.
  String get language => prefs?.getString('language') ?? (demo ? 'fr' : 'auto');

  Future<void> setAppLanguage(String lang) async {
    await prefs?.setString('language', lang);
    _applyLanguage();
    notifyListeners();
  }

  void _applyLanguage() => setLanguage(language, PlatformDispatcher.instance.locale.languageCode);

  bool get onboarded => prefs?.getBool('onboarded') ?? false;
  bool get invert => prefs?.getBool('invert') ?? false;
  set invert(bool v) {
    prefs?.setBool('invert', v);
    notifyListeners();
  }

  /// Mode clavier : l'appli tourne sur ce téléphone (appuis à l'écran) plutôt que sur un autre appareil.
  bool get sameDevice => prefs?.getBool('sameDevice') ?? false;
  Future<void> setSameDevice(bool v) async {
    await prefs?.setBool('sameDevice', v);
    await _startTransport();
    notifyListeners();
  }

  /// Touches des télécommandes, manettes de jeu et claviers Bluetooth.
  bool get captureKeys => prefs?.getBool('captureKeys') ?? false;
  Future<void> setCaptureKeys(bool v) async {
    await prefs?.setBool('captureKeys', v);
    await _pushCaptureKeys(force: true);
    notifyListeners();
  }

  String? _lastCaptureSpec;

  /// Dit au service d'accessibilité quelles touches prendre : sur un vrai clavier,
  /// seulement celles réglées sur une action (le reste tape normalement).
  Future<void> _pushCaptureKeys({bool force = false}) async {
    final p = prefs;
    if (p == null || demo) return;
    final devices = <String>[];
    final keys = <String>[];
    for (final k in p.getKeys()) {
      if (!k.startsWith('keys.')) continue;
      final descriptor = k.substring(5);
      final driver = KeyInputDriver(descriptor, [...?p.getStringList(k), ...defaultKeyActions]);
      devices.add(descriptor);
      for (final key in driver.keys.toSet()) {
        final used = Gesture.values.any((g) => keymap.actionFor(driver, key, g) != null) || keymap.inCombo(driver, key);
        if (used) keys.add('$descriptor|$key');
      }
    }
    final spec = '$captureKeys ${devices.join(',')} ${keys.join(',')}';
    if (!force && spec == _lastCaptureSpec) return;
    _lastCaptureSpec = spec;
    await taps.setCaptureKeys(captureKeys, keys: keys, devices: devices, defaults: defaultKeyActions);
  }

  final Map<String, ConnectedController> _keyDevices = {};

  void _onKey(String descriptor, String name, String key, bool down) {
    var c = _keyDevices[descriptor];
    if (c == null) {
      final known = prefs?.getStringList('keys.$descriptor') ?? [];
      c = ConnectedController(BluetoothDevice.fromId(descriptor), KeyInputDriver(descriptor, [...known]), name);
      c.state.value = LinkState.connected;
      _keyDevices[descriptor] = c;
      controllers.controllers.value = [...controllers.controllers.value, c];
      log('$name : touches reçues');
    }
    _lastKeyDevice = descriptor;
    _lastKeyAt = DateTime.now();
    final driver = c.driver as KeyInputDriver;
    if (driver.learn(key)) {
      prefs?.setStringList('keys.$descriptor', driver.keys);
      unawaited(_pushCaptureKeys());
    }
    _onButton(c, ButtonEvent(key, down));
  }

  /// Le téléphone fixé au guidon sert à tourner.
  bool get phoneSteering => prefs?.getBool('phoneSteering') ?? false;
  double get steeringThreshold => prefs?.getDouble('steerThreshold') ?? 8;
  ConnectedController? _phoneController;

  /// Le téléphone au guidon, vu comme une manette (pour régler ses actions).
  ConnectedController? get phoneController => phoneSteering ? _phoneController : null;
  PhoneSteering? _steering;

  /// Angle actuel du guidon (degrés, positif à gauche), pour l'écran de réglage.
  final ValueNotifier<double> steeringAngle = ValueNotifier(0);
  final ValueNotifier<SteeringStatus> steeringStatus = ValueNotifier(SteeringStatus.off);

  Future<void> setPhoneSteering(bool v) async {
    await prefs?.setBool('phoneSteering', v);
    _applyPhoneSteering();
    notifyListeners();
  }

  /// Délai maximal entre les deux appuis d'un double clic, en millisecondes.
  int get doubleClickMs => prefs?.getInt('doubleClickMs') ?? GestureEngine.defaultDoubleWindow.inMilliseconds;

  /// Durée d'appui qui déclenche l'appui long, en millisecondes.
  int get longPressMs => prefs?.getInt('longPressMs') ?? GestureEngine.defaultLongDelay.inMilliseconds;

  Future<void> setGestureTimings({int? doubleClick, int? longPress}) async {
    if (doubleClick != null) await prefs?.setInt('doubleClickMs', doubleClick);
    if (longPress != null) await prefs?.setInt('longPressMs', longPress);
    _resetEngines();
    notifyListeners();
  }

  void _resetEngines() {
    for (final e in _engines.values) {
      e.dispose();
    }
    _engines.clear();
  }

  Future<void> setSteeringThreshold(double v) async {
    await prefs?.setDouble('steerThreshold', v);
    _steering?.gate.threshold = v;
    notifyListeners();
  }

  Future<void> forgetController(ConnectedController c) async {
    if (c == _phoneController) return setPhoneSteering(false);
    if (c.driver is LearnedDriver) await forgetLearned(c.device.remoteId.str);
    await controllers.forget(c);
  }

  void recenterSteering() => _steering?.recenter();

  void _applyPhoneSteering() {
    if (phoneSteering) {
      var c = _phoneController;
      if (c == null) {
        c = _phoneController = ConnectedController(
          BluetoothDevice.fromId('phone-steering'),
          PhoneSteeringDriver(),
          tr('Téléphone au guidon'),
        );
        c.state.value = LinkState.connected;
        controllers.controllers.value = [...controllers.controllers.value, c];
      }
      if (demo) return;
      _steering ??= PhoneSteering(
        threshold: steeringThreshold,
        onEvent: (e) => _onButton(_phoneController!, e),
        onAngle: (a) => steeringAngle.value = a,
        onStatus: (s) => steeringStatus.value = s,
      );
      _steering!.start();
      log('Direction au téléphone : garde le guidon droit un instant');
    } else {
      _steering?.stop();
      final c = _phoneController;
      if (c != null) {
        controllers.controllers.value = [...controllers.controllers.value]..remove(c);
        _phoneController = null;
      }
    }
  }

  /// Affichage par-dessus l'appli d'entraînement.
  bool get hudEnabled => prefs?.getBool('hud') ?? false;
  Future<void> setHud(bool v) async {
    await prefs?.setBool('hud', v);
    _hudShown = null;
    _updateHud();
    notifyListeners();
  }

  Listenable? _hudListener;
  String? _hudShown;

  /// Chiffres montrés dans la fenêtre par-dessus l'appli.
  static const hudFieldChoices = ['power', 'cadence', 'erg', 'ratio', 'speed', 'hr'];
  List<String> get hudFields => prefs?.getStringList('hudFields') ?? const ['power', 'cadence', 'erg'];
  Future<void> toggleHudField(String f) async {
    final list = [...hudFields];
    list.contains(f) ? list.remove(f) : list.add(f);
    await prefs?.setStringList('hudFields', [for (final c in hudFieldChoices) if (list.contains(c)) c]);
    _hudShown = '';
    _updateHud();
    notifyListeners();
  }

  /// Boutons − et + dans la fenêtre par-dessus l'appli.
  bool get hudButtons => prefs?.getBool('hudButtons') ?? false;
  Future<void> setHudButtons(bool v) async {
    await prefs?.setBool('hudButtons', v);
    _hudShown = '';
    _updateHud();
    notifyListeners();
  }

  (String, String) get hudText {
    if (target.transport == Transport.proxy) {
      final p = proxy;
      final d = p.data.value;
      final g = p.gears;
      final erg = p.mode == TrainerMode.erg ? (p.powerLock.value ?? p.ergTarget) : null;
      final parts = [
        for (final f in hudFields)
          ?switch (f) {
            'power' => tr('{0} W', [d.power ?? '–']),
            'cadence' => tr('{0} tr/min', [d.cadence?.round() ?? '–']),
            'erg' when erg != null => tr('ERG {0} W', [erg]),
            'ratio' => g.label(),
            'speed' when p.rideSpeedKmh != null => '${p.rideSpeedKmh!.toStringAsFixed(1).replaceAll('.', ',')} km/h',
            'hr' when heartRate.bpm.value != null => '${heartRate.bpm.value} bpm',
            _ => null,
          },
      ];
      final title = g.config.infinite ? g.label() : '${p.gear.value}/${g.count}';
      return (title, parts.join(' · '));
    }
    final f = lastFired.value;
    final title = f != null
        ? f.action.label
        : (lastDelta == null ? 'ShiftLink' : (lastDelta! > 0 ? tr('Plus dur') : tr('Plus facile')));
    return (title, tr('{0} changements · {1}', [shifts, appHealth == Health.ok ? tr('connecté') : tr('pas connecté')]));
  }

  void _updateHud() {
    if (demo) return;
    if (!hudEnabled || !taps.enabled.value) {
      if (_hudShown != '') taps.hud(show: false);
      _hudShown = '';
      return;
    }
    final (t, sub) = hudText;
    final key = '$t|$sub';
    if (key == _hudShown) return;
    _hudShown = key;
    taps.hud(show: true, title: t, subtitle: sub, buttons: hudButtons);
  }

  /// Réglages des vitesses virtuelles ShiftLink.
  ShiftingConfig get shifting => ShiftingConfig.decode(prefs?.getString('shifting'));

  Future<void> setShifting(ShiftingConfig c) async {
    await prefs?.setString('shifting', c.encode());
    proxy.configure(c);
    notifyListeners();
  }

  // Cyclistes de la maison.
  List<Rider> get riders => Rider.decodeList(prefs?.getString('riders'));
  Rider? get rider {
    final name = prefs?.getString('activeRider');
    return riders.where((r) => r.name == name).firstOrNull;
  }

  /// Mode enfant du cycliste choisi, appliqué au trainer.
  void _applyKidMode() {
    final r = rider;
    final kid = r != null && r.kid;
    final grade = kid ? r.kidMaxGrade : null;
    final watts = kid ? r.kidMaxWatts : null;
    final factor = kid ? r.kidPowerFactor : 1.0;
    if (proxy.maxGrade == grade && proxy.maxWatts == watts && proxy.appPowerFactor == factor) return;
    proxy
      ..maxGrade = grade
      ..maxWatts = watts
      ..appPowerFactor = factor;
    if (kid) log('Mode enfant : pente ≤ ${grade!.toStringAsFixed(1)} %, ≤ $watts W, watts × $factor pour l’appli');
  }

  /// FTP et cardio max du cycliste choisi (sinon valeurs par défaut).
  int get ftp => rider?.ftp ?? prefs?.getInt('ftp') ?? 200;
  int get hrMax => rider?.hrMax ?? 190;

  /// Zone cardio actuelle, si une ceinture est connectée.
  HrZone? get hrZone {
    final bpm = heartRate.bpm.value;
    return bpm == null || bpm <= 0 ? null : HrZone.of(bpm, hrMax);
  }

  Future<void> saveRider(Rider r, {String? replacing}) async {
    final list = riders.where((x) => x.name != (replacing ?? r.name) && x.name != r.name).toList();
    if (list.length >= Rider.maxRiders) return;
    final old = replacing == null ? -1 : riders.indexWhere((x) => x.name == replacing);
    list.insert(old < 0 ? list.length : old.clamp(0, list.length), r);
    await prefs?.setString('riders', Rider.encodeList(list));
    if (replacing != null && prefs?.getString('activeRider') == replacing || riders.length == 1) {
      await selectRider(r.name);
    }
    notifyListeners();
  }

  Future<void> deleteRider(String name) async {
    await prefs?.setString('riders', Rider.encodeList(riders.where((r) => r.name != name).toList()));
    if (prefs?.getString('activeRider') == name) await prefs?.remove('activeRider');
    notifyListeners();
  }

  /// Choisit qui roule : son profil de vitesses puis son poids.
  Future<void> selectRider(String name) async {
    final r = riders.where((x) => x.name == name).firstOrNull;
    if (r == null) return;
    await prefs?.setString('activeRider', r.name);
    if (r.gearProfile != null && _profiles.containsKey(r.gearProfile)) await loadShiftProfile(r.gearProfile!);
    await setShifting(shifting.copyWith(totalKg: r.totalKg));
    log('Cycliste : ${r.name}');
    notifyListeners();
  }

  // Séances sans appli.
  List<Workout> get importedWorkouts => Workout.decodeList(prefs?.getString('workouts'));
  List<Workout> get workouts => [...builtInWorkouts, ...importedWorkouts];

  /// Ajoute une séance lue dans un fichier. Renvoie false si la liste est pleine.
  Future<bool> addWorkout(Workout w) async {
    final list = importedWorkouts.where((x) => x.name != w.name).toList();
    if (list.length >= Workout.maxImported) return false;
    await prefs?.setString('workouts', Workout.encodeList([...list, w]));
    notifyListeners();
    return true;
  }

  Future<void> deleteWorkout(String name) async {
    await prefs?.setString('workouts', Workout.encodeList(importedWorkouts.where((w) => w.name != name).toList()));
    notifyListeners();
  }

  bool startWorkout(Workout w) => proxy.startWorkout(w, ftp: ftp, hrMax: hrMax);

  // ------- Parcours GPX --------
  // Un fichier par parcours dans le dossier de l'appli (avant la 2.10 : tous dans les
  // préférences, 20 au plus). La liste est gardée en mémoire.
  static const maxRoutes = 200;
  List<GpxRoute> _routes = [];
  List<GpxRoute> get routes => _routes;

  /// Dossier des parcours. Les tests le remplacent.
  @visibleForTesting
  Directory? routesDir;

  Future<Directory?> _routesDirectory() async {
    if (routesDir != null) return routesDir;
    try {
      return routesDir = Directory('${(await getApplicationDocumentsDirectory()).path}/parcours');
    } catch (_) {
      return null;
    }
  }

  /// Nom de fichier stable pour un parcours (son nom peut contenir n'importe quoi).
  static String routeFileName(String name) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(name)) {
      h = ((h ^ b) * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return '${h.toRadixString(16).padLeft(16, '0')}.json';
  }

  static void _sortRoutes(List<GpxRoute> l) => l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Lit les parcours du dossier, après y avoir déplacé ceux des versions précédentes.
  Future<void> loadRoutes() async {
    final byName = <String, GpxRoute>{};
    final dir = await _routesDirectory();
    try {
      if (dir != null && await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is! File || !f.path.endsWith('.json')) continue;
          try {
            final r = GpxRoute.fromJson(jsonDecode(await f.readAsString()));
            if (r != null) byName[r.name] = r;
          } catch (_) {}
        }
      }
    } catch (_) {}
    // Anciens parcours (préférences) : un fichier chacun, puis on vide l'ancienne clé.
    final old = prefs?.getString('routes');
    if (old != null) {
      var moved = true;
      try {
        final list = jsonDecode(old);
        if (list is List) {
          for (final j in list) {
            final r = GpxRoute.fromJson(j);
            if (r == null || byName.containsKey(r.name)) continue;
            byName[r.name] = r;
            if (!await _writeRoute(r)) moved = false;
          }
        }
      } catch (_) {}
      if (moved && dir != null) await prefs?.remove('routes');
    }
    // Un parcours ajouté pendant la lecture reste.
    for (final r in _routes) {
      byName.putIfAbsent(r.name, () => r);
    }
    _routes = byName.values.toList();
    _sortRoutes(_routes);
    notifyListeners();
  }

  Future<bool> _writeRoute(GpxRoute r) async {
    final dir = await _routesDirectory();
    if (dir == null) return false;
    try {
      await dir.create(recursive: true);
      await File('${dir.path}/${routeFileName(r.name)}').writeAsString(jsonEncode(r.toJson()));
      return true;
    } catch (e) {
      log('Parcours « ${r.name} » non enregistré : $e');
      return false;
    }
  }

  Future<bool> addRoute(GpxRoute r) async {
    final list = _routes.where((x) => x.name != r.name).toList();
    if (list.length >= maxRoutes) return false;
    list.add(r);
    _sortRoutes(list);
    _routes = list;
    await _writeRoute(r);
    // Même nom, autre trace : l'ancienne reprise et l'ancien fantôme ne valent plus.
    await prefs?.remove('routePos.${r.name}');
    await prefs?.remove('ghost.${r.name}');
    notifyListeners();
    return true;
  }

  Future<void> deleteRoute(String name) async {
    _routes = _routes.where((r) => r.name != name).toList();
    final dir = await _routesDirectory();
    try {
      if (dir != null) await File('${dir.path}/${routeFileName(name)}').delete();
    } catch (_) {}
    await prefs?.remove('routePos.$name');
    await prefs?.remove('ghost.$name');
    notifyListeners();
  }

  bool startRoute(GpxRoute r, {double fromM = 0}) => proxy.startRoute(r, fromM: fromM);

  /// Distance (m) où on s'est arrêté sur ce parcours la dernière fois, ou null.
  double? routeResumeAt(GpxRoute r) {
    final d = prefs?.getDouble('routePos.${r.name}');
    if (d == null || d < 200 || d > r.length - 200) return null;
    return d;
  }

  void _saveRouteProgress(String name, double? distanceM) {
    if (demo) return;
    if (distanceM == null) {
      unawaited(prefs?.remove('routePos.$name'));
    } else if (distanceM >= 200) {
      unawaited(prefs?.setDouble('routePos.$name', distanceM));
    }
    // Arrêt ou fin : la liste montre « reprendre au km… » tout de suite.
    if (proxy.routeRun.value == null) notifyListeners();
  }

  // ------- Fantômes de parcours --------
  /// Fantôme (sortie précédente) sauvé pour le parcours nommé.
  GhostRun? ghostFor(String routeName) {
    final raw = prefs?.getString('ghost.$routeName');
    if (raw == null) return null;
    try {
      return GhostRun.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Sauve le fantôme s'il bat l'ancien (ou s'il n'y en avait pas).
  Future<void> saveGhost(String routeName, GhostRun run) async {
    final old = ghostFor(routeName);
    if (old != null && old.seconds <= run.seconds) return;
    await prefs?.setString('ghost.$routeName', jsonEncode(run.toJson()));
    log('Fantôme « $routeName » enregistré (${run.seconds} s)');
  }

  // ------- Plans d'entraînement --------
  String get activePlanId => prefs?.getString('activePlanId') ?? '';
  DateTime? get activePlanStart {
    final s = prefs?.getString('activePlanStart');
    return s == null ? null : DateTime.tryParse(s);
  }

  TrainingPlan? get activePlan => builtInPlans.where((p) => p.id == activePlanId).firstOrNull;

  Future<void> startPlan(TrainingPlan p) async {
    await prefs?.setString('activePlanId', p.id);
    await prefs?.setString('activePlanStart', DateTime.now().toIso8601String());
    notifyListeners();
  }

  Future<void> stopPlan() async {
    await prefs?.remove('activePlanId');
    await prefs?.remove('activePlanStart');
    notifyListeners();
  }

  /// Séance prévue aujourd'hui par le plan actif (ou null : pas de plan / jour de repos / plan fini).
  Workout? planWorkoutToday() {
    final p = activePlan;
    final start = activePlanStart;
    if (p == null || start == null) return null;
    final day0 = DateTime(start.year, start.month, start.day);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day).difference(day0).inDays;
    if (day < 0) return null;
    final weekIndex = day ~/ 7;
    final name = p.workoutFor(weekIndex, today.weekday);
    if (name == null) return null;
    return workouts.where((w) => w.name == name).firstOrNull;
  }

  // ------- Intervals.icu --------
  String get intervalsAthleteId => prefs?.getString('intervalsAthleteId') ?? '';
  Future<void> setIntervalsAthleteId(String v) async {
    await prefs?.setString('intervalsAthleteId', v.trim());
    notifyListeners();
  }

  String get intervalsApiKey => prefs?.getString('intervalsApiKey') ?? '';
  Future<void> setIntervalsApiKey(String v) async {
    await prefs?.setString('intervalsApiKey', v.trim());
    notifyListeners();
  }

  bool get intervalsReady => intervalsAthleteId.isNotEmpty && intervalsApiKey.isNotEmpty;

  /// Envoie une sortie enregistrée sur Intervals.icu.
  Future<void> uploadToIntervals(File fit) =>
      IntervalsIcuClient(athleteId: intervalsAthleteId, apiKey: intervalsApiKey, ftp: ftp).uploadActivity(fit);

  /// Récupère les séances prévues sur Intervals.icu et les ajoute à la liste.
  /// Renvoie (nb ajoutées, nb ignorées parce que déjà présentes ou liste pleine).
  Future<(int, int)> importIntervalsIcuWorkouts() async {
    final c = IntervalsIcuClient(athleteId: intervalsAthleteId, apiKey: intervalsApiKey, ftp: ftp);
    final events = await c.listUpcomingWorkouts();
    var added = 0, skipped = 0;
    for (final e in events) {
      try {
        final w = await c.downloadWorkout(e);
        if (w == null || !await addWorkout(w)) {
          skipped++;
          continue;
        }
        added++;
      } catch (_) {
        skipped++;
      }
    }
    return (added, skipped);
  }

  // ------- Garmin Connect --------
  GarminTokens? get _garminTokens => GarminTokens.fromJson(prefs?.getString('garminTokens'));
  bool get garminConnected => _garminTokens != null;

  /// Termine la connexion : échange le ticket rendu par la page de Garmin contre un jeton.
  Future<void> connectGarmin(String ticket, GarminLoginFlow flow) async {
    final t = await GarminConnectClient.exchangeTicket(ticket, flow);
    await prefs?.setString('garminTokens', jsonEncode(t.toJson()));
    log('Garmin Connect : connecté');
    notifyListeners();
  }

  Future<void> disconnectGarmin() async {
    await prefs?.remove('garminTokens');
    log('Garmin Connect : déconnecté');
    notifyListeners();
  }

  Future<GarminTokens> _freshGarminTokens({bool force = false}) async {
    final t = _garminTokens;
    if (t == null) throw const GarminException('Connecte d’abord ton compte Garmin', 401);
    if (!force && !t.expiresSoon) return t;
    try {
      final n = await GarminConnectClient.refresh(t);
      await prefs?.setString('garminTokens', jsonEncode(n.toJson()));
      return n;
    } on GarminException catch (e) {
      if (e.needsLogin) await disconnectGarmin();
      rethrow;
    }
  }

  /// Répare le .fit (moyennes manquantes, température de MyWhoosh) puis l'envoie sur Garmin Connect.
  /// Une copie réparée est gardée dans le dossier « garmin » de l'appli.
  Future<GarminUploadStatus> uploadToGarmin(File fit) async =>
      uploadFitToGarmin(await fit.readAsBytes(), fit.uri.pathSegments.last);

  Future<GarminUploadStatus> uploadFitToGarmin(Uint8List raw, String name) async {
    final fixed = FitFixer.fix(raw);
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/garmin');
      await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      await File('${dir.path}/${name.replaceAll(RegExp(r'\.fit$', caseSensitive: false), '')}_$stamp.fit').writeAsBytes(fixed.bytes);
    } catch (_) {}
    var t = await _freshGarminTokens();
    try {
      return await GarminConnectClient.upload(t, fixed.bytes, name);
    } on GarminException catch (e) {
      if (!e.needsLogin) rethrow;
      // Jeton refusé avant sa date : on le renouvelle une fois.
      t = await _freshGarminTokens(force: true);
      return GarminConnectClient.upload(t, fixed.bytes, name);
    }
  }

  // ------- Applis connectées : Garmin Connect, Intervals.icu --------
  bool targetConnected(SendTarget t) => switch (t) {
    SendTarget.garmin => garminConnected,
    SendTarget.intervals => intervalsReady,
  };

  String _autoKey(SendTarget t) => t == SendTarget.garmin ? 'garminAuto' : 'autoSend.${t.name}';

  /// Chaque sortie enregistrée (et chaque nouvelle sortie MyWhoosh) part toute seule vers cette appli.
  /// Garmin : oui par défaut. Intervals.icu : non, car MyWhoosh peut déjà y envoyer.
  bool targetAuto(SendTarget t) => targetConnected(t) && (prefs?.getBool(_autoKey(t)) ?? t == SendTarget.garmin);
  Future<void> setTargetAuto(SendTarget t, bool v) async {
    await prefs?.setBool(_autoKey(t), v);
    notifyListeners();
    if (v) unawaited(syncMyWhoosh());
  }

  List<SendTarget> get connectedTargets => [for (final t in SendTarget.values) if (targetConnected(t)) t];

  /// Répare le .fit (moyennes, température) puis l'envoie vers [t].
  Future<SendStatus> sendFitTo(SendTarget t, Uint8List raw, String name) async {
    switch (t) {
      case SendTarget.garmin:
        final s = await uploadFitToGarmin(raw, name);
        return s == GarminUploadStatus.duplicate ? SendStatus.duplicate : SendStatus.sent;
      case SendTarget.intervals:
        await IntervalsIcuClient(
          athleteId: intervalsAthleteId,
          apiKey: intervalsApiKey,
          ftp: ftp,
        ).uploadBytes(FitFixer.fix(raw).bytes, name);
        return SendStatus.sent;
    }
  }

  Future<SendStatus> sendRideTo(SendTarget t, File fit) async =>
      sendFitTo(t, await fit.readAsBytes(), fit.uri.pathSegments.last);

  static String sendStatusText(SendTarget t, SendStatus s) =>
      s == SendStatus.duplicate ? tr('Sortie déjà sur {0}.', [t.label]) : tr('Sortie envoyée sur {0}.', [t.label]);

  /// Dernier envoi automatique (pour l'afficher sur l'écran Rouler).
  final ValueNotifier<String?> lastAutoSend = ValueNotifier(null);

  Future<void> _autoSend(File file, List<SendTarget> targets) async {
    final lines = <String>[];
    for (final t in targets) {
      try {
        final s = await sendRideTo(t, file);
        log('${t.label} : ${s == SendStatus.duplicate ? 'sortie déjà présente' : 'sortie envoyée'}');
        lines.add(sendStatusText(t, s));
      } catch (e) {
        log('${t.label} : envoi impossible ($e)');
        lines.add('${t.label} : $e');
      }
    }
    lastAutoSend.value = lines.join('\n');
  }

  // ------- Compte MyWhoosh : ses sorties partent sur Garmin Connect --------
  MyWhooshSession? get _myWhoosh => MyWhooshSession.fromJson(prefs?.getString('mywhooshSession'));
  bool get myWhooshConnected => _myWhoosh != null;

  /// Les nouvelles sorties MyWhoosh partent toutes seules vers les applis connectées (à l'ouverture de ShiftLink).
  bool get myWhooshAuto => prefs?.getBool('mywhooshAuto') ?? true;
  Future<void> setMyWhooshAuto(bool v) async {
    await prefs?.setBool('mywhooshAuto', v);
    notifyListeners();
    if (v) unawaited(syncMyWhoosh());
  }

  String _sentKey(SendTarget t) => t == SendTarget.garmin ? 'mywhooshSent' : 'mywhooshSent.${t.name}';
  Set<String> _myWhooshSentTo(SendTarget t) => (prefs?.getStringList(_sentKey(t)) ?? const []).toSet();

  /// Les applis où cette sortie MyWhoosh est déjà partie.
  List<SendTarget> myWhooshSentTo(MyWhooshActivity a) =>
      [for (final t in SendTarget.values) if (_myWhooshSentTo(t).contains(a.id)) t];

  Future<void> connectMyWhoosh(String email, String password) async {
    var device = prefs?.getString('mywhooshDevice');
    if (device == null || device.isEmpty) {
      device = MyWhooshAccount.newDeviceId();
      await prefs?.setString('mywhooshDevice', device);
    }
    final s = await MyWhooshAccount.login(email, password, device);
    await prefs?.setString('mywhooshSession', s.toJson());
    // Les sorties des 3 derniers jours partent aussi ; les plus anciennes, à la main.
    if (prefs?.getString('mywhooshSince') == null) {
      await prefs?.setString('mywhooshSince', DateTime.now().subtract(const Duration(days: 3)).toIso8601String());
    }
    log('MyWhoosh : compte connecté');
    notifyListeners();
    unawaited(syncMyWhoosh(force: true));
  }

  Future<void> disconnectMyWhoosh() async {
    await prefs?.remove('mywhooshSession');
    log('MyWhoosh : compte déconnecté');
    notifyListeners();
  }

  Future<T> _withMyWhoosh<T>(Future<T> Function(MyWhooshSession s) run) async {
    final s = _myWhoosh;
    if (s == null) throw const MyWhooshException('Connecte d’abord ton compte MyWhoosh', 401);
    try {
      return await run(s);
    } on MyWhooshException catch (e) {
      if (e.needsLogin) await disconnectMyWhoosh();
      rethrow;
    }
  }

  /// Tes dernières sorties MyWhoosh.
  Future<List<MyWhooshActivity>> myWhooshActivities({int page = 1}) =>
      _withMyWhoosh((s) => MyWhooshAccount.activities(s, page: page));

  /// Télécharge la sortie chez MyWhoosh une fois, la répare et l'envoie vers chaque appli de [targets].
  Future<Map<SendTarget, Object>> sendMyWhooshTo(MyWhooshActivity a, List<SendTarget> targets) async {
    final fit = await _withMyWhoosh((s) => MyWhooshAccount.downloadFit(s, a));
    final t = a.start ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'MyWhoosh-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}h${two(t.minute)}.fit';
    final out = <SendTarget, Object>{};
    for (final target in targets) {
      try {
        out[target] = await sendFitTo(target, fit, name);
        final sent = _myWhooshSentTo(target)..add(a.id);
        // Les 200 dernières suffisent : la liste de MyWhoosh est triée par date.
        final keep = sent.toList();
        await prefs?.setStringList(_sentKey(target), keep.sublist(keep.length > 200 ? keep.length - 200 : 0));
      } catch (e) {
        out[target] = e;
      }
    }
    notifyListeners();
    return out;
  }

  DateTime? _lastMyWhooshSync;
  bool _myWhooshSyncing = false;

  /// Résultat du dernier envoi automatique des sorties MyWhoosh (pour la page Applis connectées).
  final ValueNotifier<String?> lastMyWhooshSync = ValueNotifier(null);

  /// Envoie les nouvelles sorties MyWhoosh vers les applis en envoi automatique.
  /// Renvoie le nombre de sorties envoyées.
  Future<int> syncMyWhoosh({bool force = false}) async {
    if (demo || !myWhooshConnected || _myWhooshSyncing) return 0;
    if (!force && !myWhooshAuto) return 0;
    final targets = [for (final t in SendTarget.values) if (targetAuto(t)) t];
    if (targets.isEmpty) return 0;
    final last = _lastMyWhooshSync;
    if (!force && last != null && DateTime.now().difference(last).inMinutes < 10) return 0;
    _myWhooshSyncing = true;
    _lastMyWhooshSync = DateTime.now();
    var sent = 0;
    final errors = <String>[];
    try {
      final since = DateTime.tryParse(prefs?.getString('mywhooshSince') ?? '');
      final list = await myWhooshActivities();
      // Les plus anciennes d'abord, pour garder l'ordre dans les applis.
      for (final a in list.reversed) {
        if (!a.downloadable) continue;
        if (since != null && a.start != null && a.start!.isBefore(since)) continue;
        final done = myWhooshSentTo(a);
        final missing = targets.where((t) => !done.contains(t)).toList();
        if (missing.isEmpty) continue;
        final res = await sendMyWhooshTo(a, missing);
        if (res.values.any((v) => v is SendStatus)) sent++;
        for (final MapEntry(:key, :value) in res.entries) {
          if (value is! SendStatus) errors.add('${key.label} : $value');
        }
      }
      if (sent > 0) log('Sorties MyWhoosh envoyées : $sent');
      lastMyWhooshSync.value = [
        if (sent > 0) tr('{0} sortie(s) MyWhoosh envoyée(s) vers {1}.', [sent, targets.map((t) => t.label).join(', ')]),
        ...errors.toSet(),
      ].join('\n');
      if (lastMyWhooshSync.value!.isEmpty) lastMyWhooshSync.value = null;
    } catch (e) {
      log('Sorties MyWhoosh : $e');
      lastMyWhooshSync.value = tr('MyWhoosh : {0}', ['$e']);
    } finally {
      _myWhooshSyncing = false;
    }
    return sent;
  }

  /// Watts ajoutés ou enlevés par + et − quand ShiftLink impose les watts :
  /// au moins 5 % de la FTP pendant une séance, pour que ça se sente.
  int get ergButtonStep {
    final step = shifting.ergStep;
    if (proxy.workout.value == null) return shifting.infinite ? 5 : step;
    final pct = ((ftp * 0.05) / 5).round() * 5;
    return pct > step ? pct : step;
  }

  /// Home trainer déjà choisi une fois (reconnecté d'un appui).
  String? get savedTrainerName => prefs?.getString('trainerId') == null ? null : prefs?.getString('trainerName');

  /// Connecte le home trainer pour une séance, même si l'appli choisie gère ses propres vitesses.
  Future<void> connectTrainerForWorkout() async {
    final id = prefs?.getString('trainerId');
    if (id == null || proxy.trainer.isConnected) return;
    await proxy.trainer.connectById(id, prefs?.getString('trainerName') ?? 'Home trainer');
  }

  /// Choisit un home trainer trouvé par la recherche et s'y connecte.
  Future<void> useTrainer(TrainerCandidate c) async {
    await prefs?.setString('trainerId', c.id);
    await prefs?.setString('trainerName', c.name);
    proxy.trainer.candidates.value = const [];
    await proxy.trainer.disconnect();
    unawaited(proxy.trainer.connectCandidate(c));
  }

  // Chiffres affichés pendant la sortie (4 au plus).
  static const rideMetricChoices = ['power', 'cadence', 'grade', 'hr', 'speed'];
  static const maxRideMetrics = 4;
  List<String> get rideMetrics {
    final saved = prefs?.getStringList('rideMetrics');
    final list = (saved ?? const ['power', 'cadence', 'grade', 'hr']).where(rideMetricChoices.contains).toList();
    return list.isEmpty ? const ['power'] : list.take(maxRideMetrics).toList();
  }

  Future<void> toggleRideMetric(String m) async {
    final list = rideMetrics.toList();
    if (list.contains(m)) {
      if (list.length == 1) return;
      list.remove(m);
    } else {
      if (list.length >= maxRideMetrics) return;
      list.add(m);
    }
    list.sort((a, b) => rideMetricChoices.indexOf(a).compareTo(rideMetricChoices.indexOf(b)));
    await prefs?.setStringList('rideMetrics', list);
    notifyListeners();
  }

  // Profils de vitesses nommés.
  Map<String, String> get _profiles {
    try {
      return (jsonDecode(prefs?.getString('shiftProfiles') ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  List<String> get shiftProfileNames => _profiles.keys.toList()..sort();
  String? get activeShiftProfile => prefs?.getString('activeShiftProfile');

  Future<void> saveShiftProfile(String name) async {
    final m = _profiles..[name] = shifting.encode();
    await prefs?.setString('shiftProfiles', jsonEncode(m));
    await _rememberProfile(name);
    notifyListeners();
  }

  Future<void> loadShiftProfile(String name) async {
    final raw = _profiles[name];
    if (raw == null) return;
    await setShifting(ShiftingConfig.decode(raw));
    await _rememberProfile(name);
    log('Profil de vitesses « $name »');
    notifyListeners();
  }

  Future<void> deleteShiftProfile(String name) async {
    final m = _profiles..remove(name);
    await prefs?.setString('shiftProfiles', jsonEncode(m));
    if (activeShiftProfile == name) await prefs?.remove('activeShiftProfile');
    notifyListeners();
  }

  Future<void> _rememberProfile(String name) async {
    await prefs?.setString('activeShiftProfile', name);
    final trainer = proxy.trainer.name.value;
    if (trainer != null) await prefs?.setString('shiftProfile.$trainer', name);
  }

  /// À la connexion d'un trainer : reprend le profil utilisé avec lui.
  void _onTrainerState() {
    final t = proxy.trainer;
    if (!t.isConnected || t.name.value == null) return;
    final name = prefs?.getString('shiftProfile.${t.name.value}');
    if (name != null && name != activeShiftProfile) loadShiftProfile(name);
  }

  TargetApp get target =>
      TargetApp.values.where((t) => t.name == prefs?.getString('target')).firstOrNull ?? TargetApp.mywhoosh;

  Future<void> setTarget(TargetApp t) async {
    await prefs?.setString('target', t.name);
    if (t.keyPreset != null) await prefs?.setString('kbPreset', t.keyPreset!);
    await prefs?.setBool('proxyEnabled', t.transport == Transport.proxy);
    displayCog = (appGearCount + 1) ~/ 2;
    await _startTransport();
    // La notification « ShiftLink est actif » garde sinon le nom de la première appli choisie.
    if (!demo && Platform.isAndroid) {
      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.updateService(
            notificationTitle: tr('ShiftLink est actif'),
            notificationText: tr('Tes vitesses sont transmises à {0}', [t.label]),
            notificationButtons: _notificationButtons,
          );
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Étape de l'installation où l'on s'était arrêté (pour reprendre au bon endroit).
  int get onboardingStep => prefs?.getInt('onboardingStep') ?? 0;
  set onboardingStep(int v) => prefs?.setInt('onboardingStep', v);

  /// Autorisations Bluetooth déjà accordées ? (sans rien demander)
  Future<bool> permissionsGranted() async {
    if (demo || !Platform.isAndroid) return true;
    return await Permission.bluetoothScan.isGranted && await Permission.bluetoothConnect.isGranted;
  }

  /// Bluetooth allumé ?
  bool get bluetoothOn => demo || !Platform.isAndroid || FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

  /// Demande à Android d'allumer le Bluetooth (fenêtre système).
  Future<void> turnOnBluetooth() async {
    if (demo || !Platform.isAndroid) return;
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}
  }

  Future<void> finishOnboarding() async {
    await prefs?.remove('onboardingStep');
    await prefs?.remove('onboardingReplay');
    await prefs?.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> restartOnboarding() async {
    await prefs?.remove('onboardingStep');
    await prefs?.setBool('onboardingReplay', true);
    await prefs?.setBool('onboarded', false);
    notifyListeners();
  }

  /// L'assistant est relancé depuis les réglages : on peut le quitter à tout moment.
  bool get onboardingReplay => prefs?.getBool('onboardingReplay') ?? false;

  /// Quitte l'assistant sans rien changer de plus.
  Future<void> quitOnboarding() async {
    await prefs?.remove('onboardingReplay');
    await finishOnboarding();
  }

  void log(String msg) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    logs.insert(0, '${two(now.hour)}:${two(now.minute)}:${two(now.second)}  $msg');
    if (logs.length > 200) logs.removeLast();
    notifyListeners();
  }

  /// Après un import : relit tous les réglages et relance la connexion à l'appli.
  Future<void> reloadSettings() async {
    _applyLanguage();
    _keymap = null;
    _resetEngines();
    taps.load(prefs!);
    proxy.configure(shifting);
    _applyPhoneSteering();
    if (onboarded && !demo) await _startTransport();
    notifyListeners();
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    displayCog = (appGearCount + 1) ~/ 2;
    registry.clickV2RightOnly = clickV2RightOnly;
    _applyLanguage();
    taps.load(prefs!);
    taps.onKey = _onKey;
    taps.onHudShift = (delta) {
      if (delta != 0) shift(delta);
    };
    // L'appli demande une vibration (souvent en butée) : on la relaie.
    obc.onHaptic = (pattern) {
      if (pattern == 0) return;
      relayHaptic(strong: pattern >= 6);
    };
    proxy.configure(shifting);
    proxy.heartRate = () => heartRate.bpm.value;
    proxy.externalCadence = _externalCadence;
    proxy.externalPower = _externalPower;
    proxy.ghostLookup = ghostFor;
    proxy.onRouteFinished = (name, run) => unawaited(saveGhost(name, run));
    proxy.onPowerLockAutoRelease = () {
      log('Power Lock relâché : tu as arrêté de pédaler');
      onNotice?.call(tr('Power Lock relâché : tu as arrêté de pédaler.'));
      if (voice && !demo) _say(tr('Power Lock relâché'));
      notifyListeners();
    };
    proxy.onRouteProgress = _saveRouteProgress;
    proxy.workout.addListener(_lapOnWorkoutStep);
    unawaited(loadRoutes());
    proxy.workout.addListener(_announceWorkoutStep);
    proxy.finishedWorkout.addListener(_onFinishedWorkout);
    proxy.data.addListener(_autoRide);
    _loadIgnored();
    _loadLearned();
    proxy.data.addListener(_driveFan);
    heartRate.bpm.addListener(_driveFan);
    controllers.controllers.addListener(() {
      if (controllers.controllers.value.any((c) => c.driver is EliteRizerDriver)) _ensureInclineTimer();
    });
    proxy.trainer.state.addListener(_onTrainerState);
    controllers.controllers.addListener(_watchControllers);
    addListener(_applyKidMode);
    _applyKidMode();
    notifyListeners();
    if (demo) {
      _loadDemo();
      _applyPhoneSteering();
      return;
    }
    unawaited(refreshWeeklyWidget());
    ips = await WhooshLinkServer.localAddresses();
    proxy.trainer.ownAddresses = ips.toSet();
    await taps.refresh();
    unawaited(refreshHealthConnect());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        taps.refresh();
        // Health Connect a pu être installée entre-temps.
        unawaited(refreshHealthConnect());
        // Manettes mises en veille faute d'appui : ShiftLink rouvert, on les réveille.
        if (controllers.asleep.value && !_appWasOk) {
          _lastPressAt = DateTime.now();
          unawaited(controllers.wake());
        }
        unawaited(refreshKeepsRunning());
        // Nouvelles sorties MyWhoosh : elles partent sur Garmin.
        unawaited(syncMyWhoosh());
      },
    );
    unawaited(syncMyWhoosh());
    unawaited(refreshKeepsRunning());
    await _pushCaptureKeys(force: true);
    addListener(_pushCaptureKeys);
    _applyPhoneSteering();
    _watchdog = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkSleep();
      _autoRide();
    });
    proxy.data.addListener(_autoShiftTick);
    _hudListener = Listenable.merge([healthListenable, lastFired]);
    _hudListener!.addListener(_updateHud);
    taps.enabled.addListener(() {
      if (taps.enabled.value) _pushCaptureKeys(force: true);
      _updateHud();
    });
    _updateHud();
    if (onboarded && await askPermissions()) {
      await startKeepAlive();
      await _startTransport();
      final hrId = prefs?.getString('hrId');
      if (hrId != null) unawaited(heartRate.connectById(hrId, prefs?.getString('hrName') ?? 'Ceinture cardio'));
      for (final s in [cadenceSensor, powerSensor]) {
        final id = prefs?.getString('${s.kind.name}.id');
        if (id != null) unawaited(s.connectById(id, prefs?.getString('${s.kind.name}.name') ?? ''));
      }
      final fanId = prefs?.getString('fanId');
      if (fanId != null) unawaited(fan.connectById(fanId, prefs?.getString('fanName') ?? 'KICKR Headwind'));
      final climbId = prefs?.getString('climbId');
      if (climbId != null) _ensureInclineTimer();
      if (climbId != null) unawaited(climb.connectById(climbId, prefs?.getString('climbName') ?? 'KICKR Climb'));
      await controllers.scan();
    }
    notifyListeners();
  }

  /// Données fictives pour les captures d'écran.
  void _loadDemo() {
    final c = ConnectedController(BluetoothDevice.fromId('AA:BB:CC:DD:EE:01'), ThinkRiderVs200Driver(), 'THINK VS200');
    c.state.value = LinkState.connected;
    c.battery.value = 27;
    c.firmware = 'V1.0.8';
    c.rssi = -60;
    controllers.controllers.value = [c];
    link.isStarted.value = true;
    link.isConnected.value = true;
    obc.isStarted.value = true;
    obc.connectedApp.value = 'Demo';
    keyboard.connectedHost.value = 'PC';
    taps.enabled.value = true;
    proxy.trainer.state.value = LinkState.connected;
    proxy.trainer.name.value = 'CYCPLUS R200';
    proxy.gears.gear = (proxy.gears.neutralGear + 2).clamp(1, proxy.gears.count);
    proxy.gear.value = proxy.gears.gear;
    proxy.mode = TrainerMode.simulation;
    proxy.appGrade.value = 4.5;
    proxy.data.value = const BikeData(speedKmh: 31.4, cadence: 88, power: 236);
    heartRate.name.value = 'HRM-Pro';
    heartRate.state.value = LinkState.connected;
    heartRate.bpm.value = 142;
    fan.name.value = 'HEADWIND 1A2B';
    fan.state.value = LinkState.connected;
    fan.level.value = 75;
    shifts = 37;
    lastDelta = 1;
    ips = ['192.168.1.42'];
    log('THINK VS200 connectée (ThinkRider VS200)');
    log('MyWhoosh connecté (192.168.1.20)');
    notifyListeners();
  }

  /// Démarre ce qu'il faut pour l'appli choisie, et arrête le reste.
  Future<void> _startTransport() async {
    if (demo) return;
    final transport = target.transport;
    if (transport == Transport.link) {
      try {
        await link.start();
      } catch (_) {}
    } else {
      await link.stop();
    }
    if (transport == Transport.obc || target == TargetApp.mywhoosh) {
      await obc.start();
    } else {
      await obc.stop();
    }
    // Applis OpenBikeControl en Bluetooth (Grimpa, applis web…) : ShiftLink se montre
    // aussi comme manette Bluetooth. Pas en mode trainer : un seul serveur à la fois.
    if (transport == Transport.obc) {
      await obc.startBluetooth();
    } else {
      await obc.stopBluetooth();
    }
    if (transport == Transport.zwiftRide) {
      await zwiftRide.start();
    } else {
      await zwiftRide.stop();
    }
    if (transport == Transport.keyboard && sameDevice) {
      await taps.refresh();
      try {
        await keyboard.stop();
      } catch (_) {}
    } else if (transport == Transport.keyboard) {
      final host = prefs?.getString('kbHost');
      if (await keyboard.isSupported()) {
        try {
          await keyboard.start(address: host);
        } catch (_) {}
      }
    }
    if (transport == Transport.proxy) {
      await proxy.server.start();
      await proxy.ble.start();
      final id = prefs?.getString('trainerId');
      if (id != null && !proxy.trainer.isConnected) {
        unawaited(proxy.trainer.connectById(id, prefs?.getString('trainerName') ?? 'Home trainer'));
      }
    } else {
      await proxy.dispose();
    }
  }

  Future<bool> askPermissions() async {
    if (demo || !Platform.isAndroid) return true;
    final res = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
    final ok = res[Permission.bluetoothScan]?.isGranted == true && res[Permission.bluetoothConnect]?.isGranted == true;
    if (!ok) log('Autorise « Appareils à proximité » dans les réglages de l’app pour trouver les manettes.');
    return ok;
  }

  Future<void> startKeepAlive() async {
    if (demo || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'shiftlink',
        channelName: tr('ShiftLink actif'),
        channelDescription: tr('Garde ShiftLink actif pendant que tu roules.'),
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    if (await FlutterForegroundTask.isRunningService) return;
    final r = await FlutterForegroundTask.startService(
      serviceId: 421,
      serviceTypes: [ForegroundServiceTypes.connectedDevice],
      notificationTitle: tr('ShiftLink est actif'),
      notificationText: tr('Tes vitesses sont transmises à {0}', [target.label]),
      notificationButtons: _notificationButtons,
      callback: startCallback,
    );
    if (r is ServiceRequestFailure) log('Mode arrière-plan indisponible : ${r.error}');
  }

  void _onTaskData(Object data) {
    if (data == 'stop') unawaited(stopEverything());
  }

  /// « Arrêter » dans la notification : manettes en veille (leurs piles sont
  /// épargnées), service arrêté, appli fermée.
  Future<void> stopEverything() async {
    log('Arrêt demandé depuis la notification');
    _resetEngines();
    try {
      await controllers.sleep();
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  void _onButton(ConnectedController c, ButtonEvent e) {
    if (e.down) {
      controllerPresses.value++;
      _lastPressAt = DateTime.now();
      _lastPressed = c;
    }
    buttonActivity.value = ButtonActivity(c.driver, e.id, e.down);
    final engine = _engines[c.device.remoteId.str] ??= GestureEngine(
      reportsRelease: c.driver.reportsRelease,
      resolve: (id, g) => prefs == null ? null : keymap.actionFor(c.driver, id, g),
      resolveCombo: (a, b) => prefs == null ? null : keymap.comboFor(c.driver, a, b),
      inCombo: (id) => prefs != null && keymap.inCombo(c.driver, id),
      doubleWindow: Duration(milliseconds: doubleClickMs),
      longDelay: Duration(milliseconds: longPressMs),
      fire: (id, g, a, phase) {
        if (phase != Phase.end) {
          lastFired.value = FiredAction(c.driver, id, g, a);
        }
        perform(a, phase);
      },
    );
    engine.onEvent(e);
  }

  /// Simule un bouton de manette (écran des boutons, tests).
  void simulateButton(ConnectedController c, ButtonEvent e) => _onButton(c, e);

  /// Actions qu'on peut choisir pour l'appli et le mode actuels.
  Set<ShiftAction> get supportedActions {
    final out = <ShiftAction>{
      ShiftAction.shiftUp,
      ShiftAction.shiftDown,
      for (final a in ShiftAction.values)
        if (a.isMedia || a.isPhone) a,
      if (fan.name.value != null) ...[ShiftAction.fanUp, ShiftAction.fanDown],
    };
    switch (target.transport) {
      case Transport.link:
        out.addAll(WhooshLinkServer.controls.map(ShiftAction.byName).nonNulls);
      case Transport.obc:
        out.addAll(ObcServer.buttons.keys.map(ShiftAction.byName).nonNulls);
      case Transport.zwiftRide:
        out.addAll(ZwiftRideEmulator.actions.keys.map(ShiftAction.byName).nonNulls);
      case Transport.keyboard:
        if (sameDevice) {
          out.addAll(keyboardActions);
        } else {
          out.addAll(_keyPreset.keys.keys);
        }
      case Transport.proxy:
        out.addAll([
          ShiftAction.ergUp,
          ShiftAction.ergDown,
          ShiftAction.powerLock,
          if (shifting.doubleRing) ShiftAction.frontShift,
        ]);
    }
    return out;
  }

  /// Départ d'un ERG manuel : dernière cible ou puissance actuelle.
  int get ergStartWatts {
    if (shifting.ergStart == 'current') return proxy.recentPower ?? 100;
    return proxy.lastErgTarget ?? prefs?.getInt('lastErg') ?? 150;
  }

  KeyPreset get _keyPreset => keyPresetFor(prefs?.getString('kbPreset') ?? 'rouvy', prefs);

  /// Exécute une action. Renvoie false si elle n'a pas pu partir.
  bool perform(ShiftAction a, [Phase phase = Phase.once]) {
    final end = phase == Phase.end;
    if (a == ShiftAction.fanUp || a == ShiftAction.fanDown) {
      if (end) return true;
      if (!fan.isConnected) {
        log('Ventilateur : pas connecté');
        return false;
      }
      if (fanMode != FanMode.manual) unawaited(setFanMode(FanMode.manual));
      unawaited(fan.step(a == ShiftAction.fanUp ? 1 : -1));
      return true;
    }
    if (a == ShiftAction.shiftUp || a == ShiftAction.shiftDown) {
      if (!end) shift(a == ShiftAction.shiftUp ? 1 : -1);
      return true;
    }
    if (a == ShiftAction.powerLock) {
      if (end) return true;
      return togglePowerLock();
    }
    if ((a == ShiftAction.ergUp || a == ShiftAction.ergDown) && proxy.powerLock.value != null) {
      if (end) return true;
      final ok = proxy.adjustPowerLock(shifting.ergStep * (a == ShiftAction.ergUp ? 1 : -1));
      _feedback(ok);
      notifyListeners();
      return ok;
    }
    if (target.transport == Transport.proxy) {
      if (end) return true;
      switch (a) {
        case ShiftAction.frontShift:
          final ok = proxy.frontShift();
          _feedback(ok);
          notifyListeners();
          return ok;
        case ShiftAction.ergUp || ShiftAction.ergDown:
          final step = shifting.ergStep * (a == ShiftAction.ergUp ? 1 : -1);
          final ok = proxy.ergAdjust(step, startWatts: ergStartWatts);
          if (ok) unawaited(prefs?.setInt('lastErg', proxy.ergTarget ?? 0));
          if (!ok) log('Intensité : seulement en mode ERG');
          _feedback(ok);
          return ok;
        default:
      }
    }
    if (a.isMedia) {
      if (end) return true;
      switch (a) {
        case ShiftAction.mediaPlayPause:
          taps.media('playPause');
        case ShiftAction.mediaNext:
          taps.media('next');
        case ShiftAction.mediaPrevious:
          taps.media('previous');
        case ShiftAction.volumeUp:
          taps.volume(true);
        case ShiftAction.volumeDown:
          taps.volume(false);
        default:
      }
      return true;
    }
    if (a.isPhone) {
      if (end) return true;
      if (!taps.enabled.value) {
        log('« ${a.label} » : active ShiftLink dans les réglages d’accessibilité');
        return false;
      }
      taps.global(switch (a) {
        ShiftAction.phoneBack => 'back',
        ShiftAction.phoneHome => 'home',
        ShiftAction.phoneRecents => 'recents',
        _ => 'screenshot',
      });
      return true;
    }
    final sent = switch (target.transport) {
      Transport.link when obc.isConnected => obc.button(a.name, pressed: phase == Phase.once ? null : !end),
      Transport.link => (end && !a.hold) || link.control(a.name, down: !end),
      Transport.obc => obc.button(a.name, pressed: phase == Phase.once ? null : !end),
      Transport.zwiftRide => zwiftRide.button(a.name, pressed: phase == Phase.once ? null : !end),
      Transport.keyboard => sameDevice ? _tapAction(a, phase) : _keyAction(a, phase),
      Transport.proxy => false,
    };
    if (!sent && !end) log('« ${a.label} » non envoyé à ${target.label}');
    return sent;
  }

  bool _tapAction(ShiftAction a, Phase phase) {
    if (phase == Phase.end) return true;
    if (!taps.enabled.value || !taps.positionsFor(target.name).containsKey(a)) return false;
    taps.tap(target.name, a);
    return true;
  }

  bool _keyAction(ShiftAction a, Phase phase) {
    final key = _keyPreset.keys[a];
    if (key == null || keyboard.connectedHost.value == null) return false;
    switch (phase) {
      case Phase.once:
        keyboard.press(key);
      case Phase.start:
        keyboard.keyDown(key);
      case Phase.end:
        keyboard.keyUp();
    }
    return true;
  }

  /// Change de vitesse (+1 / −1) vers l'appli choisie.
  /// Pause manuelle de la séance ou du parcours.
  void togglePause() {
    proxy.togglePause();
    if (voice && !demo) _say(proxy.manualPause.value ? tr('Pause') : tr('Reprise'));
    notifyListeners();
  }

  /// Power Lock : garde les watts du moment, ou relâche. Renvoie false si impossible.
  bool togglePowerLock() {
    final wasLocked = proxy.powerLock.value != null;
    final ok = proxy.togglePowerLock();
    _feedback(ok);
    if (!ok) {
      log(proxy.active ? 'Power Lock : pédale d’abord, ou l’appli impose déjà des watts' : 'Power Lock : trainer non connecté');
      // Avant, le refus ne se voyait que dans le journal : le bouton semblait ne pas marcher.
      onNotice?.call(_powerLockRefusal());
    } else if (voice && !demo) {
      _say(wasLocked ? tr('Power Lock relâché') : tr('Power Lock, {0} watts', [proxy.powerLock.value]));
    }
    notifyListeners();
    return ok;
  }

  /// Interrupteur SIM / ERG de l'écran Rouler. Sans appli : ERG fixe à la puissance
  /// de départ choisie. Avec une appli en SIM : Power Lock. Renvoie false si impossible.
  bool toggleErg() {
    if (proxy.powerLock.value != null) return togglePowerLock();
    if (proxy.fixedErg.value != null) {
      proxy.stopFixedErg();
      _feedback(true);
      notifyListeners();
      return true;
    }
    if (proxy.canRunAlone) {
      final ok = proxy.startFixedErg(ergStartWatts);
      _feedback(ok);
      notifyListeners();
      return ok;
    }
    if (proxy.mode == TrainerMode.erg) {
      log('ERG : c’est l’appli qui impose les watts');
      _feedback(false);
      onNotice?.call(_powerLockRefusal());
      return false;
    }
    return togglePowerLock();
  }

  /// Message à l'écran quand l'appli ne peut pas répondre à un appui (Power Lock, ERG…).
  void Function(String message)? onNotice;

  /// Pourquoi Power Lock (ou le bouton ERG) ne peut pas s'activer.
  String _powerLockRefusal() {
    if (!proxy.active) return tr('Connecte d’abord ton home trainer à ShiftLink (onglet Appareils).');
    if (proxy.mode == TrainerMode.erg && proxy.powerLock.value == null) {
      return tr('{0} impose déjà les watts (séance ERG) : Power Lock n’est pas possible.', [target.label]);
    }
    return tr('Pédale d’abord : Power Lock garde les watts que tu pousses (30 W minimum).');
  }

  /// Curseur de l'ERG fixe (écran Rouler).
  void setFixedErgWatts(int watts) {
    proxy.setFixedErg(watts);
    notifyListeners();
  }

  /// Watts ERG ± (boutons de l'écran Rouler).
  bool nudgeErg(int sign) {
    final step = shifting.ergStep * sign;
    if (proxy.powerLock.value != null) {
      final ok = proxy.adjustPowerLock(step);
      _feedback(ok);
      notifyListeners();
      return ok;
    }
    if (proxy.fixedErg.value != null) {
      proxy.setFixedErg((proxy.fixedErg.value ?? 0) + step);
      _feedback(true);
      notifyListeners();
      return true;
    }
    final ok = proxy.ergAdjust(step);
    _feedback(ok);
    notifyListeners();
    return ok;
  }

  /// Décale toutes les vitesses (bouton de l'écran Rouler).
  void shiftAll(int delta) {
    final ok = proxy.shiftAll(delta);
    _feedback(ok);
    notifyListeners();
  }

  void shift(int delta, {bool fromAuto = false}) {
    if (invert) delta = -delta;
    if (!fromAuto && autoShift) _autoPauseUntil = DateTime.now().add(const Duration(seconds: 10));
    // Séance ou ERG sans appli : le trainer impose des watts, les vitesses n'y changeraient rien.
    // + et − font donc monter ou descendre les watts.
    // Power Lock : + et − changent les watts tenus.
    if (proxy.powerLock.value != null) {
      final ok = proxy.adjustPowerLock(delta * ergButtonStep);
      _feedback(ok);
      shifts++;
      lastDelta = delta;
      lastShiftAt = DateTime.now();
      if (voice && ok && !demo) _say(tr('{0} watts', [proxy.powerLock.value]));
      notifyListeners();
      return;
    }
    if (proxy.ergAlone) {
      final ok = proxy.ergAdjust(delta * ergButtonStep);
      _feedback(ok);
      shifts++;
      lastDelta = delta;
      lastShiftAt = DateTime.now();
      if (voice && ok && !demo) _say(tr('{0} watts', [proxy.ergTarget]));
      notifyListeners();
      return;
    }
    var atLimit = false;
    // Parcours ShiftLink : c'est ShiftLink qui pilote le trainer, donc ses vitesses,
    // même si l'appli choisie (MyWhoosh, Rouvy…) a d'habitude les siennes.
    final alone = proxy.routeRun.value != null;
    final sent = switch (target.transport) {
      _ when alone => () {
        atLimit = !proxy.shift(delta);
        return proxy.active;
      }(),
      Transport.link when obc.isConnected => obc.shift(delta),
      Transport.link => link.shift(delta),
      Transport.obc => obc.shift(delta),
      Transport.zwiftRide => zwiftRide.shift(delta),
      Transport.proxy => () {
        atLimit = !proxy.shift(delta);
        return proxy.active;
      }(),
      Transport.keyboard => sameDevice ? _tapShift(delta) : _keyboardShift(delta),
    };
    final g = proxy.gears;
    final isProxy = alone || target.transport == Transport.proxy;
    _feedback(!atLimit, lastGear: isProxy && !atLimit && (g.gear == 1 || g.gear == g.count));
    shifts++;
    lastDelta = delta;
    displayCog = (displayCog + delta).clamp(1, appGearCount);
    lastShiftAt = DateTime.now();
    if (voice && isProxy && sent && !demo) _voice.gear(() => proxy.gear.value);
    if (!sent) log('Vitesse ${delta > 0 ? '+1' : '−1'} non envoyée : ${target.label} n’est pas connecté');
    notifyListeners();
  }

  /// Vibration et son à chaque vitesse ; vibration forte en butée.
  void _feedback(bool ok, {bool lastGear = false}) {
    final c = shifting;
    if (c.vibrate) {
      if (!ok) {
        HapticFeedback.heavyImpact();
      } else if (lastGear) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    if (c.sound) unawaited(_tone(!ok ? 'limit' : (lastGear ? 'last' : 'shift')));
    final pad = _lastKeyDevice;
    if (rumble && pad != null && DateTime.now().difference(_lastKeyAt).inMilliseconds < 1500) {
      taps.rumble(pad, strong: !ok || lastGear);
    }
    // Zwift Play / Ride : la manette qui vient de changer de vitesse vibre.
    final pressed = _lastPressed;
    if (rumble && pressed != null && DateTime.now().difference(_lastPressAt ?? DateTime(0)).inMilliseconds < 1500) {
      unawaited(pressed.driver.vibrate(strong: !ok || lastGear));
    }
  }

  /// L'appli demande une vibration (butée, fin d'intervalle…) : le téléphone vibre,
  /// et aussi la manette qui sert (Zwift Play / Ride, manette de jeu).
  void relayHaptic({bool strong = false}) {
    strong ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
    if (!rumble) return;
    final now = DateTime.now();
    final pad = _lastKeyDevice;
    if (pad != null && now.difference(_lastKeyAt).inMinutes < 10) taps.rumble(pad, strong: strong);
    final pressed = _lastPressed;
    final recent = pressed != null && now.difference(_lastPressAt ?? DateTime(0)).inMinutes < 10;
    final targets = recent
        ? [pressed]
        : controllers.controllers.value.where((c) => c.state.value == LinkState.connected).toList();
    for (final c in targets) {
      unawaited(c.driver.vibrate(strong: strong));
    }
  }

  static const _sound = MethodChannel('shiftlink/sound');

  /// Bip natif ; à défaut (tests, autre plateforme), le son système.
  Future<void> _tone(String kind) async {
    try {
      await _sound.invokeMethod<void>('tone', {'kind': kind});
    } catch (_) {
      await SystemSound.play(kind == 'shift' ? SystemSoundType.click : SystemSoundType.alert);
    }
  }

  bool _tapShift(int delta) => _tapAction(delta > 0 ? ShiftAction.shiftUp : ShiftAction.shiftDown, Phase.once);

  bool _keyboardShift(int delta) => _keyAction(delta > 0 ? ShiftAction.shiftUp : ShiftAction.shiftDown, Phase.once);

  /// Positions à l'écran prêtes pour les vitesses ?
  bool get tapsReady {
    final p = taps.positionsFor(target.name);
    return taps.enabled.value && p.containsKey(ShiftAction.shiftUp) && p.containsKey(ShiftAction.shiftDown);
  }

  /// Voyant de la manette.
  Health get controllerHealth {
    final list = controllers.controllers.value;
    if (list.any((c) => c.state.value == LinkState.connected)) return Health.ok;
    if (list.isNotEmpty || controllers.scanning.value) return Health.waiting;
    return Health.off;
  }

  /// Voyant de l'appli.
  Health get appHealth => switch (target.transport) {
    Transport.link =>
      link.isConnected.value || obc.connectedApp.value != null
          ? Health.ok
          : (link.isStarted.value || obc.isStarted.value ? Health.waiting : Health.off),
    Transport.obc => obc.connectedApp.value != null ? Health.ok : (obc.isStarted.value ? Health.waiting : Health.off),
    Transport.zwiftRide =>
      zwiftRide.isConnected ? Health.ok : (zwiftRide.isStarted.value ? Health.waiting : Health.off),
    Transport.keyboard when sameDevice => tapsReady ? Health.ok : (taps.enabled.value ? Health.waiting : Health.off),
    Transport.keyboard => keyboard.connectedHost.value != null ? Health.ok : Health.waiting,
    Transport.proxy =>
      proxy.trainer.isConnected && proxy.appClient != null
          ? Health.ok
          : (proxy.trainer.isConnected || proxy.server.isStarted.value || proxy.ble.isStarted.value
                ? Health.waiting
                : Health.off),
  };

  /// Toutes les sources de changement à écouter pour les voyants.
  Listenable get healthListenable => Listenable.merge([
    this,
    controllers.controllers,
    controllers.scanning,
    controllers.lastScanEmpty,
    heartRate.state,
    cadenceSensor.state,
    cadenceSensor.cadence,
    powerSensor.state,
    powerSensor.power,
    controllers.asleep,
    proxy.staircase,
    proxy.workout,
    proxy.finishedWorkout,
    proxy.estimatedPower,
    ftpTestResult,
    lastAutoRide,
    batteryAlert,
    fan.state,
    fan.level,
    climb.state,
    climb.name,
    climb.grade,
    heartRate.bpm,
    ride.recording,
    link.isConnected,
    link.isStarted,
    obc.connectedApp,
    zwiftRide.client,
    keyboard.connectedHost,
    taps.enabled,
    taps.revision,
    taps.calibrating,
    proxy.trainer.state,
    proxy.server.client,
    proxy.ble.client,
    proxy.gear,
    proxy.data,
    proxy.appGrade,
    proxy.ring,
    proxy.ergOffset,
    for (final c in controllers.controllers.value) c.state,
    for (final c in controllers.controllers.value) c.battery,
  ]);

  @override
  void dispose() {
    _watchdog?.cancel();
    _inclineTimer?.cancel();
    _voice.dispose();
    ride.dispose();
    _steering?.stop();
    controllers.dispose();
    link.stop();
    obc.stop();
    obc.stopBluetooth();
    zwiftRide.stop();
    keyboard.stop();
    _lifecycle?.dispose();
    _hudListener?.removeListener(_updateHud);
    _resetEngines();
    proxy.dispose();
    FlutterForegroundTask.stopService();
    super.dispose();
  }
}

/// Touches d'une appli, avec le réglage personnalisé (préférences « kb.action »).
KeyPreset keyPresetFor(String id, SharedPreferences? prefs) {
  if (id == 'custom') {
    HidKey? find(String? label) => HidKeys.all.where((k) => k.label == label).firstOrNull;
    final keys = <ShiftAction, HidKey>{
      ShiftAction.shiftUp: find(prefs?.getString('kbUp')) ?? HidKeys.arrowUp,
      ShiftAction.shiftDown: find(prefs?.getString('kbDown')) ?? HidKeys.arrowDown,
      for (final a in keyboardActions)
        if (a != ShiftAction.shiftUp && a != ShiftAction.shiftDown) a: ?find(prefs?.getString('kb.${a.name}')),
    };
    return KeyPreset('custom', 'Personnalisé', keys);
  }
  return keyPresets.where((p) => p.id == id).firstOrNull ?? keyPresets.first;
}

/// Un bouton de manette vient d'être appuyé ou relâché.
class ButtonActivity {
  final ControllerDriver driver;
  final String buttonId;
  final bool down;
  final DateTime at = DateTime.now();
  ButtonActivity(this.driver, this.buttonId, this.down);
}

/// Une action déclenchée par un geste sur un bouton.
class FiredAction {
  final ControllerDriver driver;
  final String buttonId;
  final Gesture gesture;
  final ShiftAction action;
  final DateTime at = DateTime.now();
  FiredAction(this.driver, this.buttonId, this.gesture, this.action);

  String get buttonLabel => GestureEngine.comboParts(buttonId).map(driver.labelOf).join(' + ');
}
