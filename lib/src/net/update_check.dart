// Nouvelle version de ShiftLink : ShiftLink n'est pas sur le Play Store, donc personne
// n'est prévenu d'une mise à jour. Si on l'active, ShiftLink lit à chaque ouverture la
// dernière release du dépôt GitHub (rien d'autre n'est envoyé que la requête elle-même).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dépôt GitHub où sont publiés les APK (« propriétaire/nom »). Vide : vérification masquée.
const updateRepo = 'alixdevapp/Shiftlink';

class UpdateInfo {
  /// Version proposée, sans le « v » (ex. 2.13.0).
  final String version;

  /// Page à ouvrir pour télécharger : l'APK s'il y en a un, sinon la page de la release.
  final String url;
  const UpdateInfo(this.version, this.url);
}

/// Compare deux versions « 2.12.4 » : négatif si [a] est plus ancienne que [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[+\-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Lit la réponse de l'API GitHub « releases/latest ». null si rien de plus récent que [current].
UpdateInfo? parseLatestRelease(String body, String current) {
  final Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (j is! Map || j['tag_name'] is! String) return null;
  if (j['draft'] == true || j['prerelease'] == true) return null;
  final version = (j['tag_name'] as String).replaceFirst(RegExp(r'^[vV]'), '').trim();
  if (!RegExp(r'^\d+\.\d+').hasMatch(version) || compareVersions(version, current) <= 0) return null;
  String? url;
  if (j['assets'] is List) {
    for (final a in j['assets'] as List) {
      if (a is Map && '${a['name']}'.toLowerCase().endsWith('.apk') && a['browser_download_url'] is String) {
        url = a['browser_download_url'] as String;
        break;
      }
    }
  }
  url ??= j['html_url'] is String ? j['html_url'] as String : null;
  if (url == null || !url.startsWith('https://github.com/')) return null;
  return UpdateInfo(version, url);
}

/// Demande la dernière release à GitHub. null : pas de nouvelle version, ou pas de réseau.
Future<UpdateInfo?> fetchUpdate(String current, {String repo = updateRepo}) async {
  if (repo.isEmpty) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'ShiftLink');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    return parseLatestRelease(await resp.transform(utf8.decoder).join(), current);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Ouvre [url] dans le navigateur. Faux si rien ne s'est ouvert.
Future<bool> openLink(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Vrai si [url] est un APK publié dans les releases de [repo] (seule source acceptée
/// pour une mise à jour installée depuis l'appli).
bool isTrustedApkUrl(String url, {String repo = updateRepo}) {
  if (repo.isEmpty) return false;
  final prefix = 'https://github.com/$repo/releases/download/'.toLowerCase();
  return url.toLowerCase().startsWith(prefix) && url.toLowerCase().endsWith('.apk') && !url.contains('..');
}

/// Résultat d'une mise à jour lancée depuis l'appli.
enum UpdateResult {
  /// L'installeur d'Android est ouvert.
  started,

  /// Android demande d'autoriser ShiftLink à installer des applis : réglage ouvert.
  needsPermission,

  /// Pas d'APK à télécharger : la page de la release est ouverte dans le navigateur.
  openedInBrowser,

  /// Téléchargement ou installation impossible.
  failed,
}

const _updateChannel = MethodChannel('shiftlink/update');

/// Télécharge l'APK de [u] puis ouvre l'installeur d'Android. [onProgress] reçoit 0..1
/// (ou null si la taille est inconnue). Android vérifie que l'APK est signé avec la même
/// clé que l'appli installée avant de la remplacer.
Future<UpdateResult> downloadAndInstall(UpdateInfo u, {void Function(double?)? onProgress}) async {
  if (!isTrustedApkUrl(u.url)) {
    return await openLink(u.url) ? UpdateResult.openedInBrowser : UpdateResult.failed;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/ShiftLink-${u.version.replaceAll(RegExp(r'[^0-9.]'), '')}.apk');
    final req = await client.getUrl(Uri.parse(u.url));
    req.headers.set('User-Agent', 'ShiftLink');
    final resp = await req.close().timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return UpdateResult.failed;
    final total = resp.contentLength;
    var got = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(total > 0 ? got / total : null);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && got != total) return UpdateResult.failed;
    final r = await _updateChannel.invokeMethod<String>('install', {'path': file.path});
    return switch (r) {
      'started' => UpdateResult.started,
      'permission' => UpdateResult.needsPermission,
      _ => UpdateResult.failed,
    };
  } catch (_) {
    return UpdateResult.failed;
  } finally {
    client.close();
  }
}
