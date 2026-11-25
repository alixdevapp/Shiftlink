// Manette inconnue : ShiftLink apprend ses boutons en regardant ce qu'elle envoie.
// Méthode propre à ShiftLink : on écoute toutes les caractéristiques « notify »,
// on note la trame envoyée à chaque appui (en ignorant les octets qui changent
// d'un appui à l'autre, comme un compteur) et la trame de relâchement si elle existe.
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'driver.dart';

/// Une trame reconnue : sur quelle caractéristique, quels octets, et lesquels comparer.
class LearnedFrame {
  final String characteristic;
  final List<int> bytes;

  /// true = octet à comparer, false = octet qui varie (compteur, horodatage…).
  final List<bool> mask;

  const LearnedFrame(this.characteristic, this.bytes, this.mask);

  bool matches(String char, List<int> data) {
    if (char != characteristic || data.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (mask[i] && data[i] != bytes[i]) return false;
    }
    return true;
  }

  /// Nombre d'octets comparés : une trame trop « floue » ne doit pas servir.
  int get fixedBytes => mask.where((m) => m).length;

  /// Construit la trame à partir de plusieurs exemples identiques en longueur.
  static LearnedFrame? fromSamples(String char, List<List<int>> samples) {
    if (samples.isEmpty) return null;
    final len = samples.first.length;
    if (samples.any((s) => s.length != len)) return null;
    final mask = [for (var i = 0; i < len; i++) samples.every((s) => s[i] == samples.first[i])];
    return LearnedFrame(char, List.of(samples.first), mask);
  }

  Map<String, Object> toJson() => {'c': characteristic, 'b': toHex(bytes), 'm': mask.map((m) => m ? '1' : '0').join()};

  static LearnedFrame fromJson(Map<String, Object?> j) {
    final hex = '${j['b']}';
    final bytes = [for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    final m = '${j['m']}';
    return LearnedFrame('${j['c']}', bytes, [for (var i = 0; i < bytes.length; i++) i < m.length && m[i] == '1']);
  }
}

class LearnedButton {
  final String id;
  final String label;
  final LearnedFrame frame;
  const LearnedButton(this.id, this.label, this.frame);

  Map<String, Object> toJson() => {'id': id, 'label': label, 'f': frame.toJson()};
  static LearnedButton fromJson(Map<String, Object?> j) =>
      LearnedButton('${j['id']}', '${j['label']}', LearnedFrame.fromJson((j['f'] as Map).cast()));
}

/// Ce que ShiftLink a appris d'une manette.
class LearnedProfile {
  final String name;
  final List<Subscription> subscriptions;
  final List<LearnedButton> buttons;

  /// Trames « tout relâché », par caractéristique. Vide si la manette ne signale pas le relâchement.
  final List<LearnedFrame> idle;

  const LearnedProfile({required this.name, required this.subscriptions, required this.buttons, this.idle = const []});

  Map<String, Object> toJson() => {
    'name': name,
    'subs': [
      for (final s in subscriptions) {'s': s.service.str128, 'c': s.characteristic.str128},
    ],
    'buttons': [for (final b in buttons) b.toJson()],
    'idle': [for (final f in idle) f.toJson()],
  };

  static LearnedProfile fromJson(Map<String, Object?> j) => LearnedProfile(
    name: '${j['name']}',
    subscriptions: [
      for (final s in (j['subs'] as List? ?? const []).cast<Map<String, Object?>>())
        Subscription(Guid('${s['s']}'), Guid('${s['c']}')),
    ],
    buttons: [
      for (final b in (j['buttons'] as List? ?? const []).cast<Map<String, Object?>>())
        LearnedButton.fromJson(b.cast()),
    ],
    idle: [
      for (final f in (j['idle'] as List? ?? const []).cast<Map<String, Object?>>()) LearnedFrame.fromJson(f.cast()),
    ],
  );
}

/// Pilote d'une manette apprise.
class LearnedDriver extends ControllerDriver {
  final LearnedProfile profile;
  LearnedDriver(this.profile);

  @override
  String get typeId => 'learned.${profile.name}';

  @override
  String get label => profile.name;

  @override
  List<ControllerButton> get buttons => [for (final b in profile.buttons) ControllerButton(b.id, b.label)];

  @override
  Map<String, String> get defaultClicks => {
    if (profile.buttons.isNotEmpty) profile.buttons[0].id: 'shiftUp',
    if (profile.buttons.length > 1) profile.buttons[1].id: 'shiftDown',
  };

  @override
  bool get reportsRelease => profile.idle.isNotEmpty;

  @override
  List<Subscription> get subscriptions => profile.subscriptions;

  @override
  List<ButtonEvent> decode(Guid characteristic, Uint8List bytes) {
    final c = characteristic.str128;
    for (final b in profile.buttons) {
      if (b.frame.matches(c, bytes)) return reportsRelease ? diffState({b.id}) : tap(b.id);
    }
    if (profile.idle.any((f) => f.matches(c, bytes))) return diffState({});
    return const [];
  }
}

/// La logique d'apprentissage, sans Bluetooth (testable).
class ControllerLearner {
  /// Trames reçues pendant le calme : caractéristiques bavardes à ignorer, trames de repos.
  final Map<String, List<List<int>>> _quiet = {};
  final Map<String, List<List<int>>> _capture = {};
  bool _quietPhase = false;
  bool _capturing = false;

  final List<LearnedButton> buttons = [];
  final Map<String, LearnedFrame> _idle = {};

  void startQuiet() {
    _quiet.clear();
    _quietPhase = true;
  }

  void endQuiet() => _quietPhase = false;

  /// Caractéristiques qui envoient des trames différentes sans qu'on touche à rien.
  Set<String> get noisy => {
    for (final e in _quiet.entries)
      if (e.value.any((f) => !_same(f, e.value.first))) e.key,
  };

  void startButton() {
    _capture.clear();
    _capturing = true;
  }

  void add(String char, List<int> bytes) {
    if (_quietPhase) (_quiet[char] ??= []).add(List.of(bytes));
    if (_capturing) (_capture[char] ??= []).add(List.of(bytes));
  }

  /// Trames reçues pour le bouton en cours (pour l'affichage).
  int get captured => _capture.values.fold(0, (a, l) => a + l.length);

  /// Termine la capture d'un bouton appuyé [presses] fois. Renvoie une raison d'échec, ou null si appris.
  String? finishButton(String id, String label, {int presses = 3}) {
    _capturing = false;
    // La caractéristique la plus active, hors caractéristiques bavardes.
    final candidates = _capture.entries.where((e) => !noisy.contains(e.key)).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (candidates.isEmpty) return 'nothing';
    final char = candidates.first.key;
    final frames = candidates.first.value;
    // Le repos connu (trame du calme) sépare les appuis.
    final rest = _quiet[char]?.firstOrNull;
    List<List<int>> pressFrames;
    List<List<int>> releaseFrames = [];
    if (rest != null) {
      pressFrames = frames.where((f) => !_same(f, rest)).toList();
      releaseFrames = frames.where((f) => _same(f, rest)).toList();
    } else if (frames.length >= presses * 2) {
      // Appui, relâchement, appui, relâchement…
      pressFrames = [for (var i = 0; i < frames.length; i += 2) frames[i]];
      releaseFrames = [for (var i = 1; i < frames.length; i += 2) frames[i]];
      // On garde ce découpage seulement si appui et relâchement se distinguent bien.
      final p = LearnedFrame.fromSamples(char, pressFrames);
      final r = LearnedFrame.fromSamples(char, releaseFrames);
      if (p == null || r == null || _overlap(p, r)) {
        pressFrames = frames;
        releaseFrames = [];
      }
    } else {
      pressFrames = frames;
    }
    // Certaines manettes répètent la trame tant qu'on appuie : on garde les trames distinctes du repos.
    if (pressFrames.length < presses) return 'few';
    final frame = LearnedFrame.fromSamples(char, pressFrames);
    if (frame == null || frame.fixedBytes == 0) return 'unstable';
    if (buttons.any((b) => b.frame.characteristic == char && _overlap(b.frame, frame))) return 'same';
    buttons.add(LearnedButton(id, label, frame));
    final idleSamples = releaseFrames.isNotEmpty ? releaseFrames : (rest != null ? [rest] : <List<int>>[]);
    if (idleSamples.isNotEmpty) {
      final f = LearnedFrame.fromSamples(char, idleSamples);
      if (f != null) _idle[char] = f;
    }
    return null;
  }

  /// Supprime le dernier bouton appris (pour recommencer).
  void undo() {
    if (buttons.isNotEmpty) buttons.removeLast();
  }

  LearnedProfile profile(String name, List<Subscription> subs) {
    final used = {for (final b in buttons) b.frame.characteristic};
    return LearnedProfile(
      name: name,
      subscriptions: subs.where((s) => used.contains(s.characteristic.str128)).toList(),
      buttons: List.of(buttons),
      idle: [
        for (final e in _idle.entries)
          if (used.contains(e.key)) e.value,
      ],
    );
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Deux boutons qu'on ne saurait pas distinguer.
  static bool _overlap(LearnedFrame a, LearnedFrame b) {
    if (a.bytes.length != b.bytes.length) return false;
    for (var i = 0; i < a.bytes.length; i++) {
      if (a.mask[i] && b.mask[i] && a.bytes[i] != b.bytes[i]) return false;
    }
    return true;
  }
}
