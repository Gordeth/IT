@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator access...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Define URLs and local paths
set BASE_URL=https://raw.githubusercontent.com/Gordeth/IT/main
set SCRIPT_DIR=%TEMP%\ITScripts

:: Create the local script directory
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%"

:: Download WindowsUpdateScript.ps1
echo Downloading WindowsUpdateScript.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/WindowsUpdateScript.ps1 -OutFile %SCRIPT_DIR%\WindowsUpdateScript.ps1"

:: Download winget-upgrade.ps1
echo Downloading winget-upgrade.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/winget-upgrade.ps1 -OutFile %SCRIPT_DIR%\winget-upgrade.ps1"

:: Download office-update.ps1
echo Downloading office-update.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/office-update.ps1 -OutFile %SCRIPT_DIR%\office-update.ps1"

:: Run WindowsUpdateScript.ps1
echo Running WindowsUpdateScript.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\WindowsUpdateScript.ps1"

:: Run winget-upgrade.ps1
echo Running winget-upgrade.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\winget-upgrade.ps1"

:: Run office-update.ps1
echo Running office-update.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\office-update.ps1"

pause
