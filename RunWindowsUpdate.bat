@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] Requesting administrator access... >> "%LOG_FILE%" 2>&1
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Define URLs and local paths
set BASE_URL=https://raw.githubusercontent.com/Gordeth/IT/main
set SCRIPT_DIR=%TEMP%\ITScripts
set LOG_DIR=%SCRIPT_DIR%\Log
set LOG_FILE=%LOG_DIR%\update_log.txt

:: Create the local script and log directories
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >> "%LOG_FILE%" 2>&1

:: Log the start of the script
echo [%date% %time%] Script started. >> "%LOG_FILE%" 2>&1

:: Set Execution Policy to Bypass for this session
echo [%date% %time%] Setting Execution Policy to Bypass... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Bypass -Scope Process -Force" >> "%LOG_FILE%" 2>&1

:: Check if NuGet provider is installed, install silently if needed
echo [%date% %time%] Checking for NuGet provider... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser" >> "%LOG_FILE%" 2>&1

:: --- Download or update WindowsUpdateScript.ps1 ---
echo [%date% %time%] Checking for WindowsUpdateScript.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\WindowsUpdateScript.ps1" (
    echo [%date% %time%] Existing WindowsUpdateScript.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\WindowsUpdateScript.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading WindowsUpdateScript.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/WindowsUpdateScript.ps1 -OutFile %SCRIPT_DIR%\WindowsUpdateScript.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_download

:: --- Download or update winget-upgrade.ps1 ---
echo [%date% %time%] Checking for winget-upgrade.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\winget-upgrade.ps1" (
    echo [%date% %time%] Existing winget-upgrade.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\winget-upgrade.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading winget-upgrade.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/winget-upgrade.ps1 -OutFile %SCRIPT_DIR%\winget-upgrade.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_download

:: --- Download or update office-update.ps1 ---
echo [%date% %time%] Checking for office-update.ps1 in %SCRIPT_DIR%... >> "%LOG_FILE%" 2>&1
if exist "%SCRIPT_DIR%\office-update.ps1" (
    echo [%date% %time%] Existing office-update.ps1 found. Deleting for fresh download... >> "%LOG_FILE%" 2>&1
    del /q "%SCRIPT_DIR%\office-update.ps1" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading office-update.ps1 from GitHub... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri %BASE_URL%/office-update.ps1 -OutFile %SCRIPT_DIR%\office-update.ps1 -UseBasicParsing" >> "%LOG_FILE%" 2>&1
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

:: Delete the script directory
echo [%date% %time%] Cleaning up temporary files... >> "%LOG_FILE%" 2>&1
rmdir /s /q "%SCRIPT_DIR%" >> "%LOG_FILE%" 2>&1

:: Delete this batch file. Uncomment del "%~f0" if not debugging
echo [%date% %time%] Deleting this batch file... >> "%LOG_FILE%" 2>&1
::del "%~f0"
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
echo [%date% %time%] Keeping downloaded files for debugging. >> "%LOG_FILE%" 2>&1
pause
exit /b 1
