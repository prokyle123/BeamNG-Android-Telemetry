$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedVersion = "2.4.0"
$ExpectedBuild = 36
$ExpectedHash = "43de00ecc650d4be460855ad7ba396ba693e89f804f917599d151f7a2a0d7e56"
$VirusTotalUrl = "https://www.virustotal.com/gui/file/$ExpectedHash"
$ScanResult = "0 / 74 detections"
$ScanDate = "2026-07-23"

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$Candidates = @(
    (Join-Path $Project "release-output\DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0.apk")
)

$ApkPath = $Candidates |
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
    throw "The selected APK does not match the verified VirusTotal report. Expected $ExpectedHash but found $LocalHash."
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
$LocalScript = Join-Path $env:TEMP "fix-drivelab-apk-security-$Timestamp.py"
$RemoteScript = "/tmp/fix-drivelab-apk-security-$Timestamp.py"
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

VERSION = "__VERSION__"
BUILD = "__BUILD__"
SHA256 = "__SHA256__"
VT_URL = "__VT_URL__"
SCAN_RESULT = "__SCAN_RESULT__"
SCAN_DATE = "__SCAN_DATE__"

ALLOWED_SUFFIXES = {
    ".html", ".htm", ".jinja", ".jinja2", ".py"
}
VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
}
SKIP_PARTS = {"backups", "__pycache__", ".git"}


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def visible_text(markup):
    value = re.sub(r"(?is)<script\b.*?</script>", " ", markup)
    value = re.sub(r"(?is)<style\b.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", html.unescape(value)).strip().lower()


def parse_nodes(markup):
    token_re = re.compile(r"(?is)<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)\b[^>]*?>")
    nodes = []
    stack = []

    for match in token_re.finditer(markup):
        closing = bool(match.group(1))
        tag = match.group(2).lower()
        token = match.group(0)

        if not closing:
            if tag in VOID_TAGS or token.rstrip().endswith("/>"):
                continue

            parent = stack[-1] if stack else None
            nodes.append({
                "tag": tag,
                "start": match.start(),
                "open_end": match.end(),
                "close_start": None,
                "end": None,
                "parent": parent,
            })
            stack.append(len(nodes) - 1)
            continue

        position = None
        for index in range(len(stack) - 1, -1, -1):
            if nodes[stack[index]]["tag"] == tag:
                position = index
                break

        if position is None:
            continue

        node_index = stack[position]
        nodes[node_index]["close_start"] = match.start()
        nodes[node_index]["end"] = match.end()
        del stack[position:]

    return [node for node in nodes if node["end"] is not None]


def find_page():
    candidates = []

    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in ALLOWED_SUFFIXES:
            continue
        if any(part.lower() in SKIP_PARTS for part in path.parts):
            continue

        source = read_text(path)
        if not source:
            continue

        lowered = source.lower()
        if "apk security verification" not in lowered:
            continue
        if "permanent signing" not in lowered or "virustotal" not in lowered:
            continue

        score = 0
        score += lowered.count("apk security verification") * 100
        score += lowered.count("view virustotal report") * 40
        score += lowered.count("permanent signing") * 30
        score += 20 if "</body>" in lowered else 0
        candidates.append((score, path, source))

    if not candidates:
        raise RuntimeError(
            "Could not find the existing APK security verification section. No website file was changed."
        )

    candidates.sort(key=lambda item: item[0], reverse=True)
    highest = candidates[0][0]
    tied = [item for item in candidates if item[0] == highest]

    if len(tied) != 1:
        names = "\n".join(str(item[1]) for item in tied)
        raise RuntimeError(
            "More than one equally likely security-section source file was found. No website file was changed.\n"
            + names
        )

    _, path, source = tied[0]
    return path, source


def find_security_section(source):
    phrase_position = source.lower().find("apk security verification")
    if phrase_position < 0:
        raise RuntimeError("The security heading disappeared before editing.")

    candidates = []
    for node in parse_nodes(source):
        if node["tag"] not in {"section", "article", "div", "main"}:
            continue
        if not (node["start"] <= phrase_position < node["end"]):
            continue

        fragment = source[node["start"]:node["end"]]
        text = visible_text(fragment)
        required = (
            "apk security verification",
            "version",
            "sha-256",
            "virustotal",
            "permanent signing",
        )

        if all(value in text for value in required):
            candidates.append((node["end"] - node["start"], node, fragment))

    if not candidates:
        raise RuntimeError(
            "Could not isolate the existing themed APK security verification block. No website file was changed."
        )

    candidates.sort(key=lambda item: item[0])
    _, node, fragment = candidates[0]
    return node, fragment


def replace_report_anchor(fragment):
    anchor_pattern = re.compile(
        r"(?is)<a\b(?P<attrs>[^>]*)>(?P<body>.*?)</a>"
    )

    def replace_anchor(match):
        body_text = visible_text(match.group("body"))
        if "virustotal" not in body_text:
            return match.group(0)

        attrs = match.group("attrs")
        href_pattern = re.compile(r'''(?is)\bhref\s*=\s*(["']).*?\1''')

        if href_pattern.search(attrs):
            attrs = href_pattern.sub(
                f'href="{VT_URL}"',
                attrs,
                count=1,
            )
        else:
            attrs = f' href="{VT_URL}"' + attrs

        return f"<a{attrs}>{match.group('body')}</a>"

    updated, count = anchor_pattern.subn(replace_anchor, fragment)

    if VT_URL not in updated:
        raise RuntimeError(
            "The VirusTotal report button could not be updated safely. No website file was changed."
        )

    return updated


def update_security_section(fragment):
    updated = fragment

    updated = re.sub(
        r"https://www\.virustotal\.com/gui/file/[a-fA-F0-9]{64}(?:[^\"'\s<]*)?",
        VT_URL,
        updated,
    )

    updated = replace_report_anchor(updated)

    updated = re.sub(
        r"(?<![0-9])(?:1|2)\.\d+\.\d+(?![0-9])",
        VERSION,
        updated,
    )

    updated = re.sub(
        r"(?i)\b[a-f0-9]{64}\b",
        SHA256,
        updated,
    )

    updated = re.sub(
        r"(?i)\b\d+\s*/\s*\d+\s+detections\b",
        SCAN_RESULT,
        updated,
    )

    updated = re.sub(
        r"(?i)(scanned\s+(?:utc\s*)?:?\s*)\d{4}-\d{2}-\d{2}(?:[T ][0-9:]+Z?)?",
        lambda match: match.group(1) + SCAN_DATE,
        updated,
    )

    if VERSION not in visible_text(updated):
        raise RuntimeError("Version validation failed inside the security section.")
    if SHA256 not in updated:
        raise RuntimeError("SHA-256 validation failed inside the security section.")
    if SCAN_RESULT.lower() not in visible_text(updated):
        raise RuntimeError("VirusTotal result validation failed inside the security section.")
    if VT_URL not in updated:
        raise RuntimeError("VirusTotal link validation failed inside the security section.")

    return updated


def health_check():
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

page, source = find_page()
node, old_section = find_security_section(source)
new_section = update_security_section(old_section)

if new_section == old_section:
    raise SystemExit(
        "The security section already contains the exact DriveLab 2.4.0 verification data."
    )

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_root = ROOT / "backups" / f"before-v240-apk-security-{stamp}"
backup_root.mkdir(parents=True, exist_ok=True)
backup_page = backup_root / page.name
shutil.copy2(page, backup_page)

updated_source = (
    source[:node["start"]]
    + new_section
    + source[node["end"]:]
)

temporary = page.with_name(page.name + ".v240-security.tmp")

try:
    temporary.write_text(updated_source, encoding="utf-8")
    temporary.replace(page)

    health, rendered = health_check()
    rendered_lower = rendered.lower()

    required = [
        VERSION.lower(),
        SHA256.lower(),
        SCAN_RESULT.lower(),
        VT_URL.lower(),
        "apk security verification",
        "permanent signing",
    ]

    missing = [item for item in required if item not in rendered_lower]
    if missing:
        raise RuntimeError(
            "Rendered-homepage validation failed. Missing: " + ", ".join(missing)
        )

    print("DriveLab APK security verification updated safely.")
    print(f"Homepage source: {page}")
    print(f"Version: {VERSION}")
    print(f"Build: {BUILD}")
    print(f"SHA-256: {SHA256}")
    print(f"VirusTotal: {SCAN_RESULT}")
    print(f"Report: {VT_URL}")
    print(f"Backup: {backup_root}")
    print(f"Health: {health}")

except Exception:
    shutil.copy2(backup_page, page)
    try:
        health_check()
    except Exception:
        pass
    raise
'@

$Python = $Python.Replace("__VERSION__", $ExpectedVersion)
$Python = $Python.Replace("__BUILD__", $ExpectedBuild.ToString())
$Python = $Python.Replace("__SHA256__", $ExpectedHash)
$Python = $Python.Replace("__VT_URL__", $VirusTotalUrl)
$Python = $Python.Replace("__SCAN_RESULT__", $ScanResult)
$Python = $Python.Replace("__SCAN_DATE__", $ScanDate)

[System.IO.File]::WriteAllText(
    $LocalScript,
    $Python,
    $Utf8
)

Write-Host ""
Write-Host "===== VERIFIED RELEASE INPUT =====" -ForegroundColor Cyan
Write-Host "Version:    $ExpectedVersion"
Write-Host "Build:      $ExpectedBuild"
Write-Host "APK:        $ApkPath"
Write-Host "SHA-256:    $ExpectedHash"
Write-Host "VirusTotal: $ScanResult"
Write-Host "Report:     $VirusTotalUrl"

Write-Host ""
Write-Host "===== COPYING GUARDED SECURITY UPDATE =====" -ForegroundColor Cyan

& $Scp.Source $LocalScript "${Target}:$RemoteScript"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the security update to the Pi."
}

Write-Host ""
Write-Host "===== UPDATING THE EXISTING SECURITY CARDS =====" -ForegroundColor Cyan

& $Ssh.Source -t $Target "sudo python3 '$RemoteScript'"
if ($LASTEXITCODE -ne 0) {
    throw "The security-section update failed. The previous homepage was restored automatically."
}

Remove-Item -LiteralPath $LocalScript -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB 2.4.0 SECURITY SECTION UPDATED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Only the existing APK security verification section was changed." -ForegroundColor Cyan
Write-Host "Press Ctrl+F5 when viewing the website." -ForegroundColor Yellow
