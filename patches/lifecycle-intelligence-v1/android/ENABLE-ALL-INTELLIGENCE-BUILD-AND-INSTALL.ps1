param(
    [Parameter(Mandatory = $true)]
    [string]$Stage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Get-Location).Path
$Stage = [System.IO.Path]::GetFullPath($Stage)
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Backup = Join-Path $Stage "pre-automatic-intelligence-backup-$Stamp"
$Report = Join-Path $Stage "AUTOMATIC-INTELLIGENCE-STAGE-REPORT.txt"

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

function Replace-State(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
) {
    $Old = Normalize-Lf $Old
    $New = Normalize-Lf $New
    $OldCount = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    $NewCount = ([regex]::Matches($Text, [regex]::Escape($New))).Count

    if ($OldCount -eq 1 -and $NewCount -eq 0) {
        Write-Host "Applying: $Label"
        return $Text.Replace($Old, $New)
    }
    elseif ($OldCount -eq 0 -and $NewCount -eq 1) {
        Write-Host "Already applied: $Label" -ForegroundColor Yellow
        return $Text
    }

    throw "${Label} expected exactly one pre-change or post-change state, but found old=${OldCount}, new=${NewCount}."
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
    "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt" = "00b2825c4146236b9f5784f8758625b0971237e0cb5d40725cf8644bae7cc23f"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DRIVELAB 2.4.0 BUILD 37 - AUTOMATIC INTELLIGENCE FINALIZATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Original project: $Root"
Write-Host "Existing stage:   $Stage"
Write-Host "Stage backup:     $Backup"

if (-not (Test-Path -LiteralPath $Stage -PathType Container)) {
    throw "The isolated stage was not found: ${Stage}"
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
$StoragePath = Join-Path $JavaRoot "Storage.kt"
$UpdateUiPath = Join-Path $JavaRoot "UpdateUi.kt"
$ModelsPath = Join-Path $JavaRoot "Models.kt"

Write-Host ""
Write-Host "===== VERIFYING CURRENT FINAL LIFECYCLE STAGE =====" -ForegroundColor Cyan
Assert-Contains $GradlePath 'versionCode = 37'
Assert-Contains $GradlePath 'versionName = "2.4.0"'
Assert-Contains $LifecyclePath 'LIFECYCLE_CLIENT_VERSION = "1.0.0"'
Assert-Contains $LifecyclePath 'featureUsageEnabled: Boolean = this.featureUsageEnabled,'
Assert-Contains $LifecyclePath 'sessionSummariesEnabled: Boolean = this.sessionSummariesEnabled,'
Assert-Contains $ViewModelPath 'private val lifecycleTelemetry = LifecycleTelemetryManager(application)'
Assert-Contains $UiPath 'DEVICE LIFECYCLE & PRIVACY'
Assert-Contains $StoragePath 'lifecycleReportingEnabled = true,'
Assert-Contains $UpdateUiPath 'version = "2.4.0"'
Assert-Contains $UpdateUiPath 'label = "CURRENT RELEASE"'
if ((Read-StrictUtf8 $UpdateUiPath).Contains('version = "2.4.1"')) {
    throw "The stage still contains the undeployed 2.4.1 changelog entry. Run the previous finalization first."
}
Write-Host "Current finalized lifecycle stage verified." -ForegroundColor Green

Write-Host ""
Write-Host "===== BACKING UP STAGED SOURCE FILES =====" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
foreach ($Path in @($LifecyclePath, $ModelsPath, $StoragePath, $ViewModelPath, $UiPath, $UpdateUiPath)) {
    Copy-Item -LiteralPath $Path -Destination (Join-Path $Backup ([System.IO.Path]::GetFileName($Path))) -Force
}
Write-Host "Staged source backup completed." -ForegroundColor Green

Write-Host ""
Write-Host "===== MAKING ALL INTELLIGENCE REPORTING AUTOMATIC =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $LifecyclePath
$Old = @'
data class LifecycleTelemetryState(
    val configured: Boolean = false,
    val enabled: Boolean = true,
    val featureUsageEnabled: Boolean = false,
    val sessionSummariesEnabled: Boolean = false,
'@
$New = @'
data class LifecycleTelemetryState(
    val configured: Boolean = false,
    val enabled: Boolean = true,
    val featureUsageEnabled: Boolean = true,
    val sessionSummariesEnabled: Boolean = true,
'@
$Text = Replace-State $Text $Old $New "Lifecycle state defaults"
$Old = @'
    @Volatile private var operationalEnabled = true
    @Volatile private var featureUsageEnabled = false
    @Volatile private var sessionSummariesEnabled = false
'@
$New = @'
    @Volatile private var operationalEnabled = true
    @Volatile private var featureUsageEnabled = true
    @Volatile private var sessionSummariesEnabled = true
'@
$Text = Replace-State $Text $Old $New "Lifecycle runtime defaults"
$Old = @'
    fun configure(
        enabled: Boolean,
        featureUsage: Boolean,
        sessionSummaries: Boolean
    ) {
        operationalEnabled = enabled
        featureUsageEnabled = enabled && featureUsage
        sessionSummariesEnabled = enabled && sessionSummaries
        if (!enabled) {
            synchronized(queueLock) {
                preferences.edit().remove("pendingEvents").apply()
            }
        }
        publishState(
            enabled = enabled,
            featureUsageEnabled = featureUsageEnabled,
            sessionSummariesEnabled = sessionSummariesEnabled,
            pendingEvents = pendingCount(),
            lastMessage = if (enabled) {
                "Device and reliability reporting is enabled."
            } else {
                "Lifecycle reporting is disabled and pending reports were cleared."
            }
        )
    }
'@
$New = @'
    @Suppress("UNUSED_PARAMETER")
    fun configure(
        enabled: Boolean,
        featureUsage: Boolean,
        sessionSummaries: Boolean
    ) {
        operationalEnabled = true
        featureUsageEnabled = true
        sessionSummariesEnabled = true
        publishState(
            enabled = true,
            featureUsageEnabled = true,
            sessionSummariesEnabled = true,
            pendingEvents = pendingCount(),
            lastMessage = "DriveLab telemetry intelligence is active."
        )
    }
'@
$Text = Replace-State $Text $Old $New "Lifecycle configure enforcement"
Write-Utf8Lf $LifecyclePath $Text

$Text = Read-StrictUtf8 $ModelsPath
$Text = Replace-State $Text `
    '    val featureUsageReportingEnabled: Boolean = false,' `
    '    val featureUsageReportingEnabled: Boolean = true,' `
    "Feature usage model default"
$Text = Replace-State $Text `
    '    val sessionSummarySharingEnabled: Boolean = false,' `
    '    val sessionSummarySharingEnabled: Boolean = true,' `
    "Session summary model default"
Write-Utf8Lf $ModelsPath $Text

$Text = Read-StrictUtf8 $StoragePath
$Text = Replace-State $Text `
    '        featureUsageReportingEnabled = preferences.getBoolean("featureUsageReportingEnabled", false),' `
    '        featureUsageReportingEnabled = true,' `
    "Feature usage load enforcement"
$Text = Replace-State $Text `
    '        sessionSummarySharingEnabled = preferences.getBoolean("sessionSummarySharingEnabled", false),' `
    '        sessionSummarySharingEnabled = true,' `
    "Session summary load enforcement"
$Text = Replace-State $Text `
    '            .putBoolean("featureUsageReportingEnabled", settings.featureUsageReportingEnabled)' `
    '            .putBoolean("featureUsageReportingEnabled", true)' `
    "Feature usage save enforcement"
$Text = Replace-State $Text `
    '            .putBoolean("sessionSummarySharingEnabled", settings.sessionSummarySharingEnabled)' `
    '            .putBoolean("sessionSummarySharingEnabled", true)' `
    "Session summary save enforcement"
Write-Utf8Lf $StoragePath $Text

$Text = Read-StrictUtf8 $ViewModelPath
$Old = @'
            lifecycleTelemetry.configure(
                enabled = true,
                featureUsage = _settings.value.featureUsageReportingEnabled,
                sessionSummaries = _settings.value.sessionSummarySharingEnabled
            )
'@
$New = @'
            lifecycleTelemetry.configure(
                enabled = true,
                featureUsage = true,
                sessionSummaries = true
            )
'@
$Text = Replace-State $Text $Old $New "Always-on startup configuration"
Write-Utf8Lf $ViewModelPath $Text
Write-Host "Core lifecycle, feature usage, and real-session summaries are now enforced on." -ForegroundColor Green

Write-Host ""
Write-Host "===== REMOVING FEATURE AND SESSION OPTIONS FROM SETUP =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $UiPath
$Text = Replace-State $Text `
    '                    "Core signed lifecycle and reliability intelligence runs automatically. Raw UDP packets, routes, GPS, chat, license keys, screenshots, and phone files are never included. Optional feature usage and completed-session summaries remain controlled below.",' `
    '                    "Signed lifecycle, feature-use, reliability, and completed-session intelligence runs automatically. Reports stay low volume and never include raw UDP packets, live position, routes, GPS, chat, license keys, screenshots, or phone files.",' `
    "Automatic intelligence card explanation"
$Old = @'
                SettingSwitch(
                    "Anonymous feature usage",
                    "Optional. Reports only which DriveLab screen was opened or completed; no values entered and no gameplay stream.",
                    settings.featureUsageReportingEnabled,
                    viewModel::setFeatureUsageReportingEnabled
                )
                SettingSwitch(
                    "Share driving session summaries",
                    "Optional and off by default. Sends only totals such as duration, distance, maximum speed, drift score, shifts, and crash count after a saved real session.",
                    settings.sessionSummarySharingEnabled,
                    viewModel::setSessionSummarySharingEnabled
                )
'@
$New = @'
                Text(
                    "Automatic intelligence includes screen opens and completions plus totals from completed real driving sessions. It does not upload the live gameplay stream or saved session files.",
                    color = DriveMuted,
                    style = MaterialTheme.typography.bodySmall
                )
'@
$Text = Replace-State $Text $Old $New "Remove feature and session switches"
$Text = Replace-State $Text `
    '                Text("Anonymous feature-usage reporting is optional and off by default. When enabled, it reports only the name of a DriveLab screen that was opened or completed. It does not send field values, button text, gameplay packets, routes, or chat.")' `
    '                Text("Feature-usage intelligence runs automatically and reports only the name of a DriveLab screen that was opened or completed. It does not send field values, button text, gameplay packets, routes, or chat.")' `
    "Automatic feature privacy disclosure"
$Text = Replace-State $Text `
    '                Text("Driving session summaries are optional and off by default. When enabled, DriveLab may send completed-session totals such as duration, distance, maximum speed, peak G, drift score, shifts, and crash count. Raw UDP telemetry, live vehicle position, GPS location, routes, rolling chart samples, and saved session files are not uploaded.")' `
    '                Text("Completed driving-session summaries are sent automatically after real saved sessions and contain only totals such as duration, distance, maximum speed, peak G, drift score, shifts, and crash count. Raw UDP telemetry, live vehicle position, GPS location, routes, rolling chart samples, and saved session files are not uploaded.")' `
    "Automatic session-summary privacy disclosure"
Write-Utf8Lf $UiPath $Text
Write-Host "The two reporting switches were removed while the diagnostic-report action remains available." -ForegroundColor Green

Write-Host ""
Write-Host "===== UPDATING CURRENT 2.4.0 RELEASE NOTES =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $UpdateUiPath
$Text = Replace-State $Text `
    '            "Core lifecycle and reliability reporting now runs automatically; optional anonymous feature usage and completed-session summaries remain user-controlled.",' `
    '            "Lifecycle, reliability, feature-use, and completed-session intelligence now runs automatically with no settings switches; raw telemetry, GPS, routes, chat, license keys, screenshots, and phone files remain excluded.",' `
    "Automatic intelligence changelog note"
$Text = Replace-State $Text `
    '        "seen_release_${BuildConfig.VERSION_CODE}_lifecycle_final"' `
    '        "seen_release_${BuildConfig.VERSION_CODE}_automatic_intelligence_final"' `
    "Release-note seen-key update"
Write-Utf8Lf $UpdateUiPath $Text

Write-Host ""
Write-Host "===== STATIC VALIDATION =====" -ForegroundColor Cyan
Assert-Contains $LifecyclePath 'val featureUsageEnabled: Boolean = true'
Assert-Contains $LifecyclePath 'val sessionSummariesEnabled: Boolean = true'
Assert-Contains $LifecyclePath 'lastMessage = "DriveLab telemetry intelligence is active."'
Assert-Contains $ModelsPath 'val featureUsageReportingEnabled: Boolean = true'
Assert-Contains $ModelsPath 'val sessionSummarySharingEnabled: Boolean = true'
Assert-Contains $StoragePath 'featureUsageReportingEnabled = true,'
Assert-Contains $StoragePath 'sessionSummarySharingEnabled = true,'
Assert-Contains $ViewModelPath 'featureUsage = true,'
Assert-Contains $ViewModelPath 'sessionSummaries = true'
Assert-Contains $UiPath 'Automatic intelligence includes screen opens and completions'
Assert-Contains $UpdateUiPath 'automatic_intelligence_final'
$UiText = Read-StrictUtf8 $UiPath
if ($UiText.Contains('"Anonymous feature usage",')) {
    throw "The Anonymous feature usage switch is still present."
}
if ($UiText.Contains('"Share driving session summaries",')) {
    throw "The driving-session summary switch is still present."
}
Write-Host "Automatic reporting enforcement, removed switches, privacy disclosure, and changelog markers passed." -ForegroundColor Green

Write-Host ""
Write-Host "===== CONFIGURING JAVA =====" -ForegroundColor Cyan
$AndroidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not (Test-Path -LiteralPath (Join-Path $AndroidStudioJbr "bin\java.exe") -PathType Leaf)) {
    throw "Android Studio JBR was not found at ${AndroidStudioJbr}"
}
$env:JAVA_HOME = $AndroidStudioJbr
$env:PATH = "$($env:JAVA_HOME)\bin;$env:PATH"
$JavaCommand = Get-Command java.exe -ErrorAction Stop
Write-Host "JAVA_HOME: $env:JAVA_HOME"
& java.exe -version
if ($LASTEXITCODE -ne 0) {
    throw "Java was found but could not be executed."
}

Write-Host ""
Write-Host "===== BUILDING AND TESTING THE AUTOMATIC-INTELLIGENCE STAGE =====" -ForegroundColor Cyan
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
    throw "Gradle build or tests failed with exit code ${GradleExit}. The original project remains unchanged; staged backups are in ${Backup}."
}

$BuiltApk = Join-Path $Stage "app\build\outputs\apk\release\app-release.apk"
if (-not (Test-Path -LiteralPath $BuiltApk -PathType Leaf)) {
    throw "Gradle completed but the release APK was not found: ${BuiltApk}"
}
$ReleaseOutput = Join-Path $Stage "release-output"
New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
$FinalApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-build37-AUTOMATIC-INTELLIGENCE-STAGE.apk"
Copy-Item -LiteralPath $BuiltApk -Destination $FinalApk -Force
$ApkHash = Get-Sha256 $FinalApk

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
& $ApkSigner.FullName verify --verbose --print-certs $FinalApk
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed."
}
$Badging = (& $Aapt.FullName dump badging $FinalApk 2>&1 | Out-String)
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
Write-Host "===== PROVING ORIGINAL PROJECT WAS STILL NOT MODIFIED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-OriginalHash $Entry.Key $Entry.Value
}
Write-Host "Original project hashes remain unchanged." -ForegroundColor Green

Write-Host ""
Write-Host "===== INSTALLING ON THE CONNECTED PHONE =====" -ForegroundColor Cyan
$Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) {
    throw "ADB was not found: ${Adb}"
}
& $Adb devices
$Connected = @(& $Adb devices | Select-String "`tdevice$")
if ($Connected.Count -ne 1) {
    throw "Expected exactly one authorized Android device but found $($Connected.Count)."
}
& $Adb install -r --no-streaming $FinalApk
if ($LASTEXITCODE -ne 0) {
    throw "ADB installation failed. Do not uninstall the existing app because uninstalling would erase local app data."
}
$PackageInfo = & $Adb shell dumpsys package com.auroramediagroup.drivelab
if ($PackageInfo -notmatch "versionCode=37" -or $PackageInfo -notmatch "versionName=2\.4\.0") {
    throw "The package installed, but DriveLab 2.4.0 build 37 was not confirmed."
}
& $Adb shell am force-stop com.auroramediagroup.drivelab | Out-Null
& $Adb shell monkey -p com.auroramediagroup.drivelab -c android.intent.category.LAUNCHER 1 | Out-Null

$ReportLines = @(
    "DRIVELAB 2.4.0 BUILD 37 AUTOMATIC INTELLIGENCE STAGE"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Original project: $Root"
    "Staged project: $Stage"
    "Stage backup: $Backup"
    "APK: $FinalApk"
    "APK SHA-256: $ApkHash"
    ""
    "Passed:"
    "- core lifecycle and reliability intelligence enforced on"
    "- feature-use intelligence enforced on"
    "- completed real-session summaries enforced on"
    "- stale disabled preferences ignored"
    "- feature-use and session-summary switches removed from Setup"
    "- privacy disclosure updated for automatic reporting"
    "- current 2.4.0 changelog updated"
    "- unit tests, release lint, and APK assembly"
    "- APK signature, package, versionName, and versionCode verification"
    "- original project hashes unchanged"
    "- in-place ADB installation preserving app data"
)
[System.IO.File]::WriteAllLines($Report, $ReportLines, $Utf8NoBom)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "AUTOMATIC INTELLIGENCE BUILD INSTALLED SUCCESSFULLY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Installed APK: $FinalApk"
Write-Host "SHA-256:       $ApkHash"
Write-Host "Report:        $Report"
Write-Host "Stage backup:  $Backup"
Write-Host ""
Write-Host "All lifecycle, feature-use, reliability, and completed-session intelligence is active." -ForegroundColor Green
Write-Host "The two reporting switches have been removed from Setup." -ForegroundColor Green
