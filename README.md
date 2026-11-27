<p align="center">
  <img src="docs/captures/shiftlink-virtual-shifting-smart-trainer-banner.png" alt="ShiftLink logo: virtual shifting for any smart trainer with a Bluetooth controller" width="720">
</p>

<h1 align="center">ShiftLink: virtual shifting for any smart trainer</h1>

<p align="center">
  <b>Free, open-source Android app that lets you shift the virtual gears of Zwift, MyWhoosh, Rouvy, TrainingPeaks Virtual and Biketerra with any Bluetooth controller, on any smart trainer.</b><br>
  Zwift Click · Zwift Play · Zwift Ride · Shimano Di2 · SRAM AXS · Elite Sterzo · gamepads · Bluetooth remotes
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/badge/Download-APK%202.23.1-2ea44f?style=for-the-badge&logo=android&logoColor=white" alt="Download the ShiftLink APK for Android"></a>
  <img src="https://img.shields.io/badge/Android-8%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Requires Android 8 or later">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Built with Flutter">
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge" alt="GPL-3.0 open-source license">
</p>

---

**ShiftLink** turns your phone into a bridge between your **shifters** and your **indoor cycling app**. Press a button on a Zwift Click, a Di2 hood or a cheap Bluetooth remote, and ShiftLink shifts gears in MyWhoosh, Rouvy, TPV or Biketerra. For **Zwift** and trainers without virtual shifting, ShiftLink adds its own **virtual gears** to any **FTMS smart trainer** (Wahoo, Tacx, Elite, ThinkRider…). Free and open source, with no account and no tracking.

## Features at a glance

- **Works with your controllers**: Zwift Click / Play / Ride, Elite Sterzo and Rizer, Shimano Di2, SRAM AXS, Wahoo KICKR Bike, CYCPLUS, ThinkRider, Bluetooth remotes, gamepads, volume keys…
- **Works with your apps**: MyWhoosh (Link), Rouvy, TPV, Biketerra and any app with keyboard shortcuts (your phone becomes a Bluetooth keyboard), OpenBikeControl over Wi-Fi.
- **Virtual gears for Zwift and trainers without shifting**: ShiftLink sits between the trainer and the app (Bluetooth FTMS or Wi-Fi DIRCON), with drivetrains from 1 to 30 gears and named profiles.
- **Training**: structured workouts (import .erg, .mrc, .fit, .zwo), ERG mode, ride recording to .fit, upload to Garmin Connect and Intervals.icu, heart-rate strap, KICKR Headwind fan.
- **Simple**: setup wizard, "Not working?" diagnostics, 9 languages (EN, FR, DE, ES, IT, PL, NL, PT, ZH), no account, no tracking.

## Screenshots

<p align="center">
  <img src="docs/captures/shiftlink-virtual-gears-ride-screen.png" width="240" alt="ShiftLink ride screen: virtual gear 14 of 24 with watts, cadence, grade and heart rate">
  <img src="docs/captures/shiftlink-bluetooth-controllers-devices.png" width="240" alt="ShiftLink devices screen: Bluetooth controllers and smart trainer connections">
  <img src="docs/captures/shiftlink-settings.png" width="240" alt="ShiftLink settings screen">
</p>
<p align="center"><i>Ride · Devices · Settings</i></p>

## How it works

The smart trainer stays connected directly to the app, which handles resistance and
virtual gears. ShiftLink reads the controller's buttons and sends "gear + / −" to the app:

| App | How |
|---|---|
| MyWhoosh | "Link" connection (local Wi-Fi, TCP 21587, same protocol as the MyWhoosh Link app) |
| Rouvy | Bluetooth keyboard: `.` and `,` (enable "Virtual Shifting Controls") |
| TrainingPeaks Virtual | Bluetooth keyboard: numpad `+` and `−` |
| Biketerra | Bluetooth keyboard: `W` and `S` |
| Other apps with keyboard shortcuts | Bluetooth keyboard, custom keys |
| OpenBikeControl-compatible apps | Open protocol, automatic discovery on Wi-Fi (TCP 36867) |
| Zwift and apps without virtual shifting | "ShiftLink virtual gears" mode (see below) |

In keyboard mode, the phone presents itself as a Bluetooth keyboard (HID profile,
Android 9 or later) to the computer or tablet running the app.

## Installing the APK

ShiftLink is not on the Play Store: download the APK from this repository's
**Releases** page.

1. On your Android phone (8 or later), open the latest release and tap
   `ShiftLink-x.y.z.apk` to download it.
2. Open the downloaded file. If Android asks, allow your browser (or file
   manager) to **install unknown apps**, then tap **Install**.
3. If Play Protect shows "Unrecognized app", tap **More details > Install
   anyway**. This is normal for an app outside the Play Store.
4. Launch ShiftLink: the setup wizard guides you through the rest.

### Allow restricted settings (Android 13 and later)

To tap the screen for you, or read Bluetooth remotes and volume keys, ShiftLink
uses an **accessibility service**. For apps installed outside the Play Store,
Android greys this service out and shows "Restricted setting". To unlock it,
once:

1. Try to enable ShiftLink in **Settings > Accessibility > Installed apps**:
   Android refuses and shows "Restricted setting". This attempt is what unlocks
   the next step.
2. Go to **Settings > Apps > ShiftLink**.
3. Tap the **⋮** menu in the top right, then **Allow restricted settings**, and
   confirm with your PIN or fingerprint.
4. Go back to **Settings > Accessibility > ShiftLink** and enable the service.

ShiftLink guides you through this from the setup wizard and from Settings > Not
working? The accessibility service is only needed for on-screen taps and
remotes: Bluetooth controllers, Bluetooth keyboard, MyWhoosh Link and
OpenBikeControl work without it.

Menu names vary a little by brand (Samsung, Xiaomi…). If the ⋮ menu does not
appear, repeat step 1 and try again.

### Updating

Download the new APK and install it over the old one: your settings are kept.
All release APKs are signed with the same key. A build compiled by someone else
will not install over it (you would have to uninstall first, which erases your
settings; make a backup first in Settings > Backup and sharing).

### Verifying the file (optional)

Each release lists the APK's SHA-256 fingerprint. On a computer:
`sha256sum ShiftLink-x.y.z.apk` (Linux/macOS) or
`certutil -hashfile ShiftLink-x.y.z.apk SHA256` (Windows).

## ShiftLink virtual gears (Zwift…)

ShiftLink connects to the smart trainer itself (FTMS, Bluetooth) and presents
itself to the app as a Wi-Fi trainer (Wahoo Direct Connect protocol, TCP 36866,
mDNS `_wahoo-fitness-tnp._tcp`). When the app requests a grade, ShiftLink adjusts
it for the selected gear before sending it to the trainer:

- grade + rolling resistance multiplied by the gear ratio k;
- aerodynamic coefficient multiplied by k³, wind divided by k.

24 gears, from ratio ×0.5 to ×2. In ERG mode, power passes through unchanged and
gears have no effect.

## Supported controllers

| Controller | Notes |
|---|---|
| ThinkRider VS200 | |
| CYCPLUS BC2 | |
| Zwift Click (1st generation) | |
| Zwift Click v2 | "Click v2: right side only" setting: nothing to do in Zwift (+ = harder, B = easier). Otherwise, connect it to the Zwift app for 30 s each day to get both sides |
| Zwift Play (firmware 2) | Each handle connects on its own (beta) |
| Zwift Play | Left = gear −, right = gear + (side button or paddle) |
| Zwift Ride and Ride V2 | Connects to the left handle, which relays the right one. Ride V2 (firmware 1.3+) must be unlocked in the Zwift app: ShiftLink tells you when it is locked |
| WHEELTOP EDS (OX, TX) | Beta. Rear derailleur off. Switch on R = gears, on T = two extra buttons |
| Elite Square | Left and right shift levers |
| Shimano Di2 | Buttons set to D-Fly channels in E-TUBE: channels 1/3 = +, 2/4 = − |
| SRAM AXS | Single press = +, double press = − |
| Wahoo KICKR Bike, Bike Shift, Bike Pro | Right buttons = +, left = − |
| Tacx NEO Bike (Smart, Plus) | Beta. Firmware 4.5+. Each shift on the levers = + or −, left / right buttons = steer. Also pair the bike as a trainer |
| Elite Sterzo Smart | Steering: turning the handlebar steers the rider (hold left / right) |
| Elite Rizer | Beta. Steering like the Sterzo, and the front of the bike follows the app's grade; the reported grade is shown, a refusal is logged |
| Wahoo KICKR Climb | Beta, in Devices > Accessories: the front of the bike follows the app's grade (−10 to +19 %) |
| This phone on the handlebar | Settings > Steer with this phone. Works in any phone position |

Without a controller, the large on-screen + and − buttons work too.

## Usage

On first launch, a 6-step wizard guides setup: choice of app, permissions,
controller search and test, connection to the app. It can be run again from
Settings.

During a ride, the main screen shows whether everything is ready, the current
gear (Zwift / proxy mode) or the last shift, and the status of each device.

For MyWhoosh: the phone and the MyWhoosh device must be on the same Wi-Fi (no
guest network or client isolation), and the "MyWhoosh Link" app must be closed
(it uses the same port). In MyWhoosh, choose the "Link" connection.

ShiftLink can run on the same device as the app: a "ShiftLink is active"
notification keeps it alive in the background.


## Customizable buttons

Devices > (your controller): each button can trigger a different action on
single press, double press and long press (gears, steering, U-turn, camera, ERG
intensity, music, volume, Android back…). The available actions depend on the
chosen app. Settings are saved per app. A live banner shows the button pressed
and the action triggered.

Combos: two buttons pressed together trigger their own action (for example + and
− together to change chainring). Double-press and long-press timings are set in
the same place.

On the same phone, ShiftLink taps the app's on-screen buttons: default positions
for Rouvy, TPV and MyWhoosh, adjustable per action, with "Show targets" to check.

## Adjustable virtual gears (Zwift mode / ShiftLink trainer)

Settings > Virtual gears (or the settings icon on the gear card): drivetrain (24
even gears, road 2×12 and 2×11, gravel 1×12, MTB 1×12), chainrings, double
chainring with the "Change chainring" action, real gear engaged on the trainer,
grade effect, weight, grade smoothing, ERG intensity step ("Intensity + / −"
actions), vibration and sound on each shift.

Since 1.9:
- custom drivetrain: 1 to 30 gears, each ratio adjustable by touch (0.05 steps);
- named profiles ("Mountain", "Sprint"…), picked up automatically with the same trainer;
- trainer control: grade, target power (watts computed for the speed at your
  cadence) or plain resistance; "Auto" picks based on what the trainer supports;
- cadence filter, "simple relay" mode without gears;
- the app can connect over Wi-Fi (DIRCON) or Bluetooth (ShiftLink presents itself
  as an FTMS trainer);
- "MyWhoosh with ShiftLink gears" instead of MyShift.

Tested on 6 November 2026: ThinkRider VS200 + MyWhoosh over OpenBikeControl works.

MyWhoosh (normal mode) connects over OpenBikeControl (handlebar icon on the
connections screen) or, on older versions, over Link.

## Remotes, overlay, diagnostics

- Settings > Remotes: Bluetooth remotes, gamepads and keyboards paired with the
  phone act as controllers (by default, volume / D-pad up-down = gears). Their
  keys go through the accessibility service.
- Overlay on top of the app: a small movable window (gear, watts, cadence, ERG or
  last action).
- Settings > Not working?: checks Bluetooth, permissions, controller, Wi-Fi,
  trainer, app and background, and offers the fix.
- Language: English, French, German, Spanish, Italian, Polish, Dutch, Portuguese
  or Chinese (Settings > Display > Language; "Auto" follows the phone). Each
  language has its own file `lib/src/i18n_xx.dart`, with the French text as the
  key. The log stays in French.
- Accessibility: the gear is announced by the screen reader on each change, and
  screens are checked with text enlarged to 160 %.

## Sensors and outputs (2.x)

- Bluetooth heart-rate strap: heart rate is shown, recorded and sent to the app
  when ShiftLink handles the gears.
- Wahoo KICKR Headwind fan (beta): manual ("Fan + / −" actions), or driven by
  your speed, power or heart rate (the fan's own strap, or the one paired with
  ShiftLink), with a "starts at / full at" setting.
- Ride recording: .fit file (power, cadence, speed, heart rate, distance) to send
  to Strava, Garmin Connect or intervals.icu.
- Connected apps (Settings > Automatic > Connected apps): Garmin Connect and
  Intervals.icu (API key). Strava is connected in MyWhoosh. Garmin Connect: each
  recorded ride is uploaded automatically, and a .fit from MyWhoosh can be sent
  manually. The file is repaired first: power, heart-rate and cadence averages
  added, temperature removed. The login reuses the Garmin Connect mobile app's
  flow, like [python-garminconnect](https://github.com/cyberjunky/python-garminconnect)
  (MIT): Garmin's login page inside the app, ticket exchanged for a token kept on
  the phone. This is not an official API: Garmin may change it.
- MyWhoosh account (same page): ShiftLink fetches your rides and their original
  .fit from MyWhoosh, then uploads new ones to Garmin Connect when the app opens
  (older ones manually from "My MyWhoosh rides"). The password is only used to
  log in; only the session is kept on the phone. Private, unofficial MyWhoosh
  app API: it may change.
- Settings > Backup and sharing: file, QR code or text to copy, no account
  needed. Paired devices stay on the phone.


## FAQ

**Can I use a Zwift Click or Zwift Play with MyWhoosh or Rouvy?**
Yes. ShiftLink reads the Zwift Click, Play or Ride over Bluetooth and sends the shifts to MyWhoosh (Link or OpenBikeControl), Rouvy, TPV or Biketerra.

**Can I get virtual shifting in Zwift on a trainer that does not support it?**
Yes. In "ShiftLink virtual gears" mode, ShiftLink connects to your FTMS smart trainer and appears in Zwift as a Wi-Fi or Bluetooth trainer, adjusting the resistance for the selected gear.

**Which smart trainers work?**
Any Bluetooth FTMS trainer (Wahoo KICKR, Tacx, Elite, ThinkRider…), older Bluetooth FE-C trainers and Wi-Fi DIRCON trainers.

**Is ShiftLink free? Is there an iPhone version?**
ShiftLink is free and open source (GPL-3.0). It is Android only (Android 8 or later); the app it controls can run on a PC, Mac, tablet or the same phone.

**Is ShiftLink an alternative to BikeControl?**
ShiftLink covers the same need (using Bluetooth controllers with training apps) with its own code. It is an independent project, not affiliated with BikeControl / OpenBikeControl.

## Security

- Network servers (OpenBikeControl, Link, Wi-Fi trainer) only accept devices on
  the local network, never an Internet address.
- The Bluetooth trainer accepts only one app at a time and rejects malformed
  commands. Requested power is capped at 2000 W.
- The Sterzo code file is verified by its SHA-256 fingerprint.
- No account, no tracking, no cloud backup of settings, no plain-text HTTP traffic.


## License and sources

ShiftLink is released under GPL-3.0 (see `LICENSE`). Its code is written for
ShiftLink.

Device protocols (Bluetooth identifiers, frame layouts, network messages) are
facts imposed by the hardware and apps: ShiftLink applies them as-is so things
work. Public sources used:

- Zwift Click and Play: [ajchellew/zwiftplay](https://github.com/ajchellew/zwiftplay);
  Zwift Ride and Click v2: [Makinolo, "Zwift Ride protocol"](https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/);
- Zwift Ride V2, WHEELTOP EDS, Elite Rizer, CYCPLUS T7, Tacx NEO Bike: public
  protocol descriptions by [OpenBikeControl](https://github.com/OpenBikeControl/bikecontrol)
  (protocol facts only, no code reused);
- KICKR Climb: sniffer capture by [Redback Operations](https://github.com/Redback-Operations/redback-smartbike-iot) (GPL-3.0);
- Elite Sterzo: [pycycling](https://github.com/zacharyedwardbull/pycycling) (MIT),
  whose response-code file is downloaded on first use;
- OpenBikeControl: [openbikecontrol.org](https://openbikecontrol.org), open protocol;
- keyboard shortcuts: the apps' help pages (Rouvy, Zwift…);
- other devices (ThinkRider, CYCPLUS, Elite Square, Shimano Di2, SRAM AXS, Wahoo
  KICKR Bike, Headwind, MyWhoosh Link): publicly known identifiers and frame
  formats, applied in code written for ShiftLink.

ShiftLink is an independent project. It is not affiliated with MyWhoosh, Zwift,
BikeControl / OpenBikeControl, or the controller manufacturers.
