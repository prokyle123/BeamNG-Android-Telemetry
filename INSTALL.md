# Installation, BeamNG telemetry, TrackLab, and RaceLink setup

## Install DriveLab Telem

1. Download the current `DriveLab-Telem-vX.Y.Z.apk` from [GitHub Releases](https://github.com/prokyle123/BeamNG-Android-Telemetry/releases/latest).
2. Open the downloaded APK on the Android phone or tablet.
3. Android may ask permission for the browser or file manager to install unknown apps. Enable it only for the app used to open the APK.
4. Install and open DriveLab Telem.
5. Continue in Free Edition or enter a purchased `DLT-...` serial key to activate Full Edition.

When updating, install the new APK **over the existing app**. Do not uninstall first. The package name and permanent signing certificate are preserved so Android can retain the activation, settings, progression, achievements, TrackLab courses, sessions, and other app data.

## Connect BeamNG.drive

The Android device and BeamNG PC must be on the same local network.

1. Open DriveLab Telem and note the Android device IPv4 address shown in Setup.
2. In BeamNG.drive, open `Options > Other > Protocols`.
3. Enable **OutGauge** and send it to the Android device IP on UDP port `4444`.
4. Enable **MotionSim** and send it to the same Android device IP on UDP port `4445`.
5. Return to DriveLab Telem and confirm both protocol indicators show live packets.

No PC helper program or BeamNG mod is required.

## Create a TrackLab course

1. Open **TrackLab**.
2. Start course recording at the desired location on the BeamNG map.
3. Drive the intended route and add or record checkpoints.
4. Complete the course and review checkpoint order, sectors, start/finish behavior, and course name.
5. Save the course locally.
6. Test the course before using it for a RaceLink event.

For meaningful RaceLink comparison, every driver should load the same BeamNG map and use the course shared by the host.

## Start a RaceLink room

RaceLink requires Full Edition and internet access on every participating device.

1. Open **RaceLink** and confirm your `DL-XXXXXX` friend code is visible.
2. Add friends by friend code or create a private room immediately.
3. Share the six-character room code or send a direct in-app invitation.
4. Let drivers join the lobby before configuring the race.
5. The host selects the TrackLab course, mode, laps or time limit, and room capacity.
6. Saving or changing setup clears all Ready states.
7. Drivers move to the start location and press **I'm Ready**.
8. When all connected drivers are ready, the host presses **Start Race**.
9. RaceLink performs a synchronized eight-second countdown and then tracks progress, sectors, standings, and results.

RaceLink coordinates timing and results between phones. It does not create a BeamMP server or place cars into the same BeamNG world.

## Secure in-app updates

Open **Setup > App Update** and press **Check Now**. DriveLab verifies the signed update manifest, APK SHA-256, package name, version, minimum Android version, and permanent Android signing certificate before opening Android's installer.

## Common problems

- **No telemetry:** Confirm the Android IP, UDP ports, same-network connection, and Windows firewall rules.
- **OutGauge only:** MotionSim must be enabled separately on port `4445`.
- **Wrong Android IP:** Refresh the address in Setup after changing Wi-Fi networks.
- **Invalid serial key:** Re-enter the key exactly as delivered.
- **Device limit:** Contact support to reset an old device after replacing a phone.
- **RaceLink profile missing:** Confirm internet access, open RaceLink, and use **Refresh Profile**.
- **Friend code not visible:** Update to version 2.1.0 or newer.
- **Cannot mark Ready:** The host must save a valid course and race setup first.
- **Start Race disabled:** Every connected driver must be online and ready.
- **Race results do not match:** Confirm everyone is on the same map and using the shared course.
- **Cannot install update:** Never uninstall first. Confirm the APK came from the official website, signed updater, or this repository.
