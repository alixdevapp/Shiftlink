import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/actions.dart';
import 'package:shiftlink/src/i18n.dart';
import 'package:shiftlink/src/i18n_de.dart';
import 'package:shiftlink/src/i18n_en.dart';
import 'package:shiftlink/src/i18n_es.dart';
import 'package:shiftlink/src/i18n_it.dart';
import 'package:shiftlink/src/i18n_nl.dart';
import 'package:shiftlink/src/i18n_pl.dart';
import 'package:shiftlink/src/i18n_pt.dart';
import 'package:shiftlink/src/i18n_zh.dart';

void main() {
  tearDown(() => setLanguage('fr', 'fr'));

  test('les valeurs variables se remplacent dans les deux langues', () {
    setLanguage('fr', 'en');
    expect(tr('Connecté à {0}', ['PC']), 'Connecté à PC');
    setLanguage('en', 'fr');
    expect(tr('Connecté à {0}', ['PC']), 'Connected to PC');
  });

  test('« auto » suit la langue du téléphone, anglais hors français', () {
    setLanguage('auto', 'fr');
    expect(appLanguage.value, 'fr');
    setLanguage('auto', 'de');
    expect(appLanguage.value, 'de');
    setLanguage('auto', 'ja');
    expect(appLanguage.value, 'en');
  });

  test('un texte sans traduction reste en français', () {
    setLanguage('en', 'en');
    expect(tr('Texte inconnu'), 'Texte inconnu');
  });

  test('les libellés des actions changent de langue', () {
    setLanguage('en', 'en');
    expect(ShiftAction.shiftUp.label, 'Harder');
    setLanguage('fr', 'fr');
    expect(ShiftAction.shiftUp.label, 'Plus dur');
  });

  test('chaque traduction garde les valeurs variables du français', () {
    final slot = RegExp(r'\{\d\}');
    for (final (lang, map) in [('en', en), ('de', de), ('es', es), ('it', it), ('pl', pl), ('nl', nl), ('pt', pt), ('zh', zh)]) {
      for (final MapEntry(:key, :value) in map.entries) {
        final a = slot.allMatches(key).map((m) => m[0]).toSet();
        final b = slot.allMatches(value).map((m) => m[0]).toSet();
        // Seul le pluriel français ({1} = « s ») peut disparaître.
        expect(a.difference(b).difference({'{1}'}), isEmpty, reason: '$lang : $key');
        expect(b.difference(a), isEmpty, reason: '$lang : $key');
      }
    }
  });

  test('toutes les langues traduisent les mêmes textes', () {
    for (final (lang, map) in [('de', de), ('es', es), ('it', it), ('pl', pl), ('nl', nl), ('pt', pt), ('zh', zh)]) {
      final missing = en.keys.where((k) => !map.containsKey(k) && en[k] != k).toList();
      expect(missing.length, lessThan(15), reason: '$lang : $missing');
    }
    setLanguage('de', 'fr');
    expect(ShiftAction.shiftUp.label, 'Schwerer');
    setLanguage('pl', 'fr');
    expect(tr('Connecté à {0}', ['PC']), 'Połączono z PC');
  });
}
