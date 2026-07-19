# DriveLab Telem v1.8.2 — BeamNG.drive Android Telemetry Dashboard

Turn an Android phone into a dedicated BeamNG.drive second screen with live telemetry, cockpit instruments, drift analysis, drag and braking tools, vehicle dynamics, achievements, and driver progression.

## Download

Download `DriveLab-Telem-v1.8.2.apk` from the release assets and verify it using `SHA256SUMS.txt`.

## Why DriveLab Telem

- Dedicated **Live Dashboard** for real-time BeamNG telemetry
- Focused **Digital Cockpit** display
- **Drift Lab** for tracking drift performance
- **Drag & Brake** performance testing
- **Vehicle Dynamics** views beyond basic speed and RPM
- Persistent **Achievements** and **Driver Progression**
- Full animated **Demo Mode** before activation
- Direct use of BeamNG.drive's built-in **OutGauge** and **MotionSim** outputs
- No PC helper application, game modification, or cloud telemetry relay
- Local-network gameplay telemetry for a fast, private connection

## Commercial package

- Signed commercial Android APK
- Live OutGauge and MotionSim telemetry after activation
- Purchase button connected to the publisher's checkout page
- Two-device default license allowance
- Offline grace access after successful activation

## Changes in 1.8.2

- Incorrect activation keys now show **Invalid serial key.** instead of a technical exception or API response.
- Online verification continues to run silently at launch and when the app returns to the foreground.
- The purchase button and self-hosted licensing workflow remain unchanged.
- Added a polished public GitHub distribution package without exposing commercial source code or signing credentials.

## Quick setup

1. Install and open the APK on the Android device.
2. Put the phone and BeamNG PC on the same local network.
3. In BeamNG.drive, open **Options → Other → Protocols**.
4. Send **OutGauge** to the phone IP on UDP port `4444`.
5. Send **MotionSim** to the phone IP on UDP port `4445`.
6. Open DriveLab Telem and confirm both protocol indicators show live data.

## Integrity

```text
939172fecf6e0494fae267e355e3183ed7474ee3317ff7bd554f4f729dd4c695  DriveLab-Telem-v1.8.2.apk
```

Existing customers can install this APK over a previous commercial release when it is signed by the same permanent signing key.

**BeamNG.drive® is a registered trademark of BeamNG GmbH. DriveLab Telem is an independent third-party companion application and is not affiliated with or endorsed by BeamNG GmbH.**