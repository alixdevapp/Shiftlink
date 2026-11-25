// Envoi des sorties sur Garmin Connect.
//
// Garmin n'ouvre pas son API d'envoi aux petites applis : comme
// python-garminconnect, ShiftLink passe par la connexion de l'appli Garmin Connect mobile.
// Différence : on ne voit jamais ton mot de passe. Tu te connectes sur la page de Garmin
// (dans l'appli), ShiftLink récupère seulement le « ticket » que Garmin renvoie à la fin,
// l'échange contre un jeton, et garde ce jeton sur le téléphone pour les envois suivants.
// Garmin peut changer cette connexion à tout moment : il faudra alors mettre ShiftLink à jour.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Une façon de se connecter : page de Garmin et adresse où elle renvoie le ticket.
class GarminLoginFlow {
  final String clientId;
  final String service;
  final String signInPath;
  const GarminLoginFlow(this.clientId, this.service, this.signInPath);

  /// Connexion de l'appli Garmin Connect mobile (la même que python-garminconnect).
  static const mobile = GarminLoginFlow(
    'GCM_IOS_DARK',
    'https://mobile.integration.garmin.com/gcm/ios',
    '/mobile/sso/en_US/sign-in',
  );

  /// Connexion du site connect.garmin.com, si la première est refusée.
  static const portal = GarminLoginFlow('GarminConnect', 'https://connect.garmin.com/app', '/portal/sso/en-US/sign-in');

  Uri get signInUri =>
      Uri.https('sso.garmin.com', signInPath, {'clientId': clientId, 'service': service});
}

class GarminTokens {
  final String access;
  final String? refresh;
  final String clientId;
  final DateTime expires;
  const GarminTokens({required this.access, required this.refresh, required this.clientId, required this.expires});

  bool get expiresSoon => DateTime.now().isAfter(expires.subtract(const Duration(minutes: 5)));

  Map<String, Object?> toJson() => {
    'access': access,
    'refresh': refresh,
    'clientId': clientId,
    'expires': expires.toIso8601String(),
  };

  static GarminTokens? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return GarminTokens(
        access: m['access'] as String,
        refresh: m['refresh'] as String?,
        clientId: m['clientId'] as String,
        expires: DateTime.parse(m['expires'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

enum GarminUploadStatus { sent, duplicate }

class GarminException implements Exception {
  final int? statusCode;
  final String message;
  const GarminException(this.message, [this.statusCode]);

  /// Le jeton n'est plus accepté : il faut se reconnecter.
  bool get needsLogin => statusCode == 401;
  @override
  String toString() => message;
}

class GarminConnectClient {
  static const tokenUrl = 'https://diauth.garmin.com/di-oauth2-service/oauth/token';
  static const grantType = 'https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket';
  static const clientIds = [
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI',
    'GARMIN_CONNECT_MOBILE_IOS_DI',
  ];
  static const uploadUrl = 'https://connectapi.garmin.com/upload-service/upload';

  static const Map<String, String> _nativeHeaders = {
    'User-Agent': 'GCM-Android-5.23',
    'X-Garmin-User-Agent': 'com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0',
    'X-Garmin-Paired-App-Version': '10861',
    'X-Garmin-Client-Platform': 'Android',
    'X-App-Ver': '10861',
    'X-Lang': 'en',
    'X-GCExperience': 'GC5',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Le ticket Garmin (ST-…) dans une adresse, s'il y en a un.
  /// Aussi dans la réponse JSON de la page de connexion (« serviceTicketId »).
  static String? ticketIn(String text) =>
      RegExp(r'ticket=(ST-[A-Za-z0-9._\-]+)').firstMatch(text)?.group(1) ??
      RegExp(r'serviceTicketId\\?"\s*:\s*\\?"(ST-[A-Za-z0-9._\-]+)').firstMatch(text)?.group(1);

  /// Échange le ticket de connexion contre un jeton d'accès (et de renouvellement).
  static Future<GarminTokens> exchangeTicket(String ticket, GarminLoginFlow flow) async {
    int? last;
    for (final id in clientIds) {
      final (code, body) = await _tokenPost(id, {
        'client_id': id,
        'service_ticket': ticket,
        'grant_type': grantType,
        'service_url': flow.service,
      });
      if (code == 429) throw GarminException('Garmin : trop d’essais, réessaie dans quelques minutes', code);
      if (code != 200) {
        last = code;
        continue;
      }
      final t = _parseTokens(body, id);
      if (t != null) return t;
    }
    throw GarminException('Garmin a refusé la connexion (erreur ${last ?? '?'})', last);
  }

  static Future<GarminTokens> refresh(GarminTokens t) async {
    final r = t.refresh;
    if (r == null) throw const GarminException('Connexion Garmin expirée : reconnecte-toi', 401);
    final (code, body) = await _tokenPost(t.clientId, {
      'grant_type': 'refresh_token',
      'client_id': t.clientId,
      'refresh_token': r,
    });
    if (code == 400 || code == 401) throw const GarminException('Connexion Garmin expirée : reconnecte-toi', 401);
    if (code != 200) throw GarminException('Garmin : erreur $code', code);
    final n = _parseTokens(body, t.clientId);
    if (n == null) throw const GarminException('Garmin : réponse illisible');
    return GarminTokens(access: n.access, refresh: n.refresh ?? r, clientId: n.clientId, expires: n.expires);
  }

  /// Envoie un .fit. Un doublon (sortie déjà sur Garmin) n'est pas une erreur.
  static Future<GarminUploadStatus> upload(GarminTokens t, Uint8List fit, String filename) async {
    final boundary = 'shiftlink${DateTime.now().microsecondsSinceEpoch}';
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Disposition: form-data; name="file"; filename="$safeName"\r\n'))
      ..add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'))
      ..add(fit)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final bytes = body.takeBytes();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(uploadUrl));
      _nativeHeaders.forEach(req.headers.set);
      req.headers.set('Authorization', 'Bearer ${t.access}');
      req.headers.set('Accept', 'application/json');
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      final text = await resp.transform(utf8.decoder).join();
      return statusOf(resp.statusCode, text);
    } finally {
      client.close();
    }
  }

  /// Lit la réponse de Garmin à un envoi.
  static GarminUploadStatus statusOf(int code, String body) {
    if (code == 409 || body.contains('Duplicate Activity')) return GarminUploadStatus.duplicate;
    if (code == 200 || code == 201 || code == 202) return GarminUploadStatus.sent;
    if (code == 401) throw GarminException('Connexion Garmin expirée : reconnecte-toi', code);
    if (code == 403) throw GarminException('Garmin refuse l’envoi (erreur 403)', code);
    throw GarminException('Garmin : erreur $code', code);
  }

  static Future<(int, String)> _tokenPost(String clientId, Map<String, String> form) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(tokenUrl));
      _nativeHeaders.forEach(req.headers.set);
      req.headers.set('Authorization', 'Basic ${base64Encode(utf8.encode('$clientId:'))}');
      req.headers.set('Accept', 'application/json,text/html;q=0.9,*/*;q=0.8');
      req.headers.set('Cache-Control', 'no-cache');
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final data = utf8.encode(Uri(queryParameters: form).query);
      req.contentLength = data.length;
      req.add(data);
      final resp = await req.close().timeout(const Duration(seconds: 30));
      return (resp.statusCode, await resp.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  static GarminTokens? _parseTokens(String body, String fallbackClientId) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final access = m['access_token'] as String?;
      if (access == null || access.isEmpty) return null;
      final jwt = _jwtPayload(access);
      final expiresIn = (m['expires_in'] as num?)?.toInt();
      final exp = (jwt?['exp'] as num?)?.toInt();
      final expires = expiresIn != null
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : exp != null
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          : DateTime.now().add(const Duration(hours: 1));
      return GarminTokens(
        access: access,
        refresh: m['refresh_token'] as String?,
        clientId: (jwt?['client_id'] as String?) ?? fallbackClientId,
        expires: expires,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _jwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
