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

:: Set Execution Policy to Bypass for this session
echo Setting Execution Policy to Bypass...
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Bypass -Scope Process -Force"

:: Check if NuGet provider is installed, install silently if needed
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser"

:: Download or update WindowsUpdateScript.ps1
echo Downloading WindowsUpdateScript.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/WindowsUpdateScript.ps1 -OutFile %SCRIPT_DIR%\WindowsUpdateScript.ps1 -UseBasicParsing"

:: Download or update winget-upgrade.ps1
echo Downloading winget-upgrade.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/winget-upgrade.ps1 -OutFile %SCRIPT_DIR%\winget-upgrade.ps1 -UseBasicParsing"

:: Download or update office-update.ps1
echo Downloading office-update.ps1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/office-update.ps1 -OutFile %SCRIPT_DIR%\office-update.ps1 -UseBasicParsing"

:: Run WindowsUpdateScript.ps1
echo Running WindowsUpdateScript.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\WindowsUpdateScript.ps1"
if %errorlevel% neq 0 goto error

:: Run winget-upgrade.ps1
echo Running winget-upgrade.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\winget-upgrade.ps1"
if %errorlevel% neq 0 goto error

:: Run office-update.ps1
echo Running office-update.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\office-update.ps1"
if %errorlevel% neq 0 goto error

:success
:: Reset Execution Policy to default Restricted
echo Resetting Execution Policy to Restricted...
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force"

:: Clean up temporary files
echo Cleaning up temporary files...
rmdir /s /q "%SCRIPT_DIR%"

:: Delete this batch file
echo Deleting this batch file...
# del "%~f0"
exit /b 0

:error
echo One or more scripts encountered an error.
echo Keeping downloaded files for debugging.
pause
exit /b 1
