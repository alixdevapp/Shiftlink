// Ton compte MyWhoosh : la liste de tes sorties et leur fichier .fit d'origine.
// MyWhoosh n'a pas d'API publique : ShiftLink utilise celle de l'appli MyWhoosh (connexion,
// liste des activités, lien de téléchargement). Elle peut changer sans prévenir.
// Ton mot de passe sert à la connexion puis est oublié : seul le jeton de session est gardé.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class MyWhooshSession {
  final String token;
  final String whooshId;
  const MyWhooshSession(this.token, this.whooshId);

  String toJson() => jsonEncode({'token': token, 'whooshId': whooshId});

  static MyWhooshSession? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return MyWhooshSession(m['token'] as String, m['whooshId'] as String);
    } catch (_) {
      return null;
    }
  }
}

class MyWhooshActivity {
  final String id;
  final String name;
  final DateTime? start;

  /// Référence du fichier .fit chez MyWhoosh (vide : pas de fichier).
  final String fileRef;
  const MyWhooshActivity({required this.id, required this.name, required this.start, required this.fileRef});

  bool get downloadable => fileRef.isNotEmpty;
}

class MyWhooshException implements Exception {
  final String message;
  final int? statusCode;
  const MyWhooshException(this.message, [this.statusCode]);

  /// Session expirée ou mot de passe refusé : il faut se reconnecter.
  bool get needsLogin => statusCode == 401;
  @override
  String toString() => message;
}

class MyWhooshAccount {
  static const loginUrl = 'https://services.mywhoosh.com/http-service/api/login';
  static const activitiesUrl = 'https://service14.mywhoosh.com/v2/rider/profile/activities';
  static const downloadUrl = 'https://service14.mywhoosh.com/v2/rider/profile/download-activity-file';
  static const maxFitBytes = 64 * 1024 * 1024;

  /// Identifiant d'appareil au hasard (format UUID), demandé par la connexion de MyWhoosh.
  static String newDeviceId([Random? r]) {
    final rnd = r ?? Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }

  static Future<MyWhooshSession> login(String email, String password, String deviceId) async {
    final res = await _post(loginUrl, null, {
      'Username': email.trim(),
      'Password': password,
      'Platform': 'Android',
      'Action': 1001,
      'CorrelationId': newDeviceId(),
      'DeviceId': deviceId,
      'Authorization': '',
    });
    return parseLogin(res);
  }

  static MyWhooshSession parseLogin(Object? res) {
    if (res is! Map || res['Success'] != true) {
      throw const MyWhooshException('MyWhoosh refuse l’e-mail ou le mot de passe', 401);
    }
    final token = '${res['AccessToken'] ?? ''}';
    final id = res['WhooshId'];
    final whooshId = id == null ? '' : '$id';
    if (token.isEmpty || whooshId.isEmpty || whooshId == 'null') {
      throw const MyWhooshException('MyWhoosh : réponse inattendue');
    }
    return MyWhooshSession(token, whooshId);
  }

  /// Une page de sorties, la plus récente en premier.
  static Future<List<MyWhooshActivity>> activities(MyWhooshSession s, {int page = 1, int limit = 20}) async =>
      parseActivities(await _post(activitiesUrl, s.token, {'page': page, 'limit': limit, 'sortDate': 'DESC'}));

  /// Lit la liste : tableau seul, ou dans « data », ou dans « data.results ».
  static List<MyWhooshActivity> parseActivities(Object? res) {
    Object? cur = res;
    for (var depth = 0; depth < 3 && cur is Map; depth++) {
      if (cur['error'] == true || cur['Success'] == false) throw const MyWhooshException('MyWhoosh : liste refusée');
      cur = cur['results'] ?? cur['data'];
    }
    if (cur is! List) throw const MyWhooshException('MyWhoosh : réponse inattendue');
    final out = <MyWhooshActivity>[];
    for (final e in cur) {
      if (e is! Map) continue;
      String first(List<String> keys) {
        for (final k in keys) {
          final v = e[k];
          if (v != null && '$v'.isNotEmpty && '$v' != 'null') return '$v';
        }
        return '';
      }

      final id = first(['id', '_id']);
      if (id.isEmpty) continue;
      out.add(
        MyWhooshActivity(
          id: id,
          name: first(['name', 'title']),
          start: parseTime(e['date'] ?? e['startTime'] ?? e['createdAt'] ?? e['timestamp']),
          fileRef: first(['activityFileId']),
        ),
      );
    }
    return out;
  }

  static DateTime? parseTime(Object? v) {
    if (v == null) return null;
    if (v is num) {
      final n = v.toInt();
      // Secondes ou millisecondes depuis 1970.
      return DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n, isUtc: true).toLocal();
    }
    final s = '$v';
    final n = int.tryParse(s);
    if (n != null) return parseTime(n);
    return DateTime.tryParse(s)?.toLocal();
  }

  /// Le .fit d'origine de la sortie.
  static Future<Uint8List> downloadFit(MyWhooshSession s, MyWhooshActivity a) async {
    if (!a.downloadable) throw const MyWhooshException('Cette sortie MyWhoosh n’a pas de fichier');
    final res = await _post(downloadUrl, s.token, {'key': s.whooshId, 'fileId': a.fileRef});
    final link = res is Map && res['error'] != true ? '${res['data'] ?? ''}' : '';
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const MyWhooshException('MyWhoosh ne donne pas le fichier de cette sortie');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) throw MyWhooshException('MyWhoosh : téléchargement refusé (${resp.statusCode})');
      final b = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        b.add(chunk);
        if (b.length > maxFitBytes) throw const MyWhooshException('Fichier trop volumineux.');
      }
      return b.takeBytes();
    } finally {
      client.close();
    }
  }

  static Future<Object?> _post(String url, String? token, Map<String, Object?> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.followRedirects = false; // le mot de passe ne part que vers cette adresse
      req.headers.contentType = ContentType.json;
      req.headers.set('Accept', 'application/json');
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      final data = utf8.encode(jsonEncode(body));
      req.contentLength = data.length;
      req.add(data);
      final resp = await req.close().timeout(const Duration(seconds: 40));
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 401) throw const MyWhooshException('Connexion MyWhoosh expirée : reconnecte-toi', 401);
      if (resp.statusCode == 429) throw const MyWhooshException('MyWhoosh : trop d’essais, réessaie plus tard', 429);
      if (resp.statusCode < 200 || resp.statusCode > 299) {
        throw MyWhooshException('MyWhoosh : erreur ${resp.statusCode}', resp.statusCode);
      }
      try {
        return jsonDecode(text);
      } catch (_) {
        throw const MyWhooshException('MyWhoosh : réponse inattendue');
      }
    } finally {
      client.close();
    }
  }
}
