@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-DRIVELAB-CODRIVER-30S.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
  echo DriveLab patch or build failed. Nothing was published.
) else (
  echo DriveLab 2.2.2 test build completed. Nothing was published yet.
)
echo.
pause
exit /b %EXIT_CODE%
