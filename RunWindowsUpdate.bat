@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator access... >> "%LOG_FILE%" 2>&1
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Define URLs and local paths
set BASE_URL=https://raw.githubusercontent.com/Gordeth/IT/main
set SCRIPT_DIR=%TEMP%\ITScripts
set LOG_DIR=%SCRIPT_DIR%\Log
set LOG_FILE=%LOG_DIR%\update_log.txt

:: Create the local script and log directories
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Log the start of the script
echo [%date% %time%] Script started. >> "%LOG_FILE%" 2>&1

:: Set Execution Policy to Bypass for this session
echo Setting Execution Policy to Bypass... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Bypass -Scope Process -Force" >> "%LOG_FILE%" 2>&1

:: Check if NuGet provider is installed, install silently if needed
echo Checking for NuGet provider... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser" >> "%LOG_FILE%" 2>&1

:: Download or update WindowsUpdateScript.ps1
echo Checking for WindowsUpdateScript.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\WindowsUpdateScript.ps1" (
    echo Updating WindowsUpdateScript.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
) else (
    echo Downloading WindowsUpdateScript.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/WindowsUpdateScript.ps1 -OutFile %SCRIPT_DIR%\WindowsUpdateScript.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1

:: Download or update winget-upgrade.ps1
echo Checking for winget-upgrade.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\winget-upgrade.ps1" (
    echo Updating winget-upgrade.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
) else (
    echo Downloading winget-upgrade.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/winget-upgrade.ps1 -OutFile %SCRIPT_DIR%\winget-upgrade.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1

:: Download or update office-update.ps1
echo Checking for office-update.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\office-update.ps1" (
    echo Updating office-update.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
) else (
    echo Downloading office-update.ps1 from GitHub... >> "%LOG_FILE%" 2>&1 [cite: 3]
)
powershell -Command "Invoke-WebRequest -Uri %BASE_URL%/office-update.ps1 -OutFile %SCRIPT_DIR%\office-update.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1

:: Run WindowsUpdateScript.ps1 and log output
echo Running WindowsUpdateScript.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\WindowsUpdateScript.ps1" >> "%LOG_FILE%" 2>&1 [cite: 1]
if %errorlevel% neq 0 goto error

:: Run winget-upgrade.ps1 and log output
echo Running winget-upgrade.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\winget-upgrade.ps1" >> "%LOG_FILE%" 2>&1 [cite: 1]
if %errorlevel% neq 0 goto error

:: Run office-update.ps1 and log output
echo Running office-update.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\office-update.ps1" >> "%LOG_FILE%" 2>&1 [cite: 1]
if %errorlevel% neq 0 goto error

:cleanup
:: Reset the Execution Policy back to default
echo Resetting Execution Policy to default... >> "%LOG_FILE%" 2>&1 [cite: 4]
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1 [cite: 4]

:: Delete the script directory
echo Cleaning up temporary files... >> "%LOG_FILE%" 2>&1 [cite: 4]
rmdir /s /q "%SCRIPT_DIR%" >> "%LOG_FILE%" 2>&1

:: Delete this batch file. Uncomment del "%~f0" if not debugging
echo Deleting this batch file... >> "%LOG_FILE%" 2>&1
::del "%~f0"
exit /b 0

:error
echo One or more scripts encountered an error. >> "%LOG_FILE%" 2>&1 [cite: 5]
echo Resetting Execution Policy to default... >> "%LOG_FILE%" 2>&1 [cite: 5]
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1 [cite: 5]
echo Keeping downloaded files for debugging. >> "%LOG_FILE%" 2>&1 [cite: 6]
pause
exit /b 1
