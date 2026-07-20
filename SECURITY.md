# DriveLab Telem security and APK verification

## Current production APK

| Item | Verified value |
|---|---|
| Version | **2.1.0 (32)** |
| Android package | `com.auroramediagroup.drivelab` |
| APK filename | `DriveLab-Telem-v2.1.0.apk` |
| APK SHA-256 | `57f610404070d6f5deee471c531962d3d02d9397f7a73a0d5c274fcad7facbf3` |
| Signing certificate SHA-256 | `c27df4a0e5f3cd2f99d7240a49f3ce7936340d3359420872a651e3d4fed8b82d` |
| VirusTotal result | **0 of 74 engine results flagged the APK** |
| Scan time | `2026-07-20T18:00:34Z` |

[View the independent VirusTotal report](https://www.virustotal.com/gui/file/57f610404070d6f5deee471c531962d3d02d9397f7a73a0d5c274fcad7facbf3/detection)

The exact APK was matched against DriveLab's signed production update feed, verified with Android's `apksigner`, and submitted for a fresh VirusTotal multi-engine analysis. Microsoft Defender status for the publisher's local release copy: **passed**.

## Verify a download

On Windows PowerShell:

```powershell
Get-FileHash .\DriveLab-Telem-v2.1.0.apk -Algorithm SHA256
```

The result must match:

```text
57f610404070d6f5deee471c531962d3d02d9397f7a73a0d5c274fcad7facbf3
```

Install updates directly over the existing app. Do not uninstall first, because uninstalling removes local DriveLab data.

## Important limitation

No antivirus or malware-scanning service can guarantee that software is completely risk-free. The published result is a point-in-time independent scan of one exact SHA-256 build. Download only from the official DriveLab website, the signed in-app updater, or this GitHub repository, and confirm the checksum before manual installation.

## Reporting a security concern

Do not post license keys, refresh tokens, admin tokens, private customer information, or signing material in a public issue. Contact **auroramediagroup1@gmail.com** with the app version, APK SHA-256, device model, Android version, and a description of the concern.
