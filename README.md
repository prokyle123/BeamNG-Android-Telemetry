# DriveLab Telem for BeamNG.drive

<p align="center">
  <img src="assets/feature-graphic-1024x500.svg" alt="DriveLab Telem Android telemetry dashboard for BeamNG.drive" width="100%">
</p>

<p align="center">
  <strong>Turn an Android phone or tablet into a dedicated BeamNG.drive dashboard, TrackLab course tool, and RaceLink multiplayer race companion.</strong>
</p>

<p align="center">
  <a href="https://drivelabregistration.org"><img alt="Official website" src="https://img.shields.io/badge/Official_Website-DriveLab_Telem-00C2FF?style=for-the-badge"></a>
  <a href="https://github.com/prokyle123/BeamNG-Android-Telemetry/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/prokyle123/BeamNG-Android-Telemetry?display_name=tag&style=for-the-badge"></a>
  <img alt="Android app" src="https://img.shields.io/badge/Android-Telemetry_App-3DDC84?style=for-the-badge&logo=android&logoColor=white">
  <img alt="BeamNG drive telemetry" src="https://img.shields.io/badge/BeamNG.drive-OutGauge_%2B_MotionSim-F36F21?style=for-the-badge">
</p>

<p align="center">
  <a href="https://github.com/prokyle123/BeamNG-Android-Telemetry/releases/latest"><strong>DOWNLOAD THE LATEST APK</strong></a>
  &nbsp; | &nbsp;
  <a href="https://drivelabregistration.org/go/buy"><strong>GET FULL EDITION</strong></a>
  &nbsp; | &nbsp;
  <a href="INSTALL.md"><strong>SETUP GUIDE</strong></a>
  &nbsp; | &nbsp;
  <a href="FAQ.md"><strong>FAQ</strong></a>
  &nbsp; | &nbsp;
  <a href="PRIVACY.md"><strong>PRIVACY</strong></a>
</p>

---

## DriveLab Telem 2.1.0

Version **2.1.0 (32)** introduces **RaceLink**, the new Full Edition online racing and comparison system, alongside the refined **TrackLab** course workflow.

### RaceLink

- Add friends using permanent `DL-XXXXXX` friend codes
- Send and accept friend requests inside the app
- Create private six-character RaceLink rooms before selecting a course
- Join by room code or direct friend invitation
- Built-in lobby chat
- Host-selected TrackLab course and race configuration
- Circuit, point-to-point, and timed best-lap modes
- Ready checks that automatically reset whenever the host changes setup
- Host-controlled synchronized eight-second countdown
- Live driver positions, connection state, progress, sectors, standings, and final results
- Up to eight Full Edition drivers per room

RaceLink coordinates phones, course data, timing, standings, and results. It does **not** place vehicles into another player's BeamNG world. Drivers should use the same BeamNG map and the same shared TrackLab course for meaningful comparison.

### TrackLab

TrackLab lets drivers build reusable courses from recorded checkpoints, choose start/finish behavior, configure sectors, save courses locally, and share the selected course through a RaceLink lobby.

## Put your telemetry where it belongs

Stop covering the game with extra HUD windows. Mount an Android phone beside your wheel or on your desk and use it as a clean, dedicated second screen for live driving data.

DriveLab Telem connects directly to BeamNG.drive over your local network using the game's built-in **OutGauge** and **MotionSim** UDP outputs.

**No PC helper program and no BeamNG mod are required.** Normal dashboard telemetry stays between the BeamNG PC and Android device. RaceLink network data is sent only while the driver uses RaceLink features.

## Major features

- **Live Dashboard** — real-time speed, RPM, gear, temperatures, fuel, forces, and driving data
- **Digital Cockpit** — focused instrument cluster for normal driving and racing
- **TrackLab** — create, save, refine, and share custom courses
- **RaceLink** — friends, rooms, invites, chat, ready checks, countdowns, live standings, and results
- **Drift Lab** — drift angle, scoring, performance, and session results
- **Drag and Brake Testing** — acceleration runs and braking performance
- **Vehicle Dynamics** — motion and handling data beyond basic gauges
- **Achievements** — more than 1,000 goals
- **Driver Progression** — persistent local driving profile
- **Automatic drive tracking** — completed-drive summaries and comparisons
- **Secure in-app updates** — signed manifests, SHA-256 verification, package checks, and permanent signing-certificate verification
- **Free Edition** — basic live telemetry, setup, settings, licensing, TrackLab access, and secure updates
- **Full Edition** — Cockpit, advanced labs, Analyze, RaceLink, automatic drive tracking, progression, achievements, saved sessions, crash history, advanced graphs, exports, and layout customization

## See DriveLab Telem in action

<table>
  <tr>
    <td width="50%" align="center"><strong>Live Dashboard</strong><br><img src="screenshots/01-live-dashboard.png" alt="DriveLab Telem live dashboard" width="100%"></td>
    <td width="50%" align="center"><strong>Digital Cockpit</strong><br><img src="screenshots/02-cockpit.png" alt="DriveLab Telem digital cockpit" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Drift Lab</strong><br><img src="screenshots/03-drift-lab.png" alt="DriveLab Telem Drift Lab" width="100%"></td>
    <td width="50%" align="center"><strong>Achievements</strong><br><img src="screenshots/04-achievements.png" alt="DriveLab Telem achievements" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Driver Progression</strong><br><img src="screenshots/05-driver-progression.png" alt="DriveLab Telem driver progression" width="100%"></td>
    <td width="50%" align="center"><strong>Drag and Brake Testing</strong><br><img src="screenshots/06-drag-brake.png" alt="DriveLab Telem drag and brake testing" width="100%"></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Vehicle Dynamics</strong><br><img src="screenshots/07-dynamics.png" alt="DriveLab Telem vehicle dynamics" width="100%"></td>
    <td width="50%" align="center"><strong>Guided Setup</strong><br><img src="screenshots/08-setup-demo.png" alt="DriveLab Telem setup" width="100%"></td>
  </tr>
</table>

## Start free, unlock more when ready

The signed APK starts in Free Edition without an account, email address, subscription, or activation. Full Edition is unlocked using a purchased DriveLab serial key.

A standard Full license supports **two active Android devices** unless the purchase listing states otherwise. RaceLink requires Full Edition on every participating device.

## Quick setup

1. Install the signed APK on the Android device.
2. Connect the Android device and BeamNG PC to the same network.
3. In BeamNG.drive, open `Options > Other > Protocols`.
4. Send **OutGauge** to the Android device IP on UDP port `4444`.
5. Send **MotionSim** to the Android device IP on UDP port `4445`.
6. Open DriveLab Telem and confirm both telemetry indicators are active.

Read the complete [installation and telemetry setup guide](INSTALL.md).

## Download

### [Download the latest signed DriveLab Telem APK](https://github.com/prokyle123/BeamNG-Android-Telemetry/releases/latest)

Current production release: **DriveLab Telem 2.1.0 (32)**.

When manually updating, install the new APK directly over the existing version. **Do not uninstall first**, because uninstalling removes local progression, achievements, settings, courses, sessions, and the stored activation.

The APK is also distributed by DriveLab's signed in-app update system. Open **Setup > App Update** to check, download, verify, and install future releases.

## Requirements

- Android 8.0 or newer
- BeamNG.drive on a Windows PC
- Phone and PC on the same local network for game telemetry
- BeamNG OutGauge and MotionSim enabled
- Internet access for activation, updates, and RaceLink
- Full Edition for RaceLink

## Privacy and ownership

Normal BeamNG telemetry is sent locally from the PC to the Android device. When RaceLink is used, the app sends the minimum room, identity, course, timing, position/progress, chat, readiness, and result data needed to operate that online feature. See the [privacy policy](PRIVACY.md) for details.

DriveLab Telem is commercial software. This repository distributes the signed customer APK and documentation. It does not publish proprietary Android source code, permanent signing keys, license-server private keys, customer databases, or server credentials.

## Support

Visit the **[official DriveLab Telem website](https://drivelabregistration.org)**, then check the [setup guide](INSTALL.md) and [FAQ](FAQ.md). For support, email **auroramediagroup1@gmail.com** with the app version, Android device, BeamNG setup, connection status, and a screenshot that does not expose a serial key, admin token, or other sensitive information.

---

**BeamNG.drive is a trademark of BeamNG GmbH. DriveLab Telem is an independent third-party companion application and is not affiliated with or endorsed by BeamNG GmbH.**
