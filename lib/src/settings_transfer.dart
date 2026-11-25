// Sauvegarde et partage des réglages : fichier JSON ou QR code, sans compte.
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:shared_preferences/shared_preferences.dart';

class SettingsTransfer {
  static const format = 'ShiftLink';
  static const version = 1;

  /// Préfixe des réglages compressés (QR code, presse-papiers).
  static const compactPrefix = 'SL1:';

  /// Limites de sécurité à l'import : un fichier piégé ne doit pas tout remplir.
  static const maxBytes = 256 * 1024;
  static const maxKeys = 500;

  /// Propres à ce téléphone : jamais exportés ni importés.
  static const _excluded = {
    'onboarded',
    'routes',
    'fanId',
    'fanName',
    'trainerId',
    'trainerName',
    'kbHost',
    'sterzoCodes',
    'proxyEnabled',
    'hrId',
    'hrName',
    'garminTokens', // jeton de connexion Garmin : reste sur ce téléphone
    'mywhooshSession', // session MyWhoosh : idem
    'mywhooshDevice',
    'mywhooshSent',
    'mywhooshSince',
    'mywhooshSent.intervals',
  };
  // Parcours, fantômes et reprises : trop gros pour un QR code, et propres à ce téléphone.
  static const _excludedPrefixes = ['taps.', 'ghost.', 'routePos.'];

  static bool shared(String key) => !_excluded.contains(key) && !_excludedPrefixes.any(key.startsWith);

  /// Tous les réglages partageables, en JSON lisible.
  static String export(SharedPreferences prefs) {
    final values = <String, Object>{
      for (final k in prefs.getKeys().toList()..sort())
        if (shared(k) && prefs.get(k) != null) k: prefs.get(k)!,
    };
    return const JsonEncoder.withIndent('  ').convert({'format': format, 'version': version, 'settings': values});
  }

  /// Version courte pour un QR code : JSON compressé en base64.
  static String compact(String json) => compactPrefix + base64Url.encode(gzip.encode(utf8.encode(json)));

  /// Lit un fichier, un texte collé ou un QR code. Lève [FormatException] si ce n'est pas un réglage ShiftLink.
  static Map<String, Object> parse(String text) {
    var raw = text.trim();
    if (raw.startsWith(compactPrefix)) {
      final bytes = base64Url.decode(raw.substring(compactPrefix.length));
      if (bytes.length > maxBytes) throw const FormatException('Réglages trop volumineux');
      final unzipped = gzip.decode(bytes);
      if (unzipped.length > maxBytes) throw const FormatException('Réglages trop volumineux');
      raw = utf8.decode(unzipped);
    }
    if (raw.length > maxBytes) throw const FormatException('Réglages trop volumineux');
    final Object? data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Ce n’est pas un fichier de réglages ShiftLink');
    }
    if (data is! Map || data['format'] != format || data['settings'] is! Map) {
      throw const FormatException('Ce n’est pas un fichier de réglages ShiftLink');
    }
    if ((data['version'] as num? ?? 0) > version) {
      throw const FormatException('Réglages faits avec une version plus récente de ShiftLink : mets l’appli à jour');
    }
    final settings = data['settings'] as Map;
    if (settings.length > maxKeys) throw const FormatException('Trop de réglages dans ce fichier');
    final out = <String, Object>{};
    for (final e in settings.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || !shared(k) || k.length > 200) continue;
      if (v is bool || v is num || v is String) {
        out[k] = v as Object;
      } else if (v is List && v.every((x) => x is String)) {
        out[k] = v.cast<String>();
      }
    }
    return out;
  }

  /// Écrit les réglages importés. Les réglages absents du fichier restent tels quels.
  static Future<int> apply(SharedPreferences prefs, Map<String, Object> settings) async {
    var n = 0;
    for (final e in settings.entries) {
      final v = e.value;
      final ok = switch (v) {
        final bool b => await prefs.setBool(e.key, b),
        final int i => await prefs.setInt(e.key, i),
        final double d => await prefs.setDouble(e.key, d),
        final String s => await prefs.setString(e.key, s),
        final List<String> l => await prefs.setStringList(e.key, l),
        _ => false,
      };
      if (ok) n++;
    }
    return n;
  }
}
