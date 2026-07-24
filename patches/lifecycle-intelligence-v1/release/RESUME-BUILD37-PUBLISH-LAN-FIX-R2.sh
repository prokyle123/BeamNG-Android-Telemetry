#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_SHA="598ecb27ace565c169bf51d7cff1656308f33ed63752bbb01ef80e7b525765f0"
VERSION_NAME="2.4.0"
VERSION_CODE="37"
LAN_IP="192.168.1.132"
SITE_BASE="http://192.168.1.132:8790"
PUBLIC_API="https://license.drivelabregistration.org"
PUBLIC_SITE="https://drivelabregistration.org"
SITE_ENV="/etc/drivelab-site/site.env"
UPDATES="/var/lib/drivelab-license/updates"
SITE_ROOT="/opt/drivelab-site"
SITE_INDEX="$SITE_ROOT/public/index.html"
OWNER_SECURITY_DIR="$SITE_ROOT/static/security"
PUBLIC_SECURITY_DIR="$SITE_ROOT/public/assets/security"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/backups/drivelab-release-publish-lan-fix-r2/$STAMP"
CHANGED=0

rollback() {
    echo
    echo "===== AUTOMATIC RELEASE ROLLBACK ====="
    set +e
    if [[ -d "$BACKUP/updates" ]]; then
        rm -rf "$UPDATES"
        cp -a "$BACKUP/updates" "$UPDATES"
    fi
    if [[ -f "$BACKUP/index.html" ]]; then
        install -o drivelab-site -g drivelab-site -m 0644 "$BACKUP/index.html" "$SITE_INDEX"
    fi
    if [[ -d "$BACKUP/owner-security" ]]; then
        rm -rf "$OWNER_SECURITY_DIR"
        cp -a "$BACKUP/owner-security" "$OWNER_SECURITY_DIR"
    fi
    if [[ -d "$BACKUP/public-security" ]]; then
        rm -rf "$PUBLIC_SECURITY_DIR"
        cp -a "$BACKUP/public-security" "$PUBLIC_SECURITY_DIR"
    elif [[ -e "$PUBLIC_SECURITY_DIR" ]]; then
        rm -rf "$PUBLIC_SECURITY_DIR"
    fi
    if [[ -f "$BACKUP/site.env" ]]; then
        install -o root -g drivelab-site -m 0640 "$BACKUP/site.env" "$SITE_ENV"
    fi
    systemctl restart drivelab-site.service || true
    systemctl start drivelab-public-status-publisher.service || true
    echo "Rollback attempted from: $BACKUP"
}

on_error() {
    local status="$1"
    local line="$2"
    trap - ERR
    echo "Release repair/resume failed at line $line with status $status." >&2
    if [[ "$CHANGED" -eq 1 ]]; then rollback; fi
    echo
    echo "===== DRIVELAB SITE STATUS =====" >&2
    systemctl --no-pager --full status drivelab-site.service >&2 || true
    echo
    echo "===== RECENT DRIVELAB SITE LOGS =====" >&2
    journalctl -u drivelab-site.service -n 60 --no-pager >&2 || true
    exit "$status"
}
trap 'on_error $? $LINENO' ERR

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

find_release_dir() {
    local candidate
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if [[ -f "$candidate/DriveLab-Telem-v2.4.0.apk" ]] && \
           [[ "$(sha256sum "$candidate/DriveLab-Telem-v2.4.0.apk" | awk '{print $1}')" == "$EXPECTED_SHA" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find /home/kali -maxdepth 1 -type d -name 'drivelab-release-2.4.0-build37-*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
    return 1
}

REMOTE_DIR="$(find_release_dir)" || {
    echo "Could not find the previously uploaded build 37 release package with SHA-256 $EXPECTED_SHA" >&2
    exit 1
}
APK="$REMOTE_DIR/DriveLab-Telem-v2.4.0.apk"
NOTES="$REMOTE_DIR/release-notes.txt"
SECURITY_BLOCK="$REMOTE_DIR/security-block.html"

for required in \
    "$APK" \
    "$NOTES" \
    "$SECURITY_BLOCK" \
    "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt" \
    "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.json" \
    "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal-URL.txt" \
    "$REMOTE_DIR/DriveLab-Telem-v2.4.0-SHA256.txt"; do
    [[ -f "$required" ]] || { echo "Missing verified release file: $required" >&2; exit 1; }
done
[[ "$(sha256sum "$APK" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || { echo "Uploaded APK hash mismatch." >&2; exit 1; }
grep -Fq "Build: 37" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt"
grep -Fq "$EXPECTED_SHA" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt"
grep -Fq "Malicious: 0" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt"
grep -Fq "Suspicious: 0" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt"

printf '\n============================================================\n'
printf 'DRIVELAB BUILD 37 RELEASE REPAIR/RESUME - LAN FIX R2\n'
printf '============================================================\n'
printf 'Release package: %s\n' "$REMOTE_DIR"
printf 'Website target:  %s\n' "$SITE_BASE"
printf 'Expected SHA:    %s\n' "$EXPECTED_SHA"

printf '\n===== VERIFYING LAN ADDRESS AND CURRENT SITE CONFIGURATION =====\n'
ip -4 addr show | grep -Fq "inet $LAN_IP/" || {
    echo "The Pi does not currently own LAN address $LAN_IP. No configuration was changed." >&2
    ip -4 addr show >&2
    exit 1
}
[[ -f "$SITE_ENV" ]] || { echo "Missing site environment file: $SITE_ENV" >&2; exit 1; }
printf 'Current non-secret site binding settings:\n'
grep -E '^(SITE_HOST|SITE_PORT)=' "$SITE_ENV" || true
systemctl --no-pager --full status drivelab-site.service || true
ss -ltnp | grep -E ':(8790)\b' || true

printf '\n===== CREATING VERIFIED PRE-REPAIR BACKUP =====\n'
mkdir -p "$BACKUP"
chmod 0700 "$BACKUP"
cp -a "$UPDATES" "$BACKUP/updates"
cp -a "$SITE_INDEX" "$BACKUP/index.html"
cp -a "$OWNER_SECURITY_DIR" "$BACKUP/owner-security"
if [[ -d "$PUBLIC_SECURITY_DIR" ]]; then cp -a "$PUBLIC_SECURITY_DIR" "$BACKUP/public-security"; fi
cp -a "$SITE_ENV" "$BACKUP/site.env"
sha256sum "$APK" > "$BACKUP/release-apk.sha256"
CHANGED=1
printf 'Backup: %s\n' "$BACKUP"

printf '\n===== REPAIRING WEBSITE BINDING TO THE LAN ADDRESS =====\n'
python3 - "$SITE_ENV" "$LAN_IP" <<'PYENV'
import sys
from pathlib import Path
path = Path(sys.argv[1])
host = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
updates = {"SITE_HOST": host, "SITE_PORT": "8790"}
out = []
seen = set()
for line in lines:
    stripped = line.strip()
    if stripped and not stripped.startswith("#") and "=" in line:
        key = line.split("=", 1)[0].strip()
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PYENV
chown root:drivelab-site "$SITE_ENV"
chmod 0640 "$SITE_ENV"
systemctl restart drivelab-site.service

SITE_READY=0
for attempt in $(seq 1 40); do
    if curl -fsS --max-time 5 "$SITE_BASE/healthz" >/dev/null; then
        SITE_READY=1
        break
    fi
    sleep 1
done
[[ "$SITE_READY" -eq 1 ]] || { echo "Website did not become healthy at $SITE_BASE" >&2; exit 1; }
printf 'Website is healthy at %s\n' "$SITE_BASE"
printf 'Active non-secret site binding settings:\n'
grep -E '^(SITE_HOST|SITE_PORT)=' "$SITE_ENV"
ss -ltnp | grep -E '192\.168\.1\.132:8790\b'

printf '\n===== REPUBLISHING SIGNED BUILD 37 UPDATE =====\n'
/usr/local/bin/drivelab-license-admin publish-update \
    --apk "$APK" \
    --version-code "$VERSION_CODE" \
    --version-name "$VERSION_NAME" \
    --notes-file "$NOTES" \
    --min-android-sdk 26 \
    --channel stable

printf '\n===== INSTALLING VERIFIED VIRUSTOTAL DATA =====\n'
install -d -o drivelab-site -g drivelab-site -m 0755 "$OWNER_SECURITY_DIR"
install -d -o drivelab-site -g drivelab-site -m 0755 "$PUBLIC_SECURITY_DIR"
for name in \
    DriveLab-Telem-v2.4.0-VirusTotal.txt \
    DriveLab-Telem-v2.4.0-VirusTotal.json \
    DriveLab-Telem-v2.4.0-VirusTotal-URL.txt \
    DriveLab-Telem-v2.4.0-SHA256.txt; do
    install -o drivelab-site -g drivelab-site -m 0644 "$REMOTE_DIR/$name" "$OWNER_SECURITY_DIR/$name"
    install -o drivelab-site -g drivelab-site -m 0644 "$REMOTE_DIR/$name" "$PUBLIC_SECURITY_DIR/$name"
done

python3 - "$SITE_INDEX" "$SECURITY_BLOCK" <<'PYHTML'
import re
import sys
from pathlib import Path
index = Path(sys.argv[1])
block_path = Path(sys.argv[2])
text = index.read_text(encoding="utf-8")
block = block_path.read_text(encoding="utf-8").strip()
block = block.replace('/static/security/', '/assets/security/')
pattern = re.compile(r"<!-- DRIVELAB DOWNLOAD TRUST START -->.*?<!-- DRIVELAB DOWNLOAD TRUST END -->", re.S)
updated, count = pattern.subn(block, text, count=1)
if count != 1:
    raise SystemExit(f"Expected one website trust block, found {count}")
index.write_text(updated, encoding="utf-8")
PYHTML
chown drivelab-site:drivelab-site "$SITE_INDEX"
chmod 0644 "$SITE_INDEX"
systemctl restart drivelab-site.service
systemctl start drivelab-public-status-publisher.service

SITE_READY=0
for attempt in $(seq 1 40); do
    if curl -fsS --max-time 5 "$SITE_BASE/healthz" >/dev/null; then
        SITE_READY=1
        break
    fi
    sleep 1
done
[[ "$SITE_READY" -eq 1 ]] || { echo "Website did not return after release data installation." >&2; exit 1; }

printf '\n===== VALIDATING LAN WEBSITE AND SERVED RECEIPTS =====\n'
curl -fsS --max-time 10 "$SITE_BASE/" > "$BACKUP/live-site.html"
grep -Fq "$EXPECTED_SHA" "$BACKUP/live-site.html"
grep -Fq 'DriveLab Telem 2.4.0 (37)' "$BACKUP/live-site.html"
grep -Fq '/assets/security/DriveLab-Telem-v2.4.0-VirusTotal.txt' "$BACKUP/live-site.html"
curl -fsS --max-time 10 "$SITE_BASE/assets/security/DriveLab-Telem-v2.4.0-VirusTotal.txt" > "$BACKUP/live-vt-receipt.txt"
grep -Fq "Build: 37" "$BACKUP/live-vt-receipt.txt"
grep -Fq "$EXPECTED_SHA" "$BACKUP/live-vt-receipt.txt"
grep -Fq "Malicious: 0" "$BACKUP/live-vt-receipt.txt"
grep -Fq "Suspicious: 0" "$BACKUP/live-vt-receipt.txt"

printf '\n===== VALIDATING PUBLIC SIGNED UPDATE FEED =====\n'
curl -fsS --max-time 20 "$PUBLIC_API/v1/update/latest" > "$BACKUP/public-update-bundle.json"
python3 - "$BACKUP/public-update-bundle.json" "$EXPECTED_SHA" <<'PYUPDATE'
import json
import sys
from pathlib import Path
bundle = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload = bundle.get("payload")
if isinstance(payload, str):
    manifest = json.loads(payload)
elif isinstance(payload, dict):
    manifest = payload
else:
    raise SystemExit("Signed update response did not contain a usable payload")
expected = sys.argv[2]
assert manifest.get("version_name") == "2.4.0", manifest
assert int(manifest.get("version_code", 0)) == 37, manifest
assert manifest.get("apk_sha256") == expected, manifest
assert manifest.get("apk_filename") == "DriveLab-Telem-v2.4.0.apk", manifest
print("Signed manifest is DriveLab 2.4.0 build 37 with the expected SHA-256.")
PYUPDATE
curl -fsSL --max-time 120 "$PUBLIC_API/v1/public/download/latest" -o "$BACKUP/public-download.apk"
[[ "$(sha256sum "$BACKUP/public-download.apk" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || {
    echo "Public download SHA-256 mismatch." >&2
    exit 1
}
/usr/local/bin/drivelab-license-admin update-status > "$BACKUP/update-status-after.txt"

printf '\n===== CHECKING PUBLIC WEBSITE =====\n'
PUBLIC_SITE_OK=0
for attempt in $(seq 1 12); do
    if curl -fsS --max-time 20 "$PUBLIC_SITE/" > "$BACKUP/public-site.html" && \
       grep -Fq "$EXPECTED_SHA" "$BACKUP/public-site.html" && \
       grep -Fq '/assets/security/DriveLab-Telem-v2.4.0-VirusTotal.txt' "$BACKUP/public-site.html"; then
        PUBLIC_SITE_OK=1
        break
    fi
    sleep 5
done
if [[ "$PUBLIC_SITE_OK" -eq 1 ]]; then
    printf 'Public website contains the exact build 37 SHA-256 and working security receipt path.\n'
else
    printf 'WARNING: LAN website, public feed, and public APK are correct, but the public HTML has not reflected the change yet. This may be tunnel or cache delay.\n' >&2
fi

CHANGED=0
trap - ERR
printf '\n============================================================\n'
printf 'DRIVELAB BUILD 37 PUBLISHED SUCCESSFULLY\n'
printf '============================================================\n'
printf 'Backup:        %s\n' "$BACKUP"
printf 'Release files: %s\n' "$REMOTE_DIR"
printf 'SHA-256:       %s\n' "$EXPECTED_SHA"
printf 'Website:       %s\n' "$SITE_BASE"
printf 'VirusTotal, signed feed, public APK download, LAN website, and served receipt links were validated.\n'
