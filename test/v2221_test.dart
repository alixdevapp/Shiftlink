import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/net/update_check.dart';

void main() {
  test('la vérification des mises à jour vise le dépôt GitHub de ShiftLink', () {
    expect(updateRepo, 'alixdevapp/Shiftlink');
  });

  test('seul un APK des releases du dépôt est installé depuis l’appli', () {
    const ok = 'https://github.com/alixdevapp/Shiftlink/releases/download/v2.22.1/ShiftLink-2.22.1.apk';
    expect(isTrustedApkUrl(ok), isTrue);
    expect(isTrustedApkUrl(ok.toLowerCase()), isTrue);
    expect(isTrustedApkUrl('https://github.com/autre/Shiftlink/releases/download/v1/ShiftLink.apk'), isFalse);
    expect(isTrustedApkUrl('https://github.com/alixdevapp/Shiftlink/releases/tag/v2.22.1'), isFalse);
    expect(isTrustedApkUrl('https://evil.example/alixdevapp/Shiftlink/releases/download/v1/x.apk'), isFalse);
    expect(isTrustedApkUrl('https://github.com/alixdevapp/Shiftlink/releases/download/../../x.apk'), isFalse);
  });

  test('la release la plus récente donne le lien direct vers l’APK', () {
    const body = '{"tag_name":"v2.22.1","draft":false,"prerelease":false,'
        '"html_url":"https://github.com/alixdevapp/Shiftlink/releases/tag/v2.22.1",'
        '"assets":[{"name":"ShiftLink-2.22.1.apk","browser_download_url":'
        '"https://github.com/alixdevapp/Shiftlink/releases/download/v2.22.1/ShiftLink-2.22.1.apk"}]}';
    final u = parseLatestRelease(body, '2.22.0');
    expect(u?.version, '2.22.1');
    expect(isTrustedApkUrl(u!.url), isTrue);
    expect(parseLatestRelease(body, '2.22.1'), isNull);
  });
}
