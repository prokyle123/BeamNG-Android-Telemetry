$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Remote = "kali@ak47"
$RemoteInstaller = "/home/kali/APPLY-DRIVELAB-OWNER-CONSOLE-V3.sh"
$InstallerUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0/APPLY-DRIVELAB-OWNER-CONSOLE-V3.sh"

$Ssh = Get-Command ssh.exe -ErrorAction Stop

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DRIVELAB OWNER CONSOLE V3 DEPLOYMENT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Target: $Remote" -ForegroundColor White
Write-Host ""
Write-Host "The Pi installer will first validate the exact live source," -ForegroundColor Yellow
Write-Host "create a verified backup, compile and test staged code, and" -ForegroundColor Yellow
Write-Host "automatically restore the previous console if validation fails." -ForegroundColor Yellow
Write-Host ""
Write-Host "Do not close this window while the installer is running." -ForegroundColor Yellow
Write-Host "You may be asked for your SSH key passphrase and sudo password." -ForegroundColor Yellow
Write-Host ""

$RemoteCommand = @"
set -Eeuo pipefail
curl --fail --silent --show-error --location --retry 3 '$InstallerUrl' --output '$RemoteInstaller'
chmod 0700 '$RemoteInstaller'
sudo bash '$RemoteInstaller'
"@

& $Ssh.Source `
    $Remote `
    "bash -lc '$($RemoteCommand.Replace("'", "'\"'\"'"))'"

$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
    throw "The DriveLab Owner Console v3 installer failed with exit code ${ExitCode}. Review the output above."
}

Write-Host ""
Write-Host "DriveLab Owner Console v3 deployment completed successfully." -ForegroundColor Green
Write-Host "Open the same Owner Console address you already use, then select Control Center." -ForegroundColor Green
