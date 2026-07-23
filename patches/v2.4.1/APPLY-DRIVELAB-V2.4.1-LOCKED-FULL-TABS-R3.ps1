$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/v2.4.1/APPLY-DRIVELAB-V2.4.1-LOCKED-FULL-TABS-R2.ps1"
$Temporary = Join-Path $env:TEMP "APPLY-DRIVELAB-V2.4.1-LOCKED-FULL-TABS-R2-UTF8.ps1"

$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

Write-Host ""
Write-Host "===== PREPARING UTF-8 SAFE DRIVELAB 2.4.1 INSTALLER =====" -ForegroundColor Cyan

Invoke-WebRequest `
    -Uri $SourceUrl `
    -OutFile $Temporary `
    -UseBasicParsing

$Text = [System.IO.File]::ReadAllText(
    $Temporary,
    $Utf8Strict
)

if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "The downloaded DriveLab installer was empty."
}

# Keep the generated Kotlin source ASCII-safe inside the PowerShell script.
# Kotlin renders this surrogate pair as the lock icon at runtime.
$Text = $Text.Replace(
    [char]0xD83D + [char]0xDD12,
    '\uD83D\uDD12'
)

[System.IO.File]::WriteAllText(
    $Temporary,
    $Text,
    $Utf8WithBom
)

$Tokens = $null
$Errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Temporary,
    [ref]$Tokens,
    [ref]$Errors
)

if ($Errors.Count -gt 0) {
    $Message = ($Errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"

    throw "The corrected installer still contains a PowerShell syntax error.`n$Message"
}

Write-Host "PowerShell syntax validation passed." -ForegroundColor Green
Write-Host "Starting the guarded DriveLab 2.4.1 patch and signed build..." -ForegroundColor Cyan
Write-Host "Do not close this window or press Ctrl+C while Gradle is running." -ForegroundColor Yellow

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Temporary

$ExitCode = $LASTEXITCODE

Remove-Item `
    -LiteralPath $Temporary `
    -Force `
    -ErrorAction SilentlyContinue

if ($ExitCode -ne 0) {
    throw "The DriveLab 2.4.1 installer failed with exit code $ExitCode."
}
