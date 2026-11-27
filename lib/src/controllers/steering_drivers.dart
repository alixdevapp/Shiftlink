// Direction : Elite Sterzo Smart, Elite Rizer et téléphone posé sur le guidon.
//
// Code écrit pour ShiftLink. Protocole du Sterzo (UUID, défi-réponse, mesure en
// flottant) d'après pycycling, licence MIT :
// https://github.com/zacharyedwardbull/pycycling/blob/master/pycycling/sterzo.py
// Les codes de réponse du Sterzo viennent du même projet, téléchargés au premier
// usage puis gardés en cache.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../sensors/incline.dart';
import 'driver.dart';

/// Change un angle de guidon en appui maintenu « gauche » ou « droite ».
/// On entre au-delà de [threshold] ; on revient au centre sous 60 % du seuil.
class SteeringGate {
  double threshold;
  String? _held;
  SteeringGate(this.threshold);

  String? _next(double angle) {
    if (angle > threshold) return 'left';
    if (angle < -threshold) return 'right';
    final exit = threshold * 0.6;
    return switch (_held) {
      'left' when angle < exit => null,
      'right' when angle > -exit => null,
      _ => _held,
    };
  }

  /// [angle] en degrés, positif = à gauche.
  List<ButtonEvent> update(double angle) {
    final next = _next(angle);
    if (next == _held) return const [];
    final events = <ButtonEvent>[];
    if (_held != null) events.add(release(_held!));
    if (next != null) events.add(press(next));
    _held = next;
    return events;
  }

  void reset() => _held = null;
}

const _steerButtons = [ControllerButton('left', 'Tourner à gauche'), ControllerButton('right', 'Tourner à droite')];
const _steerDefaults = {'left': 'steerLeft', 'right': 'steerRight'};

/// Elite Sterzo Smart : défi-réponse puis angle du guidon en flottant 32 bits.
class EliteSterzoDriver extends ControllerDriver {
  static Guid _elite(String n) => Guid('347b$n-7635-408b-8918-8ff3949ce592');
  static final service = _elite('0001');
  static final measurement = _elite('0030');
  static final control = _elite('0031');
  static final challenge = _elite('0032');

  static const codesUrl =
      'https://raw.githubusercontent.com/zacharyedwardbull/pycycling/master/pycycling/data/sterzo-challenge-codes.dat';

  /// Empreinte SHA-256 du fichier attendu (vérifiée sur GitHub et sur le paquet PyPI 0.4.1).
  /// Un fichier modifié ou corrompu est refusé.
  static const codesSha256 = 'b31d56e06619e908bd853a2ab4397903f87595949d10636866f021c384d9a954';
  static const codesLength = 131072;
  static const _cacheKey = 'sterzoCodes';

  /// Nombre de mesures moyennées pour trouver le zéro.
  static const calibrationSamples = 10;

  /// Réponse envoyée si on ne connaît pas le code (le Sterzo ne démarrera pas).
  static const _unknownReply = [0x96, 0x96];

  /// Codes de réponse (2 octets par défi). Chargés à la demande.
  static Uint8List? codes;

  final gate = SteeringGate(10);
  final List<double> _zeroSamples = [];
  double? _zero;
  BluetoothCharacteristic? _control;

  /// Dernier angle mesuré, en degrés (positif = gauche).
  double angle = 0;

  @override
  String get typeId => 'sterzo';
  @override
  String get label => 'Elite Sterzo Smart';
  @override
  List<ControllerButton> get buttons => _steerButtons;
  @override
  Map<String, String> get defaultClicks => _steerDefaults;
  @override
  String get hint => tr('Garde le guidon droit quelques secondes après la connexion : c’est le zéro.');

  @override
  List<Subscription> get subscriptions => [Subscription(service, challenge), Subscription(service, measurement)];

  @override
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {
    _control = services
        .where((s) => s.uuid == service)
        .expand((s) => s.characteristics)
        .firstWhere((c) => c.uuid == control);
    await _control!.write(const [0x03, 0x10]); // « envoie-moi un défi »
  }

  @override
  void reset() {
    super.reset();
    gate.reset();
    _zeroSamples.clear();
    _zero = null;
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (c == challenge) {
      // Le défi est sur les octets 2 et 3, gros-boutiste.
      if (bytes.length >= 4) unawaited(_reply(ByteData.sublistView(bytes, 2, 4).getUint16(0)));
      return const [];
    }
    if (c != measurement || bytes.length < 4) return const [];
    final raw = ByteData.sublistView(bytes, 0, 4).getFloat32(0, Endian.little);
    if (!raw.isFinite) return const [];
    final zero = _zero;
    if (zero == null) {
      _zeroSamples.add(raw);
      if (_zeroSamples.length == calibrationSamples) {
        _zero = _zeroSamples.fold<double>(0, (a, b) => a + b) / calibrationSamples;
      }
      return const [];
    }
    // Le Sterzo compte positif vers la droite ; ShiftLink, vers la gauche.
    angle = zero - raw;
    return gate.update(angle);
  }

  /// Les deux octets de réponse au défi [challenge], lus dans la table.
  static List<int> responseFor(int challenge, Uint8List? table) {
    final at = challenge * 2;
    if (table == null || at < 0 || at + 2 > table.length) return _unknownReply;
    return table.sublist(at, at + 2);
  }

  Future<void> _reply(int value) async {
    final ctl = _control;
    if (ctl == null) return;
    await ctl.write([0x03, 0x11, ...responseFor(value, await loadCodes())]);
    await Future.delayed(const Duration(seconds: 1));
    await ctl.write(const [0x02, 0x02]); // démarre l'envoi des angles
  }

  /// Le fichier de codes est-il bien celui de pycycling ?
  static bool isGenuine(Uint8List data) => data.length == codesLength && sha256.convert(data).toString() == codesSha256;

  static Future<Uint8List?> loadCodes() async {
    if (codes != null) return codes;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final data = base64Decode(cached);
        if (isGenuine(data)) return codes = data;
        await prefs.remove(_cacheKey);
      }
      final data = await _download();
      if (data == null || !isGenuine(data)) return null;
      await prefs.setString(_cacheKey, base64Encode(data));
      return codes = data;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _download() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final res = await (await client.getUrl(Uri.parse(codesUrl))).close();
      if (res.statusCode != 200) return null;
      final buf = BytesBuilder(copy: false);
      await for (final chunk in res) {
        buf.add(chunk);
        if (buf.length > codesLength) return null; // trop gros : ce n'est pas le bon fichier
      }
      return buf.takeBytes();
    } finally {
      client.close();
    }
  }
}

/// Elite Rizer : direction (angle en flottant 32 bits sur 347b0030, sans défi) et
/// pente réelle (écriture sur 347b0020, voir sensors/incline.dart).
/// Le Rizer répond à chaque commande sur 347b0021 (indications) : [0x80, commande, code],
/// code 2 = fait ; et donne sa pente réelle sur 347b0022 : octet 1 = 100 + 2 × pente %.
class EliteRizerDriver extends ControllerDriver implements InclineSink {
  static Guid _elite(String n) => Guid('347b$n-7635-408b-8918-8ff3949ce592');
  static final service = _elite('0001');
  static final write = _elite('0020');
  static final measurement = _elite('0030');
  static final status = _elite('0021');
  static final reportedIncline = _elite('0022');

  /// Code de réponse « commande faite ».
  static const ackDone = 0x02;

  /// Code de réponse « commande non accessible » : le Rizer est verrouillé (LED rouge)
  /// et refuse toute pente jusqu'à ce qu'on le déverrouille.
  static const ackLocked = 0x05;

  /// Temps laissé au Rizer pour répondre à une commande de pente.
  static const ackTimeout = Duration(seconds: 1);

  /// Pente où le Rizer dit être, en % (null = pas encore reçue).
  final ValueNotifier<double?> reportedGrade = ValueNotifier(null);

  /// Le Rizer refuse les pentes parce qu'il est verrouillé (LED rouge).
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// Ligne à écrire dans le journal (refus, verrouillage), ou null.
  String? lastRefusal;

  Completer<int?>? _ack;

  final gate = SteeringGate(10);
  final follower = InclineFollower(max: 20);
  final List<double> _zeroSamples = [];
  double? _zero;
  BluetoothCharacteristic? _write;

  /// Dernier angle mesuré, en degrés (positif = gauche).
  double angle = 0;

  @override
  String get typeId => 'rizer';
  @override
  String get label => tr('Elite Rizer (bêta)');
  @override
  List<ControllerButton> get buttons => _steerButtons;
  @override
  Map<String, String> get defaultClicks => _steerDefaults;
  @override
  String get hint => tr(
    'Garde le guidon droit quelques secondes après la connexion : c’est le zéro. L’avant du vélo suit la pente de l’appli.',
  );

  @override
  List<Subscription> get subscriptions => [
    Subscription(service, measurement),
    Subscription(service, status, optional: true),
    Subscription(service, reportedIncline, optional: true),
  ];

  /// Code de la réponse du Rizer à la commande de pente, ou null si ce n'en est pas une.
  static int? ackCode(Uint8List b) => b.length >= 3 && b[0] == 0x80 && b[1] == 0x0a ? b[2] : null;

  /// Pente rapportée par le Rizer, en %.
  static double? gradeReported(Uint8List b) => b.length < 2 ? null : (b[1] - 100) / 2;

  static String ackName(int code) => switch (code) {
    0 => 'paramètres faux',
    1 => 'hors limites',
    3 => 'commande fausse',
    4 => 'échec',
    5 => 'commande non accessible',
    _ => 'code $code',
  };

  @override
  Future<void> afterSubscribe(BluetoothDevice device, List<BluetoothService> services) async {
    _write = services
        .where((s) => s.uuid == service)
        .expand((s) => s.characteristics)
        .where((c) => c.uuid == write)
        .firstOrNull;
    follower.reset();
  }

  @override
  void reset() {
    super.reset();
    gate.reset();
    _zeroSamples.clear();
    _zero = null;
    _write = null;
    reportedGrade.value = null;
    locked.value = false;
    _ack?.complete(null);
    _ack = null;
  }

  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) {
    if (c == status) {
      final code = ackCode(bytes);
      final pending = _ack;
      if (code != null && pending != null && !pending.isCompleted) pending.complete(code);
      return const [];
    }
    if (c == reportedIncline) {
      reportedGrade.value = gradeReported(bytes) ?? reportedGrade.value;
      return const [];
    }
    if (c != measurement || bytes.length < 4) return const [];
    final raw = ByteData.sublistView(bytes, 0, 4).getFloat32(0, Endian.little);
    if (!raw.isFinite) return const [];
    final zero = _zero;
    if (zero == null) {
      _zeroSamples.add(raw);
      if (_zeroSamples.length == EliteSterzoDriver.calibrationSamples) {
        _zero = _zeroSamples.fold<double>(0, (a, b) => a + b) / _zeroSamples.length;
      }
      return const [];
    }
    // Le Rizer compte positif vers la droite ; ShiftLink, vers la gauche.
    angle = zero - raw;
    return gate.update(angle);
  }

  @override
  Future<bool> writeGrade(double percent) async {
    final w = _write;
    if (w == null) return false;
    _ack?.complete(null);
    final ack = _ack = Completer<int?>();
    try {
      await w.write(rizerGradeCommand(percent), withoutResponse: !w.properties.write);
    } catch (_) {
      if (identical(_ack, ack)) _ack = null;
      return false;
    }
    // Sans réponse (ancien firmware), la commande est partie : on la compte comme faite.
    final code = await ack.future.timeout(ackTimeout, onTimeout: () => null);
    if (identical(_ack, ack)) _ack = null;
    return handleAck(code, percent);
  }

  /// Lit la réponse du Rizer à une pente : true si elle est faite (ou sans réponse,
  /// ancien firmware). Tient à jour [locked] et la ligne de journal [lastRefusal].
  @visibleForTesting
  bool handleAck(int? code, double percent) {
    if (code == null || code == ackDone) {
      if (code == ackDone && locked.value) {
        locked.value = false;
        lastRefusal = 'déverrouillé, la pente suit de nouveau';
      }
      return true;
    }
    if (code == ackLocked) {
      // Verrouillé : une seule ligne dans le journal, pas une par seconde.
      if (!locked.value) {
        locked.value = true;
        lastRefusal = 'verrouillé (LED rouge), les pentes sont refusées';
      }
      return false;
    }
    lastRefusal = 'pente ${percent.toStringAsFixed(1)} % refusée (${ackName(code)})';
    return false;
  }

  /// Suit la pente de l'appli (null = plus de pente : retour à plat).
  Future<void> follow(double? appGrade) async {
    final g = follower.next(appGrade);
    if (g != null && await writeGrade(g)) follower.sent(g);
  }
}

/// Le téléphone ShiftLink fixé au guidon sert de capteur de direction.
class PhoneSteeringDriver extends ControllerDriver {
  @override
  String get typeId => 'phoneSteering';
  @override
  String get label => tr('Direction');
  @override
  List<ControllerButton> get buttons => _steerButtons;
  @override
  Map<String, String> get defaultClicks => _steerDefaults;
  @override
  List<Subscription> get subscriptions => const [];
  @override
  List<ButtonEvent> decode(Guid c, Uint8List bytes) => const [];
  @override
  String get hint => tr('Fixe le téléphone au guidon et garde-le immobile 1 s : c’est le zéro.');
}

/// Angle du guidon d'après le gyroscope, dans n'importe quelle position du téléphone.
///
/// La rotation mesurée est projetée sur la verticale (donnée par l'accéléromètre),
/// puis intégrée. Quand tout est immobile près du centre, on apprend le biais du
/// gyroscope pour que l'angle ne dérive pas.
class SteeringEstimator {
  static const _gravity = 9.80665;

  /// Rotation sous laquelle on se considère immobile (rad/s).
  final double gyroStill;

  /// Écart toléré à la gravité pour se considérer immobile (m/s²).
  final double accelStill;

  /// Temps immobile avant d'apprendre le biais (s).
  final double minStillForBias;

  /// On n'apprend le biais que près du centre (degrés).
  final double biasDeadband;

  /// Vitesse d'apprentissage du biais, par mesure.
  final double biasLearningRate;

  /// Angle maximal (degrés) et pas de temps maximal (s).
  final double maxAngle;
  final double maxDt;

  /// Constante de temps du lissage de l'angle affiché (s).
  final double smoothing;

  SteeringEstimator({
    this.gyroStill = 0.03,
    this.accelStill = 0.6,
    this.minStillForBias = 0.4,
    this.biasDeadband = 3,
    this.biasLearningRate = 0.02,
    this.maxAngle = 60,
    this.maxDt = 0.05,
    this.smoothing = 0.06,
  });

  final List<double> _g = [0, 0, 0];
  bool _hasAccel = false;
  double _bias = 0;
  double _integrated = 0;
  double _shown = 0;
  double _stillFor = 0;

  double get angle => _shown;
  double get stillTime => _stillFor;
  double get bias => _bias;
  bool get hasAccel => _hasAccel;

  double get _gNorm => math.sqrt(_g[0] * _g[0] + _g[1] * _g[1] + _g[2] * _g[2]);

  void reset() {
    _g.fillRange(0, 3, 0);
    _hasAccel = false;
    _bias = _integrated = _shown = _stillFor = 0;
  }

  /// Guidon droit maintenant : l'angle repart de zéro.
  void center() {
    _integrated = _shown = _stillFor = 0;
  }

  /// Nouvelle mesure de l'accéléromètre (m/s²). Filtrée pour ne garder que la gravité.
  void updateAccel(double x, double y, double z) {
    final a = [x, y, z];
    for (var i = 0; i < 3; i++) {
      _g[i] = _hasAccel ? _g[i] + (a[i] - _g[i]) * 0.1 : a[i];
    }
    _hasAccel = true;
  }

  /// Rotation autour de la verticale (rad/s), positive vers la gauche.
  double yawRate(double wx, double wy, double wz) {
    final n = _gNorm;
    if (!_hasAccel || n < 1) return wz;
    return (wx * _g[0] + wy * _g[1] + wz * _g[2]) / n;
  }

  /// Nouvelle mesure du gyroscope (rad/s) après [dt] secondes ; renvoie l'angle en degrés.
  double updateGyro(double wx, double wy, double wz, double dt) {
    if (dt <= 0) return angle;
    final step = math.min(dt, maxDt);
    final rate = yawRate(wx, wy, wz);

    final still = _hasAccel && rate.abs() < gyroStill && (_gNorm - _gravity).abs() < accelStill;
    _stillFor = still ? _stillFor + step : 0;
    if (still && _stillFor >= minStillForBias && _integrated.abs() <= biasDeadband) {
      _bias += (rate - _bias) * biasLearningRate;
    }

    final deg = (rate - _bias) * step * 180 / math.pi;
    _integrated = (_integrated + deg).clamp(-maxAngle, maxAngle).toDouble();
    _shown += (_integrated - _shown) * step / (smoothing + step);
    return angle;
  }
}
