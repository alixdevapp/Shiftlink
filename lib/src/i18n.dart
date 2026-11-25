// Traduction : le texte français sert de clé, chaque langue a son fichier i18n_xx.dart.
// Les valeurs variables s'écrivent {0}, {1}… : tr('Connecté à {0}', [nom]).
import 'package:flutter/foundation.dart';

import 'i18n_de.dart';
import 'i18n_en.dart';
import 'i18n_es.dart';
import 'i18n_it.dart';
import 'i18n_nl.dart';
import 'i18n_pl.dart';
import 'i18n_pt.dart';
import 'i18n_zh.dart';

/// Langues proposées, avec leur nom dans leur propre langue.
const languageNames = {
  'fr': 'Français',
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'it': 'Italiano',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'pt': 'Português',
  'zh': '简体中文',
};

const Map<String, Map<String, String>> _translations = {
  'en': en,
  'de': de,
  'es': es,
  'it': it,
  'pl': pl,
  'nl': nl,
  'pt': pt,
  'zh': zh,
};

/// Langue de l'interface, un code de [languageNames].
final ValueNotifier<String> appLanguage = ValueNotifier('fr');

/// Choisit la langue d'après le réglage (« auto » = celle du téléphone, l'anglais si elle n'est pas proposée).
void setLanguage(String setting, String systemLanguage) {
  final lang = setting == 'auto' ? systemLanguage : setting;
  appLanguage.value = languageNames.containsKey(lang) ? lang : 'en';
}

/// Texte traduit ; sans traduction, l'anglais puis le français.
String tr(String fr, [List<Object?> args = const []]) {
  final lang = appLanguage.value;
  var s = lang == 'fr' ? fr : (_translations[lang]?[fr] ?? en[fr] ?? fr);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
