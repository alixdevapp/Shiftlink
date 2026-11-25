// N'accepte que les connexions venant du réseau local (Wi-Fi de la maison),
// jamais d'Internet : une adresse IPv6 publique en données mobiles ne doit pas
// pouvoir piloter le trainer ou les vitesses.
import 'dart:io';
import 'dart:typed_data';

class LocalNetwork {
  /// Préfixes /64 des adresses IPv6 publiques du téléphone (même réseau = autorisé).
  final Set<String> _ownPrefixes = {};

  /// Relit les adresses du téléphone. À appeler au démarrage d'un serveur.
  Future<void> refresh() async {
    _ownPrefixes.clear();
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv6)) {
        for (final a in i.addresses) {
          _ownPrefixes.add(prefix64(a.rawAddress));
        }
      }
    } catch (_) {
      // Sans la liste, seules les adresses privées restent autorisées.
    }
  }

  /// La connexion vient-elle du réseau local ?
  bool allows(InternetAddress remote) =>
      isPrivate(remote.rawAddress) || _ownPrefixes.contains(prefix64(remote.rawAddress));

  static String prefix64(Uint8List raw) => raw.length == 16 ? raw.sublist(0, 8).join('.') : '';

  /// Adresse de boucle locale, privée ou de lien local (IPv4 ou IPv6).
  static bool isPrivate(Uint8List raw) {
    if (raw.length == 16) {
      // IPv4 encapsulée (::ffff:a.b.c.d), ce qu'on reçoit sur un serveur IPv6.
      final mapped = raw.sublist(0, 10).every((b) => b == 0) && raw[10] == 0xff && raw[11] == 0xff;
      if (mapped) return isPrivate(raw.sublist(12));
      final loopback = raw.sublist(0, 15).every((b) => b == 0) && raw[15] == 1;
      final uniqueLocal = (raw[0] & 0xfe) == 0xfc; // fc00::/7
      final linkLocal = raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80; // fe80::/10
      return loopback || uniqueLocal || linkLocal;
    }
    if (raw.length != 4) return false;
    final a = raw[0], b = raw[1];
    return a == 10 || a == 127 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
  }
}
