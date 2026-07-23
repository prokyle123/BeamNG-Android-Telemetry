$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/v2.4.0/FIX-DRIVELAB-V2.4.0-NATIVE-WEBSITE-INTEGRATION.ps1"
$Temporary = Join-Path $env:TEMP "FIX-DRIVELAB-V2.4.0-NATIVE-WEBSITE-INTEGRATION-R3-expanded.ps1"
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

Invoke-WebRequest `
    -Uri $SourceUrl `
    -OutFile $Temporary `
    -UseBasicParsing

$Text = [System.IO.File]::ReadAllText(
    $Temporary,
    $Utf8Read
)

$OldParser = @'
    return [node for node in nodes if node["end"] is not None]
'@

$NewParser = @'
    complete_indices = [
        index
        for index, node in enumerate(nodes)
        if node["end"] is not None
    ]

    index_map = {
        old_index: new_index
        for new_index, old_index in enumerate(complete_indices)
    }

    complete_nodes = []

    for old_index in complete_indices:
        copied = dict(nodes[old_index])
        parent = copied.get("parent")

        while parent is not None and parent not in index_map:
            parent = nodes[parent].get("parent")

        copied["parent"] = index_map.get(parent)
        complete_nodes.append(copied)

    return complete_nodes
'@

$ParserCount = (
    [regex]::Matches(
        $Text,
        [regex]::Escape($OldParser.Trim())
    )
).Count

if ($ParserCount -ne 1) {
    throw "Could not prepare the corrected HTML parser. Expected one parser anchor but found $ParserCount."
}

$Text = $Text.Replace(
    $OldParser.Trim(),
    $NewParser.Trim()
)

$NewGalleryFunction = @'
def clone_gallery_card(template, image_url, title, caption):
    result = template

    image_match = re.search(r"(?is)<img\b[^>]*>", result)
    if not image_match:
        raise RuntimeError("The native screenshot-card template did not contain an image.")

    image_tag = image_match.group(0)
    image_tag, src_count = replace_attribute(image_tag, "src", image_url)
    image_tag, alt_count = replace_attribute(
        image_tag,
        "alt",
        f"{title} in DriveLab Telem 2.4.0",
    )

    if src_count == 0:
        raise RuntimeError("The native screenshot image did not contain a src attribute.")

    if alt_count == 0:
        image_tag = (
            image_tag[:-1]
            + f' alt="{escape(title, quote=True)} in DriveLab Telem 2.4.0">'
        )

    result = (
        result[:image_match.start()]
        + image_tag
        + result[image_match.end():]
    )

    anchor_match = re.search(r"(?is)<a\b[^>]*>", result)
    if anchor_match:
        anchor_tag, href_count = replace_attribute(
            anchor_match.group(0),
            "href",
            image_url,
        )
        if href_count:
            result = (
                result[:anchor_match.start()]
                + anchor_tag
                + result[anchor_match.end():]
            )

    # The live website's native screenshot cards use a caption container
    # with a bold title followed by plain caption text. Replacing the
    # complete caption body preserves the container's existing classes.
    figcaption_pattern = re.compile(
        r"(?is)(<figcaption\b[^>]*>).*?(</figcaption>)"
    )
    figcaption_match = figcaption_pattern.search(result)

    if figcaption_match:
        replacement = (
            f"{figcaption_match.group(1)}"
            f"<b>{escape(title)}</b> {escape(caption)}"
            f"{figcaption_match.group(2)}"
        )
        return (
            result[:figcaption_match.start()]
            + replacement
            + result[figcaption_match.end():]
        )

    title_count = 0
    title_closing_tag = None

    for tag in ("h1", "h2", "h3", "h4", "h5", "h6", "strong", "b"):
        title_pattern = re.compile(
            rf"(?is)(<{tag}\b[^>]*>).*?(</{tag}>)"
        )
        result, count = title_pattern.subn(
            lambda match: (
                f"{match.group(1)}"
                f"{escape(title)}"
                f"{match.group(2)}"
            ),
            result,
            count=1,
        )
        if count:
            title_count = 1
            title_closing_tag = tag
            break

    caption_count = 0

    for tag in ("p", "span", "small"):
        caption_pattern = re.compile(
            rf"(?is)(<{tag}\b[^>]*>).*?(</{tag}>)"
        )
        result, count = caption_pattern.subn(
            lambda match: (
                f"{match.group(1)}"
                f"{escape(caption)}"
                f"{match.group(2)}"
            ),
            result,
            count=1,
        )
        if count:
            caption_count = 1
            break

    # Common native format:
    # <div class="caption"><b>Title</b> Caption text</div>
    if title_count and caption_count == 0 and title_closing_tag:
        inline_caption_pattern = re.compile(
            rf"(?is)"
            rf"(</{title_closing_tag}>\s*(?:<br\s*/?>\s*)?)"
            rf"([^<]*?)"
            rf"(?=</(?:figcaption|div|td|figure|article|li)>)"
        )
        result, caption_count = inline_caption_pattern.subn(
            lambda match: (
                f"{match.group(1)} "
                f"{escape(caption)}"
            ),
            result,
            count=1,
        )

    # Final native-markup fallback: reuse the first meaningful text
    # container after the image and place a bold title plus caption in it.
    if title_count == 0:
        image_end = re.search(r"(?is)<img\b[^>]*>", result)
        search_start = image_end.end() if image_end else 0
        tail = result[search_start:]
        text_pattern = re.compile(
            r"(?is)>(\s*[^<>]*[A-Za-z][^<>]*)<"
        )
        text_match = text_pattern.search(tail)

        if text_match:
            replacement = (
                ">"
                f"<b>{escape(title)}</b> {escape(caption)}"
                "<"
            )
            absolute_start = search_start + text_match.start()
            absolute_end = search_start + text_match.end()
            result = (
                result[:absolute_start]
                + replacement
                + result[absolute_end:]
            )
            title_count = 1
            caption_count = 1

    if title_count == 0:
        raise RuntimeError(
            "The native screenshot card did not contain a reusable caption container."
        )

    return result
'@

$GalleryPattern = '(?s)def clone_gallery_card\(template, image_url, title, caption\):.*?(?=\r?\ndef insert_gallery_cards\()'
$GalleryMatches = [regex]::Matches($Text, $GalleryPattern)

if ($GalleryMatches.Count -ne 1) {
    throw "Could not prepare the native gallery repair. Expected one gallery function but found $($GalleryMatches.Count)."
}

$Text = [regex]::Replace(
    $Text,
    $GalleryPattern,
    $NewGalleryFunction.TrimEnd() + "`r`n`r`n",
    1
)

[System.IO.File]::WriteAllText(
    $Temporary,
    $Text,
    $Utf8Write
)

powershell.exe `
    -ExecutionPolicy Bypass `
    -File $Temporary

if ($LASTEXITCODE -ne 0) {
    throw "The R3 native website integration failed. The Pi-side installer restored the previous homepage automatically."
}

Remove-Item `
    -LiteralPath $Temporary `
    -Force `
    -ErrorAction SilentlyContinue
