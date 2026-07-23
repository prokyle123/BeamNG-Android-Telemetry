$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/v2.4.0/FIX-DRIVELAB-V2.4.0-NATIVE-WEBSITE-INTEGRATION.ps1"
$Temporary = Join-Path $env:TEMP "FIX-DRIVELAB-V2.4.0-NATIVE-WEBSITE-INTEGRATION-corrected.ps1"
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

$Old = @'
    return [node for node in nodes if node["end"] is not None]
'@

$New = @'
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

$Count = (
    [regex]::Matches(
        $Text,
        [regex]::Escape($Old.Trim())
    )
).Count

if ($Count -ne 1) {
    throw "Could not prepare the corrected website integration script. Expected one parser anchor but found $Count."
}

$Text = $Text.Replace(
    $Old.Trim(),
    $New.Trim()
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
    throw "The corrected native website integration failed. The Pi-side script restores the previous homepage automatically."
}

Remove-Item `
    -LiteralPath $Temporary `
    -Force `
    -ErrorAction SilentlyContinue
