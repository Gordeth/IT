@echo off
:: Define URLs and local paths first!
set BASE_URL=https://raw.githubusercontent.com/Gordeth/IT/main
set SCRIPT_DIR=%TEMP%\ITScripts
set LOG_DIR=%SCRIPT_DIR%\Log
set LOG_FILE=%LOG_DIR%\update_log.txt

:: Create the local script and log directories
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >> "%LOG_FILE%" 2>&1
:: Create the log file if it doesn't exist, and write a creation message.
if not exist "%LOG_FILE%" echo [%date% %time%] Log file created. > "%LOG_FILE%"

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] Requesting administrator access... >> "%LOG_FILE%" 2>&1
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Log start of script
echo [%date% %time%] Script started. >> "%LOG_FILE%" 2>&1

:: Set Execution Policy to Bypass
echo [%date% %time%] Setting Execution Policy to Bypass... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Bypass -Scope Process -Force" >> "%LOG_FILE%" 2>&1

:: Check for NuGet provider and install if missing (with CurrentUser scope)
echo [%date% %time%] Checking for NuGet provider... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser; }" >> "%LOG_FILE%" 2>&1

:: --- Download or update WU.ps1 ---
echo [%date% %time%] Checking for WU.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\WU.ps1" (
    echo [%date% %time%] Existing WU.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\WU.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading WU.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/WU.ps1 -OutFile %SCRIPT_DIR%\WU.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_download

:: --- Download or update WGET.ps1 ---
echo [%date% %time%] Checking for WGET.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\WGET.ps1" (
    echo [%date% %time%] Existing WGET.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\WGET.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading WGET.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/WGET.ps1 -OutFile %SCRIPT_DIR%\WGET.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_download

:: --- Download or update MSO_UPDATE.ps1 ---
echo [%date% %time%] Checking for MSO_UPDATE.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\MSO_UPDATE.ps1" (
    echo [%date% %time%] Existing MSO_UPDATE.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\MSO_UPDATE.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading MSO_UPDATE from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/MSO_UPDATE.ps1 -OutFile %SCRIPT_DIR%\MSO_UPDATE.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_download

:: Run WindowsUpdateScript.ps1 and log output
echo [%date% %time%] Running WindowsUpdateScript.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\WindowsUpdateScript.ps1" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_script_execution

:: Run winget-upgrade.ps1 and log output
echo [%date% %time%] Running winget-upgrade.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\winget-upgrade.ps1" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_script_execution

:: Run office-update.ps1 and log output
echo [%date% %time%] Running office-update.ps1... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\office-update.ps1" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_script_execution

:cleanup
:: Reset the Execution Policy back to default
echo [%date% %time%] Resetting Execution Policy to default... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1

:: Delete the downloaded PowerShell scripts.
echo [%date% %time%] Deleting downloaded scripts... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\WindowsUpdateScript.ps1" del /q "%SCRIPT_DIR%\WindowsUpdateScript.ps1" >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\winget-upgrade.ps1" del /q "%SCRIPT_DIR%\winget-upgrade.ps1" >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\office-update.ps1" del /q "%SCRIPT_DIR%\office-update.ps1" >> "%LOG_FILE%" 2>&1

:: The following line for deleting the entire script directory remains commented out to keep the log folder.
echo [%date% %time%] Temporary script folder (excluding log) will remain, or delete manually if needed. >> "%LOG_FILE%" 2>&1
:: rmdir /s /q "%SCRIPT_DIR%" >> "%LOG_FILE%" 2>&1

:: Delete this batch file.
echo [%date% %time%] Deleting this batch file... >> "%LOG_FILE%" 2>&1
del "%~f0"
exit /b 0

:error_download
echo [%date% %time%] A file download encountered an error. >> "%LOG_FILE%" 2>&1
goto error_common

:error_script_execution
echo [%date% %time%] One or more scripts encountered an error during execution. >> "%LOG_FILE%" 2>&1
goto error_common

:error_common
echo [%date% %time%] Resetting Execution Policy to default... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1
echo [%date% %time%] Keeping downloaded files for debugging. (Scripts and batch file will not be deleted on error) >> "%LOG_FILE%" 2>&1
pause
exit /b 1
