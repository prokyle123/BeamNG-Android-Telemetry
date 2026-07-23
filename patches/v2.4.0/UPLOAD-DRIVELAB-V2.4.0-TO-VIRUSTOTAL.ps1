$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$OutputDirectory = Join-Path $Project "release-output"

$Candidates = @(
    (Join-Path $OutputDirectory "DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Downloads\DriveLab-Telem-v2.4.0.apk"),
    (Join-Path $HOME "Desktop\DriveLab-Telem-v2.4.0.apk")
)

$ApkPath = $Candidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Read-Host "Full path to DriveLab-Telem-v2.4.0.apk"
}

if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK was not found: $ApkPath"
}

$ApkItem = Get-Item -LiteralPath $ApkPath
$Sha256 = (
    Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256
).Hash.ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $OutputDirectory |
    Out-Null

Write-Host ""
Write-Host "===== DRIVELAB 2.4.0 VIRUSTOTAL UPLOAD =====" -ForegroundColor Cyan
Write-Host "APK:    $ApkPath"
Write-Host "Size:   $([math]::Round($ApkItem.Length / 1MB, 2)) MB"
Write-Host "SHA256: $Sha256"
Write-Host ""
Write-Host "The API key stays in this PowerShell process and is not written to disk." -ForegroundColor Yellow

$SecureKey = Read-Host "VirusTotal API key" -AsSecureString
$KeyPointer = [IntPtr]::Zero
$ApiKey = $null
$Client = $null
$Stream = $null
$Multipart = $null
$FileContent = $null

function Get-ResponseText {
    param(
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]$Response,

        [Parameter(Mandatory)]
        [string]$Action
    )

    $Body = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if (-not $Response.IsSuccessStatusCode) {
        throw "$Action failed with HTTP $([int]$Response.StatusCode) $($Response.ReasonPhrase).`n$Body"
    }

    return $Body
}

try {
    $KeyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($KeyPointer)

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "The VirusTotal API key was empty."
    }

    $Handler = [System.Net.Http.HttpClientHandler]::new()
    $Handler.AllowAutoRedirect = $true

    $Client = [System.Net.Http.HttpClient]::new($Handler)
    $Client.Timeout = [TimeSpan]::FromMinutes(10)
    $Client.DefaultRequestHeaders.Add("x-apikey", $ApiKey)
    $Client.DefaultRequestHeaders.UserAgent.ParseAdd("DriveLab-Telem-Release-Tool/2.4.0")

    $UploadUrl = "https://www.virustotal.com/api/v3/files"

    if ($ApkItem.Length -gt 32MB) {
        Write-Host "Requesting a large-file upload URL..." -ForegroundColor Cyan

        $UploadUrlResponse = $Client.GetAsync(
            "https://www.virustotal.com/api/v3/files/upload_url"
        ).GetAwaiter().GetResult()

        $UploadUrlJson = Get-ResponseText \
            -Response $UploadUrlResponse \
            -Action "Requesting the VirusTotal upload URL" |
            ConvertFrom-Json

        $UploadUrl = [string]$UploadUrlJson.data

        if ([string]::IsNullOrWhiteSpace($UploadUrl)) {
            throw "VirusTotal did not return a large-file upload URL."
        }
    }

    Write-Host "Uploading the exact signed APK..." -ForegroundColor Cyan

    $Multipart = [System.Net.Http.MultipartFormDataContent]::new()
    $Stream = [System.IO.File]::OpenRead($ApkPath)
    $FileContent = [System.Net.Http.StreamContent]::new($Stream)
    $FileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new(
        "application/vnd.android.package-archive"
    )

    $Multipart.Add(
        $FileContent,
        "file",
        [System.IO.Path]::GetFileName($ApkPath)
    )

    $UploadResponse = $Client.PostAsync(
        $UploadUrl,
        $Multipart
    ).GetAwaiter().GetResult()

    $UploadJsonText = Get-ResponseText \
        -Response $UploadResponse \
        -Action "VirusTotal file upload"

    $UploadJson = $UploadJsonText | ConvertFrom-Json
    $AnalysisId = [string]$UploadJson.data.id

    if ([string]::IsNullOrWhiteSpace($AnalysisId)) {
        throw "VirusTotal accepted the upload but did not return an analysis ID."
    }

    Write-Host "Upload accepted." -ForegroundColor Green
    Write-Host "Analysis ID: $AnalysisId"
    Write-Host "Waiting for antivirus engines to finish..." -ForegroundColor Cyan

    $EncodedAnalysisId = [Uri]::EscapeDataString($AnalysisId)
    $Deadline = (Get-Date).AddMinutes(40)
    $Status = "queued"
    $AnalysisJsonText = $null

    while ((Get-Date) -lt $Deadline) {
        Start-Sleep -Seconds 20

        $AnalysisResponse = $Client.GetAsync(
            "https://www.virustotal.com/api/v3/analyses/$EncodedAnalysisId"
        ).GetAwaiter().GetResult()

        $AnalysisJsonText = Get-ResponseText \
            -Response $AnalysisResponse \
            -Action "Reading VirusTotal analysis status"

        $AnalysisJson = $AnalysisJsonText | ConvertFrom-Json
        $Status = [string]$AnalysisJson.data.attributes.status

        Write-Host "Analysis status: $Status"

        if ($Status -eq "completed") {
            break
        }
    }

    if ($Status -ne "completed") {
        throw "VirusTotal analysis did not complete within 40 minutes. The upload succeeded, so the report may still finish later."
    }

    Write-Host "Retrieving the final file report..." -ForegroundColor Cyan

    $ReportResponse = $Client.GetAsync(
        "https://www.virustotal.com/api/v3/files/$Sha256"
    ).GetAwaiter().GetResult()

    $ReportJsonText = Get-ResponseText \
        -Response $ReportResponse \
        -Action "Retrieving the VirusTotal file report"

    $ReportJson = $ReportJsonText | ConvertFrom-Json
    $ReportedId = [string]$ReportJson.data.id

    if ($ReportedId.ToLowerInvariant() -ne $Sha256) {
        throw "VirusTotal returned a different SHA-256 than the APK uploaded. Expected $Sha256 but received $ReportedId."
    }

    $Stats = $ReportJson.data.attributes.last_analysis_stats
    $StatProperties = @($Stats.PSObject.Properties)
    $TotalEngines = (
        $StatProperties |
        ForEach-Object { [int]$_.Value } |
        Measure-Object -Sum
    ).Sum

    $Malicious = [int]$Stats.malicious
    $Suspicious = [int]$Stats.suspicious
    $Undetected = [int]$Stats.undetected
    $Harmless = [int]$Stats.harmless
    $Timeouts = [int]$Stats.timeout
    $Failures = [int]$Stats.failure

    $ReportUrl = "https://www.virustotal.com/gui/file/$Sha256"
    $ScannedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $JsonReceipt = Join-Path $OutputDirectory "DriveLab-Telem-v2.4.0-VirusTotal.json"
    $TextReceipt = Join-Path $OutputDirectory "DriveLab-Telem-v2.4.0-VirusTotal.txt"
    $UrlReceipt = Join-Path $OutputDirectory "DriveLab-Telem-v2.4.0-VirusTotal-URL.txt"

    [System.IO.File]::WriteAllText(
        $JsonReceipt,
        $ReportJsonText,
        [System.Text.UTF8Encoding]::new($false)
    )

    $Receipt = @"
DriveLab Telem 2.4.0 VirusTotal verification

Version: 2.4.0
Build: 36
APK: $([System.IO.Path]::GetFileName($ApkPath))
SHA-256: $Sha256
Scanned UTC: $ScannedUtc
VirusTotal report: $ReportUrl

Analysis statistics
Malicious: $Malicious
Suspicious: $Suspicious
Undetected: $Undetected
Harmless: $Harmless
Timeouts: $Timeouts
Failures: $Failures
Total engine results: $TotalEngines
"@

    [System.IO.File]::WriteAllText(
        $TextReceipt,
        $Receipt.Trim() + "`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    [System.IO.File]::WriteAllText(
        $UrlReceipt,
        $ReportUrl + "`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
        Set-Clipboard -Value $ReportUrl
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "VIRUSTOTAL SCAN COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "SHA-256:   $Sha256"
    Write-Host "Detections: $Malicious malicious, $Suspicious suspicious"
    Write-Host "Engines:    $TotalEngines results"
    Write-Host "Report:     $ReportUrl"
    Write-Host ""
    Write-Host "Saved receipts:" -ForegroundColor Cyan
    Write-Host $JsonReceipt
    Write-Host $TextReceipt
    Write-Host $UrlReceipt
    Write-Host ""
    Write-Host "The public report URL was copied to the clipboard." -ForegroundColor Yellow
}
finally {
    if ($Multipart) {
        $Multipart.Dispose()
    }
    elseif ($FileContent) {
        $FileContent.Dispose()
    }
    elseif ($Stream) {
        $Stream.Dispose()
    }

    if ($Client) {
        $Client.Dispose()
    }

    if ($KeyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($KeyPointer)
    }

    $ApiKey = $null
    $SecureKey = $null
}
