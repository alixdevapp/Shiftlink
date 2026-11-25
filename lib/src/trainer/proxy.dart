// Proxy de vitesses virtuelles : l'appli (Zwift…) pilote le trainer émulé,
// ShiftLink ajuste la résistance selon la vitesse engagée et pilote le vrai
// trainer.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../riders.dart' show estimatePower, nextVirtualSpeed;
import 'ble_ftms.dart';
import 'dircon.dart';
import 'ftms.dart';
import 'gears.dart';
import 'route.dart';
import 'trainer_client.dart';
import 'workout.dart';

enum TrainerMode { none, simulation, erg }

class StaircaseState {
  final int step;
  final int steps;
  final int watts;
  final int secondsLeft;
  const StaircaseState(this.step, this.steps, this.watts, this.secondsLeft);
}

enum ResistanceTestOutcome { ok, noChange, noPedaling, noTrainer }

class ResistanceTestResult {
  final ResistanceTestOutcome outcome;
  final int? easyWatts;
  final int? hardWatts;
  const ResistanceTestResult(this.outcome, [this.easyWatts, this.hardWatts]);
}

class VirtualShiftingProxy {
  final void Function(String) log;
  final VirtualGears gears = VirtualGears();
  late final TrainerClient trainer = TrainerClient(log: log, onBikeData: handleBikeData);
  late final DirconServer server = DirconServer(log: log, onControlPoint: handleControlPoint);
  late final BleFtmsServer ble = BleFtmsServer(log: log, onControlPoint: handleControlPoint);

  /// Appli connectée, en Wi-Fi ou en Bluetooth.
  String? get appClient => server.client.value ?? ble.client.value;

  final ValueNotifier<int> gear = ValueNotifier(12);
  final ValueNotifier<BikeData> data = ValueNotifier(const BikeData());
  final ValueNotifier<double?> appGrade = ValueNotifier(null);
  TrainerMode mode = TrainerMode.none;
  SimulationParams? _lastSim;

  /// Puissance demandée par l'appli en ERG, et décalage choisi avec la manette.
  int? appTargetPower;
  final ValueNotifier<int> ergOffset = ValueNotifier(0);

  /// Puissance ERG réellement demandée au trainer.
  /// Puissance maximale annoncée aux applis (caractéristique « Supported Power Range »).
  static const maxErgWatts = 2000;

  int? get ergTarget =>
      appTargetPower == null ? null : (appTargetPower! + ergOffset.value).clamp(0, maxWatts ?? maxErgWatts);

  /// Mode enfant : pente maximale (%), watts maximum demandés au trainer, et
  /// coefficient des watts envoyés à l'appli (l'avatar avance malgré une petite roue).
  double? maxGrade;
  int? maxWatts;
  double appPowerFactor = 1;

  /// Simple relais (l'appli pilote le trainer sans vitesses ShiftLink). Pendant un
  /// parcours ShiftLink, il n'y a pas d'appli : les vitesses ShiftLink servent toujours.
  bool get _relay => gears.config.relay && routeRun.value == null;

  SimulationParams _capped(SimulationParams s) {
    final m = maxGrade;
    return m == null || s.gradePercent <= m ? s : SimulationParams(s.wind, m, s.crr, s.cw);
  }

  /// Envoie une commande au vrai trainer (remplaçable pour les tests).
  late Future<void> Function(Uint8List) sendToTrainer = trainer.send;

  VirtualShiftingProxy({required this.log}) {
    gear.value = gears.gear;
  }

  bool get active => trainer.isConnected;

  final CadenceFilter _cadence = CadenceFilter();
  double? cadence;
  int? _lastPower;
  DateTime _lastPowerAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Puissance demandée au trainer en mode « puissance ».
  final ValueNotifier<int?> simPower = ValueNotifier(null);

  /// Les watts viennent d'une estimation (le trainer ne les mesure pas).
  final ValueNotifier<bool> estimatedPower = ValueNotifier(false);

  /// Fréquence cardiaque d'une ceinture connectée à ShiftLink, ajoutée aux trames envoyées à l'appli.
  int? Function()? heartRate;

  /// Capteurs à part (cadence, puissance) : remplacent les valeurs du trainer.
  double? Function()? externalCadence;
  int? Function()? externalPower;

  void handleBikeData(Uint8List raw) {
    final hr = heartRate?.call();
    raw = withValues(
      raw,
      heartRate: hr != null && hr > 0 ? hr : null,
      cadence: externalCadence?.call(),
      power: externalPower?.call(),
    );
    var d = BikeData.parse(raw);
    // Trainer sans capteur de puissance : watts estimés d'après la vitesse et le poids.
    final noPower = d.power == null && d.speedKmh != null;
    if (noPower) {
      raw = withValues(raw, power: estimatePower(d.speedKmh!, gears.config.totalKg));
      d = BikeData.parse(raw);
    }
    if (estimatedPower.value != noPower) estimatedPower.value = noPower;
    _updateVirtualSpeed(d, measuredPower: !noPower);
    _sample(d);
    data.value = d;
    if (appPowerFactor != 1 && d.power != null) raw = withValues(raw, power: (d.power! * appPowerFactor).round());
    server.notify(Ftms.indoorBikeData, raw);
    ble.notify(Ftms.indoorBikeData, raw);
    if (d.cadence != null) {
      cadence = gears.config.cadenceFilter ? _cadence.add(d.cadence!) : d.cadence;
      if (mode == TrainerMode.simulation && control == 'power' && !_relay && powerLock.value == null) _sendPower();
    }
    _watchPowerLock(d);
  }

  // ---------------------------------------------------------------------------
  // Vitesse virtuelle : d'après les watts, la pente et le poids, pas la roue du
  // trainer (fausse avec les vitesses virtuelles, et absente sur certains trainers).

  /// Vitesse sur la route virtuelle (km/h), null sans mesure de puissance.
  final ValueNotifier<double?> virtualSpeedKmh = ValueNotifier(null);
  DateTime? _speedAt;

  /// Pente de la route du moment : parcours ShiftLink, sinon celle de l'appli (0 en ERG).
  double get roadGrade {
    final run = routeRun.value;
    if (run != null) return run.grade;
    if (mode == TrainerMode.simulation) return appGrade.value ?? 0;
    return 0;
  }

  /// Vitesse à afficher et à enregistrer : la vitesse virtuelle si on l'a, sinon celle du trainer.
  double? get rideSpeedKmh => virtualSpeedKmh.value ?? data.value.speedKmh;

  void _updateVirtualSpeed(BikeData d, {required bool measuredPower, DateTime? now}) {
    if (!measuredPower || d.power == null) {
      virtualSpeedKmh.value = null;
      _speedAt = null;
      return;
    }
    final t = now ?? DateTime.now();
    final last = _speedAt;
    _speedAt = t;
    if (last == null) {
      virtualSpeedKmh.value ??= d.speedKmh ?? 0;
      return;
    }
    final dt = t.difference(last).inMilliseconds / 1000;
    if (dt <= 0) return;
    virtualSpeedKmh.value = nextVirtualSpeed(
      virtualSpeedKmh.value ?? 0,
      d.power!,
      roadGrade,
      gears.config.totalKg,
      dt.clamp(0, 5).toDouble(),
    );
  }

  /// Pour les tests : une mesure à une heure donnée.
  @visibleForTesting
  void virtualSpeedSample(BikeData d, DateTime now) => _updateVirtualSpeed(d, measuredPower: true, now: now);

  // ---------------------------------------------------------------------------
  // Power Lock : un appui garde la puissance du moment, quelle que soit la route.

  /// Watts tenus par le verrou (null : pas de verrou).
  final ValueNotifier<int?> powerLock = ValueNotifier(null);

  /// Relâcher le verrou quand on arrête de pédaler (moins de 25 tr/min pendant 3 s).
  bool powerLockReleaseOnStop = true;

  /// Appelé quand le verrou se relâche tout seul (arrêt du pédalage).
  void Function()? onPowerLockAutoRelease;

  static const powerLockStopRpm = 25;
  static const powerLockStopDelay = Duration(seconds: 3);
  DateTime? _slowSince;
  TrainerMode _modeBeforeLock = TrainerMode.none;

  /// Le verrou est possible : ShiftLink pilote le trainer et l'appli n'impose pas de watts.
  bool get canPowerLock => active && !(mode == TrainerMode.erg && powerLock.value == null);

  /// Verrouille la puissance actuelle, ou relâche le verrou. Renvoie false si impossible.
  bool togglePowerLock({int? watts}) {
    if (powerLock.value != null) {
      releasePowerLock();
      return true;
    }
    if (!canPowerLock) return false;
    final w = watts ?? recentPower ?? simPower.value;
    if (w == null || w < 30) return false;
    _modeBeforeLock = mode;
    _slowSince = null;
    powerLock.value = w.clamp(30, maxWatts ?? maxErgWatts);
    mode = TrainerMode.erg;
    sendToTrainer(Ftms.targetPower(powerLock.value!));
    log('Power Lock : ${powerLock.value} W');
    return true;
  }

  /// Change les watts tenus par le verrou.
  bool adjustPowerLock(int delta) {
    final w = powerLock.value;
    if (w == null) return false;
    powerLock.value = (w + delta).clamp(30, maxWatts ?? maxErgWatts);
    sendToTrainer(Ftms.targetPower(powerLock.value!));
    return true;
  }

  void _clearPowerLock() {
    powerLock.value = null;
    _slowSince = null;
  }

  /// Relâche le verrou : on retrouve la pente de l'appli et ses vitesses.
  void releasePowerLock() {
    if (powerLock.value == null) return;
    _clearPowerLock();
    log('Power Lock relâché');
    if (_lastSim != null) {
      mode = TrainerMode.simulation;
      _applySimulation(fresh: false);
    } else {
      mode = _modeBeforeLock == TrainerMode.erg ? TrainerMode.none : _modeBeforeLock;
      sendToTrainer(Ftms.simulation(gradePercent: 0));
    }
  }

  void _watchPowerLock(BikeData d, {DateTime? now}) {
    if (powerLock.value == null || !powerLockReleaseOnStop) return;
    final rpm = cadence ?? d.cadence?.toDouble();
    if (rpm == null) return;
    final t = now ?? DateTime.now();
    if (rpm >= powerLockStopRpm) {
      _slowSince = null;
      return;
    }
    _slowSince ??= t;
    if (t.difference(_slowSince!) >= powerLockStopDelay) {
      releasePowerLock();
      onPowerLockAutoRelease?.call();
    }
  }

  /// Pour les tests : fait avancer la surveillance du pédalage à une heure donnée.
  @visibleForTesting
  void checkPowerLockAt(DateTime now) => _watchPowerLock(data.value, now: now);

  /// Mode de pilotage réellement utilisé.
  String get control => gears.config.control == 'auto' ? trainer.caps.value.bestControl : gears.config.control;

  void _sendPower({bool force = false}) {
    final sim = _lastSim;
    if (sim == null) return;
    final rpm = cadence ?? 0;
    final watts = (rpm < 20 ? 0 : gears.roadPower(_capped(sim), rpm)).round().clamp(0, maxWatts ?? 1500);
    final now = DateTime.now();
    final last = _lastPower;
    if (!force && last != null && (watts - last).abs() < 3 && now.difference(_lastPowerAt).inSeconds < 2) return;
    _lastPower = watts;
    _lastPowerAt = now;
    simPower.value = watts;
    sendToTrainer(Ftms.targetPower(watts));
  }

  /// Commande reçue de l'appli. Renvoie la réponse FTMS.
  Uint8List handleControlPoint(Uint8List cmd) {
    if (cmd.isEmpty) return Ftms.response(0, Ftms.resultNotSupported);
    final op = cmd[0];
    // L'appli reprend la main : la séance sans appli s'arrête.
    if (workout.value != null && (op == Ftms.opSetSimulation || op == Ftms.opSetTargetPower)) stopWorkout();
    if (routeRun.value != null && (op == Ftms.opSetSimulation || op == Ftms.opSetTargetPower)) stopRoute();
    switch (op) {
      case Ftms.opRequestControl:
      case Ftms.opReset:
        break;
      case Ftms.opSetSimulation:
        final sim = SimulationParams.parse(cmd);
        if (sim == null) return Ftms.response(op, Ftms.resultNotSupported);
        _lastSim = sim;
        appGrade.value = sim.gradePercent;
        // Power Lock : la pente de l'appli est gardée pour plus tard, les watts restent.
        if (powerLock.value != null) break;
        mode = TrainerMode.simulation;
        _applySimulation();
      case Ftms.opSetTargetPower:
        // L'appli passe en ERG : c'est elle qui fixe les watts, le verrou s'efface.
        if (powerLock.value != null) _clearPowerLock();
        mode = TrainerMode.erg;
        if (cmd.length >= 3) {
          // L'appli voit des watts multipliés (mode enfant) : on revient aux vrais watts.
          appTargetPower = (ByteData.sublistView(cmd).getInt16(1, Endian.little) / appPowerFactor).round();
          sendToTrainer(Ftms.targetPower(ergTarget!));
        } else {
          sendToTrainer(cmd);
        }
      case Ftms.opSetTargetResistance:
      case Ftms.opStartResume:
      case Ftms.opStopPause:
      case Ftms.opSetWheelCircumference:
        sendToTrainer(cmd);
      default:
        return Ftms.response(op, Ftms.resultNotSupported);
    }
    return Ftms.response(op, Ftms.resultSuccess);
  }

  void _applySimulation({bool fresh = true}) {
    if (powerLock.value != null) return;
    final last = _lastSim;
    if (last == null) return;
    final sim = _capped(last);
    if (_relay) {
      simPower.value = null;
      sendToTrainer(Ftms.simulation(gradePercent: sim.gradePercent, wind: sim.wind, crr: sim.crr, cw: sim.cw));
      return;
    }
    final out = _capped(gears.adjust(sim, fresh: fresh));
    switch (control) {
      case 'power':
        _sendPower(force: true);
      case 'resistance':
        simPower.value = null;
        final caps = trainer.caps.value;
        // −5 % → résistance minimale, +20 % → maximale.
        final t = ((out.gradePercent + 5) / 25).clamp(0.0, 1.0);
        sendToTrainer(
          Ftms.targetResistance((caps.minResistance + (caps.maxResistance - caps.minResistance) * t).round()),
        );
      default:
        simPower.value = null;
        sendToTrainer(Ftms.simulation(gradePercent: out.gradePercent, wind: out.wind, crr: out.crr, cw: out.cw));
    }
  }

  /// Change de vitesse. Renvoie false si on est déjà en butée.
  bool shift(int delta) {
    if (_relay) return false;
    final changed = gears.shift(delta);
    gear.value = gears.gear;
    if (changed && mode == TrainerMode.simulation) _applySimulation(fresh: false);
    return changed;
  }

  /// « Tout plus dur / tout plus facile » : décale toutes les vitesses.
  bool shiftAll(int delta) {
    if (_relay) return false;
    final changed = gears.shiftAll(delta);
    if (changed && mode == TrainerMode.simulation) _applySimulation(fresh: false);
    return changed;
  }

  /// Change de plateau (double plateau). Renvoie false si impossible.
  bool frontShift() {
    if (_relay) return false;
    final changed = gears.frontShift();
    gear.value = gears.gear;
    ring.value = gears.currentRing;
    if (changed && mode == TrainerMode.simulation) _applySimulation(fresh: false);
    return changed;
  }

  final ValueNotifier<int> ring = ValueNotifier(50);

  /// Applique de nouveaux réglages de vitesses.
  void configure(ShiftingConfig c) {
    gears.config = c;
    powerLockReleaseOnStop = c.powerLockRelease;
    trainer.riderKg = c.totalKg;
    gear.value = gears.gear;
    ring.value = gears.currentRing;
    if (mode == TrainerMode.simulation) _applySimulation(fresh: false);
  }

  /// Intensité ERG ± [watts]. Hors ERG, sans appli qui pilote, démarre un ERG
  /// manuel à [startWatts]. Renvoie false si impossible.
  bool ergAdjust(int watts, {int? startWatts}) {
    if (mode != TrainerMode.erg || appTargetPower == null) {
      if (startWatts == null || !active || appClient != null) return false;
      mode = TrainerMode.erg;
      appTargetPower = startWatts;
      ergOffset.value = 0;
      log('ERG manuel : $startWatts W');
    } else {
      ergOffset.value += watts;
    }
    lastErgTarget = ergTarget;
    if (fixedErg.value != null) fixedErg.value = ergTarget;
    sendToTrainer(Ftms.targetPower(ergTarget!));
    return true;
  }

  /// Dernière puissance ERG demandée (pour reprendre là où on en était).
  int? lastErgTarget;

  /// ERG à puissance fixe lancé depuis l'onglet Séances (null : arrêté).
  /// Le trainer tient ces watts quelle que soit la cadence.
  final ValueNotifier<int?> fixedErg = ValueNotifier(null);
  Timer? _fixedTimer;

  bool startFixedErg(int watts) {
    if (!canRunAlone) return false;
    stopWorkout();
    stopStaircase();
    stopRoute();
    _fixedTimer?.cancel();
    mode = TrainerMode.erg;
    appTargetPower = watts.clamp(0, maxErgWatts);
    ergOffset.value = 0;
    lastErgTarget = ergTarget;
    fixedErg.value = ergTarget;
    if (trainer.caps.value.power) {
      sendToTrainer(Ftms.targetPower(ergTarget!));
    } else {
      // Trainer sans consigne en watts : ShiftLink règle la résistance chaque seconde.
      _ergLevel = 0.2;
      log('Le trainer ne vise pas les watts lui-même : ShiftLink règle la résistance');
      _fixedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (fixedErg.value == null || ergTarget == null) return;
        _followPower(ergTarget!);
      });
      _followPower(ergTarget!);
    }
    log('ERG fixe : $ergTarget W');
    return true;
  }

  /// Change les watts de l'ERG fixe en cours.
  void setFixedErg(int watts) {
    if (fixedErg.value == null) return;
    appTargetPower = watts.clamp(0, maxErgWatts);
    ergOffset.value = 0;
    lastErgTarget = ergTarget;
    fixedErg.value = ergTarget;
    if (_fixedTimer == null) sendToTrainer(Ftms.targetPower(ergTarget!));
  }

  void stopFixedErg() {
    _fixedTimer?.cancel();
    _fixedTimer = null;
    if (fixedErg.value == null) return;
    fixedErg.value = null;
    if (appClient == null && mode == TrainerMode.erg) {
      mode = TrainerMode.none;
      appTargetPower = null;
      ergOffset.value = 0;
      sendToTrainer(Ftms.simulation(gradePercent: 0));
    }
  }

  /// Puissance moyenne des 3 dernières secondes, arrondie à 5 W.
  int? get recentPower {
    final now = DateTime.now();
    final list = _powers.where((p) => now.difference(p.$1).inMilliseconds < 3000).map((p) => p.$2).toList();
    if (list.isEmpty) return null;
    final avg = list.reduce((a, b) => a + b) / list.length;
    return (avg / 5).round() * 5;
  }

  final List<(DateTime, int)> _powers = [];

  void _sample(BikeData d) {
    if (d.power == null) return;
    final now = DateTime.now();
    _powers.add((now, d.power!));
    _powers.removeWhere((p) => now.difference(p.$1).inSeconds > 15);
  }

  /// Séance « escalier » en ERG : [steps] paliers de [minutes] min, +[stepWatts] W à chaque palier.
  final ValueNotifier<StaircaseState?> staircase = ValueNotifier(null);
  Timer? _stairTimer;

  bool startStaircase({required int startWatts, required int stepWatts, int steps = 5, int minutes = 2}) {
    if (!active || appClient != null) return false;
    stopFixedErg();
    stopWorkout();
    stopStaircase();
    var step = 0;
    var left = minutes * 60;
    void apply() {
      mode = TrainerMode.erg;
      appTargetPower = startWatts + step * stepWatts;
      ergOffset.value = 0;
      lastErgTarget = appTargetPower;
      sendToTrainer(Ftms.targetPower(appTargetPower!));
    }

    apply();
    staircase.value = StaircaseState(step + 1, steps, appTargetPower!, left);
    _stairTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      left--;
      if (left <= 0) {
        step++;
        if (step >= steps) {
          log('Escalier terminé, bravo !');
          stopStaircase();
          return;
        }
        left = minutes * 60;
        apply();
      }
      staircase.value = StaircaseState(step + 1, steps, ergTarget ?? 0, left);
    });
    log('Escalier : $steps paliers de $minutes min, de $startWatts W à ${startWatts + (steps - 1) * stepWatts} W');
    return true;
  }

  void stopStaircase() {
    _stairTimer?.cancel();
    _stairTimer = null;
    if (staircase.value != null) {
      staircase.value = null;
      if (appClient == null && mode == TrainerMode.erg) {
        mode = TrainerMode.none;
        appTargetPower = null;
        sendToTrainer(Ftms.simulation(gradePercent: 0));
      }
    }
  }

  /// Séance jouée en ERG, sans appli.
  final ValueNotifier<WorkoutRun?> workout = ValueNotifier(null);

  /// Parcours GPX en cours (si non null, la pente vient de ce parcours).
  final ValueNotifier<RouteRun?> routeRun = ValueNotifier(null);
  Timer? _routeTimer;

  Timer? _workoutTimer;

  /// ERG piloté par ShiftLink lui-même (séance, escalier, ERG manuel), sans appli.
  bool get ergAlone => mode == TrainerMode.erg && appTargetPower != null && active && appClient == null;

  /// Une séance (ou l'escalier) est possible : trainer connecté, aucune appli ne le pilote.
  bool get canRunAlone => active && appClient == null;

  /// Pause demandée d'un bouton (séance ou parcours) : le chrono et la distance
  /// s'arrêtent, le trainer passe en roue libre (pente 0).
  final ValueNotifier<bool> manualPause = ValueNotifier(false);

  void togglePause() {
    if (workout.value == null && routeRun.value == null) return;
    manualPause.value = !manualPause.value;
    if (manualPause.value) {
      log('Pause');
      mode = TrainerMode.none;
      sendToTrainer(Ftms.simulation(gradePercent: 0));
    } else {
      log('Reprise');
      if (routeRun.value != null) {
        mode = TrainerMode.simulation;
        _applySimulation(fresh: false);
      }
      // Séance : la minuterie renvoie la cible au prochain tour (mode ≠ ERG).
    }
  }

  bool startWorkout(Workout w, {required int ftp, int hrMax = 190}) {
    if (!canRunAlone || w.steps.isEmpty) return false;
    stopFixedErg();
    stopStaircase();
    stopWorkout();
    var elapsed = 0;
    var overSeconds = 0;
    _ergLevel = 0.2;
    final byResistance = !trainer.caps.value.power;
    if (byResistance) log('Le trainer ne vise pas les watts lui-même : ShiftLink règle la résistance');
    // Séance au cardio : un régulateur par bloc « au cardio ».
    final hrTarget = w.hrTarget(hrMax);
    HeartRateErg? hrErg;
    var hrStep = -1;
    var noHr = 0;
    HeartRateErg? heartBlock() {
      final at = w.stepAt(elapsed);
      if (hrTarget == null || at == null || !w.steps[at.$1].byHeartRate) return null;
      if (hrErg == null || hrStep != at.$1) {
        hrStep = at.$1;
        // Départ : la puissance actuelle si on vient d'un bloc, sinon celle du bloc.
        final start = appTargetPower ?? (w.steps[at.$1].from * ftp).round();
        hrErg = HeartRateErg(
          low: hrTarget.$1,
          high: hrTarget.$2,
          watts: start,
          minWatts: (ftp * 0.3).round(),
          maxWatts: (ftp * 1.0).round(),
        );
      }
      return hrErg;
    }

    int target() =>
        (heartBlock()?.watts ?? ((w.intensityAt(elapsed) ?? 0) * ftp).round()).clamp(0, maxErgWatts);
    void apply() {
      final watts = target();
      final changed = mode != TrainerMode.erg || appTargetPower != watts;
      mode = TrainerMode.erg;
      appTargetPower = watts;
      lastErgTarget = ergTarget;
      if (byResistance) {
        _followPower(ergTarget!);
      } else if (changed) {
        sendToTrainer(Ftms.targetPower(ergTarget!));
      }
    }

    ergOffset.value = 0;
    final powerLog = <int>[];
    _lastPowerLog = powerLog;
    var dropped = 0;
    apply();
    workout.value = WorkoutRun(w, 0, ergTarget ?? 0, hrTarget: hrTarget);
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final d = data.value;
      final rpm = d.cadence ?? 0;
      if (manualPause.value) {
        final cur = workout.value;
        if (cur != null && !cur.paused) {
          workout.value = WorkoutRun(w, elapsed, cur.watts, paused: true, avgPower: cur.avgPower, hrTarget: hrTarget);
        }
        return;
      }
      final paused = rpm < 20;
      if (!paused) {
        elapsed++;
        final p = d.power;
        if (p != null && p > 0) powerLog.add(p);
        final bpm = heartRate?.call();
        final hb = heartBlock();
        if (hb != null) {
          hb.tick(bpm);
          noHr = bpm == null || bpm <= 0 ? noHr + 1 : 0;
        } else {
          noHr = 0;
        }
      }
      // Test en rampe : on lâche (moins de 50 tr/min pendant 5 s) = fin du test.
      if (w.ftpTest == 'ramp' && elapsed > w.steps.first.seconds + 60) {
        dropped = rpm < 50 ? dropped + 1 : 0;
        if (dropped >= 5) {
          powerLog.removeRange((powerLog.length - dropped).clamp(0, powerLog.length), powerLog.length);
          log('Test FTP : rampe terminée après ${elapsed - w.steps.first.seconds} s');
          stopWorkout(finished: true);
          return;
        }
      }
      if (elapsed >= w.seconds) {
        log('Séance « ${w.name} » terminée, bravo !');
        _lastPowerLog = powerLog;
        stopWorkout(finished: true);
        return;
      }
      apply();
      // Le trainer donne bien plus que demandé : souvent un trop grand braquet sur le vrai vélo.
      final t = ergTarget ?? 0;
      final p = d.power;
      overSeconds = (!paused && rpm >= 55 && p != null && p > t * 1.3 + 20) ? overSeconds + 1 : 0;
      final avg = powerLog.isEmpty ? 0 : (powerLog.reduce((a, b) => a + b) / powerLog.length).round();
      final last = powerLog.length < 30
          ? 0
          : (powerLog.skip(powerLog.length - 60.clamp(1, powerLog.length)).reduce((a, b) => a + b) /
                    (powerLog.length < 60 ? powerLog.length : 60))
                .round();
      workout.value = WorkoutRun(
        w,
        elapsed,
        t,
        paused: paused,
        tooHard: overSeconds >= 8,
        avgPower: avg,
        lastMinutePower: last,
        hrTarget: hrTarget,
        noHeartRate: noHr >= 20,
      );
    });
    log('Séance « ${w.name} » : ${w.steps.length} blocs, ${w.seconds ~/ 60} min, FTP $ftp W');
    return true;
  }

  /// Résistance (0 à 1) quand le trainer ne sait pas viser des watts tout seul.
  double _ergLevel = 0.2;

  /// Règle la résistance pas à pas pour approcher [watts] (une fois par seconde).
  void _followPower(int watts) {
    final p = data.value.power;
    if (p != null && (data.value.cadence ?? 0) >= 20) {
      final error = (watts - p) / (watts < 50 ? 50 : watts);
      _ergLevel = (_ergLevel + (error * 0.15).clamp(-0.08, 0.08)).clamp(0.0, 1.0);
    }
    final caps = trainer.caps.value;
    sendToTrainer(
      Ftms.targetResistance((caps.minResistance + (caps.maxResistance - caps.minResistance) * _ergLevel).round()),
    );
  }

  /// Dernière séance finie jusqu'au bout (pour le « bravo »).
  final ValueNotifier<Workout?> finishedWorkout = ValueNotifier(null);

  /// Watts seconde par seconde du dernier run (gardés pour le test FTP).
  List<int> _lastPowerLog = const [];
  List<int> get lastPowerLog => _lastPowerLog;

  void stopWorkout({bool finished = false}) {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    if (routeRun.value == null) manualPause.value = false;
    final w = workout.value;
    if (w == null) return;
    workout.value = null;
    // Test en rampe arrêté à la main une fois la rampe commencée : c'est sa fin normale.
    if (w.workout.ftpTest == 'ramp' && w.elapsed > w.workout.steps.first.seconds + 60) finished = true;
    if (finished) finishedWorkout.value = w.workout;
    if (appClient == null && mode == TrainerMode.erg) {
      mode = TrainerMode.none;
      appTargetPower = null;
      ergOffset.value = 0;
      sendToTrainer(Ftms.simulation(gradePercent: 0));
    }
  }

  /// Dernière sortie enregistrée pour ce parcours (clé : nom du parcours). Rempli par l'appli.
  GhostRun? Function(String)? ghostLookup;

  /// Appelé à la fin d'un parcours pour sauver le fantôme (s'il est meilleur que l'ancien).
  void Function(String name, GhostRun run)? onRouteFinished;

  /// Appelé pendant un parcours (toutes les 20 s) et à son arrêt, avec la distance atteinte,
  /// pour pouvoir le reprendre plus tard. Distance null : parcours fini, plus rien à reprendre.
  void Function(String name, double? distanceM)? onRouteProgress;

  /// Démarre un parcours GPX : la pente du parcours pilote le trainer tant que ShiftLink roule tout seul.
  /// [fromM] : distance de départ sur la trace (reprise, ou départ à un km choisi).
  bool startRoute(GpxRoute r, {double fromM = 0}) {
    if (!canRunAlone || r.length <= 0) return false;
    stopFixedErg();
    stopStaircase();
    stopWorkout();
    stopRoute();
    final startM = fromM.clamp(0.0, (r.length - 100).clamp(0.0, r.length)).toDouble();
    var distance = startM;
    var elapsed = 0;
    final samples = <(int, double)>[(0, 0)];
    final ghost = ghostLookup?.call(r.name);
    // Départ en cours de trace : le fantôme est comparé depuis le même endroit.
    final ghostStart = ghost?.timeAt(startM);
    final firstGrade = r.gradeAt(startM);
    mode = TrainerMode.simulation;
    _lastSim = SimulationParams(0, firstGrade, 0.004, 0.51);
    _applySimulation();
    routeRun.value = RouteRun(r, startM, firstGrade, ghostGap: ghost == null || ghostStart == null ? null : 0);
    _routeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (manualPause.value) return;
      final kmh = rideSpeedKmh ?? 0;
      if (kmh > 0) elapsed++;
      distance += kmh * 1000 / 3600;
      samples.add((elapsed, distance));
      if (distance >= r.length) {
        log('Parcours « ${r.name} » terminé !');
        // Le fantôme ne vaut que pour un parcours fait en entier.
        if (startM == 0) onRouteFinished?.call(r.name, GhostRun(samples));
        stopRoute(finished: true);
        return;
      }
      final grade = r.gradeAt(distance);
      _lastSim = SimulationParams(_lastSim?.wind ?? 0, grade, 0.004, 0.51);
      appGrade.value = grade;
      _applySimulation(fresh: false);
      int? gap;
      if (ghost != null && ghostStart != null) {
        final gt = ghost.timeAt(distance);
        if (gt != null) gap = elapsed - (gt - ghostStart);
      }
      routeRun.value = RouteRun(r, distance, grade, ghostGap: gap);
      if (elapsed % 20 == 0 && kmh > 0) onRouteProgress?.call(r.name, distance);
    });
    log(
      'Parcours « ${r.name} » : ${(r.length / 1000).toStringAsFixed(1)} km'
      '${startM > 0 ? ', départ au km ${(startM / 1000).toStringAsFixed(1)}' : ''}',
    );
    return true;
  }

  final ValueNotifier<String?> finishedRoute = ValueNotifier(null);

  void stopRoute({bool finished = false}) {
    _routeTimer?.cancel();
    _routeTimer = null;
    if (workout.value == null) manualPause.value = false;
    final r = routeRun.value;
    if (r == null) return;
    routeRun.value = null;
    onRouteProgress?.call(r.route.name, finished ? null : r.distance);
    if (finished) finishedRoute.value = r.route.name;
    if (appClient == null) {
      mode = TrainerMode.none;
      appGrade.value = null;
      sendToTrainer(Ftms.simulation(gradePercent: 0));
    }
  }

  /// Calibration possible : le trainer la propose, aucune appli ne le pilote, rien n'est en cours.
  bool get canCalibrate =>
      canRunAlone &&
      trainer.caps.value.spinDown &&
      workout.value == null &&
      routeRun.value == null &&
      fixedErg.value == null;

  /// Lance la calibration (« spin down ») : roue libre, puis le trainer guide.
  Future<bool> startCalibration() async {
    if (!canCalibrate) return false;
    stopStaircase();
    mode = TrainerMode.none;
    await trainer.startSpinDown();
    return true;
  }

  /// Fin (ou abandon) de la calibration : on reprend la main sur le trainer.
  Future<void> endCalibration() async {
    await trainer.cancelSpinDown();
    if (!active) return;
    await sendToTrainer(Ftms.requestControl());
    if (appClient == null) await sendToTrainer(Ftms.simulation(gradePercent: 0));
  }

  /// Test de résistance : 10 s facile, 10 s dur, à pédaler régulièrement.
  /// [progress] reçoit le texte de l'étape. Renvoie le résultat.
  Future<ResistanceTestResult> resistanceTest({void Function(int step, int secondsLeft)? progress}) async {
    if (!active) return const ResistanceTestResult(ResistanceTestOutcome.noTrainer);
    final hard = control == 'resistance' || !trainer.caps.value.simulation;
    Future<int?> phase(int step, Uint8List cmd) async {
      await sendToTrainer(cmd);
      final seen = <int>[];
      for (var s = 10; s > 0; s--) {
        progress?.call(step, s);
        await Future<void>.delayed(const Duration(seconds: 1));
        final p = data.value.power;
        if (s <= 6 && p != null && (data.value.cadence ?? 60) > 20) seen.add(p);
      }
      if (seen.isEmpty) return null;
      return (seen.reduce((a, b) => a + b) / seen.length).round();
    }

    final caps = trainer.caps.value;
    int lvl(double t) => (caps.minResistance + (caps.maxResistance - caps.minResistance) * t).round();
    final easy = await phase(1, hard ? Ftms.targetResistance(lvl(0.1)) : Ftms.simulation(gradePercent: 0));
    final strong = await phase(2, hard ? Ftms.targetResistance(lvl(0.6)) : Ftms.simulation(gradePercent: 8));
    // Rend la main à l'appli, ou une route plate.
    if (_lastSim != null && mode == TrainerMode.simulation) {
      _applySimulation(fresh: false);
    } else {
      await sendToTrainer(Ftms.simulation(gradePercent: 0));
    }
    if (easy == null || strong == null) return const ResistanceTestResult(ResistanceTestOutcome.noPedaling);
    final ok = strong >= easy * 1.2 + 10;
    log('Test de résistance : $easy W facile, $strong W dur → ${ok ? 'OK' : 'pas de différence'}');
    return ResistanceTestResult(ok ? ResistanceTestOutcome.ok : ResistanceTestOutcome.noChange, easy, strong);
  }

  Future<void> dispose() async {
    stopFixedErg();
    stopStaircase();
    stopWorkout();
    await server.stop();
    await ble.stop();
    await trainer.disconnect();
  }
}
