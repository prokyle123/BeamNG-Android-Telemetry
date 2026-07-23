$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ServiceName = "drivelab-site.service"
$SitePort = 8790
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
$LocalScript = Join-Path $env:TEMP "drivelab-native-website-integration-$Timestamp.py"
$RemoteScript = "/tmp/drivelab-native-website-integration-$Timestamp.py"
$Utf8 = [System.Text.UTF8Encoding]::new($false)

$Python = @'
from pathlib import Path
from datetime import datetime
from html import escape
import re
import shutil
import subprocess
import time
import urllib.request

SITE_ROOT = Path("/opt/drivelab-site")
SERVICE = "drivelab-site.service"
HEALTH_URL = "http://127.0.0.1:8790/healthz"

OLD_START = "<!-- DRIVELAB DRIVE INTELLIGENCE START -->"
OLD_END = "<!-- DRIVELAB DRIVE INTELLIGENCE END -->"
OLD_CSS_START = "/* DRIVELAB DRIVE INTELLIGENCE CSS START */"
OLD_CSS_END = "/* DRIVELAB DRIVE INTELLIGENCE CSS END */"
FEATURE_START = "<!-- DRIVELAB 2.4.0 NATIVE FEATURE CARDS START -->"
FEATURE_END = "<!-- DRIVELAB 2.4.0 NATIVE FEATURE CARDS END -->"
GALLERY_START = "<!-- DRIVELAB 2.4.0 NATIVE GALLERY START -->"
GALLERY_END = "<!-- DRIVELAB 2.4.0 NATIVE GALLERY END -->"

ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}
VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
}

CAPTIONS = {
    "01-drive-intelligence-settings.png": (
        "Drive Intelligence settings",
        "Control stunt detection, event popups, spoken announcements, Driver DNA, Drive Stories, and detection sensitivity from one place."
    ),
    "02-stunt-maneuver-popup.png": (
        "Live maneuver detection",
        "Confirmed maneuvers can appear with vehicle speed, detection confidence, and earned XP."
    ),
    "03-driver-dna-available.png": (
        "Driver DNA remains optional",
        "The feature stays visible but completely inactive until the driver chooses to enable it."
    ),
    "04-driver-dna-profile.png": (
        "A profile that develops gradually",
        "When enabled, Driver DNA builds a private long-term profile from completed drives rather than one isolated run."
    ),
    "05-drive-story-session.png": (
        "Drive Stories in saved sessions",
        "Saved sessions can include a locally generated story, major moments, detected maneuvers, and important statistics."
    ),
    "06-drive-story-complete-dialog.png": (
        "Review and share the drive",
        "Completed drives can be reviewed immediately and exported as a clean Drive Story share card."
    ),
}


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def choose_homepage():
    candidates = [
        SITE_ROOT / "templates" / "index.html",
        SITE_ROOT / "site" / "templates" / "index.html",
        SITE_ROOT / "app" / "templates" / "index.html",
        SITE_ROOT / "static" / "index.html",
        SITE_ROOT / "public" / "index.html",
        SITE_ROOT / "index.html",
    ]

    scored = []
    for candidate in candidates:
        if not candidate.exists():
            continue
        text = read_text(candidate)
        if not text:
            continue
        lowered = text.lower()
        score = 0
        score += lowered.count("drivelab") * 8
        score += lowered.count("tracklab") * 5
        score += lowered.count("racelink") * 5
        score += lowered.count("custom layouts") * 5
        score += 20 if "</body>" in lowered else 0
        scored.append((score, candidate, text))

    if not scored:
        for candidate in SITE_ROOT.rglob("index.html"):
            text = read_text(candidate)
            if not text:
                continue
            lowered = text.lower()
            score = 0
            score += lowered.count("drivelab") * 8
            score += lowered.count("tracklab") * 5
            score += lowered.count("racelink") * 5
            score += lowered.count("custom layouts") * 5
            score += 20 if "</body>" in lowered else 0
            scored.append((score, candidate, text))

    if not scored:
        raise RuntimeError("Could not locate the DriveLab homepage.")

    scored.sort(key=lambda item: item[0], reverse=True)
    return scored[0][1], scored[0][2]


def remove_marked_block(html, start, end):
    return re.sub(
        r"(?is)\s*" + re.escape(start) + r".*?" + re.escape(end) + r"\s*",
        "\n",
        html,
    )


def clean_old_injection(html):
    html = remove_marked_block(html, OLD_START, OLD_END)
    html = remove_marked_block(html, FEATURE_START, FEATURE_END)
    html = remove_marked_block(html, GALLERY_START, GALLERY_END)
    html = re.sub(
        r"(?is)\s*" + re.escape(OLD_CSS_START) + r".*?" + re.escape(OLD_CSS_END) + r"\s*",
        "\n",
        html,
    )
    html = re.sub(
        r'''(?is)\s*<section\b[^>]*id\s*=\s*["']drive-intelligence["'][^>]*>.*?</section>\s*''',
        "\n",
        html,
    )
    return re.sub(r"\n{4,}", "\n\n\n", html)


def visible_text(markup):
    value = re.sub(r"(?is)<script\b.*?</script>", " ", markup)
    value = re.sub(r"(?is)<style\b.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", value).strip().lower()


def parse_nodes(html):
    token_re = re.compile(r"(?is)<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)\b[^>]*?>")
    nodes = []
    stack = []

    for match in token_re.finditer(html):
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

        matching_position = None
        for position in range(len(stack) - 1, -1, -1):
            if nodes[stack[position]]["tag"] == tag:
                matching_position = position
                break

        if matching_position is None:
            continue

        node_index = stack[matching_position]
        nodes[node_index]["close_start"] = match.start()
        nodes[node_index]["end"] = match.end()
        del stack[matching_position:]

    return [node for node in nodes if node["end"] is not None]


def node_fragment(html, node):
    return html[node["start"]:node["end"]]


def node_length(node):
    return node["end"] - node["start"]


def parent_node(nodes, node):
    index = node.get("parent")
    if index is None or index >= len(nodes):
        return None
    return nodes[index]


def find_feature_card_and_grid(html):
    nodes = parse_nodes(html)
    candidates = []

    for node in nodes:
        if node["tag"] not in {"article", "div", "li", "td"}:
            continue
        fragment = node_fragment(html, node)
        text = visible_text(fragment)
        if "custom layouts" not in text:
            continue
        if "<p" not in fragment.lower():
            continue
        if node_length(node) > 6500:
            continue
        candidates.append(node)

    if not candidates:
        raise RuntimeError("Could not locate the existing Custom Layouts feature card.")

    card = min(candidates, key=node_length)
    current = parent_node(nodes, card)
    required = ("racelink", "race labs", "analyze", "progression", "custom layouts")

    while current is not None:
        fragment = node_fragment(html, current)
        text = visible_text(fragment)
        image_count = fragment.lower().count("<img")
        if all(term in text for term in required) and image_count <= 2:
            return card, current
        current = parent_node(nodes, current)

    raise RuntimeError("Could not locate the native feature-card grid.")


def clone_feature_card(template, number, title, body):
    result = template

    number_pattern = re.compile(r"(?is)(>\s*)0?8(\s*<)")
    result, number_count = number_pattern.subn(
        lambda match: f"{match.group(1)}{number}{match.group(2)}",
        result,
        count=1,
    )

    heading_pattern = re.compile(r"(?is)(<h[1-6]\b[^>]*>).*?(</h[1-6]>)")
    result, heading_count = heading_pattern.subn(
        lambda match: f"{match.group(1)}{escape(title)}{match.group(2)}",
        result,
        count=1,
    )

    if heading_count == 0:
        result = re.sub(
            r"(?is)custom\s+layouts",
            escape(title),
            result,
            count=1,
        )

    paragraph_pattern = re.compile(r"(?is)(<p\b[^>]*>).*?(</p>)")
    result, paragraph_count = paragraph_pattern.subn(
        lambda match: f"{match.group(1)}{escape(body)}{match.group(2)}",
        result,
        count=1,
    )

    if paragraph_count == 0:
        raise RuntimeError("The native feature-card template did not contain a description paragraph.")

    if number_count == 0:
        raise RuntimeError("The native feature-card template did not contain card number 08.")

    return result


def insert_feature_cards(html):
    card, grid = find_feature_card_and_grid(html)
    template = node_fragment(html, card)

    cards = [
        clone_feature_card(
            template,
            "09",
            "Stunt Detection",
            "Live recognition for donuts, burnouts, J-turns, reverse 180s, drift transitions, jumps, flips, two-wheel driving, wheelies, stoppies, hard landings, and major recoveries."
        ),
        clone_feature_card(
            template,
            "10",
            "Driver DNA",
            "An optional private driving profile that develops gradually across twelve traits. Driver DNA starts disabled and stays out of the normal app until enabled."
        ),
        clone_feature_card(
            template,
            "11",
            "Drive Stories",
            "Completed sessions become readable stories with major moments, detected maneuvers, important statistics, and clean share cards generated locally on the phone."
        ),
    ]

    block = "\n" + FEATURE_START + "\n" + "\n".join(cards) + "\n" + FEATURE_END + "\n"
    return html[:grid["close_start"]] + block + html[grid["close_start"]:]


def find_media():
    candidates = []
    for directory in SITE_ROOT.rglob("drive-intelligence"):
        if not directory.is_dir() or "/backups/" in str(directory):
            continue
        images = [
            item for item in directory.iterdir()
            if item.is_file() and item.suffix.lower() in ALLOWED
        ]
        if images:
            candidates.append((len(images), directory, sorted(images, key=lambda item: item.name.lower())))

    if not candidates:
        raise RuntimeError("Could not locate the uploaded Drive Intelligence screenshots.")

    candidates.sort(key=lambda item: item[0], reverse=True)
    _, directory, images = candidates[0]

    parent_name = directory.parent.name.lower()
    if parent_name == "static":
        prefix = "/static/drive-intelligence"
    elif parent_name == "assets":
        prefix = "/assets/drive-intelligence"
    elif parent_name == "media":
        prefix = "/media/drive-intelligence"
    elif parent_name == "public":
        prefix = "/public/drive-intelligence"
    else:
        prefix = "/static/drive-intelligence"

    return directory, prefix, images


def find_gallery_card_and_container(html):
    nodes = parse_nodes(html)
    gallery_sections = []

    for node in nodes:
        fragment = node_fragment(html, node)
        lowered = fragment.lower()
        text = visible_text(fragment)
        image_count = lowered.count("<img")
        if image_count < 3:
            continue
        if (
            "in action" in text
            or "real android" in text
            or "screens" in text
            or "screenshot" in text
        ):
            gallery_sections.append(node)

    if not gallery_sections:
        raise RuntimeError("Could not locate the existing website screenshot gallery.")

    gallery = min(gallery_sections, key=node_length)
    gallery_start = gallery["start"]
    gallery_end = gallery["end"]

    card_candidates = []
    for node in nodes:
        if node["start"] < gallery_start or node["end"] > gallery_end:
            continue
        if node["tag"] not in {"figure", "article", "li", "td", "div"}:
            continue
        fragment = node_fragment(html, node)
        if fragment.lower().count("<img") != 1:
            continue
        if node_length(node) > 7000:
            continue
        text = visible_text(fragment)
        if len(text) < 8:
            continue
        card_candidates.append(node)

    if not card_candidates:
        raise RuntimeError("Could not locate a reusable screenshot card inside the existing gallery.")

    priority = {"td": 0, "figure": 1, "article": 2, "li": 3, "div": 4}
    card_candidates.sort(key=lambda node: (priority.get(node["tag"], 9), node_length(node)))
    card = card_candidates[0]

    if card["tag"] == "td":
        row = parent_node(nodes, card)
        if row is None or row["tag"] != "tr":
            raise RuntimeError("The screenshot table cell did not have a valid row parent.")
        container = parent_node(nodes, row)
        if container is None or container["tag"] not in {"tbody", "table"}:
            raise RuntimeError("The screenshot row did not have a valid table container.")
        return card, container, row

    container = parent_node(nodes, card)
    while container is not None:
        fragment = node_fragment(html, container)
        if fragment.lower().count("<img") >= 3:
            return card, container, None
        container = parent_node(nodes, container)

    raise RuntimeError("Could not locate the native screenshot-card container.")


def replace_attribute(tag_markup, attribute, value):
    pattern = re.compile(
        rf'''(?is)(\b{re.escape(attribute)}\s*=\s*["'])[^"']*(["'])'''
    )
    replacement = lambda match: f"{match.group(1)}{escape(value, quote=True)}{match.group(2)}"
    updated, count = pattern.subn(replacement, tag_markup, count=1)
    return updated, count


def clone_gallery_card(template, image_url, title, caption):
    result = template

    image_match = re.search(r"(?is)<img\b[^>]*>", result)
    if not image_match:
        raise RuntimeError("The native screenshot-card template did not contain an image.")

    image_tag = image_match.group(0)
    image_tag, src_count = replace_attribute(image_tag, "src", image_url)
    image_tag, alt_count = replace_attribute(image_tag, "alt", f"{title} in DriveLab Telem 2.4.0")

    if src_count == 0:
        raise RuntimeError("The native screenshot image did not contain a src attribute.")

    if alt_count == 0:
        image_tag = image_tag[:-1] + f' alt="{escape(title, quote=True)} in DriveLab Telem 2.4.0">'

    result = result[:image_match.start()] + image_tag + result[image_match.end():]

    anchor_match = re.search(r"(?is)<a\b[^>]*>", result)
    if anchor_match:
        anchor_tag, href_count = replace_attribute(anchor_match.group(0), "href", image_url)
        if href_count:
            result = result[:anchor_match.start()] + anchor_tag + result[anchor_match.end():]

    heading_pattern = re.compile(r"(?is)(<h[1-6]\b[^>]*>).*?(</h[1-6]>)")
    result, title_count = heading_pattern.subn(
        lambda match: f"{match.group(1)}{escape(title)}{match.group(2)}",
        result,
        count=1,
    )

    if title_count == 0:
        strong_pattern = re.compile(r"(?is)(<strong\b[^>]*>).*?(</strong>)")
        result, title_count = strong_pattern.subn(
            lambda match: f"{match.group(1)}{escape(title)}{match.group(2)}",
            result,
            count=1,
        )

    paragraph_pattern = re.compile(r"(?is)(<p\b[^>]*>).*?(</p>)")
    result, caption_count = paragraph_pattern.subn(
        lambda match: f"{match.group(1)}{escape(caption)}{match.group(2)}",
        result,
        count=1,
    )

    if caption_count == 0:
        span_pattern = re.compile(r"(?is)(<span\b[^>]*>).*?(</span>)")
        result, caption_count = span_pattern.subn(
            lambda match: f"{match.group(1)}{escape(caption)}{match.group(2)}",
            result,
            count=1,
        )

    if title_count == 0:
        raise RuntimeError("The native screenshot card did not contain a reusable title element.")

    return result


def insert_gallery_cards(html, media_prefix, images):
    card, container, row = find_gallery_card_and_container(html)
    template = node_fragment(html, card)
    clones = []

    for number, image in enumerate(images, start=1):
        title, caption = CAPTIONS.get(
            image.name.lower(),
            (
                f"Drive Intelligence screen {number}",
                "A real screen captured from the working DriveLab Telem 2.4.0 Android build."
            ),
        )
        image_url = f"{media_prefix}/{image.name}"
        clones.append(clone_gallery_card(template, image_url, title, caption))

    if row is not None:
        row_open = html[row["start"]:row["open_end"]]
        row_close = html[row["close_start"]:row["end"]]
        rows = []
        for index in range(0, len(clones), 2):
            rows.append(row_open + "\n" + "\n".join(clones[index:index + 2]) + "\n" + row_close)
        block = "\n" + GALLERY_START + "\n" + "\n".join(rows) + "\n" + GALLERY_END + "\n"
    else:
        block = "\n" + GALLERY_START + "\n" + "\n".join(clones) + "\n" + GALLERY_END + "\n"

    return html[:container["close_start"]] + block + html[container["close_start"]:]


def restart_and_check():
    subprocess.run(["systemctl", "restart", SERVICE], check=True)
    time.sleep(3)
    with urllib.request.urlopen(HEALTH_URL, timeout=12) as response:
        payload = response.read().decode("utf-8", errors="replace")
        if response.status != 200:
            raise RuntimeError(f"Health check returned HTTP {response.status}")
        return payload.strip()


if not SITE_ROOT.exists():
    raise SystemExit(f"Website root was not found: {SITE_ROOT}")

page, current_html = choose_homepage()
media_root, media_prefix, images = find_media()
clean_html = clean_old_injection(current_html)

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_root = SITE_ROOT / "backups" / f"before-native-drive-intelligence-integration-{stamp}"
backup_root.mkdir(parents=True, exist_ok=True)
backup_page = backup_root / page.name
shutil.copy2(page, backup_page)

try:
    updated_html = insert_feature_cards(clean_html)
    updated_html = insert_gallery_cards(updated_html, media_prefix, images)
    updated_html = re.sub(r"\n{4,}", "\n\n\n", updated_html)

    required_text = [
        "Stunt Detection",
        "Driver DNA",
        "Drive Stories",
        FEATURE_START,
        FEATURE_END,
        GALLERY_START,
        GALLERY_END,
    ]

    for text in required_text:
        if text not in updated_html:
            raise RuntimeError(f"Validation failed: missing {text}")

    if OLD_START in updated_html or OLD_CSS_START in updated_html or 'id="drive-intelligence"' in updated_html:
        raise RuntimeError("Validation failed: the old standalone Drive Intelligence section is still present.")

    for image in images:
        expected = f"{media_prefix}/{image.name}"
        if expected not in updated_html:
            raise RuntimeError(f"Validation failed: screenshot was not inserted: {image.name}")

    temporary = page.with_name(page.name + ".native-drive-intelligence.tmp")
    temporary.write_text(updated_html, encoding="utf-8")
    temporary.replace(page)

    health = restart_and_check()

    with urllib.request.urlopen("http://127.0.0.1:8790/", timeout=12) as response:
        rendered = response.read().decode("utf-8", errors="replace")

    for text in ("Stunt Detection", "Driver DNA", "Drive Stories"):
        if text not in rendered:
            raise RuntimeError(f"Rendered-homepage validation failed: missing {text}")

    if "NEW IN DRIVELAB TELEM 2.4.0" in rendered and OLD_START not in rendered:
        raise RuntimeError("Rendered-homepage validation found leftover standalone Drive Intelligence copy.")

    print("Drive Intelligence is now integrated into the native website layout.")
    print(f"Homepage: {page}")
    print(f"Feature cards added: 3")
    print(f"Screenshots added to native gallery: {len(images)}")
    print(f"Screenshot source: {media_root}")
    print(f"Backup: {backup_root}")
    print(f"Health: {health}")

except Exception:
    shutil.copy2(backup_page, page)
    try:
        restart_and_check()
    except Exception:
        pass
    raise
'@

[System.IO.File]::WriteAllText(
    $LocalScript,
    $Python,
    $Utf8
)

Write-Host ""
Write-Host "===== COPYING SAFE WEBSITE REPAIR =====" -ForegroundColor Cyan

& $Scp.Source $LocalScript "${Target}:$RemoteScript"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the repair script to the Pi."
}

Write-Host ""
Write-Host "===== INTEGRATING INTO NATIVE WEBSITE CARDS =====" -ForegroundColor Cyan

& $Ssh.Source -t $Target "sudo python3 '$RemoteScript'"
if ($LASTEXITCODE -ne 0) {
    throw "The native website integration failed. The previous homepage was restored automatically."
}

Remove-Item -LiteralPath $LocalScript -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB NATIVE WEBSITE INTEGRATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "The standalone Drive Intelligence block is gone." -ForegroundColor Cyan
Write-Host "Stunt Detection, Driver DNA, and Drive Stories now use the website's existing feature cards." -ForegroundColor Cyan
Write-Host "The uploaded screens now use the website's existing screenshot-gallery cards." -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+F5 when viewing the website." -ForegroundColor Yellow
