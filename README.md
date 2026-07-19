# DriveLab Telem — BeamNG.drive Android Telemetry Dashboard

<p align="center">
  <img src="assets/feature-graphic-1024x500.svg" alt="DriveLab Telem for BeamNG.drive" width="100%">
</p>

<p align="center">
  <strong>Turn your Android phone into a dedicated BeamNG.drive cockpit, telemetry display, drift analyzer, drag timer, and driver-progression companion.</strong>
</p>

<p align="center">
  <a href="https://github.com/prokyle123/DriveLab-Telem/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/prokyle123/DriveLab-Telem?display_name=tag&style=for-the-badge"></a>
  <img alt="Android" src="https://img.shields.io/badge/Android-Companion_App-3DDC84?style=for-the-badge&logo=android&logoColor=white">
  <img alt="BeamNG telemetry" src="https://img.shields.io/badge/BeamNG.drive-Telemetry-F36F21?style=for-the-badge">
</p>

<p align="center">
  <a href="https://github.com/prokyle123/DriveLab-Telem/releases/latest"><strong>Download the latest APK</strong></a>
  ·
  <a href="INSTALL.md">Setup guide</a>
  ·
  <a href="FAQ.md">FAQ</a>
  ·
  <a href="PRIVACY.md">Privacy</a>
</p>

---

## Your BeamNG cockpit—off the PC screen

DriveLab Telem receives live telemetry directly from BeamNG.drive over your local Wi-Fi network. Mount your Android phone beside your wheel, on your dash, or anywhere you want a clean second-screen display without covering the game with extra HUD elements.

It uses BeamNG.drive's built-in **OutGauge** and **MotionSim** UDP outputs, so there is **no PC helper program, game modification, or cloud telemetry relay required**.

## Built for more than a speedometer

- **Live Dashboard** — real-time driving data at a glance
- **Digital Cockpit** — a focused instrument-panel view for regular driving
- **Drift Lab** — analyze and track drift performance
- **Drag & Brake Testing** — performance runs and braking measurements
- **Vehicle Dynamics** — see how the vehicle behaves beyond basic speed and RPM
- **Achievements** — goals that give every session something to chase
- **Driver Progression** — build a persistent driving profile over time
- **Animated Demo Mode** — explore the complete interface before activating
- **Fast local connection** — OutGauge on UDP `4444` and MotionSim on UDP `4445`
- **Private by design** — gameplay telemetry remains on your local network and phone

## See it in action

<table>
  <tr>
    <td width="50%" align="center"><strong>Live Dashboard</strong><br><img src="screenshots/01-live-dashboard.png" alt="DriveLab Telem live dashboard" width="100%"></td>
    <td width="50%" align="center"><strong>Digital Cockpit</strong><br><img src="screenshots/02-cockpit.png" alt="DriveLab Telem cockpit" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Drift Lab</strong><br><img src="screenshots/03-drift-lab.png" alt="DriveLab Telem Drift Lab" width="100%"></td>
    <td width="50%" align="center"><strong>Achievements</strong><br><img src="screenshots/04-achievements.png" alt="DriveLab Telem achievements" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Driver Progression</strong><br><img src="screenshots/05-driver-progression.png" alt="DriveLab Telem driver progression" width="100%"></td>
    <td width="50%" align="center"><strong>Drag & Brake</strong><br><img src="screenshots/06-drag-brake.png" alt="DriveLab Telem drag and brake testing" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Vehicle Dynamics</strong><br><img src="screenshots/07-dynamics.png" alt="DriveLab Telem vehicle dynamics" width="100%"></td>
    <td width="50%" align="center"><strong>Guided Setup & Demo</strong><br><img src="screenshots/08-setup-demo.png" alt="DriveLab Telem setup and demo mode" width="100%"></td>
  </tr>
</table>

## Simple setup

1. Install the signed APK on your Android phone.
2. Put the phone and BeamNG PC on the same local network.
3. In BeamNG.drive, open **Options → Other → Protocols**.
4. Send **OutGauge** to the phone on UDP port `4444`.
5. Send **MotionSim** to the phone on UDP port `4445`.
6. Open DriveLab Telem and drive.

See the complete [installation and telemetry setup guide](INSTALL.md).

## Try before activation

The APK includes a full animated Demo Mode so you can explore the interface and feature layout before entering a license key. Live BeamNG telemetry and the complete commercial experience require activation.

A standard license supports **two active Android devices** unless the purchase listing states otherwise. Initial activation requires internet; afterward, the app supports offline use through its signed local-license grace period.

## Download

### [Download DriveLab Telem for Android](https://github.com/prokyle123/DriveLab-Telem/releases/latest)

Download the newest signed `DriveLab-Telem-vX.Y.Z.apk` from **Releases**. Each release includes a SHA-256 checksum so the APK can be verified before installation.

When updating, install the new APK directly over the existing version. Do not uninstall first unless troubleshooting requires it, because uninstalling removes local progression and settings.

## Requirements

- Android phone or tablet
- BeamNG.drive on a Windows PC
- Phone and PC connected to the same local network
- BeamNG OutGauge and MotionSim protocols enabled

## Privacy and ownership

Gameplay telemetry is sent locally from BeamNG.drive to the Android device. It is not uploaded as part of normal telemetry operation. Licensing requests contain only activation-related information described in the [privacy policy](PRIVACY.md).

DriveLab Telem is commercial software. This repository distributes the signed customer APK and documentation; it does not publish the proprietary source code, signing keys, or licensing-server credentials.

## Support

Before requesting help, check the [setup guide](INSTALL.md) and [FAQ](FAQ.md). Include the app version, Android device, BeamNG setup, connection status, and a screenshot of any error.

---

**BeamNG.drive® is a registered trademark of BeamNG GmbH. DriveLab Telem is an independent third-party companion application and is not affiliated with or endorsed by BeamNG GmbH.**
