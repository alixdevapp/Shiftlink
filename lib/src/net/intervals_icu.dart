// Récupère les séances prévues sur Intervals.icu grâce à son API publique.
// Il te faut une clé d'API (intervals.icu › Settings › Developer) et ton identifiant d'athlète.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../trainer/workout.dart';

class IntervalsIcuEvent {
  final String id;
  final String name;
  final DateTime date;
  const IntervalsIcuEvent(this.id, this.name, this.date);
}

class IntervalsIcuClient {
  final String athleteId;
  final String apiKey;
  final int ftp;
  IntervalsIcuClient({required this.athleteId, required this.apiKey, required this.ftp});

  Map<String, String> get _headers => {
    'Authorization': 'Basic ${base64Encode(utf8.encode('API_KEY:$apiKey'))}',
    'Accept': 'application/json',
  };

  /// Les séances prévues sur les 30 prochains jours (ou [daysAhead] jours).
  Future<List<IntervalsIcuEvent>> listUpcomingWorkouts({int daysAhead = 30}) async {
    final uri = Uri.parse(
      'https://intervals.icu/api/v1/athlete/$athleteId/events'
      '?oldest=today&newest=today%2B${daysAhead}d&category=WORKOUT',
    );
    final body = await _get(uri);
    final decoded = jsonDecode(body);
    if (decoded is! List) return [];
    final out = <IntervalsIcuEvent>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final id = '${e['id'] ?? ''}';
      if (id.isEmpty) continue;
      final date = DateTime.tryParse('${e['start_date_local'] ?? ''}') ?? DateTime.now();
      final name = '${e['name'] ?? 'Séance'}';
      out.add(IntervalsIcuEvent(id, name, date));
    }
    return out;
  }

  /// Télécharge et lit la séance [eventId] au format .zwo.
  Future<Workout?> downloadWorkout(IntervalsIcuEvent event) async {
    final uri = Uri.parse('https://intervals.icu/api/v1/athlete/$athleteId/events/${event.id}/downloadzwo');
    final body = await _get(uri);
    return Workout.parseZwo(body, fallbackName: event.name);
  }

  /// Envoie une sortie (.fit) dans les activités Intervals.icu.
  Future<void> uploadActivity(File fit) async => uploadBytes(await fit.readAsBytes(), fit.uri.pathSegments.last);

  Future<void> uploadBytes(Uint8List fit, String name) async {
    final uri = Uri.parse('https://intervals.icu/api/v1/athlete/$athleteId/activities');
    final boundary = 'shiftlink${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Disposition: form-data; name="file"; filename="$name"\r\n'))
      ..add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'))
      ..add(fit)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final bytes = body.takeBytes();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      _headers.forEach(req.headers.set);
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close().timeout(const Duration(seconds: 40));
      await resp.drain<void>();
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw IntervalsIcuException(resp.statusCode, 'Intervals.icu : erreur ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<String> _get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      _headers.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        throw IntervalsIcuException(resp.statusCode, 'Intervals.icu : erreur ${resp.statusCode}');
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}

class IntervalsIcuException implements Exception {
  final int statusCode;
  final String message;
  const IntervalsIcuException(this.statusCode, this.message);
  @override
  String toString() => message;
}
