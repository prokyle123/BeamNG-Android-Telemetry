@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo DriveLab 2.3.0 - Achievement Vault Rebuilt
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
  echo The patch did not complete. The source was restored automatically when modification had started.
) else (
  echo Build verification completed. Nothing has been published.
)
echo.
pause
exit /b %EXITCODE%
