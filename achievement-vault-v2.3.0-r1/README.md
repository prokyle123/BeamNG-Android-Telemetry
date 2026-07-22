# DriveLab 2.3.0 — Achievement Vault Rebuilt

This patch replaces the original tier-heavy 1,001-achievement catalog with **1,000 distinct driving challenges** plus the final **DriveLab Legend** achievement.

## What changes

- Ten challenge categories with 100 goals each
- Common, Skilled, Expert, Extreme, Insane, and Legendary rarity levels
- Secret achievements with hidden requirements until unlocked
- Multi-condition, streak, recovery, full-drive, and alternative-route goals
- Live tracking for launches, speed holds, reverse driving, shifting, drifting, braking, G-force, rollovers, endurance, heat, impacts, recoveries, and unusual pedal combinations
- No course creation, manual recording, BeamNG mod, or PC helper required

All rules use the existing stock OutGauge and MotionSim telemetry already processed by DriveLab.

## Existing customer data

The migration preserves:

- XP and driver level
- Speed, Drift, Control, and Endurance specialty levels
- Cumulative distance, drive time, sessions, shifts, braking tests, quarter-mile runs, impacts, and personal records
- License activation and Android signing compatibility
- TrackLab courses and laps
- Auto Co-Driver settings and edited notes
- RaceLink data
- Saved sessions and crashes

The old achievement IDs are retired because they represented the former catalog. Their unlocked count is preserved as a **Legacy Vault** record, and anyone with at least one old unlock receives the new **Original Driver** achievement.

## Apply, test, and build

1. Extract the downloaded ZIP.
2. Open `achievement-vault-v2.3.0-r1`.
3. Connect one authorized Android device when automatic installation is desired.
4. Double-click `RUN-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0.bat`.

The runner will:

1. Find the configured DriveLab 2.2.1 Windows project.
2. Verify that the permanent signing configuration exists.
3. Create a timestamped source backup.
4. Apply the catalog, rule engine, migration, UI, tests, version, changelog, and release notes.
5. Run unit tests, release lint, and the signed release build.
6. Verify the APK signature with Android `apksigner`.
7. Copy the verified APK and SHA-256 checksum to the Desktop.
8. Install it over the existing app when exactly one authorized device is connected.
9. Restore the original source automatically if patching or building fails.

## Test before publishing

Confirm these behaviors in Full Edition:

- Existing XP, levels, records, courses, Auto Co-Driver data, RaceLink data, sessions, and license activation remain intact.
- The Achievement Vault shows rarity instead of numbered tiers.
- The Legacy Vault count matches the former unlocked total.
- `Original Driver` unlocks for an upgraded installation.
- Common live challenges unlock during normal driving.
- Reverse, pedal-combination, shifting, drift, braking, impact, and recovery challenges respond correctly.
- Secret challenges hide their titles and conditions until unlocked.
- Clearing Driver Data resets the new catalog and live counters.
- Reopening the app preserves new unlocks and progress.
- Free Edition still cannot persist paid progression.

## Publishing

The patch does **not** publish an APK, update manifest, GitHub Release, or website update. Release only after live Free/Full testing passes.
