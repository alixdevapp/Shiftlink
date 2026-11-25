// Reconnaissance des manettes à partir des annonces Bluetooth.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'driver.dart';
import 'simple_drivers.dart';
import 'steering_drivers.dart';
import 'tacx_neo_bike.dart';
import 'zwift_drivers.dart';

/// Toutes les manettes reconnues, pour l'écran d'aide.
const supportedControllers = [
  'ThinkRider VS200',
  'CYCPLUS BC2',
  'CYCPLUS T7 (manettes du vélo, bêta)',
  'Zwift Click (1re génération)',
  'Zwift Play',
  'Zwift Ride et Ride V2',
  'Zwift Click v2 (côté droit seul : sans Zwift)',
  'Zwift Play (firmware 2)',
  'Elite Square',
  'Elite Rizer (direction et pente, bêta)',
  'WHEELTOP EDS (OX, TX, bêta)',
  'Shimano Di2 (canaux D-Fly)',
  'SRAM AXS',
  'Wahoo KICKR Bike, KICKR Bike Shift et Pro',
  'Tacx NEO Bike, Smart et Plus (manettes et boutons, bêta)',
  'Elite Sterzo Smart (direction)',
  'Wahoo KICKR Climb (pente réelle, bêta, dans les accessoires)',
  'Ce téléphone sur le guidon (direction, option dans les réglages)',
  'Télécommandes Bluetooth, manettes de jeu (8BitDo Micro…) et claviers (option dans les réglages)',
  'Magene Onelap Key (5 boutons, bêta)',
  'Autres manettes Bluetooth (Magene, LTWOO, Stages SB20…) : ShiftLink apprend leurs boutons, à essayer',
];

/// Zwift Click v2 : n'utiliser que le côté droit, qui n'a pas besoin d'être déverrouillé dans Zwift.
bool clickV2RightOnly = false;

/// Résultat de l'identification d'une annonce Bluetooth.
class Match {
  final ControllerDriver? driver;

  /// Raison pour laquelle l'appareil est reconnu mais ignoré.
  final String? unsupportedReason;

  const Match.driver(ControllerDriver this.driver) : unsupportedReason = null;
  const Match.unsupported(String this.unsupportedReason) : driver = null;
}

/// Service public « Cycling Power ».
final cyclingPowerService = Guid('1818');

/// Pédalier Shimano à capteur de puissance : nom « FCR…P », « FC-R…-P » ou
/// service E-TUBE annoncé avec le service Cycling Power.
bool isShimanoPowerMeter(String upperName, List<Guid> services) {
  final compact = upperName.replaceAll('-', '');
  if (RegExp(r'^FC[A-Z]?\d{3,4}P').hasMatch(compact)) return true;
  final etube = services.contains(ShimanoDi2Driver.service) || services.contains(ShimanoDi2Driver.serviceAlt);
  return etube && services.contains(cyclingPowerService);
}

/// Manette Elite Square : son service, ou un nom « SQUARE… ». Les lecteurs de cartes
/// bancaires Square (« Square Reader », « Square Terminal »…) ont aussi ce nom : on les écarte.
bool looksLikeEliteSquare(String upperName, List<Guid> services) {
  if (services.contains(EliteSquareDriver.service)) return true;
  if (!upperName.startsWith('SQUARE')) return false;
  return !RegExp(r'^SQUARE[\s_-]*(READER|TERMINAL|REGISTER|STAND|KIOSK|POS|HANDHELD)').hasMatch(upperName);
}

/// Identifie la manette correspondant à une annonce, ou null.
Match? identify(ScanResult r) {
  final adv = r.advertisementData;
  final name = (adv.advName.isNotEmpty ? adv.advName : r.device.platformName).toUpperCase();
  final services = adv.serviceUuids;

  // Capteurs de puissance qui exposent des services similaires.
  if (name.startsWith('ASSIOMA') || name.startsWith('QUARQ') || name.startsWith('POWERCRANK')) return null;
  // Pédaliers Shimano à capteur de puissance (FC-R8100-P, annoncé « FCR8100P… ») : ils
  // annoncent le service E-TUBE comme un Di2, mais ce sont des capteurs de puissance.
  if (isShimanoPowerMeter(name, services)) return null;

  // Le vélo Tacx annonce aussi FTMS : on le reconnaît à son nom, avant tout le reste.
  if (TacxNeoBikeDriver.matchesName(name)) return Match.driver(TacxNeoBikeDriver());
  if (name.startsWith('THINK VS') || services.contains(ThinkRiderVs200Driver.service)) {
    return Match.driver(ThinkRiderVs200Driver());
  }
  if (OnelapKeyDriver.matchesName(name)) return Match.driver(OnelapKeyDriver());
  if (name.startsWith('CYCPLUS') && name.contains('BC2')) return Match.driver(CycplusBc2Driver());
  if (CycplusT7Driver.matchesName(name)) return Match.driver(CycplusT7Driver());
  // Le Sterzo et le Rizer partagent le service Elite du Square : on les reconnaît à leur nom.
  if (name.startsWith('STERZO')) return Match.driver(EliteSterzoDriver());
  if (name.startsWith('RIZER')) return Match.driver(EliteRizerDriver());
  if (WheeltopEdsDriver.typeFromAdvertisement(adv.manufacturerData) case final type?) {
    return Match.driver(WheeltopEdsDriver(type));
  }
  if (looksLikeEliteSquare(name, services)) {
    return Match.driver(EliteSquareDriver());
  }
  if (name.contains('KICKR BIKE') || services.contains(WahooKickrBikeDriver.service)) {
    return Match.driver(WahooKickrBikeDriver());
  }
  if (services.contains(ShimanoDi2Driver.service)) return Match.driver(ShimanoDi2Driver());
  if (services.contains(ShimanoDi2Driver.serviceAlt)) return Match.driver(ShimanoDi2Driver(alternative: true));
  if (name.startsWith('RDR')) return Match.driver(ShimanoDi2Driver());
  if (services.contains(SramAxsDriver.advertisedService) || name.startsWith('SRAM')) {
    return Match.driver(SramAxsDriver());
  }

  // Zwift : le type est dans les données constructeur.
  final zwiftData = adv.manufacturerData[ZwiftIds.manufacturerId];
  final isZwift = services.contains(ZwiftIds.customService) || services.contains(ZwiftIds.rideService);
  if (zwiftData != null && zwiftData.isNotEmpty) {
    final rideService = services.contains(ZwiftIds.rideService) ? ZwiftIds.rideService : ZwiftIds.customService;
    switch (zwiftData.first) {
      case ZwiftIds.click:
        return Match.driver(ZwiftClickDriver());
      case ZwiftIds.playLeft:
        return Match.driver(ZwiftPlayDriver(left: true));
      case ZwiftIds.playRight:
        return Match.driver(ZwiftPlayDriver(left: false));
      case ZwiftIds.rideLeft:
        return Match.driver(ZwiftRideDriver(rideService));
      case ZwiftIds.playFw2:
        return Match.driver(ZwiftPlayFw2Driver(rideService));
      case ZwiftIds.rideRight:
        return null; // la poignée gauche relaie la droite
      case ZwiftIds.clickV2Left:
        return clickV2RightOnly ? null : Match.driver(ZwiftClickV2Driver(rideService));
      case ZwiftIds.clickV2Right:
        // Sinon le côté gauche relaie le droit.
        return clickV2RightOnly ? Match.driver(ZwiftClickV2RightDriver(rideService)) : null;
    }
  } else if (isZwift && name == 'ZWIFT CLICK') {
    return Match.driver(ZwiftClickDriver());
  }
  return null;
}
