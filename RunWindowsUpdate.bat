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

:: Download or update WindowsUpdateScript.ps1
echo Checking for WindowsUpdateScript.ps1 in %SCRIPT_DIR%...
if exist "%SCRIPT_DIR%\WindowsUpdateScript.ps1" (
    echo Updating WindowsUpdateScript.ps1 from GitHub...
) else (
    echo Downloading WindowsUpdateScript.ps1 from GitHub...
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/WindowsUpdateScript.ps1 -OutFile %SCRIPT_DIR%\WindowsUpdateScript.ps1 -UseBasicParsing"

:: Download or update winget-upgrade.ps1
echo Checking for winget-upgrade.ps1 in %SCRIPT_DIR%...
if exist "%SCRIPT_DIR%\winget-upgrade.ps1" (
    echo Updating winget-upgrade.ps1 from GitHub...
) else (
    echo Downloading winget-upgrade.ps1 from GitHub...
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/winget-upgrade.ps1 -OutFile %SCRIPT_DIR%\winget-upgrade.ps1 -UseBasicParsing"

:: Download or update office-update.ps1
echo Checking for office-update.ps1 in %SCRIPT_DIR%...
if exist "%SCRIPT_DIR%\office-update.ps1" (
    echo Updating office-update.ps1 from GitHub...
) else (
    echo Downloading office-update.ps1 from GitHub...
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/office-update.ps1 -OutFile %SCRIPT_DIR%\office-update.ps1 -UseBasicParsing"

:: Run WindowsUpdateScript.ps1
echo Running WindowsUpdateScript.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\WindowsUpdateScript.ps1"
if %errorlevel% neq 0 goto cleanup

:: Run winget-upgrade.ps1
echo Running winget-upgrade.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\winget-upgrade.ps1"
if %errorlevel% neq 0 goto cleanup

:: Run office-update.ps1
echo Running office-update.ps1...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\office-update.ps1"
if %errorlevel% neq 0 goto cleanup

:cleanup
:: Delete the script directory
echo Cleaning up temporary files...
rmdir /s /q "%SCRIPT_DIR%"

:: Delete this batch file. Uncomment del "%~f0" if not debugging
echo Deleting this batch file...
::del "%~f0"
