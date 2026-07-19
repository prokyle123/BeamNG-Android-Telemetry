# Installation and telemetry setup

## Install the APK

1. Download the current `DriveLab-Telem-vX.Y.Z.apk` from GitHub Releases.
2. Open the downloaded file on the Android phone.
3. Android may ask permission for the browser or file manager to install unknown apps. Enable that permission only for the application you used to download the APK.
4. Install and open DriveLab Telem.
5. Enter the supplied `DLT-...` serial key or choose Demo Mode.

## Connect BeamNG.drive®

The phone and PC must be on the same local network.

1. Find the Android phone's local IPv4 address in Wi-Fi settings.
2. In BeamNG.drive®, open `Options > Other > Protocols`.
3. Enable **OutGauge** and set the destination to the phone IP on UDP port `4444`.
4. Enable **MotionSim** and set the destination to the phone IP on UDP port `4445`.
5. Return to DriveLab Telem and confirm both protocol indicators show live data.

No PC helper program or game modification is required.

## Updating

Install a newer APK over the existing commercial installation. Android preserves app data only when the package name and signing certificate match. Do not uninstall first unless troubleshooting requires it, because uninstalling removes local progression and settings.

## Common problems

- **No telemetry:** Confirm the phone IP, UDP ports, same-network connection, and firewall rules.
- **OutGauge only:** MotionSim must be enabled separately on port `4445`.
- **Invalid serial key:** Re-enter the serial exactly as delivered. Contact support when the problem continues.
- **Device limit:** Contact support to reset an old device after replacing a phone.
- **Cannot install update:** The APK may have been signed by a different key. Contact support before uninstalling.
