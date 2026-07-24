param(
    [Parameter(Mandatory = $true)]
    [string]$Stage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Get-Location).Path
$Stage = [System.IO.Path]::GetFullPath($Stage)
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Report = Join-Path $Stage "LIFECYCLE-ANDROID-STAGE-REPORT.txt"

function Normalize-Lf([string]$Value) {
    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Read-StrictUtf8([string]$Path) {
    return Normalize-Lf ([System.IO.File]::ReadAllText($Path, $Utf8Strict))
}

function Write-Utf8Lf([string]$Path, [string]$Value) {
    [System.IO.File]::WriteAllText($Path, (Normalize-Lf $Value), $Utf8NoBom)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitBlobSha1([byte[]]$Bytes) {
    $Prefix = [System.Text.Encoding]::UTF8.GetBytes("blob $($Bytes.Length)`0")
    $Packed = New-Object byte[] ($Prefix.Length + $Bytes.Length)
    [Array]::Copy($Prefix, 0, $Packed, 0, $Prefix.Length)
    [Array]::Copy($Bytes, 0, $Packed, $Prefix.Length, $Bytes.Length)
    $Sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        return (($Sha1.ComputeHash($Packed) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $Sha1.Dispose()
    }
}

function Assert-OriginalHash([string]$Relative, [string]$Expected) {
    $Path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required original source file is missing: ${Path}"
    }
    $Actual = Get-Sha256 $Path
    if ($Actual -ne $Expected) {
        throw "Original working-project baseline mismatch for ${Relative}. Expected ${Expected} but found ${Actual}."
    }
}

function Assert-Contains([string]$Path, [string]$Marker) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required staged file is missing: ${Path}"
    }
    $Text = Read-StrictUtf8 $Path
    if (-not $Text.Contains($Marker)) {
        throw "Required staged marker is missing from ${Path}: ${Marker}"
    }
}

$Baseline = [ordered]@{
    "app\build.gradle.kts" = "c43eeeece37af4b61e5d216b385376a46921f0bc12ae2abfb9eb42908f135c65"
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt" = "8ec170cea01161a7444d168f1857ee4c8591927b26edeb3cae1a999ea2cc5143"
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt" = "f2c342e647669768e06a7e93b6221eb66359af6d9dfa71072bc1d4371c40a7ec"
    "app\src\main\java\com\auroramediagroup\drivelab\MainActivity.kt" = "83a516b6540b45d006a2018c73b4633ec98be6821e31b40ed787ed470a88c215"
    "app\src\main\java\com\auroramediagroup\drivelab\Models.kt" = "353a679a1ce9a4787630043adbd4b4c61f6ba7b9ceb726fa201c187c535a08dc"
    "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt" = "8911ec4f3068e77014ba044a39cb7d057e7664c97ad06b90459ae598c91fab33"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DRIVELAB ANDROID LIFECYCLE BUILD RESUME - KOTLIN FIX R3" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Original project: $Root"
Write-Host "Existing stage:   $Stage"

if (-not (Test-Path -LiteralPath $Stage -PathType Container)) {
    throw "The existing isolated stage was not found: ${Stage}"
}
if ($Stage.TrimEnd('\') -eq $Root.TrimEnd('\')) {
    throw "The stage must not be the original working project."
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "gradlew.bat") -PathType Leaf)) {
    throw "Run this command from the original DriveLab Android project root."
}
if (-not (Test-Path -LiteralPath (Join-Path $Stage "gradlew.bat") -PathType Leaf)) {
    throw "The staged Gradle wrapper is missing."
}

Write-Host ""
Write-Host "===== VERIFYING ORIGINAL PROJECT REMAINS UNCHANGED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-OriginalHash $Entry.Key $Entry.Value
}
Write-Host "Original project baseline hashes passed." -ForegroundColor Green

$JavaRoot = Join-Path $Stage "app\src\main\java\com\auroramediagroup\drivelab"
$GradlePath = Join-Path $Stage "app\build.gradle.kts"
$LifecyclePath = Join-Path $JavaRoot "LifecycleTelemetry.kt"
$ViewModelPath = Join-Path $JavaRoot "DriveLabViewModel.kt"
$UiPath = Join-Path $JavaRoot "DriveLabUi.kt"
$MainActivityPath = Join-Path $JavaRoot "MainActivity.kt"
$ModelsPath = Join-Path $JavaRoot "Models.kt"
$StoragePath = Join-Path $JavaRoot "Storage.kt"

Write-Host ""
Write-Host "===== VERIFYING THE EXISTING PATCHED STAGE =====" -ForegroundColor Cyan
Assert-Contains $GradlePath 'versionCode = 37'
Assert-Contains $GradlePath 'versionName = "2.4.0"'
Assert-Contains $LifecyclePath 'LIFECYCLE_CLIENT_VERSION = "1.0.0"'
Assert-Contains $ViewModelPath 'private val lifecycleTelemetry = LifecycleTelemetryManager(application)'
Assert-Contains $UiPath 'DEVICE LIFECYCLE & PRIVACY'
Assert-Contains $MainActivityPath 'viewModel.onAppBackgrounded()'
Assert-Contains $ModelsPath 'val lifecycleReportingEnabled: Boolean = true'
Assert-Contains $StoragePath 'preferences.getBoolean("sessionSummarySharingEnabled", false)'
Write-Host "The existing stage contains the expected lifecycle patch and version markers." -ForegroundColor Green

Write-Host ""
Write-Host "===== APPLYING KOTLIN DEFAULT-PARAMETER HOTFIX R3 =====" -ForegroundColor Cyan
$LifecycleBytesBefore = [System.IO.File]::ReadAllBytes($LifecyclePath)
$LifecycleBlobBefore = Get-GitBlobSha1 $LifecycleBytesBefore
$LifecycleText = Read-StrictUtf8 $LifecyclePath
$OldFeature = '        featureUsageEnabled: Boolean = featureUsageEnabled,'
$NewFeature = '        featureUsageEnabled: Boolean = this.featureUsageEnabled,'
$OldSummary = '        sessionSummariesEnabled: Boolean = sessionSummariesEnabled,'
$NewSummary = '        sessionSummariesEnabled: Boolean = this.sessionSummariesEnabled,'

$OldFeatureCount = ([regex]::Matches($LifecycleText, [regex]::Escape($OldFeature))).Count
$OldSummaryCount = ([regex]::Matches($LifecycleText, [regex]::Escape($OldSummary))).Count
$NewFeatureCount = ([regex]::Matches($LifecycleText, [regex]::Escape($NewFeature))).Count
$NewSummaryCount = ([regex]::Matches($LifecycleText, [regex]::Escape($NewSummary))).Count

if ($OldFeatureCount -eq 1 -and $OldSummaryCount -eq 1 -and $NewFeatureCount -eq 0 -and $NewSummaryCount -eq 0) {
    if ($LifecycleBlobBefore -ne "ad278bebfd63519189a9972838147ec2db46721d") {
        throw "The staged lifecycle client contains the expected buggy anchors but does not match the verified payload blob. Found ${LifecycleBlobBefore}."
    }
    $LifecycleText = $LifecycleText.Replace($OldFeature, $NewFeature).Replace($OldSummary, $NewSummary)
    Write-Utf8Lf $LifecyclePath $LifecycleText
    Write-Host "Kotlin default-parameter hotfix R3 applied." -ForegroundColor Green
}
elseif ($OldFeatureCount -eq 0 -and $OldSummaryCount -eq 0 -and $NewFeatureCount -eq 1 -and $NewSummaryCount -eq 1) {
    Write-Host "Kotlin default-parameter hotfix R3 was already present." -ForegroundColor Yellow
}
else {
    throw "LifecycleTelemetry.kt did not match either the exact pre-fix or exact post-fix state. No build was started."
}

$LifecycleTextAfter = Read-StrictUtf8 $LifecyclePath
if (-not $LifecycleTextAfter.Contains($NewFeature) -or -not $LifecycleTextAfter.Contains($NewSummary)) {
    throw "Kotlin default-parameter hotfix R3 did not validate."
}
if ($LifecycleTextAfter.Contains($OldFeature) -or $LifecycleTextAfter.Contains($OldSummary)) {
    throw "The buggy Kotlin default-parameter lines are still present."
}
$LifecycleHashAfter = Get-Sha256 $LifecyclePath
Write-Host "LifecycleTelemetry.kt SHA-256 after R3: $LifecycleHashAfter"

Write-Host ""
Write-Host "===== CONFIGURING JAVA FOR THIS BUILD PROCESS =====" -ForegroundColor Cyan
$AndroidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not (Test-Path -LiteralPath (Join-Path $AndroidStudioJbr "bin\java.exe") -PathType Leaf)) {
    throw "Android Studio JBR was not found at ${AndroidStudioJbr}"
}
$env:JAVA_HOME = $AndroidStudioJbr
$env:PATH = "$($env:JAVA_HOME)\bin;$env:PATH"
$JavaCommand = Get-Command java.exe -ErrorAction Stop
Write-Host "JAVA_HOME: $env:JAVA_HOME"
Write-Host "Java command: $($JavaCommand.Source)"
& java.exe -version
if ($LASTEXITCODE -ne 0) {
    throw "Java was found but could not be executed."
}

Write-Host ""
Write-Host "===== BUILDING AND TESTING THE EXISTING ISOLATED STAGE =====" -ForegroundColor Cyan
$GradleExit = -1
Push-Location $Stage
try {
    & .\gradlew.bat --no-daemon clean testReleaseUnitTest lintRelease assembleRelease
    $GradleExit = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($GradleExit -ne 0) {
    throw "Gradle build or tests failed with exit code ${GradleExit}. The original project remains unchanged."
}

$BuiltApk = Join-Path $Stage "app\build\outputs\apk\release\app-release.apk"
if (-not (Test-Path -LiteralPath $BuiltApk -PathType Leaf)) {
    throw "Gradle completed but the release APK was not found: ${BuiltApk}"
}

$ReleaseOutput = Join-Path $Stage "release-output"
New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
$StagedApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-build37-lifecycle-STAGE.apk"
Copy-Item -LiteralPath $BuiltApk -Destination $StagedApk -Force
$ApkHash = Get-Sha256 $StagedApk

Write-Host ""
Write-Host "===== VERIFYING APK SIGNATURE AND MANIFEST =====" -ForegroundColor Cyan
$BuildToolsRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
$ApkSigner = Get-ChildItem -Path $BuildToolsRoot -Filter apksigner.bat -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$Aapt = Get-ChildItem -Path $BuildToolsRoot -Filter aapt.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $ApkSigner) {
    throw "apksigner.bat was not found under ${BuildToolsRoot}"
}
if ($null -eq $Aapt) {
    throw "aapt.exe was not found under ${BuildToolsRoot}"
}

& $ApkSigner.FullName verify --verbose --print-certs $StagedApk
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed."
}
$Badging = (& $Aapt.FullName dump badging $StagedApk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "aapt could not inspect the staged APK."
}
if ($Badging -notmatch "package: name='com\.auroramediagroup\.drivelab'") {
    throw "The staged APK package name is incorrect."
}
if ($Badging -notmatch "versionCode='37'") {
    throw "The staged APK versionCode is not 37."
}
if ($Badging -notmatch "versionName='2\.4\.0'") {
    throw "The staged APK versionName is not 2.4.0."
}
Write-Host "APK package, version, build number, and signature verification passed." -ForegroundColor Green

Write-Host ""
Write-Host "===== PROVING THE ORIGINAL PROJECT WAS STILL NOT MODIFIED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-OriginalHash $Entry.Key $Entry.Value
}
Write-Host "Original project hashes remain unchanged." -ForegroundColor Green

$ReportLines = @(
    "DRIVELAB 2.4.0 BUILD 37 LIFECYCLE ANDROID STAGE"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Original project: $Root"
    "Staged project: $Stage"
    "Public version: 2.4.0"
    "Version code: 37"
    "Lifecycle client: 1.0.0"
    "LifecycleTelemetry.kt SHA-256 after R3: $LifecycleHashAfter"
    "JAVA_HOME: $env:JAVA_HOME"
    "Java executable: $($JavaCommand.Source)"
    "APK: $StagedApk"
    "APK SHA-256: $ApkHash"
    ""
    "Passed:"
    "- original working-project baseline hashes"
    "- existing isolated lifecycle stage"
    "- exact Kotlin default-parameter hotfix R3"
    "- Gradle release unit tests"
    "- release lint"
    "- release APK assembly"
    "- APK cryptographic signature verification"
    "- APK package com.auroramediagroup.drivelab"
    "- APK versionName 2.4.0"
    "- APK versionCode 37"
    "- original working-project hashes unchanged after build"
    ""
    "Not performed:"
    "- APK installation"
    "- production project replacement"
    "- update-server publication"
    "- GitHub release replacement"
    "- public website change"
    "- VirusTotal upload"
)
[System.IO.File]::WriteAllLines($Report, $ReportLines, $Utf8NoBom)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "ANDROID LIFECYCLE STAGE BUILT - ORIGINAL PROJECT UNCHANGED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Staged project: $Stage"
Write-Host "Staged APK:     $StagedApk"
Write-Host "SHA-256:        $ApkHash"
Write-Host "Report:         $Report"
Write-Host ""
Write-Host "The staged APK has not been installed or published." -ForegroundColor Yellow
