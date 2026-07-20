# DriveLab Telem Privacy Policy

**Effective:** July 20, 2026  
**Publisher:** Kyle Williams / Aurora Media Group  
**Contact:** auroramediagroup1@gmail.com

## Normal gameplay telemetry

DriveLab Telem receives gameplay telemetry directly from a computer on the same local network using BeamNG.drive OutGauge and MotionSim UDP protocols. Outside RaceLink, gameplay telemetry, rolling charts, driver progress, achievements, dashboard layouts, TrackLab courses, saved sessions, and crash samples remain in Android app-private storage and are not uploaded to the licensing server.

## RaceLink online features

RaceLink is optional and is used only when a Full Edition driver opens and operates its online features. To provide friends, invitations, private rooms, lobby chat, shared course setup, ready checks, synchronized countdowns, live standings, and results, the app may send and store:

- a randomly assigned RaceLink profile identifier and `DL-XXXXXX` friend code
- chosen display nickname
- friend requests, friend relationships, invitations, and room membership
- private room code, host identity, room status, capacity, and timestamps
- selected TrackLab course definition and race configuration
- lobby chat messages
- online presence, Ready state, connection timestamps, and heartbeat information
- race timing, checkpoint, sector, lap, progress, position, speed/status summaries, standings, and final results

RaceLink does not upload general saved-session history or unrelated telemetry merely because the app is installed. RaceLink data is transmitted when the driver uses RaceLink and as needed to maintain an active room. Room codes are private but should not be treated as passwords for sensitive information.

## License activation data

Online activation and periodic license refreshes send the entered serial key, a randomly generated installation ID, an Android Keystore public key, app version, request timestamps, and security nonces to the publisher-operated licensing server. The raw serial key is checked transiently and stored server-side only as a one-way keyed hash. Refresh tokens are also stored server-side only as one-way keyed hashes.

The licensing database may contain an optional customer email or order reference entered by the publisher, license status, device allowance, activation timestamps, app version, installation ID, device public key and hash, and activation history. Connection IP addresses may be processed temporarily for rate limiting, abuse prevention, hosting security, and server logs.

## Payment provider and infrastructure

The Buy button opens an external checkout page in the phone's browser. The payment provider processes payment information under its own privacy policy. DriveLab Telem does not receive or store card numbers. The licensing, update, and RaceLink APIs may use Cloudflare Tunnel or related hosting infrastructure, which may process network request information under the provider's terms.

## Advertising, analytics, and permissions

The app contains no advertising SDK, behavioral analytics SDK, microphone access, camera access, contacts access, phone access, SMS access, advertising ID use, or broad storage permission. Position information used by TrackLab and RaceLink comes from BeamNG MotionSim game telemetry, not the Android device's GPS location permission.

## User-initiated sharing

The app can generate result images and sharing text. That content leaves the app only when the user chooses Android's Share action and selects a destination. RaceLink chat and room activity are transmitted when the user chooses to participate in RaceLink.

## Retention and control

Local app data remains until the user clears it or uninstalls the app. License and activation records may be retained while a license is active and afterward for support, fraud prevention, accounting, and audit purposes.

RaceLink profiles, friendships, invitations, room history, chat, race data, and operational event history may be retained for service operation, abuse prevention, troubleshooting, support, and product reliability. Expired rooms and older operational data may be deleted or compacted. Contact the publisher for privacy or deletion requests that can be reasonably associated with your license or RaceLink profile.

## Security

License certificates and update manifests are digitally signed. Device refresh tokens are encrypted using Android Keystore, and server-side serial and refresh secrets are stored as one-way keyed hashes. RaceLink requests are tied to activated app installations and use authenticated request signing. No system can guarantee absolute security.

## Contact

Privacy or data questions: **auroramediagroup1@gmail.com**
