$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$JavaHome = "C:\Program Files\Android\Android Studio\jbr"
$ExpectedVersion = "2.4.0"
$ExpectedBuild = 36
$NewVersion = "2.4.1"
$NewBuild = 37

$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $Project "backups\before-v2.4.1-locked-full-tabs-$Timestamp"

$Paths = [ordered]@{
    DriveLabUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt"
    EditionUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\EditionUi.kt"
    UpdateUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt"
    BuildGradle = Join-Path $Project "app\build.gradle.kts"
    Changelog = Join-Path $Project "CHANGELOG.md"
    ReleaseNotes = Join-Path $Project "UPDATE-RELEASE-NOTES.txt"
}

function Read-Utf8Text {
    param([Parameter(Mandatory)][string]$Path)

    $Text = [System.IO.File]::ReadAllText($Path, $Utf8Read)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, $Utf8Write)
}

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New,
        [Parameter(Mandatory)][string]$Label
    )

    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "$Label expected exactly one source anchor but found $Count. No source file was changed."
    }

    return $Text.Replace($Old, $New)
}

function Replace-RegexOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement,
        [Parameter(Mandatory)][string]$Label
    )

    $Regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $Matches = $Regex.Matches($Text)

    if ($Matches.Count -ne 1) {
        throw "$Label expected exactly one source anchor but found $($Matches.Count). No source file was changed."
    }

    return $Regex.Replace($Text, $Replacement, 1)
}

foreach ($Entry in $Paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $Entry.Value)) {
        throw "Required project file was not found: $($Entry.Value)"
    }
}

$BuildGradle = Read-Utf8Text $Paths.BuildGradle

if ($BuildGradle -notmatch "versionCode\s*=\s*$ExpectedBuild") {
    throw "Expected DriveLab build $ExpectedBuild before applying 2.4.1. The project was not changed."
}

if ($BuildGradle -notmatch "versionName\s*=\s*\"$([regex]::Escape($ExpectedVersion))\"") {
    throw "Expected DriveLab version $ExpectedVersion before applying 2.4.1. The project was not changed."
}

if ($BuildGradle -match "versionName\s*=\s*\"$([regex]::Escape($NewVersion))\"") {
    throw "DriveLab $NewVersion already appears to be applied."
}

$DriveLabUi = Read-Utf8Text $Paths.DriveLabUi
$EditionUi = Read-Utf8Text $Paths.EditionUi
$UpdateUi = Read-Utf8Text $Paths.UpdateUi
$Changelog = Read-Utf8Text $Paths.Changelog

# Normalize the bottom navigation to always iterate every MainTab. This also
# repairs earlier Free-only filters if one was introduced locally.
$NavigationLoopPattern = '(NavigationBar\([^{}]*\)\s*\{\s*)(?:MainTab\.entries(?:\s*\.filter\s*\{.*?\})?|[A-Za-z_][A-Za-z0-9_]*)(\s*\.forEach\s*\{\s*tab\s*->\s*)(?=val\s+label)'
$NavigationLoopRegex = [regex]::new(
    $NavigationLoopPattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$NavigationLoopMatches = $NavigationLoopRegex.Matches($DriveLabUi)

if ($NavigationLoopMatches.Count -ne 1) {
    throw "Could not safely locate the main DriveLab navigation loop. Found $($NavigationLoopMatches.Count) candidates."
}

$DriveLabUi = $NavigationLoopRegex.Replace(
    $DriveLabUi,
    '$1MainTab.entries$2',
    1
)

$LockedVariablePattern = '(MainTab\.entries\s*\.forEach\s*\{\s*tab\s*->\s*)(val\s+label\s*=)'
$LockedVariableRegex = [regex]::new(
    $LockedVariablePattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if ($DriveLabUi -notmatch 'val\s+locked\s*=\s*tab\.requiresFullEdition\(\)') {
    if ($LockedVariableRegex.Matches($DriveLabUi).Count -ne 1) {
        throw "Could not add the locked-tab state beside the main navigation loop."
    }

    $DriveLabUi = $LockedVariableRegex.Replace(
        $DriveLabUi,
        '$1val locked = tab.requiresFullEdition() && !licenseState.fullFeaturesUnlocked' + "`n                    " + '$2',
        1
    )
}

$OldNavigationItemPattern = 'NavigationBarItem\(\s*selected\s*=\s*selectedTab\s*==\s*tab,\s*onClick\s*=\s*\{\s*selectedTab\s*=\s*tab\s*\},\s*icon\s*=\s*\{\s*Text\(symbol,\s*fontWeight\s*=\s*FontWeight\.Black\)\s*\},\s*label\s*=\s*\{\s*Text\(label,\s*maxLines\s*=\s*1\)\s*\}\s*\)'
$NewNavigationItem = @'
NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = {
                            Text(
                                text = if (locked) "🔒" else symbol,
                                fontWeight = FontWeight.Black
                            )
                        },
                        label = {
                            Text(
                                text = label,
                                maxLines = 1
                            )
                        },
                        alwaysShowLabel = true,
                        colors =
                            NavigationBarItemDefaults.colors(
                                selectedIconColor =
                                    if (locked) {
                                        DriveAmber.copy(alpha = 0.72f)
                                    } else {
                                        DriveCyan
                                    },
                                selectedTextColor =
                                    if (locked) {
                                        DriveMuted.copy(alpha = 0.72f)
                                    } else {
                                        Color.White
                                    },
                                indicatorColor =
                                    if (locked) {
                                        DriveAmber.copy(alpha = 0.08f)
                                    } else {
                                        DriveCyan.copy(alpha = 0.12f)
                                    },
                                unselectedIconColor =
                                    if (locked) {
                                        DriveMuted.copy(alpha = 0.52f)
                                    } else {
                                        DriveMuted
                                    },
                                unselectedTextColor =
                                    if (locked) {
                                        DriveMuted.copy(alpha = 0.52f)
                                    } else {
                                        DriveMuted
                                    }
                            )
                    )
'@

$DriveLabUi = Replace-RegexOnce `
    -Text $DriveLabUi `
    -Pattern $OldNavigationItemPattern `
    -Replacement $NewNavigationItem.Trim() `
    -Label "Main navigation item"

if ($DriveLabUi -notmatch 'import\s+androidx\.compose\.material3\.NavigationBarItemDefaults') {
    $DriveLabUi = Replace-ExactOnce `
        -Text $DriveLabUi `
        -Old "import androidx.compose.material3.NavigationBarItem`n" `
        -New "import androidx.compose.material3.NavigationBarItem`nimport androidx.compose.material3.NavigationBarItemDefaults`n" `
        -Label "NavigationBarItemDefaults import"
}

$NewLockedScreen = @'
@Composable
fun FullEditionLockedScreen(
    featureName: String,
    contentPadding: PaddingValues,
    onUpgrade: () -> Unit
) {
    val context = LocalContext.current
    val featureDescription =
        when (featureName) {
            "Cockpit Dashboards" ->
                "Build custom cockpit layouts with advanced gauges, live vehicle details, dashboard styles, and configurable telemetry panels."

            "RaceLink Multiplayer" ->
                "Connect with friends, create private race rooms, send invitations, use room chat, compare runs, and compete through DriveLab."

            "Driving Analysis" ->
                "Review saved drives, performance graphs, crash records, coaching, history, achievements, and detailed session analysis."

            else ->
                "$featureName and every other advanced DriveLab tool are included with the Full Edition."
        }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .padding(contentPadding)
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(18.dp),
        verticalArrangement =
            Arrangement.spacedBy(14.dp)
    ) {
        Text(
            text = "LOCKED IN FREE EDITION",
            color = DriveAmber,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.labelLarge
        )

        Text(
            text = featureName,
            color = Color.White,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.headlineSmall
        )

        Text(
            text =
                "This tab stays visible so Free Edition drivers can see what DriveLab Full adds.",
            color = DriveMuted
        )

        Column(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .background(
                        DrivePanel,
                        RoundedCornerShape(18.dp)
                    )
                    .border(
                        1.dp,
                        DriveAmber.copy(alpha = 0.38f),
                        RoundedCornerShape(18.dp)
                    )
                    .padding(16.dp),
            verticalArrangement =
                Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement =
                    Arrangement.SpaceBetween
            ) {
                Text(
                    text = "WHAT FULL UNLOCKS",
                    color = DriveCyan,
                    fontWeight = FontWeight.Black
                )

                Text(
                    text = "FULL",
                    color = DriveAmber,
                    fontWeight = FontWeight.Black
                )
            }

            Text(
                text = featureDescription,
                color = Color.White.copy(alpha = 0.90f),
                style = MaterialTheme.typography.bodyMedium
            )

            Button(
                onClick = {
                    if (
                        BuildConfig.LICENSE_PURCHASE_URL
                            .isNotBlank()
                    ) {
                        openEditionPurchaseUrl(
                            context,
                            BuildConfig.LICENSE_PURCHASE_URL
                        )
                    } else {
                        onUpgrade()
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("GET FULL VERSION")
            }

            OutlinedButton(
                onClick = onUpgrade,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("ENTER LICENSE KEY")
            }

            Text(
                text = "One permanent license. No subscription required.",
                color = DriveMuted,
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
'@

$LockedScreenPattern = '@Composable\s+fun\s+FullEditionLockedScreen\(.*?(?=\n@Composable\s+fun\s+UpgradeFullEditionCard\()'
$EditionUi = Replace-RegexOnce `
    -Text $EditionUi `
    -Pattern $LockedScreenPattern `
    -Replacement ($NewLockedScreen.TrimEnd() + "`n`n") `
    -Label "Full Edition locked screen"

$BuildGradle = Replace-RegexOnce `
    -Text $BuildGradle `
    -Pattern 'versionCode\s*=\s*36' `
    -Replacement 'versionCode = 37' `
    -Label "Android versionCode"

$BuildGradle = Replace-RegexOnce `
    -Text $BuildGradle `
    -Pattern 'versionName\s*=\s*"2\.4\.0"' `
    -Replacement 'versionName = "2.4.1"' `
    -Label "Android versionName"

if ($UpdateUi -match 'version\s*=\s*"2\.4\.1"') {
    throw "UpdateUi.kt already contains a 2.4.1 release entry."
}

$UpdateUi = Replace-ExactOnce `
    -Text $UpdateUi `
    -Old @'
ReleaseEntry(
        version = "2.4.0",
        label = "CURRENT RELEASE",
'@ `
    -New @'
ReleaseEntry(
        version = "2.4.0",
        label = "PREVIOUS RELEASE",
'@ `
    -Label "2.4.0 release-history label"

$NewReleaseEntry = @'
    ReleaseEntry(
        version = "2.4.1",
        label = "CURRENT RELEASE",
        notes = listOf(
            "Kept Cockpit, Link, and Analyze visible in Free Edition so drivers can see the advanced areas available in DriveLab Full.",
            "Added dimmed navigation styling and lock icons to Full-only tabs while preserving normal access for licensed users.",
            "Added dedicated locked-feature previews describing what each Full tab provides.",
            "Added a direct Get Full Version purchase action and a separate Enter License Key path.",
            "Preserved licenses, Drive Intelligence data, sessions, achievements, TrackLab courses, RaceLink profiles, settings, and Android signing compatibility."
        )
    ),
'@

$UpdateUi = Replace-ExactOnce `
    -Text $UpdateUi `
    -Old "private val ReleaseHistory = listOf(`n" `
    -New ("private val ReleaseHistory = listOf(`n" + $NewReleaseEntry + "`n") `
    -Label "Release-history list"

$ChangelogEntry = @'
## 2.4.1

- Kept Cockpit, Link, and Analyze visible in Free Edition.
- Added dimmed navigation styling and lock icons to Full-only tabs.
- Added dedicated previews explaining what each locked Full tab provides.
- Added a direct Get Full Version button and a separate Enter License Key action.
- Preserved licenses, Drive Intelligence data, sessions, achievements, TrackLab courses, RaceLink profiles, settings, and signing compatibility.

'@

if ($Changelog -match '(?m)^##\s+2\.4\.1\s*$') {
    throw "CHANGELOG.md already contains a 2.4.1 entry."
}

$Changelog = Replace-ExactOnce `
    -Text $Changelog `
    -Old "# DriveLab Telem Changelog`n`n" `
    -New ("# DriveLab Telem Changelog`n`n" + $ChangelogEntry) `
    -Label "Changelog title"

$ReleaseNotes = @'
DriveLab Telem 2.4.1 — Full Edition tab previews

- Cockpit, Link, and Analyze remain visible in Free Edition
- Full-only tabs are dimmed and display lock icons
- Tapping a locked tab opens a real feature preview
- Added a direct Get Full Version purchase button
- Added a separate Enter License Key action
- Full Edition navigation and functionality remain unchanged
- Preserved licenses, Drive Intelligence data, sessions, achievements, TrackLab courses, RaceLink profiles, settings, and signing compatibility

Install this update directly over the existing DriveLab installation. Do not uninstall first.
'@

# Final source validation before touching the project.
$RequiredUiMarkers = @(
    'val locked = tab.requiresFullEdition() && !licenseState.fullFeaturesUnlocked',
    'text = if (locked) "🔒" else symbol',
    'NavigationBarItemDefaults.colors'
)

foreach ($Marker in $RequiredUiMarkers) {
    if (-not $DriveLabUi.Contains($Marker)) {
        throw "DriveLabUi validation failed before writing: $Marker"
    }
}

$RequiredEditionMarkers = @(
    'LOCKED IN FREE EDITION',
    'GET FULL VERSION',
    'ENTER LICENSE KEY',
    'One permanent license. No subscription required.'
)

foreach ($Marker in $RequiredEditionMarkers) {
    if (-not $EditionUi.Contains($Marker)) {
        throw "EditionUi validation failed before writing: $Marker"
    }
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

foreach ($Entry in $Paths.GetEnumerator()) {
    $Relative = $Entry.Value.Substring($Project.Length).TrimStart('\')
    $BackupPath = Join-Path $BackupRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path $BackupPath -Parent) | Out-Null
    Copy-Item -LiteralPath $Entry.Value -Destination $BackupPath -Force
}

$WroteSource = $false

try {
    Write-Host ""
    Write-Host "===== APPLYING DRIVELAB 2.4.1 =====" -ForegroundColor Cyan

    Write-Utf8Text $Paths.DriveLabUi $DriveLabUi
    Write-Utf8Text $Paths.EditionUi $EditionUi
    Write-Utf8Text $Paths.UpdateUi $UpdateUi
    Write-Utf8Text $Paths.BuildGradle $BuildGradle
    Write-Utf8Text $Paths.Changelog $Changelog
    Write-Utf8Text $Paths.ReleaseNotes ($ReleaseNotes.TrimEnd() + "`n")
    $WroteSource = $true

    $env:JAVA_HOME = $JavaHome
    $env:Path = "$JavaHome\bin;$env:Path"

    Push-Location $Project
    try {
        Write-Host ""
        Write-Host "===== UNIT TESTS, LINT, AND SIGNED RELEASE BUILD =====" -ForegroundColor Cyan
        Write-Host "Do not close this window or press Ctrl+C while Gradle is running." -ForegroundColor Yellow

        & .\gradlew.bat `
            --no-daemon `
            testReleaseUnitTest `
            lintRelease `
            assembleRelease

        if ($LASTEXITCODE -ne 0) {
            throw "Gradle failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    $BuiltApk = Join-Path $Project "app\build\outputs\apk\release\app-release.apk"
    if (-not (Test-Path -LiteralPath $BuiltApk)) {
        throw "Gradle completed but the signed release APK was not found: $BuiltApk"
    }

    $ReleaseOutput = Join-Path $Project "release-output"
    New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
    $NamedApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.1.apk"
    Copy-Item -LiteralPath $BuiltApk -Destination $NamedApk -Force

    $Hash = (
        Get-FileHash -LiteralPath $NamedApk -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "DRIVELAB 2.4.1 BUILD COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "APK:     $NamedApk"
    Write-Host "SHA-256: $Hash"
    Write-Host "Backup:  $BackupRoot"

    $Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $Adb) {
        $ConnectedDevices = & $Adb devices |
            Select-String -Pattern "\tdevice$"

        if ($ConnectedDevices) {
            Write-Host ""
            Write-Host "===== INSTALLING ON CONNECTED ANDROID DEVICE =====" -ForegroundColor Cyan
            & $Adb install -r $NamedApk

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "The APK built successfully, but ADB installation failed. Install the APK manually from release-output."
            }
        } else {
            Write-Host "No authorized Android device was connected. The APK was not installed automatically." -ForegroundColor Yellow
        }
    }
}
catch {
    if ($WroteSource) {
        Write-Host ""
        Write-Host "PATCH OR BUILD FAILED — RESTORING SOURCE BACKUP" -ForegroundColor Red

        foreach ($Entry in $Paths.GetEnumerator()) {
            $Relative = $Entry.Value.Substring($Project.Length).TrimStart('\')
            $BackupPath = Join-Path $BackupRoot $Relative
            if (Test-Path -LiteralPath $BackupPath) {
                Copy-Item -LiteralPath $BackupPath -Destination $Entry.Value -Force
            }
        }

        Write-Host "The DriveLab 2.4.0 source files were restored." -ForegroundColor Yellow
    }

    throw
}
