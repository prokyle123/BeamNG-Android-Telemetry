param(
    [string]$SshTarget = "kali@192.168.1.132"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PackageRoot = $PSScriptRoot
$RemotePatch = Join-Path $PackageRoot "remote_remove_exact_release_block.py"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$RemoteScript = "/tmp/drivelab-remove-exact-release-block-$Stamp.py"

$Ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$Scp = (Get-Command scp.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $RemotePatch -PathType Leaf)) {
    throw "The exact-removal payload is missing: $RemotePatch"
}

$SshOptions = @(
    "-o", "BatchMode=no",
    "-o", "PreferredAuthentications=publickey,keyboard-interactive,password",
    "-o", "NumberOfPasswordPrompts=3",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=accept-new"
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "REMOVE ONLY THE BOTTOM RELEASE-SECURITY BLOCK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Target: $SshTarget"
Write-Host ""
Write-Host "This removes only the exact DL-RELEASE-TRUST marked block." -ForegroundColor White
Write-Host "Everything before and after that block must remain byte-for-byte identical." -ForegroundColor White
Write-Host ""

$ScpArgs = @()
$ScpArgs += $SshOptions
$ScpArgs += "-q"
$ScpArgs += $RemotePatch
$ScpArgs += "${SshTarget}:$RemoteScript"

Write-Host "[1/2] Uploading the exact-removal script..." -ForegroundColor Cyan
& $Scp @ScpArgs
if ($LASTEXITCODE -ne 0) {
    throw "Could not upload the exact-removal script. No website files were changed."
}

Write-Host "[2/2] Backing up and removing only the marked block..." -ForegroundColor Cyan
$RemoteCommand = "sudo python3 '$RemoteScript'; code=`$?; rm -f '$RemoteScript'; exit `$code"
$SshArgs = @()
$SshArgs += $SshOptions
$SshArgs += "-tt"
$SshArgs += $SshTarget
$SshArgs += $RemoteCommand

& $Ssh @SshArgs
$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0) {
    throw "The exact website cleanup failed with exit code $ExitCode. The homepage was left unchanged or restored."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "BOTTOM RELEASE-SECURITY BLOCK REMOVED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Reload https://drivelabregistration.org/ with Ctrl+F5." -ForegroundColor Cyan
Write-Host "No other website content was changed." -ForegroundColor White
Write-Host ""
