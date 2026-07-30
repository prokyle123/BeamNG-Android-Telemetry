# Installation, BeamNG telemetry, TrackLab, and RaceLink setup

## Install DriveLab Telem

1. Visit the [official DriveLab website](https://drivelabregistration.org).
2. During closed testing, follow the website instructions to join the approved Google Play test and open the Play Store testing link.
3. After public launch, open the official DriveLab Telem listing in the Google Play Store.
4. Install and open DriveLab Telem through Google Play.
5. Continue with the available Free Edition features. After production launch, Full Edition can be unlocked through the optional one-time Google Play purchase.

DriveLab is no longer distributed as a downloadable APK through GitHub, the website, or third-party mirrors. Google Play is the official installation and update channel.

### Migrating from a legacy GitHub APK

Legacy GitHub/sideloaded builds were signed differently from the Google Play release and cannot be updated in place.

1. Export or record any locally stored information you want to keep where the legacy app provides that option.
2. Uninstall the legacy DriveLab APK.
3. Join the approved test or open the public Play Store listing.
4. Install the official Google Play build.
5. Use Google Play for all future updates.

Uninstalling a legacy build removes its local app data, including locally stored settings, progression, achievements, TrackLab courses, sessions, and other saved information.

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

## Updates

Google Play is the only supported update channel for the Play-distributed build. Leave automatic updates enabled or open the DriveLab Telem Play Store listing and press **Update** when a new release is available.

Do not install archived APK files over the Google Play version. Android will reject packages signed with a different key, and unofficial files may be outdated or unsafe.

## Common problems

- **No telemetry:** Confirm the Android IP, UDP ports, same-network connection, and Windows firewall rules.
- **OutGauge only:** MotionSim must be enabled separately on port `4445`.
- **Wrong Android IP:** Refresh the address in Setup after changing Wi-Fi networks.
- **Cannot install the Play version:** Uninstall any legacy GitHub/sideloaded DriveLab build first because it uses a different signing identity.
- **Lost local data after migration:** Uninstalling the legacy build removes its local data. The different signing identity prevents an in-place upgrade.
- **Purchase not restored:** Confirm the same Google account is active in Google Play, verify internet access, and use the app's restore/refresh entitlement option.
- **RaceLink profile missing:** Confirm internet access, open RaceLink, and use **Refresh Profile**.
- **Friend code not visible:** Confirm the current Google Play version is installed.
- **Cannot mark Ready:** The host must save a valid course and race setup first.
- **Start Race disabled:** Every connected driver must be online and ready.
- **Race results do not match:** Confirm everyone is on the same map and using the shared course.
