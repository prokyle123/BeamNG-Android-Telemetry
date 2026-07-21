[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TargetVersion = "2.2.2"
$ExpectedVersion = "2.2.1"
$BackupRoot = $null
$ProjectRoot = $null
$CreatedFiles = New-Object System.Collections.Generic.List[string]

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Text([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Get-RelativePath([string]$BasePath, [string]$FullPath) {
    $base = (Resolve-Path $BasePath).Path.TrimEnd('\') + '\'
    $baseUri = New-Object System.Uri($base)
    $fullUri = New-Object System.Uri((Resolve-Path $FullPath).Path)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '\')
}

function Backup-File([string]$Path) {
    if (-not (Test-Path $Path)) {
        $CreatedFiles.Add($Path) | Out-Null
        return
    }
    $relative = Get-RelativePath $ProjectRoot $Path
    $destination = Join-Path $BackupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Force
}

function Restore-Backup {
    if (-not $BackupRoot -or -not (Test-Path $BackupRoot) -or -not $ProjectRoot) {
        return
    }
    Write-Host "Restoring the pre-patch source backup..." -ForegroundColor Yellow
    Get-ChildItem -Path $BackupRoot -File -Recurse | ForEach-Object {
        $relative = Get-RelativePath $BackupRoot $_.FullName
        $destination = Join-Path $ProjectRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    foreach ($created in $CreatedFiles) {
        if (Test-Path $created) {
            Remove-Item -LiteralPath $created -Force
        }
    }
}

function Replace-FirstLiteral([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $index = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($index -lt 0) {
        throw "$Label anchor was not found."
    }
    return $Text.Substring(0, $index) + $New + $Text.Substring($index + $Old.Length)
}

function Find-DriveLabProject {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($path in @(
        (Get-Location).Path,
        $PSScriptRoot,
        (Join-Path $env:USERPROFILE "OneDrive\Desktop"),
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:USERPROFILE "Documents")
    )) {
        if ($path -and (Test-Path $path) -and -not $roots.Contains($path)) {
            $roots.Add($path) | Out-Null
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($root in $roots) {
        $direct = Join-Path $root "gradlew.bat"
        $wrappers = @()
        if (Test-Path $direct) {
            $wrappers += Get-Item $direct
        }
        try {
            $wrappers += Get-ChildItem -Path $root -Filter gradlew.bat -File -Recurse -ErrorAction SilentlyContinue
        } catch {
        }

        foreach ($wrapper in $wrappers) {
            $candidate = $wrapper.Directory.FullName
            if ($seen.ContainsKey($candidate)) { continue }
            $seen[$candidate] = $true

            $gradle = Join-Path $candidate "app\build.gradle.kts"
            if (-not (Test-Path $gradle)) { continue }
            $text = Read-Text $gradle
            if ($text -notmatch 'applicationId\s*=\s*"com\.auroramediagroup\.drivelab"') { continue }
            $versionMatch = [regex]::Match($text, 'versionName\s*=\s*"([^"]+)"')
            if (-not $versionMatch.Success) { continue }
            $cleanVersion = $versionMatch.Groups[1].Value.Split('-')[0]
            try {
                $parsed = New-Object System.Version($cleanVersion)
            } catch {
                continue
            }
            $candidates.Add([pscustomobject]@{
                Root = $candidate
                Version = $cleanVersion
                Parsed = $parsed
            }) | Out-Null
        }
    }

    $selected = $candidates |
        Where-Object { $_.Version -eq $ExpectedVersion -or $_.Version -eq $TargetVersion } |
        Sort-Object Parsed -Descending |
        Select-Object -First 1

    if (-not $selected) {
        $found = ($candidates | Sort-Object Parsed -Descending | ForEach-Object { "$($_.Version)  $($_.Root)" }) -join "`r`n"
        throw "DriveLab $ExpectedVersion was not found. Projects discovered:`r`n$found"
    }
    return $selected.Root
}

function Update-CoDriverSource([string[]]$Files) {
    $updated = @{}
    $runtimeChanges = 0
    $displayChanges = 0
    $changeReport = New-Object System.Collections.Generic.List[string]

    foreach ($file in $Files) {
        $text = Read-Text $file
        if ($text -notmatch '(?i)(auto\s*co[- ]?driver|co[- ]?driver|codriver|pace\s*notes?|paceNote)') {
            continue
        }

        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = $text -split "`r?`n", -1
        $changed = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $from = [Math]::Max(0, $i - 3)
            $to = [Math]::Min($lines.Count - 1, $i + 3)
            $context = ($lines[$from..$to] -join " ")
            $oldLine = $lines[$i]
            $newLine = $oldLine
            $runtimeLineChanged = $false

            if ($context -match '(?i)(free|trial|preview|limit|remaining|edition|unlock|full)') {
                $beforeRuntime = $newLine
                $newLine = $newLine.Replace('60_000L', '30_000L')
                $newLine = $newLine.Replace('60_000', '30_000')
                $newLine = $newLine.Replace('60000L', '30000L')
                $newLine = $newLine.Replace('60000', '30000')
                $newLine = [regex]::Replace($newLine, '(?i)Duration\.ofSeconds\(\s*60\s*\)', 'Duration.ofSeconds(30)')
                $newLine = [regex]::Replace($newLine, '(?i)TimeUnit\.SECONDS\.toMillis\(\s*60\s*\)', 'TimeUnit.SECONDS.toMillis(30)')
                $newLine = [regex]::Replace($newLine, '(?<!\d)60\s*\*\s*1_?000L?', '30 * 1000L')
                $newLine = [regex]::Replace($newLine, '(?<![\d.])60\.0(?!\d)', '30.0')
                $newLine = [regex]::Replace($newLine, '(?<!\d)60\.seconds(?!\w)', '30.seconds')

                if (
                    $newLine -notmatch '["'']' -and
                    (
                        $newLine -match '(?i)(seconds?|duration|trial|preview|limit|remaining|free)' -or
                        $newLine.Trim() -match '^60(?:L|f)?[,;]?$'
                    )
                ) {
                    $newLine = [regex]::Replace($newLine, '(?<![\d.])60L(?!\w)', '30L')
                    $newLine = [regex]::Replace($newLine, '(?<![\d.])60f(?!\w)', '30f')
                    $newLine = [regex]::Replace($newLine, '(?<![\d.])60(?![\d.]|\s*[-–]\s*0|\.sp|\.dp)', '30')
                }

                if ($newLine -ne $beforeRuntime -and $oldLine -notmatch '["'']') {
                    $runtimeLineChanged = $true
                }
            }

            if ($context -match '(?i)(auto\s*co[- ]?driver|co[- ]?driver|codriver|pace\s*notes?)') {
                $newLine = [regex]::Replace($newLine, '(?i)60-second', '30-second')
                $newLine = [regex]::Replace($newLine, '(?i)60 seconds', '30 seconds')
                $newLine = [regex]::Replace($newLine, '(?i)60 second', '30 second')
            }

            if ($newLine -ne $oldLine) {
                if ($runtimeLineChanged) { $runtimeChanges++ } else { $displayChanges++ }
                $changeReport.Add("${file}:$($i + 1): $($oldLine.Trim())  ->  $($newLine.Trim())") | Out-Null
                $lines[$i] = $newLine
                $changed = $true
            }
        }

        if ($changed) {
            $updated[$file] = ($lines -join $newline)
        }
    }

    if ($runtimeChanges -lt 1) {
        $names = ($Files | ForEach-Object { $_ }) -join "`r`n"
        throw "The Auto Co-Driver files were found, but the runtime 60-second Free limit could not be identified safely. No source was changed.`r`n$names"
    }

    return [pscustomobject]@{
        Updated = $updated
        RuntimeChanges = $runtimeChanges
        DisplayChanges = $displayChanges
        Report = $changeReport
    }
}

try {
    Write-Host "Finding the current DriveLab project..." -ForegroundColor Cyan
    $ProjectRoot = Find-DriveLabProject
    Set-Location $ProjectRoot
    Write-Host "Project: $ProjectRoot" -ForegroundColor Green

    $GradlePath = Join-Path $ProjectRoot "app\build.gradle.kts"
    $GradleText = Read-Text $GradlePath
    $versionMatch = [regex]::Match($GradleText, 'versionName\s*=\s*"([^"]+)"')
    $currentVersion = $versionMatch.Groups[1].Value.Split('-')[0]

    if ($currentVersion -eq $TargetVersion) {
        throw "This project is already version $TargetVersion. The patch was not applied twice."
    }
    if ($currentVersion -ne $ExpectedVersion) {
        throw "Expected DriveLab $ExpectedVersion but found $currentVersion."
    }

    $sourceRoots = @(
        (Join-Path $ProjectRoot "app\src\main\java"),
        (Join-Path $ProjectRoot "app\src\main\kotlin"),
        (Join-Path $ProjectRoot "app\src\test\java"),
        (Join-Path $ProjectRoot "app\src\test\kotlin")
    ) | Where-Object { Test-Path $_ }

    $allKotlin = @($sourceRoots | ForEach-Object {
        Get-ChildItem -Path $_ -Filter *.kt -File -Recurse -ErrorAction SilentlyContinue
    })

    $featureFiles = @($allKotlin | Where-Object {
        (Read-Text $_.FullName) -match '(?i)(auto\s*co[- ]?driver|co[- ]?driver|codriver|pace\s*notes?|paceNote)'
    } | Select-Object -ExpandProperty FullName -Unique)

    if ($featureFiles.Count -lt 1) {
        throw "Auto Co-Driver source files were not found in the $ExpectedVersion project."
    }

    Write-Host "Auto Co-Driver files found: $($featureFiles.Count)" -ForegroundColor Cyan
    $coDriverResult = Update-CoDriverSource $featureFiles

    $codeRegex = [regex]::new('versionCode\s*=\s*(\d+)')
    $codeMatch = $codeRegex.Match($GradleText)
    if (-not $codeMatch.Success) { throw "versionCode was not found in app\build.gradle.kts." }
    $oldCode = [int]$codeMatch.Groups[1].Value
    $newCode = $oldCode + 1
    $newCodeText = $codeMatch.Value -replace '\d+', $newCode
    $NewGradleText = $GradleText.Substring(0, $codeMatch.Index) + $newCodeText + $GradleText.Substring($codeMatch.Index + $codeMatch.Length)
    $NewGradleText = Replace-FirstLiteral $NewGradleText "versionName = `"$ExpectedVersion`"" "versionName = `"$TargetVersion`"" "versionName"

    $UpdateUiPath = Join-Path $ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt"
    if (-not (Test-Path $UpdateUiPath)) {
        $UpdateUiPath = Join-Path $ProjectRoot "app\src\main\kotlin\com\auroramediagroup\drivelab\UpdateUi.kt"
    }
    if (-not (Test-Path $UpdateUiPath)) { throw "UpdateUi.kt was not found." }
    $UpdateUiText = Read-Text $UpdateUiPath
    if ($UpdateUiText.Contains("version = `"$TargetVersion`"")) {
        throw "The in-app release history already contains $TargetVersion."
    }
    $UpdateUiText = Replace-FirstLiteral $UpdateUiText 'label = "CURRENT RELEASE"' 'label = "PREVIOUS RELEASE"' "Current release label"
    $releaseAnchor = 'private val ReleaseHistory = listOf('
    $releaseEntry = @'
private val ReleaseHistory = listOf(
    ReleaseEntry(
        version = "2.2.2",
        label = "CURRENT RELEASE",
        notes = listOf(
            "Reduced the Free Edition Auto Co-Driver preview from 60 seconds to 30 seconds.",
            "Full Edition Auto Co-Driver remains unlimited.",
            "Preserved licenses, settings, TrackLab courses, pace notes, progression, sessions, and Android signing compatibility."
        )
    ),
'@
    $NewUpdateUiText = Replace-FirstLiteral $UpdateUiText $releaseAnchor $releaseEntry "Release history"

    $ChangelogPath = Join-Path $ProjectRoot "CHANGELOG.md"
    if (-not (Test-Path $ChangelogPath)) { throw "CHANGELOG.md was not found." }
    $ChangelogText = Read-Text $ChangelogPath
    $heading = "# DriveLab Telem Changelog"
    if (-not $ChangelogText.StartsWith($heading)) { throw "CHANGELOG.md heading was not recognized." }
    $changelogEntry = @'
# DriveLab Telem Changelog

## 2.2.2

- Reduced the Free Edition Auto Co-Driver preview from 60 seconds to 30 seconds.
- Full Edition Auto Co-Driver remains unlimited.
- Preserved licenses, settings, TrackLab courses, pace notes, progression, sessions, and Android signing compatibility.

'@
    $NewChangelogText = $changelogEntry + $ChangelogText.Substring($heading.Length).TrimStart([char[]]"`r`n")

    $ReleaseNotesPath = Join-Path $ProjectRoot "UPDATE-RELEASE-NOTES.txt"
    $NewReleaseNotes = @'
DriveLab Telem 2.2.2

- Reduced the Free Edition Auto Co-Driver preview from 60 seconds to 30 seconds.
- Full Edition Auto Co-Driver remains unlimited.
- Preserves existing licenses, settings, TrackLab courses, pace notes, progression, sessions, and saved data.
'@

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupRoot = Join-Path $ProjectRoot ".drivelab-backups\codriver-free-30s-$timestamp"
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

    $pathsToChange = New-Object System.Collections.Generic.List[string]
    $pathsToChange.Add($GradlePath) | Out-Null
    $pathsToChange.Add($UpdateUiPath) | Out-Null
    $pathsToChange.Add($ChangelogPath) | Out-Null
    $pathsToChange.Add($ReleaseNotesPath) | Out-Null
    foreach ($path in $coDriverResult.Updated.Keys) { $pathsToChange.Add($path) | Out-Null }

    foreach ($path in ($pathsToChange | Select-Object -Unique)) {
        Backup-File $path
    }

    Write-Host "Backup: $BackupRoot" -ForegroundColor Cyan
    Write-Text $GradlePath $NewGradleText
    Write-Text $UpdateUiPath $NewUpdateUiText
    Write-Text $ChangelogPath $NewChangelogText
    Write-Text $ReleaseNotesPath $NewReleaseNotes
    foreach ($entry in $coDriverResult.Updated.GetEnumerator()) {
        Write-Text $entry.Key $entry.Value
    }

    $auditGradle = Read-Text $GradlePath
    if ($auditGradle -notmatch 'versionName\s*=\s*"2\.2\.2"') { throw "Version-name validation failed." }
    if ($auditGradle -notmatch ("versionCode\s*=\s*" + $newCode)) { throw "Version-code validation failed." }

    $reportPath = Join-Path $ProjectRoot "DRIVELAB-2.2.2-PATCH-REPORT.txt"
    if (-not (Test-Path $reportPath)) { $CreatedFiles.Add($reportPath) | Out-Null }
    $reportText = @(
        "DriveLab 2.2.2 Auto Co-Driver Free Preview Patch",
        "Project: $ProjectRoot",
        "Previous version: $ExpectedVersion ($oldCode)",
        "New version: $TargetVersion ($newCode)",
        "Runtime timing changes: $($coDriverResult.RuntimeChanges)",
        "Display-text changes: $($coDriverResult.DisplayChanges)",
        "Backup: $BackupRoot",
        "",
        "Changed timing lines:",
        ($coDriverResult.Report -join "`r`n")
    ) -join "`r`n"
    Write-Text $reportPath $reportText

    Write-Host "Running unit tests, release lint, and signed release build..." -ForegroundColor Cyan
    $setupScript = Join-Path $ProjectRoot "SETUP-WINDOWS.ps1"
    if (Test-Path $setupScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
        if ($LASTEXITCODE -ne 0) { throw "SETUP-WINDOWS.ps1 failed with exit code $LASTEXITCODE." }
    }

    & (Join-Path $ProjectRoot "gradlew.bat") clean testDebugUnitTest lintRelease assembleRelease --stacktrace
    if ($LASTEXITCODE -ne 0) { throw "Gradle tests, lint, or release build failed with exit code $LASTEXITCODE." }

    $builtApk = Join-Path $ProjectRoot "app\build\outputs\apk\release\app-release.apk"
    if (-not (Test-Path $builtApk)) { throw "The release APK was not produced." }
    if (-not (Test-Path (Join-Path $ProjectRoot "keystore.properties"))) {
        throw "keystore.properties is missing, so the permanent customer signing identity could not be confirmed."
    }

    $releaseOutput = Join-Path $ProjectRoot "release-output"
    New-Item -ItemType Directory -Force -Path $releaseOutput | Out-Null
    $customerApk = Join-Path $releaseOutput "DriveLab-Telem-v2.2.2.apk"
    Copy-Item -LiteralPath $builtApk -Destination $customerApk -Force
    $sha256 = (Get-FileHash -LiteralPath $customerApk -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Text (Join-Path $releaseOutput "DriveLab-Telem-v2.2.2.apk.sha256") "$sha256  DriveLab-Telem-v2.2.2.apk`r`n"

    $sdkRoot = $env:ANDROID_SDK_ROOT
    if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_HOME }
    if (-not $sdkRoot) { $sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    $apksigner = Get-ChildItem -Path (Join-Path $sdkRoot "build-tools") -Filter apksigner.bat -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($apksigner) {
        & $apksigner.FullName verify --verbose --print-certs $customerApk
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed." }
    }

    $adb = Join-Path $sdkRoot "platform-tools\adb.exe"
    $installed = $false
    if (Test-Path $adb) {
        $deviceLines = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice\s*$" })
        if ($deviceLines.Count -eq 1) {
            Write-Host "Installing the signed 2.2.2 test APK on the connected Android device..." -ForegroundColor Cyan
            & $adb install -r $customerApk
            if ($LASTEXITCODE -eq 0) {
                $installed = $true
            } else {
                Write-Host "The APK built and verified, but automatic phone installation failed. Install it manually from release-output." -ForegroundColor Yellow
            }
        } elseif ($deviceLines.Count -gt 1) {
            Write-Host "Multiple Android devices are connected, so automatic installation was skipped." -ForegroundColor Yellow
        } else {
            Write-Host "No Android device is connected, so automatic installation was skipped." -ForegroundColor Yellow
        }
    }

    $checklistPath = Join-Path $ProjectRoot "DRIVELAB-2.2.2-TEST-CHECKLIST.txt"
    if (-not (Test-Path $checklistPath)) { $CreatedFiles.Add($checklistPath) | Out-Null }
    $checklist = @'
DRIVELAB 2.2.2 TEST CHECKLIST

Nothing has been published yet.

FREE EDITION
1. Open Auto Co-Driver in live or demo telemetry.
2. Start the Free preview.
3. Confirm the countdown begins at 30 seconds.
4. Confirm spoken pace notes stop when the 30-second preview expires.
5. Confirm the upgrade message appears and the app remains stable.

FULL EDITION
1. Activate or retain a Full license.
2. Start Auto Co-Driver.
3. Confirm it continues beyond 30 and 60 seconds without interruption.
4. Confirm saved courses, pace notes, TrackLab data, settings, and progression remain intact.

GENERAL
1. Confirm DriveLab reports version 2.2.2.
2. Confirm secure update checking still works.
3. Confirm RaceLink, TrackLab, telemetry, and licensing still open normally.
4. Do not run the publisher until both Free and Full checks pass.
'@
    Write-Text $checklistPath $checklist

    Write-Host ""
    Write-Host "DRIVELAB 2.2.2 TEST BUILD PASSED" -ForegroundColor Green
    Write-Host "APK: $customerApk" -ForegroundColor Cyan
    Write-Host "SHA-256: $sha256" -ForegroundColor Cyan
    Write-Host "Installed on phone: $installed" -ForegroundColor Cyan
    Write-Host "Checklist: $checklistPath" -ForegroundColor Cyan
    Write-Host "Nothing was published to customers, GitHub Releases, the website, or the Pi update server." -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    try { Restore-Backup } catch { Write-Host "Rollback warning: $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host "Nothing was published." -ForegroundColor Yellow
    exit 1
}
