$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Get-Location).Path
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Stage = Join-Path (Split-Path $Root -Parent) "DriveLabTelem-v2.4.0-lifecycle-stage-$Stamp"
$Report = Join-Path $Stage "LIFECYCLE-ANDROID-STAGE-REPORT.txt"
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Normalize-Lf([string]$Value) {
    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Read-StrictUtf8([string]$Path) {
    return Normalize-Lf ([System.IO.File]::ReadAllText($Path, $Utf8Strict))
}

function Write-Utf8Lf([string]$Path, [string]$Value) {
    [System.IO.File]::WriteAllText($Path, (Normalize-Lf $Value), $Utf8NoBom)
}

function Replace-Once(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
) {
    $Old = Normalize-Lf $Old
    $New = Normalize-Lf $New
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "$Label expected exactly one source anchor but found $Count."
    }
    return $Text.Replace($Old, $New)
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

function Assert-Hash([string]$Relative, [string]$Expected, [string]$Base = $Root) {
    $Path = Join-Path $Base $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required source file is missing: $Path"
    }
    $Actual = Get-Sha256 $Path
    if ($Actual -ne $Expected) {
        throw "Baseline mismatch for $Relative. Expected $Expected but found $Actual. Do not patch a different source tree."
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
Write-Host "DRIVELAB 2.4.0 BUILD 37 - ISOLATED LIFECYCLE ANDROID STAGE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Source: $Root"
Write-Host "Stage:  $Stage"
Write-Host ""
Write-Host "The working project will not be modified. The complete project is copied" -ForegroundColor Yellow
Write-Host "to a sibling staging directory before any source edit or build." -ForegroundColor Yellow

if (-not (Test-Path (Join-Path $Root "gradlew.bat"))) {
    throw "Run this command from the DriveLab Android project root."
}

foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-Hash $Entry.Key $Entry.Value
}

$GradleSource = Read-StrictUtf8 (Join-Path $Root "app\build.gradle.kts")
if ($GradleSource -notmatch 'versionCode\s*=\s*37') {
    throw "Expected the captured source to contain versionCode 37."
}
if ($GradleSource -notmatch 'versionName\s*=\s*"2\.4\.1"') {
    throw "Expected the captured source to contain the abandoned local versionName 2.4.1 before restoring it to 2.4.0."
}

Write-Host "" 
Write-Host "===== COPYING THE COMPLETE PROJECT TO AN ISOLATED STAGE =====" -ForegroundColor Cyan
if (Test-Path $Stage) {
    throw "The stage already exists: $Stage"
}

$RoboArgs = @(
    $Root,
    $Stage,
    "/E",
    "/COPY:DAT",
    "/DCOPY:DAT",
    "/R:2",
    "/W:1",
    "/XJ",
    "/NFL",
    "/NDL",
    "/NP",
    "/XD",
    ".git",
    ".gradle",
    "build",
    "release-output",
    "/XF",
    "DriveLab-2.4.0-Lifecycle-Source-*.zip",
    "DriveLab-2.4.0-Lifecycle-READABLE-*.txt"
)
& robocopy.exe @RoboArgs | Out-Null
$RoboCode = $LASTEXITCODE
if ($RoboCode -ge 8) {
    throw "Project staging copy failed with robocopy exit code $RoboCode."
}

foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-Hash $Entry.Key $Entry.Value $Stage
}

$JavaRoot = Join-Path $Stage "app\src\main\java\com\auroramediagroup\drivelab"
$LifecyclePath = Join-Path $JavaRoot "LifecycleTelemetry.kt"
$LifecycleUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/lifecycle-intelligence-v1/patches/lifecycle-intelligence-v1/android/LifecycleTelemetry.kt?stage=$Stamp"
$ExpectedLifecycleBlob = "ad278bebfd63519189a9972838147ec2db46721d"

Write-Host "" 
Write-Host "===== DOWNLOADING AND VERIFYING THE LIFECYCLE CLIENT =====" -ForegroundColor Cyan
$WebClient = New-Object System.Net.WebClient
try {
    $PayloadBytes = $WebClient.DownloadData($LifecycleUrl)
}
finally {
    $WebClient.Dispose()
}
if ($PayloadBytes.Length -lt 1000) {
    throw "The LifecycleTelemetry.kt payload was unexpectedly small."
}
$PayloadBlob = Get-GitBlobSha1 $PayloadBytes
if ($PayloadBlob -ne $ExpectedLifecycleBlob) {
    throw "LifecycleTelemetry.kt Git blob mismatch. Expected $ExpectedLifecycleBlob but found $PayloadBlob."
}
$PayloadText = $Utf8Strict.GetString($PayloadBytes)
if ($PayloadText -notmatch 'LIFECYCLE_CLIENT_VERSION = "1\.0\.0"') {
    throw "The lifecycle payload marker is missing."
}
[System.IO.File]::WriteAllBytes($LifecyclePath, $PayloadBytes)
Write-Host "Lifecycle client payload verified." -ForegroundColor Green

Write-Host "" 
Write-Host "===== PATCHING ONLY THE STAGED PROJECT =====" -ForegroundColor Cyan

$GradlePath = Join-Path $Stage "app\build.gradle.kts"
$Text = Read-StrictUtf8 $GradlePath
$Text = Replace-Once $Text '        versionName = "2.4.1"' '        versionName = "2.4.0"' "Gradle public version"
Write-Utf8Lf $GradlePath $Text

$ModelsPath = Join-Path $JavaRoot "Models.kt"
$Text = Read-StrictUtf8 $ModelsPath
$Old = @'
    val driveStoryDetail: DriveStoryDetail = DriveStoryDetail.NORMAL,
    val dashboardLayouts: Map<DashboardPage, List<String>> = emptyMap()
'@
$New = @'
    val driveStoryDetail: DriveStoryDetail = DriveStoryDetail.NORMAL,
    val lifecycleReportingEnabled: Boolean = true,
    val featureUsageReportingEnabled: Boolean = false,
    val sessionSummarySharingEnabled: Boolean = false,
    val dashboardLayouts: Map<DashboardPage, List<String>> = emptyMap()
'@
$Text = Replace-Once $Text $Old $New "AppSettings lifecycle fields"
Write-Utf8Lf $ModelsPath $Text

$StoragePath = Join-Path $JavaRoot "Storage.kt"
$Text = Read-StrictUtf8 $StoragePath
$Old = '        dashboardLayouts = decodeDashboardLayouts(preferences.getString("dashboardLayouts", null))'
$New = @'
        lifecycleReportingEnabled = preferences.getBoolean("lifecycleReportingEnabled", true),
        featureUsageReportingEnabled = preferences.getBoolean("featureUsageReportingEnabled", false),
        sessionSummarySharingEnabled = preferences.getBoolean("sessionSummarySharingEnabled", false),
        dashboardLayouts = decodeDashboardLayouts(preferences.getString("dashboardLayouts", null))
'@
$Text = Replace-Once $Text $Old $New "SettingsStore load lifecycle fields"
$Old = @'
            .putString("driveStoryDetail", settings.driveStoryDetail.name)
            .putString("dashboardLayouts", encodeDashboardLayouts(settings.dashboardLayouts))
'@
$New = @'
            .putString("driveStoryDetail", settings.driveStoryDetail.name)
            .putBoolean("lifecycleReportingEnabled", settings.lifecycleReportingEnabled)
            .putBoolean("featureUsageReportingEnabled", settings.featureUsageReportingEnabled)
            .putBoolean("sessionSummarySharingEnabled", settings.sessionSummarySharingEnabled)
            .putString("dashboardLayouts", encodeDashboardLayouts(settings.dashboardLayouts))
'@
$Text = Replace-Once $Text $Old $New "SettingsStore save lifecycle fields"
Write-Utf8Lf $StoragePath $Text

$MainActivityPath = Join-Path $JavaRoot "MainActivity.kt"
$Text = Read-StrictUtf8 $MainActivityPath
$Old = @'
        viewModel.checkUpdateInstallPermission()
        viewModel.refreshNetworkAddress()
'@
$New = @'
        viewModel.checkUpdateInstallPermission()
        viewModel.refreshNetworkAddress()
        viewModel.onAppForegrounded()
'@
$Text = Replace-Once $Text $Old $New "MainActivity foreground lifecycle hook"
$Old = '    override fun onCreate(savedInstanceState: Bundle?) {'
$New = @'
    override fun onStop() {
        viewModel.onAppBackgrounded()
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
'@
$Text = Replace-Once $Text $Old $New "MainActivity background lifecycle hook"
Write-Utf8Lf $MainActivityPath $Text

$ViewModelPath = Join-Path $JavaRoot "DriveLabViewModel.kt"
$Text = Read-StrictUtf8 $ViewModelPath
$Old = @'
    private val licenseManager = LicenseManager(application)
    private val raceLinkManager =
'@
$New = @'
    private val licenseManager = LicenseManager(application)
    private val lifecycleTelemetry = LifecycleTelemetryManager(application)
    private val raceLinkManager =
'@
$Text = Replace-Once $Text $Old $New "ViewModel lifecycle manager"

$Old = @'
    val licenseState: StateFlow<LicenseState> = licenseManager.state
    val updateState: StateFlow<UpdateState> = appUpdateManager.state
'@
$New = @'
    val licenseState: StateFlow<LicenseState> = licenseManager.state
    val lifecycleTelemetryState: StateFlow<LifecycleTelemetryState> = lifecycleTelemetry.state
    val updateState: StateFlow<UpdateState> = appUpdateManager.state
'@
$Text = Replace-Once $Text $Old $New "ViewModel lifecycle state"

$Old = @'
    private var lastLiveTraceAtMs = 0L

    val driveIntelligenceState: StateFlow<DriveIntelligenceState> = driveIntelligenceEngine.state
'@
$New = @'
    private var lastLiveTraceAtMs = 0L
    private var lifecycleConnectionAttemptAtMs = 0L
    private var lifecycleConnectedAtMs = 0L
    private var lifecycleReconnectCount = 0

    val driveIntelligenceState: StateFlow<DriveIntelligenceState> = driveIntelligenceEngine.state
'@
$Text = Replace-Once $Text $Old $New "ViewModel lifecycle connection runtime"

$Old = @'
                _completedDriveSession.value =
                    CompletedDriveSession(
                        session = session,
                        previousSession =
                            previousSession,
                        xpEarned =
                            xpEarned,
                        automatic =
                            wasAutomatic,
                        intelligence =
                            intelligenceRecord
                    )
'@
$New = @'
                _completedDriveSession.value =
                    CompletedDriveSession(
                        session = session,
                        previousSession =
                            previousSession,
                        xpEarned =
                            xpEarned,
                        automatic =
                            wasAutomatic,
                        intelligence =
                            intelligenceRecord
                    )

                lifecycleTelemetry.recordFeatureCompleted(
                    "sessions",
                    "completed"
                )
                lifecycleTelemetry.recordSessionSummary(
                    session,
                    wasAutomatic
                )
                lifecycleTelemetry.flush()
'@
$Text = Replace-Once $Text $Old $New "Completed session lifecycle event"

$Old = @'
            licenseManager.initialize()
            licenseManager.reportDeviceStatus(force = true)
'@
$New = @'
            licenseManager.initialize()
            lifecycleTelemetry.configure(
                enabled = _settings.value.lifecycleReportingEnabled,
                featureUsage = _settings.value.featureUsageReportingEnabled,
                sessionSummaries = _settings.value.sessionSummarySharingEnabled
            )
            lifecycleTelemetry.initialize(
                if (licenseManager.state.value.canUseFullApp) "full" else "free"
            )
            licenseManager.reportDeviceStatus(force = true)
'@
$Text = Replace-Once $Text $Old $New "Lifecycle startup initialization"

$Old = @'
                licenseManager
                    .reportDeviceStatus(
                        force = false
                    )

                if (
'@
$New = @'
                licenseManager
                    .reportDeviceStatus(
                        force = false
                    )
                lifecycleTelemetry.flush()

                if (
'@
$Text = Replace-Once $Text $Old $New "Periodic lifecycle flush"

$Old = @'
        }
        viewModelScope.launch {
            delay(1_500L)
            appUpdateManager.check(force = true)
        }
'@
$New = @'
        }
        viewModelScope.launch {
            licenseManager.state.collect { state ->
                lifecycleTelemetry.updateEdition(
                    if (state.canUseFullApp) "full" else "free"
                )
                lifecycleTelemetry.flush()
            }
        }
        viewModelScope.launch {
            delay(1_500L)
            appUpdateManager.check(force = true)
        }
'@
$Text = Replace-Once $Text $Old $New "License edition lifecycle collector"

$Old = @'
        viewModelScope.launch {
            var wasConnected = false
            repository.connection.collect { state ->
                val connected = state.outGaugeActive || state.motionActive || state.demoMode
                if (
                    wasConnected &&
                    !connected &&
                    progressReady &&
                    licenseManager
                        .state
                        .value
                        .canUseFullApp &&
                    _settings
                        .value
                        .automaticDriveTrackingEnabled
                ) {
                    liveProgressTracker
                        .finish(
                            analyzer.state.value
                        )
                        ?.let(
                            ::applyLiveProgress
                        )
                }
                wasConnected = connected
            }
        }
'@
$New = @'
        viewModelScope.launch {
            var wasConnected = false
            var wasListening = false
            var lastError = ""
            repository.connection.collect { state ->
                val now = System.currentTimeMillis()
                val connected = state.outGaugeActive || state.motionActive || state.demoMode
                var lifecycleEventQueued = false

                if (!state.demoMode && !wasListening && state.listening) {
                    lifecycleConnectionAttemptAtMs = now
                    lifecycleTelemetry.recordConnectionAttempt("outgauge_motion")
                    lifecycleEventQueued = true
                }

                if (!state.demoMode && !wasConnected && connected) {
                    val mode = when {
                        state.outGaugeActive && state.motionActive -> "outgauge_motion"
                        state.outGaugeActive -> "outgauge"
                        else -> "motionsim"
                    }
                    lifecycleTelemetry.recordConnected(
                        mode,
                        (now - lifecycleConnectionAttemptAtMs).coerceAtLeast(0L)
                    )
                    lifecycleConnectedAtMs = now
                    if (wasListening) lifecycleReconnectCount++
                    lifecycleEventQueued = true
                }

                if (
                    !state.demoMode &&
                    !connected &&
                    state.error.isNotBlank() &&
                    state.error != lastError
                ) {
                    lifecycleTelemetry.recordConnectionFailed(state.error)
                    lifecycleEventQueued = true
                }

                if (!state.demoMode && wasConnected && !connected) {
                    lifecycleTelemetry.recordDisconnected(
                        reason = state.error.ifBlank { "packet_timeout" },
                        durationSeconds =
                            (now - lifecycleConnectedAtMs)
                                .coerceAtLeast(0L) / 1000.0,
                        reconnectCount = lifecycleReconnectCount
                    )
                    lifecycleEventQueued = true
                }

                if (
                    wasConnected &&
                    !connected &&
                    progressReady &&
                    licenseManager
                        .state
                        .value
                        .canUseFullApp &&
                    _settings
                        .value
                        .automaticDriveTrackingEnabled
                ) {
                    liveProgressTracker
                        .finish(
                            analyzer.state.value
                        )
                        ?.let(
                            ::applyLiveProgress
                        )
                }

                if (lifecycleEventQueued) {
                    lifecycleTelemetry.flush()
                }
                lastError = state.error
                wasListening = state.listening
                wasConnected = connected
            }
        }
'@
$Text = Replace-Once $Text $Old $New "BeamNG connection lifecycle collector"

$Old = @'
            if (
                licenseManager.activate(key)
            ) {
                licenseManager
'@
$New = @'
            if (
                licenseManager.activate(key)
            ) {
                lifecycleTelemetry.recordFeatureCompleted(
                    "license_activation",
                    "full"
                )
                lifecycleTelemetry.updateEdition("full")
                lifecycleTelemetry.flush()
                licenseManager
'@
$Text = Replace-Once $Text $Old $New "Full conversion lifecycle event"

$Old = @'
            if (
                licenseManager.deactivate()
            ) {
                resetAutomaticTrackingRuntime()

                licenseManager
'@
$New = @'
            if (
                licenseManager.deactivate()
            ) {
                resetAutomaticTrackingRuntime()
                lifecycleTelemetry.updateEdition("free")
                lifecycleTelemetry.flush()

                licenseManager
'@
$Text = Replace-Once $Text $Old $New "License deactivation lifecycle event"

$Old = '    fun setDemoMode(enabled: Boolean) {'
$New = @'
    fun setLifecycleReportingEnabled(enabled: Boolean) {
        val updated = _settings.value.copy(
            lifecycleReportingEnabled = enabled,
            featureUsageReportingEnabled =
                if (enabled) _settings.value.featureUsageReportingEnabled else false,
            sessionSummarySharingEnabled =
                if (enabled) _settings.value.sessionSummarySharingEnabled else false
        )
        updateSettings(updated, restartNetwork = false)
        lifecycleTelemetry.configure(
            enabled = updated.lifecycleReportingEnabled,
            featureUsage = updated.featureUsageReportingEnabled,
            sessionSummaries = updated.sessionSummarySharingEnabled
        )
        if (enabled) {
            viewModelScope.launch {
                lifecycleTelemetry.updateEdition(
                    if (licenseManager.state.value.canUseFullApp) "full" else "free"
                )
                lifecycleTelemetry.flush()
            }
        }
    }

    fun setFeatureUsageReportingEnabled(enabled: Boolean) {
        val allowed = enabled && _settings.value.lifecycleReportingEnabled
        val updated = _settings.value.copy(featureUsageReportingEnabled = allowed)
        updateSettings(updated, restartNetwork = false)
        lifecycleTelemetry.configure(
            enabled = updated.lifecycleReportingEnabled,
            featureUsage = updated.featureUsageReportingEnabled,
            sessionSummaries = updated.sessionSummarySharingEnabled
        )
    }

    fun setSessionSummarySharingEnabled(enabled: Boolean) {
        val allowed = enabled && _settings.value.lifecycleReportingEnabled
        val updated = _settings.value.copy(sessionSummarySharingEnabled = allowed)
        updateSettings(updated, restartNetwork = false)
        lifecycleTelemetry.configure(
            enabled = updated.lifecycleReportingEnabled,
            featureUsage = updated.featureUsageReportingEnabled,
            sessionSummaries = updated.sessionSummarySharingEnabled
        )
    }

    fun recordFeatureOpened(feature: String) {
        lifecycleTelemetry.recordFeatureOpened(feature)
        viewModelScope.launch { lifecycleTelemetry.flush() }
    }

    fun sendLifecycleDiagnosticReport() {
        viewModelScope.launch {
            lifecycleTelemetry.sendDiagnosticReport(repository.connection.value)
        }
    }

    fun onAppForegrounded() {
        lifecycleTelemetry.onForegrounded()
        viewModelScope.launch { lifecycleTelemetry.flush() }
    }

    fun onAppBackgrounded() {
        lifecycleTelemetry.onBackgrounded()
        viewModelScope.launch { lifecycleTelemetry.flush() }
    }

    fun setDemoMode(enabled: Boolean) {
'@
$Text = Replace-Once $Text $Old $New "Lifecycle settings and actions"

$Old = @'
    override fun onCleared() {
        repository.close()
        super.onCleared()
    }
'@
$New = @'
    override fun onCleared() {
        lifecycleTelemetry.markCleanShutdown()
        repository.close()
        super.onCleared()
    }
'@
$Text = Replace-Once $Text $Old $New "Lifecycle clean shutdown marker"
Write-Utf8Lf $ViewModelPath $Text

$UiPath = Join-Path $JavaRoot "DriveLabUi.kt"
$Text = Read-StrictUtf8 $UiPath
$Old = @'
private fun startupTabLabel(
    tab: MainTab
): String = when (tab) {
    MainTab.LIVE -> "LIVE"
    MainTab.COCKPIT -> "COCKPIT"
    MainTab.LABS -> "RACE"
    MainTab.RACELINK -> "RACELINK"
    MainTab.ANALYZE -> "ANALYZE"
    MainTab.SETUP -> "SETUP"
}
'@
$New = @'
private fun startupTabLabel(
    tab: MainTab
): String = when (tab) {
    MainTab.LIVE -> "LIVE"
    MainTab.COCKPIT -> "COCKPIT"
    MainTab.LABS -> "RACE"
    MainTab.RACELINK -> "RACELINK"
    MainTab.ANALYZE -> "ANALYZE"
    MainTab.SETUP -> "SETUP"
}

private fun MainTab.lifecycleFeatureName(): String = when (this) {
    MainTab.LIVE -> "live"
    MainTab.COCKPIT -> "cockpit"
    MainTab.LABS -> "tracklab"
    MainTab.RACELINK -> "racelink"
    MainTab.ANALYZE -> "progress"
    MainTab.SETUP -> "setup"
}

private fun LabTab.lifecycleFeatureName(): String = when (this) {
    LabTab.TRACK -> "tracklab"
    LabTab.DRAG -> "drag_lab"
    LabTab.BRAKE -> "brake_lab"
    LabTab.DRIFT -> "drift_lab"
    LabTab.OFFROAD -> "offroad_lab"
}

private fun AnalyzeTab.lifecycleFeatureName(): String = when (this) {
    AnalyzeTab.PROGRESS -> "progress"
    AnalyzeTab.ACHIEVEMENTS -> "achievements"
    AnalyzeTab.TEMPS -> "temperatures"
    AnalyzeTab.DAMAGE -> "damage"
    AnalyzeTab.COACH -> "coach"
    AnalyzeTab.DYNAMICS -> "dynamics"
    AnalyzeTab.RECORDS -> "records"
    AnalyzeTab.PROTOCOL -> "protocol"
    AnalyzeTab.SESSIONS -> "sessions"
    AnalyzeTab.GRAPHS -> "graphs"
}
'@
$Text = Replace-Once $Text $Old $New "Lifecycle feature-name mappings"

$Old = @'
    var selectedTab by rememberSaveable { mutableStateOf(settings.startupTab) }
    Scaffold(
'@
$New = @'
    var selectedTab by rememberSaveable { mutableStateOf(settings.startupTab) }
    LaunchedEffect(selectedTab) {
        viewModel.recordFeatureOpened(selectedTab.lifecycleFeatureName())
    }
    Scaffold(
'@
$Text = Replace-Once $Text $Old $New "Main tab lifecycle event"

$Old = @'
    var selected by rememberSaveable { mutableStateOf(LabTab.TRACK) }
    val labLicenseState by
'@
$New = @'
    var selected by rememberSaveable { mutableStateOf(LabTab.TRACK) }
    LaunchedEffect(selected) {
        viewModel.recordFeatureOpened(selected.lifecycleFeatureName())
    }
    val labLicenseState by
'@
$Text = Replace-Once $Text $Old $New "Lab tab lifecycle event"

$Old = @'
    var selected by rememberSaveable { mutableStateOf(AnalyzeTab.PROGRESS) }
    Column(modifier = Modifier.fillMaxSize().padding(contentPadding).statusBarsPadding()) {
'@
$New = @'
    var selected by rememberSaveable { mutableStateOf(AnalyzeTab.PROGRESS) }
    LaunchedEffect(selected) {
        viewModel.recordFeatureOpened(selected.lifecycleFeatureName())
    }
    Column(modifier = Modifier.fillMaxSize().padding(contentPadding).statusBarsPadding()) {
'@
$Text = Replace-Once $Text $Old $New "Analyze tab lifecycle event"

$Old = @'
    val context = LocalContext.current
    var outPort by remember(settings.outGaugePort) { mutableStateOf(settings.outGaugePort.toString()) }
'@
$New = @'
    val context = LocalContext.current
    val lifecycleState by viewModel.lifecycleTelemetryState.collectAsState()
    var outPort by remember(settings.outGaugePort) { mutableStateOf(settings.outGaugePort.toString()) }
'@
$Text = Replace-Once $Text $Old $New "Setup lifecycle state"

$Old = @'
        item {
            UpdateSettingsCard(
                state = updateState,
                onCheck = viewModel::checkForUpdate,
                onInstall = viewModel::downloadAndInstallUpdate
            )
        }
        item {
            Column(
'@
$New = @'
        item {
            UpdateSettingsCard(
                state = updateState,
                onCheck = viewModel::checkForUpdate,
                onInstall = viewModel::downloadAndInstallUpdate
            )
        }
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(DrivePanel, RoundedCornerShape(18.dp))
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp)
            ) {
                Text(
                    "DEVICE LIFECYCLE & PRIVACY",
                    color = DriveCyan,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "Signed, low-volume reports help identify app versions, active days, license conversions, crashes, and BeamNG connection failures. Raw UDP packets, routes, GPS, chat, license keys, screenshots, and phone files are never included.",
                    color = DriveMuted,
                    style = MaterialTheme.typography.bodySmall
                )
                SettingSwitch(
                    "Device and reliability reporting",
                    "Installation/version history, app launches, crash-free status, edition changes, and connection outcomes. Enabled by default and may be disabled here.",
                    settings.lifecycleReportingEnabled,
                    viewModel::setLifecycleReportingEnabled
                )
                SettingSwitch(
                    "Anonymous feature usage",
                    "Optional. Reports only which DriveLab screen was opened or completed; no values entered and no gameplay stream.",
                    settings.lifecycleReportingEnabled && settings.featureUsageReportingEnabled,
                    viewModel::setFeatureUsageReportingEnabled
                )
                SettingSwitch(
                    "Share driving session summaries",
                    "Optional and off by default. Sends only totals such as duration, distance, maximum speed, drift score, shifts, and crash count after a saved real session.",
                    settings.lifecycleReportingEnabled && settings.sessionSummarySharingEnabled,
                    viewModel::setSessionSummarySharingEnabled
                )
                Button(
                    onClick = viewModel::sendLifecycleDiagnosticReport,
                    enabled = !lifecycleState.busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (lifecycleState.busy) "SENDING…" else "SEND DIAGNOSTIC REPORT")
                }
                Text(
                    "Pending: ${lifecycleState.pendingEvents} • ${lifecycleState.lastMessage}",
                    color = if (lifecycleState.lastMessage.contains("complete", ignoreCase = true)) DriveGreen else DriveMuted,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        item {
            Column(
'@
$Text = Replace-Once $Text $Old $New "Setup lifecycle privacy controls"

$Old = @'
                Text("Effective July 20, 2026", color = DriveMuted)
                Text("DriveLab Telem is published by Kyle Williams / Aurora Media Group.")
                Text("The app does not display ads, use analytics, or track location. Solo gameplay telemetry remains local. RaceLink sends only the profile, room, course, chat, live progress, and results needed while the user voluntarily joins a RaceLink room.")
                Text("License activation sends the entered license key, a random installation ID, an Android Keystore public key, app version, and activation timestamps to the publisher-operated licensing server. The raw license key is checked transiently and is stored server-side only as a one-way keyed hash.")
                Text("The app receives UDP gameplay telemetry directly from a computer on the same local network. Outside RaceLink, gameplay telemetry, rolling charts, driver progress, saved sessions, and incidents remain in app-private storage unless the user explicitly shares a result. RaceLink uploads a temporary simplified course, lap and sector status, progress percentage, room chat, and final race results to connect participating Full Edition devices.")
                Text("The DriveLab server may process the connection IP address for rate limiting and security. License activation and refresh do not include gameplay data. RaceLink requests are separately signed, opt-in, and used only while RaceLink is active.")
                Text("Cloud and device-transfer backup are disabled. Uninstalling the app removes local app data; server activation records may be retained for licensing, fraud prevention, and customer support.")
                Text("Privacy contact: auroramediagroup1@gmail.com")
'@
$New = @'
                Text("Effective July 23, 2026", color = DriveMuted)
                Text("DriveLab Telem is published by Kyle Williams / Aurora Media Group. The app does not display ads or collect phone location.")
                Text("Device and reliability reporting sends a random installation ID, Android Keystore public key, app version, Free or Full association, app launch and active-day events, version and edition changes, clean or unclean app-session status, and summarized BeamNG connection outcomes. This reporting is low volume, cryptographically signed by the device, enabled by default, and may be disabled in Setup.")
                Text("Anonymous feature-usage reporting is optional and off by default. When enabled, it reports only the name of a DriveLab screen that was opened or completed. It does not send field values, button text, gameplay packets, routes, or chat.")
                Text("Driving session summaries are optional and off by default. When enabled, DriveLab may send completed-session totals such as duration, distance, maximum speed, peak G, drift score, shifts, and crash count. Raw UDP telemetry, live vehicle position, GPS location, routes, rolling chart samples, and saved session files are not uploaded.")
                Text("The Send Diagnostic Report button uploads a user-requested sanitized report containing app version, connection state, error count, recent connection errors, and an app-storage availability check. It does not include license keys, Wi-Fi passwords, screenshots, phone files, or raw gameplay telemetry.")
                Text("License activation sends the entered license key, a random installation ID, an Android Keystore public key, app version, and activation timestamps to the publisher-operated licensing server. The raw license key is checked transiently and is stored server-side only as a one-way keyed hash.")
                Text("RaceLink remains separately opt-in and sends only the profile, room, course, chat, live progress, and results required while the user voluntarily participates in a RaceLink room.")
                Text("The DriveLab server may process the connection IP address for rate limiting and security. Server lifecycle and activation records may be retained for product reliability, fraud prevention, customer support, and version adoption analysis.")
                Text("Cloud and device-transfer backup remain disabled. Uninstalling the app removes local app data. Privacy contact: auroramediagroup1@gmail.com")
'@
$Text = Replace-Once $Text $Old $New "Updated lifecycle privacy disclosure"
Write-Utf8Lf $UiPath $Text

Write-Host "Staged source patch completed." -ForegroundColor Green

Write-Host "" 
Write-Host "===== STATIC VALIDATION =====" -ForegroundColor Cyan
$RequiredMarkers = [ordered]@{
    $GradlePath = 'versionName = "2.4.0"'
    $LifecyclePath = 'LIFECYCLE_CLIENT_VERSION = "1.0.0"'
    $ModelsPath = 'val lifecycleReportingEnabled: Boolean = true'
    $StoragePath = 'preferences.getBoolean("sessionSummarySharingEnabled", false)'
    $MainActivityPath = 'viewModel.onAppBackgrounded()'
    $ViewModelPath = 'private val lifecycleTelemetry = LifecycleTelemetryManager(application)'
    $UiPath = 'DEVICE LIFECYCLE & PRIVACY'
}
foreach ($Entry in $RequiredMarkers.GetEnumerator()) {
    $Current = Read-StrictUtf8 $Entry.Key
    if (-not $Current.Contains($Entry.Value)) {
        throw "Static marker missing from $($Entry.Key): $($Entry.Value)"
    }
}
if ((Read-StrictUtf8 $GradlePath) -match 'versionName\s*=\s*"2\.4\.1"') {
    throw "The staged Gradle file still contains versionName 2.4.1."
}
Write-Host "Version, privacy, lifecycle, settings, UI, and integration markers passed." -ForegroundColor Green

Write-Host "" 
Write-Host "===== BUILDING AND TESTING THE ISOLATED COPY =====" -ForegroundColor Cyan
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $AndroidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
    if (Test-Path $AndroidStudioJbr) {
        $env:JAVA_HOME = $AndroidStudioJbr
    }
}
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME) -or -not (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    throw "JAVA_HOME is not configured and Android Studio JBR was not found."
}

Push-Location $Stage
try {
    & .\gradlew.bat --no-daemon clean testReleaseUnitTest lintRelease assembleRelease
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build or tests failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$BuiltApk = Join-Path $Stage "app\build\outputs\apk\release\app-release.apk"
if (-not (Test-Path $BuiltApk -PathType Leaf)) {
    throw "Gradle completed but the release APK was not found: $BuiltApk"
}

$ReleaseOutput = Join-Path $Stage "release-output"
New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
$StagedApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-build37-lifecycle-STAGE.apk"
Copy-Item -LiteralPath $BuiltApk -Destination $StagedApk -Force
$ApkHash = Get-Sha256 $StagedApk

$ApkSigner = Get-ChildItem -Path "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Filter apksigner.bat -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -ne $ApkSigner) {
    & $ApkSigner.FullName verify --verbose --print-certs $StagedApk
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed."
    }
}
else {
    Write-Warning "apksigner.bat was not found; Gradle succeeded but signature verification was not independently run."
}

Write-Host "" 
Write-Host "===== PROVING THE WORKING PROJECT WAS NOT MODIFIED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-Hash $Entry.Key $Entry.Value
}

$ReportLines = @(
    "DRIVELAB 2.4.0 BUILD 37 LIFECYCLE ANDROID STAGE"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Original project: $Root"
    "Staged project: $Stage"
    "Public version: 2.4.0"
    "Version code: 37"
    "Lifecycle client: 1.0.0"
    "APK: $StagedApk"
    "APK SHA-256: $ApkHash"
    ""
    "Passed:"
    "- exact captured source baseline"
    "- isolated full-project copy"
    "- strict UTF-8 source patch"
    "- versionName restored from abandoned 2.4.1 to production line 2.4.0"
    "- app launches and active-day lifecycle events"
    "- version and Free/Full edition history"
    "- BeamNG connection success/failure/disconnect events"
    "- clean/unclean app-session detection"
    "- optional feature usage reporting"
    "- optional session summaries"
    "- user-triggered diagnostic reports"
    "- updated in-app privacy disclosure and controls"
    "- Gradle unit tests, release lint, and release APK assembly"
    "- original working-project hashes unchanged"
    ""
    "Not performed:"
    "- APK installation"
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
Write-Host "Do not publish this APK yet. Install it only on the test phone after the" -ForegroundColor Yellow
Write-Host "build output is reviewed and the live server remains healthy." -ForegroundColor Yellow
