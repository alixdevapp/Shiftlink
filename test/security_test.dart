import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftlink/src/controllers/steering_drivers.dart';
import 'package:shiftlink/src/net/local_network.dart';

void main() {
  bool private(String a) => LocalNetwork.isPrivate(InternetAddress(a).rawAddress);

  test('réseau local : adresses privées acceptées', () {
    for (final a in [
      '192.168.1.20',
      '10.0.0.5',
      '172.20.3.4',
      '127.0.0.1',
      '169.254.1.1',
      '::1',
      'fe80::1',
      'fd12::4',
      '::ffff:192.168.1.9',
    ]) {
      expect(private(a), isTrue, reason: a);
    }
  });

  test('réseau local : adresses publiques refusées', () {
    for (final a in ['8.8.8.8', '172.32.0.1', '100.64.0.1', '2001:4860::8888', '::ffff:8.8.8.8']) {
      expect(private(a), isFalse, reason: a);
    }
  });

  test('IPv6 publique du même réseau /64 acceptée', () {
    final mine = InternetAddress('2a01:cb00:1:2::10').rawAddress;
    final peer = InternetAddress('2a01:cb00:1:2::99').rawAddress;
    final other = InternetAddress('2a01:cb00:1:3::99').rawAddress;
    expect(LocalNetwork.prefix64(mine), LocalNetwork.prefix64(peer));
    expect(LocalNetwork.prefix64(mine) == LocalNetwork.prefix64(other), isFalse);
  });

  test('Sterzo : fichier de codes falsifié refusé', () {
    expect(EliteSterzoDriver.isGenuine(Uint8List(EliteSterzoDriver.codesLength)), isFalse);
    expect(EliteSterzoDriver.isGenuine(Uint8List(10)), isFalse);
  });
}
