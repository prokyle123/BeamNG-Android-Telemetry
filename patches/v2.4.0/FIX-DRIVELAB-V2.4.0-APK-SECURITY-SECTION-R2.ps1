$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$ReleaseOutput = Join-Path $Project "release-output"
$ExpectedHash = "43de00ecc650d4be460855ad7ba396ba693e89f804f917599d151f7a2a0d7e56"
$OldHash = "57f610404070d6f5deee471c531962d3d02d9397f7a73a0d5c274fcad7facbf3"
$VirusTotalUrl = "https://www.virustotal.com/gui/file/$ExpectedHash"

$ApkCandidates = @(
    (Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0.apk")
)

$ApkPath = $ApkCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not $ApkPath) {
    $ApkPath = Read-Host "Full path to DriveLab-Telem-v2.4.0.apk"
}

if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "The DriveLab 2.4.0 APK was not found: $ApkPath"
}

$LocalHash = (
    Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256
).Hash.ToLowerInvariant()

if ($LocalHash -ne $ExpectedHash) {
    throw "The APK does not match the verified VirusTotal report. Expected $ExpectedHash but found $LocalHash."
}

$ReceiptCandidates = @(
    (Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-VirusTotal.txt"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0-VirusTotal.txt"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0-VirusTotal.txt")
)

$JsonCandidates = @(
    (Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-VirusTotal.json"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0-VirusTotal.json"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0-VirusTotal.json")
)

$UrlCandidates = @(
    (Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-VirusTotal-URL.txt"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0-VirusTotal-URL.txt"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0-VirusTotal-URL.txt")
)

$ReceiptPath = $ReceiptCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

$JsonPath = $JsonCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

$UrlPath = $UrlCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not $ReceiptPath) {
    throw "DriveLab-Telem-v2.4.0-VirusTotal.txt was not found in release-output, Desktop, or Downloads."
}

if (-not $JsonPath) {
    throw "DriveLab-Telem-v2.4.0-VirusTotal.json was not found in release-output, Desktop, or Downloads."
}

if (-not $UrlPath) {
    throw "DriveLab-Telem-v2.4.0-VirusTotal-URL.txt was not found in release-output, Desktop, or Downloads."
}

$Target = Read-Host "Pi SSH target [kali@ak47]"
if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = "kali@ak47"
}

$Ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$Scp = Get-Command scp.exe -ErrorAction SilentlyContinue

if (-not $Ssh -or -not $Scp) {
    throw "Windows OpenSSH ssh.exe and scp.exe are required."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LocalScript = Join-Path $env:TEMP "fix-drivelab-security-card-r2-$Timestamp.py"
$RemoteScript = "/tmp/fix-drivelab-security-card-r2-$Timestamp.py"
$RemoteReceipt = "/tmp/DriveLab-Telem-v2.4.0-VirusTotal-$Timestamp.txt"
$RemoteJson = "/tmp/DriveLab-Telem-v2.4.0-VirusTotal-$Timestamp.json"
$RemoteUrl = "/tmp/DriveLab-Telem-v2.4.0-VirusTotal-URL-$Timestamp.txt"
$Utf8 = [System.Text.UTF8Encoding]::new($false)

$Python = @'
from pathlib import Path
from datetime import datetime
import html
import re
import shutil
import subprocess
import time
import urllib.request

ROOT = Path("/opt/drivelab-site")
SERVICE = "drivelab-site.service"
HEALTH_URL = "http://127.0.0.1:8790/healthz"
HOME_URL = "http://127.0.0.1:8790/"

VERSION = "2.4.0"
BUILD = "36"
SHA256 = "__EXPECTED_HASH__"
OLD_SHA256 = "__OLD_HASH__"
VT_URL = "__VT_URL__"
SCAN_DATE_LONG = "July 23, 2026"
SCAN_DATE_ISO = "2026-07-23"
RECEIPT_SOURCE = Path("__REMOTE_RECEIPT__")
JSON_SOURCE = Path("__REMOTE_JSON__")
URL_SOURCE = Path("__REMOTE_URL__")

ALLOWED_SUFFIXES = {".html", ".htm", ".jinja", ".jinja2", ".py"}
VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
}


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def visible_text(markup):
    value = re.sub(r"(?is)<script\b.*?</script>", " ", markup)
    value = re.sub(r"(?is)<style\b.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value).strip().lower()


def parse_nodes(source):
    token_re = re.compile(r"(?is)<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)\b[^>]*?>")
    nodes = []
    stack = []

    for match in token_re.finditer(source):
        closing = bool(match.group(1))
        tag = match.group(2).lower()
        token = match.group(0)

        if not closing:
            if tag in VOID_TAGS or token.rstrip().endswith("/>"):
                continue
            nodes.append({
                "tag": tag,
                "start": match.start(),
                "open_end": match.end(),
                "close_start": None,
                "end": None,
            })
            stack.append(len(nodes) - 1)
            continue

        matching = None
        for position in range(len(stack) - 1, -1, -1):
            if nodes[stack[position]]["tag"] == tag:
                matching = position
                break

        if matching is None:
            continue

        index = stack[matching]
        nodes[index]["close_start"] = match.start()
        nodes[index]["end"] = match.end()
        del stack[matching:]

    return [node for node in nodes if node["end"] is not None]


def find_source_file():
    candidates = []

    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in ALLOWED_SUFFIXES:
            continue
        if "backups" in path.parts:
            continue

        source = read_text(path)
        if not source:
            continue

        lowered = source.lower()
        score = 0
        score += 150 if "verified production apk" in lowered else 0
        score += 80 if "microsoft defender passed" in lowered else 0
        score += 60 if "virustotal report" in lowered else 0
        score += 40 if "verification receipt" in lowered else 0
        score += 40 if "sha-256 details" in lowered else 0
        score += 30 if OLD_SHA256 in lowered else 0
        score += 20 if "production feed online" in lowered else 0

        if score >= 210:
            candidates.append((score, path, source))

    if not candidates:
        raise RuntimeError(
            "Could not find the native VERIFIED PRODUCTION APK card source. No website file was changed."
        )

    candidates.sort(key=lambda item: item[0], reverse=True)
    highest = candidates[0][0]
    tied = [item for item in candidates if item[0] == highest]

    if len(tied) != 1:
        names = "\n".join(str(item[1]) for item in tied)
        raise RuntimeError(
            "More than one equally likely security-card source file was found. No website file was changed.\n"
            + names
        )

    return candidates[0][1], candidates[0][2]


def find_card(source):
    position = source.lower().find("verified production apk")
    if position < 0:
        return None, source

    candidates = []
    for node in parse_nodes(source):
        if node["tag"] not in {"section", "article", "div", "main"}:
            continue
        if not (node["start"] <= position < node["end"]):
            continue

        fragment = source[node["start"]:node["end"]]
        text = visible_text(fragment)
        required = (
            "verified production apk",
            "virustotal report",
            "verification receipt",
            "sha-256 details",
        )

        if all(value in text for value in required):
            candidates.append((node["end"] - node["start"], node, fragment))

    if not candidates:
        # Safe fallback: exact replacements only in the uniquely matched source file.
        return None, source

    candidates.sort(key=lambda item: item[0])
    _, node, fragment = candidates[0]
    return node, fragment


def replace_anchor_href(fragment, anchor_text, href):
    pattern = re.compile(r"(?is)<a\b(?P<attrs>[^>]*)>(?P<body>.*?)</a>")
    changed = 0

    def replacement(match):
        nonlocal changed
        if anchor_text not in visible_text(match.group("body")):
            return match.group(0)

        attrs = match.group("attrs")
        href_pattern = re.compile(r'''(?is)\bhref\s*=\s*(["']).*?\1''')

        if href_pattern.search(attrs):
            attrs = href_pattern.sub(f'href="{href}"', attrs, count=1)
        else:
            attrs = f' href="{href}"' + attrs

        changed += 1
        return f"<a{attrs}>{match.group('body')}</a>"

    updated = pattern.sub(replacement, fragment)
    return updated, changed


def update_fragment(fragment, broad):
    updated = fragment

    if broad:
        updated = re.sub(
            r"DriveLab\s+Telem\s+\d+\.\d+\.\d+\s*\(\d+\)",
            f"DriveLab Telem {VERSION} ({BUILD})",
            updated,
            flags=re.IGNORECASE,
        )
        updated = re.sub(
            r"(?i)\b[a-f0-9]{64}\b",
            SHA256,
            updated,
        )
        updated = re.sub(
            r"https://www\.virustotal\.com/gui/file/[a-fA-F0-9]{64}(?:[^\"'\s<]*)?",
            VT_URL,
            updated,
        )
    else:
        updated = updated.replace("DriveLab Telem 2.2.1 (32)", f"DriveLab Telem {VERSION} ({BUILD})")
        updated = updated.replace(OLD_SHA256, SHA256)
        updated = updated.replace(
            f"https://www.virustotal.com/gui/file/{OLD_SHA256}",
            VT_URL,
        )

    updated = re.sub(
        r"(?i)scanned\s+(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},\s+\d{4}",
        f"scanned {SCAN_DATE_LONG}",
        updated,
    )
    updated = re.sub(
        r"(?i)(scanned\s+(?:utc\s*)?:?\s*)\d{4}-\d{2}-\d{2}(?:[T ][0-9:]+Z?)?",
        lambda match: match.group(1) + SCAN_DATE_ISO,
        updated,
    )
    updated = re.sub(
        r"(?i)VirusTotal\s+\d+\s+engine\s+results",
        "VirusTotal 74 engine results",
        updated,
    )
    updated = re.sub(
        r"(?i)\d+\s+malicious\s*[•·|]\s*\d+\s+suspicious",
        "0 malicious • 0 suspicious",
        updated,
    )

    updated, vt_count = replace_anchor_href(updated, "virustotal report", VT_URL)
    updated, receipt_count = replace_anchor_href(
        updated,
        "verification receipt",
        "/static/security/DriveLab-Telem-v2.4.0-VirusTotal.txt",
    )
    updated, checksum_count = replace_anchor_href(
        updated,
        "sha-256 details",
        "/static/security/DriveLab-Telem-v2.4.0-SHA256.txt",
    )

    if vt_count < 1 or receipt_count < 1 or checksum_count < 1:
        raise RuntimeError(
            "The three existing security links could not all be updated safely. No website file was changed."
        )

    text = visible_text(updated)
    required = (
        f"drivelab telem {VERSION} ({BUILD})",
        "0 malicious",
        "0 suspicious",
        "virustotal 74 engine results",
    )

    for value in required:
        if value not in text:
            raise RuntimeError(f"Security-card validation failed: missing {value}")

    if SHA256 not in updated or VT_URL not in updated:
        raise RuntimeError("Security-card hash or VirusTotal URL validation failed.")

    return updated


def choose_static_root():
    choices = [
        ROOT / "static",
        ROOT / "site" / "static",
        ROOT / "app" / "static",
        ROOT / "public" / "static",
    ]

    for choice in choices:
        if choice.exists() and choice.is_dir():
            return choice

    (ROOT / "static").mkdir(parents=True, exist_ok=True)
    return ROOT / "static"


def restart_and_check():
    subprocess.run(["systemctl", "restart", SERVICE], check=True)
    time.sleep(3)

    with urllib.request.urlopen(HEALTH_URL, timeout=12) as response:
        health = response.read().decode("utf-8", errors="replace").strip()
        if response.status != 200:
            raise RuntimeError(f"Health check returned HTTP {response.status}")

    with urllib.request.urlopen(HOME_URL, timeout=12) as response:
        rendered = response.read().decode("utf-8", errors="replace")
        if response.status != 200:
            raise RuntimeError(f"Homepage returned HTTP {response.status}")

    return health, rendered


if not ROOT.exists():
    raise SystemExit(f"Website root was not found: {ROOT}")

for required_file in (RECEIPT_SOURCE, JSON_SOURCE, URL_SOURCE):
    if not required_file.exists():
        raise RuntimeError(f"Uploaded verification file was not found: {required_file}")

page, source = find_source_file()
node, old_fragment = find_card(source)
new_fragment = update_fragment(old_fragment, broad=node is not None)

if new_fragment == old_fragment:
    raise SystemExit("The native security card already contains the exact DriveLab 2.4.0 verification data.")

if node is None:
    updated_source = new_fragment
else:
    updated_source = source[:node["start"]] + new_fragment + source[node["end"]:]

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_root = ROOT / "backups" / f"before-v240-security-card-r2-{stamp}"
backup_root.mkdir(parents=True, exist_ok=True)
backup_page = backup_root / page.name
shutil.copy2(page, backup_page)

static_root = choose_static_root()
security_dir = static_root / "security"
security_dir.mkdir(parents=True, exist_ok=True)

receipt_target = security_dir / "DriveLab-Telem-v2.4.0-VirusTotal.txt"
json_target = security_dir / "DriveLab-Telem-v2.4.0-VirusTotal.json"
url_target = security_dir / "DriveLab-Telem-v2.4.0-VirusTotal-URL.txt"
checksum_target = security_dir / "DriveLab-Telem-v2.4.0-SHA256.txt"

static_targets = [receipt_target, json_target, url_target, checksum_target]
static_backups = {}

for target in static_targets:
    if target.exists():
        backup = backup_root / target.name
        shutil.copy2(target, backup)
        static_backups[target] = backup

try:
    shutil.copy2(RECEIPT_SOURCE, receipt_target)
    shutil.copy2(JSON_SOURCE, json_target)
    shutil.copy2(URL_SOURCE, url_target)
    checksum_target.write_text(
        "DriveLab Telem 2.4.0\n"
        "Build: 36\n"
        f"SHA-256: {SHA256}\n"
        f"VirusTotal: {VT_URL}\n",
        encoding="utf-8",
    )

    temporary = page.with_name(page.name + ".v240-security-r2.tmp")
    temporary.write_text(updated_source, encoding="utf-8")
    temporary.replace(page)

    health, rendered = restart_and_check()
    rendered_lower = rendered.lower()

    rendered_requirements = (
        "verified production apk",
        "drivelab telem 2.4.0 (36)",
        "0 malicious",
        "0 suspicious",
        "virustotal 74 engine results",
        SHA256[:16],
    )

    for value in rendered_requirements:
        if value.lower() not in rendered_lower:
            raise RuntimeError(f"Rendered homepage validation failed: missing {value}")

    print("Native VERIFIED PRODUCTION APK card updated successfully.")
    print(f"Source file: {page}")
    print(f"Static security files: {security_dir}")
    print(f"Version: {VERSION} ({BUILD})")
    print(f"SHA-256: {SHA256}")
    print("VirusTotal: 0 malicious, 0 suspicious, 74 engine results")
    print(f"Report: {VT_URL}")
    print(f"Backup: {backup_root}")
    print(f"Health: {health}")

except Exception:
    shutil.copy2(backup_page, page)

    for target in static_targets:
        if target in static_backups:
            shutil.copy2(static_backups[target], target)
        elif target.exists():
            target.unlink()

    try:
        restart_and_check()
    except Exception:
        pass

    raise
'@

$Python = $Python.Replace("__EXPECTED_HASH__", $ExpectedHash)
$Python = $Python.Replace("__OLD_HASH__", $OldHash)
$Python = $Python.Replace("__VT_URL__", $VirusTotalUrl)
$Python = $Python.Replace("__REMOTE_RECEIPT__", $RemoteReceipt)
$Python = $Python.Replace("__REMOTE_JSON__", $RemoteJson)
$Python = $Python.Replace("__REMOTE_URL__", $RemoteUrl)

[System.IO.File]::WriteAllText(
    $LocalScript,
    $Python,
    $Utf8
)

Write-Host ""
Write-Host "===== COPYING VERIFIED 2.4.0 SECURITY DATA =====" -ForegroundColor Cyan

& $Scp.Source $LocalScript "${Target}:$RemoteScript"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the security updater to the Pi."
}

& $Scp.Source $ReceiptPath "${Target}:$RemoteReceipt"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the VirusTotal text receipt to the Pi."
}

& $Scp.Source $JsonPath "${Target}:$RemoteJson"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the VirusTotal JSON receipt to the Pi."
}

& $Scp.Source $UrlPath "${Target}:$RemoteUrl"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the VirusTotal URL receipt to the Pi."
}

Write-Host ""
Write-Host "===== UPDATING THE NATIVE VERIFIED APK CARD =====" -ForegroundColor Cyan

& $Ssh.Source -t $Target "sudo python3 '$RemoteScript'"
if ($LASTEXITCODE -ne 0) {
    throw "The R2 security-card update failed. The website was left unchanged or restored automatically."
}

& $Ssh.Source $Target "rm -f '$RemoteScript' '$RemoteReceipt' '$RemoteJson' '$RemoteUrl'" | Out-Null

Remove-Item -LiteralPath $LocalScript -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB 2.4.0 SECURITY CARD UPDATED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Version: 2.4.0 build 36" -ForegroundColor Cyan
Write-Host "VirusTotal: 0 malicious, 0 suspicious, 74 engine results" -ForegroundColor Cyan
Write-Host "SHA-256: $ExpectedHash" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+F5 when viewing the website." -ForegroundColor Yellow
