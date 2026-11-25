// Mail vers l'équipe ShiftLink : ouvre l'appli mail, adresse, sujet et texte déjà remplis.
// Rien ne part tout seul : la personne appuie elle-même sur Envoyer.
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Adresse qui reçoit les problèmes et les manettes inconnues.
const supportEmail = 'shiftlink.help@gmail.com';

/// Ouvre l'appli mail. Faux si aucune appli mail ne s'est ouverte.
Future<bool> openSupportMail(String subject, String body) async {
  final uri = Uri.parse(
    'mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Repli sans appli mail : le partage d'Android, avec l'adresse en tête du texte.
Future<void> shareForSupport(String subject, String body) =>
    SharePlus.instance.share(ShareParams(text: '$supportEmail\n\n$body', subject: subject));
