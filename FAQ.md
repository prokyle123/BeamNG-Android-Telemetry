# Frequently asked questions

## Is DriveLab Telem free?

Yes. DriveLab is a free Google Play download with basic live telemetry and setup access. After production launch, Full Edition is available as an optional one-time Google Play purchase that unlocks the advanced dashboards, analysis, progression, achievements, saved sessions, automatic drive tracking, RaceLink, and other premium tools.

## Where should I download DriveLab?

Use only the official Google Play testing or production listing reached through the [DriveLab website](https://drivelabregistration.org). GitHub remains online for documentation and screenshots but no longer distributes the APK.

## Why was the GitHub APK removed?

DriveLab moved to Google Play as its only supported installation and update channel. This prevents users from being stranded on outdated builds and keeps future releases, purchase entitlement, signing, and updates under the official Play distribution system.

## Can an old GitHub APK update to the Google Play version?

No. Legacy GitHub/sideloaded builds were signed differently from the Google Play release. Android will not install the Play version over a package signed with the older identity.

Export or record anything important where possible, uninstall the legacy build, and then install DriveLab through Google Play. Uninstalling removes locally stored app data.

## Does it require a PC helper application or BeamNG mod?

No. DriveLab Telem uses BeamNG.drive's built-in OutGauge and MotionSim UDP outputs.

## What is TrackLab?

TrackLab lets you record and save custom courses made from checkpoints and sectors. A saved TrackLab course can be selected and shared by a RaceLink host.

## What is RaceLink?

RaceLink is DriveLab Telem's built-in online friend, lobby, race coordination, timing, standings, and result system. It supports private rooms for up to eight Full Edition drivers, friend codes, invitations, chat, ready checks, synchronized countdowns, live progress, sectors, standings, and final results.

## Does RaceLink replace BeamMP?

No. RaceLink does not place cars into another driver's BeamNG world. It coordinates phones and compares drivers who are using the same map and shared TrackLab course. Drivers may use single-player sessions or any separate multiplayer arrangement they choose.

## How do I add a friend?

Open RaceLink, copy your permanent `DL-XXXXXX` friend code, and send it to the other driver. Enter their code in the Add Friend field and accept the request in the app.

## Can drivers join before the host selects a course?

Yes. The host creates the lobby first. Friends can join, chat, and prepare while the host chooses the course and race settings. Any setup change resets Ready states.

## Why is Start Race disabled?

The room must have a valid setup and every connected driver must be online and marked Ready. Only the host starts the synchronized countdown.

## Is gameplay telemetry uploaded?

Normal dashboard telemetry stays on the local network and Android device. While using RaceLink, the app sends the room, identity, course, chat, readiness, timing, position/progress, sector, standings, and result data needed to run the online room. See `PRIVACY.md` for details.

## Does it work offline?

Normal telemetry and locally stored features can continue offline. A previously verified Full Edition entitlement can remain available for up to 30 days without a successful online refresh. Initial installation, purchase verification, entitlement refresh, updates, and RaceLink require internet access.

## Is payment processed inside the app?

The optional Full Edition purchase is processed by Google Play Billing. DriveLab does not directly collect or store card information.

## Can I transfer to a replacement phone?

Install DriveLab from Google Play while signed into the Google account that purchased Full Edition, then use the app's restore or entitlement refresh option. Device and entitlement limits still apply where shown in the app or purchase terms.

## Will a Google Play update erase progress?

A normal Google Play update keeps local app data. Do not uninstall the current Play version during routine updates.

Migrating from a legacy GitHub APK is different: the old signing identity prevents an in-place update, so the legacy build must be uninstalled and its local data will be removed.

## Where is the source code?

DriveLab Telem is commercial software. This public repository provides customer documentation and product media, not proprietary Android source, signing keys, license-server private keys, customer databases, or server credentials.
