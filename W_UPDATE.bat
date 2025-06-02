@echo off
:: =================== CONFIGURATION ===================
set "BASE_URL=https://raw.githubusercontent.com/Gordeth/IT/main"
set "SCRIPT_DIR=%TEMP%\ITScripts"
set "LOG_DIR=%SCRIPT_DIR%\Log"
set "LOG_FILE=%LOG_DIR%\W_UPDATE_log.txt"

:: =================== CREATE DIRECTORIES ===================
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%LOG_FILE%" echo [%date% %time%] Log file created. > "%LOG_FILE%"

:: =================== CHECK FOR ADMIN PRIVILEGES ===================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] Requesting administrator access... >> "%LOG_FILE%"
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo [%date% %time%] Script started. >> "%LOG_FILE%"

:: =================== SET EXECUTION POLICY ===================
echo [%date% %time%] Setting Execution Policy to Bypass... >> "%LOG_FILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force" >> "%LOG_FILE%" 2>&1

:: =================== INSTALL NUGET PROVIDER ===================
:: Check for NuGet provider and install if missing (with CurrentUser scope)
echo [%date% %time%] Checking for NuGet provider... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser; }" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_common

:: Register PSGallery as a repository if not already present
echo [%date% %time%] Registering PSGallery repository if needed... >> "%LOG_FILE%" 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-PSRepository | Where-Object { $_.Name -eq 'PSGallery' })) { Register-PSRepository -Default }" >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto error_common

:: =================== DOWNLOAD SCRIPTS ===================
call :DownloadScript "WU.ps1"
if %errorlevel% neq 0 goto error_download

call :DownloadScript "WGET.ps1"
if %errorlevel% neq 0 goto error_download

call :DownloadScript "MSO_UPDATE.ps1"
if %errorlevel% neq 0 goto error_download

:: =================== RUN SCRIPTS ===================
call :RunScript "WU.ps1"
if %errorlevel% neq 0 goto error_script_execution

call :RunScript "WGET.ps1"
if %errorlevel% neq 0 goto error_script_execution

call :RunScript "MSO_UPDATE.ps1"
if %errorlevel% neq 0 goto error_script_execution

:: =================== CLEANUP ===================
goto cleanup

:: =================== FUNCTION: DownloadScript ===================
:DownloadScript
set "SCRIPT_NAME=%~1"
echo [%date% %time%] Checking for %SCRIPT_NAME% in %SCRIPT_DIR%... >> "%LOG_FILE%"
if exist "%SCRIPT_DIR%\%SCRIPT_NAME%" (
    echo [%date% %time%] Existing %SCRIPT_NAME% found. Deleting for fresh download... >> "%LOG_FILE%"
    del /q "%SCRIPT_DIR%\%SCRIPT_NAME%" >> "%LOG_FILE%" 2>&1
)
echo [%date% %time%] Downloading %SCRIPT_NAME% from GitHub... >> "%LOG_FILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Invoke-WebRequest -Uri '%BASE_URL%/%SCRIPT_NAME%' -OutFile '%SCRIPT_DIR%\%SCRIPT_NAME%' -UseBasicParsing -Verbose; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }" >> "%LOG_FILE%" 2>&1
exit /b %errorlevel%

:: =================== FUNCTION: RunScript ===================
:RunScript
set "SCRIPT_NAME=%~1"
echo [%date% %time%] Running %SCRIPT_NAME%... >> "%LOG_FILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\%SCRIPT_NAME%" >> "%LOG_FILE%" 2>&1
exit /b %errorlevel%

:: =================== CLEANUP ===================
:cleanup
echo [%date% %time%] Resetting Execution Policy to default... >> "%LOG_FILE%"
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1

echo [%date% %time%] Deleting downloaded scripts... >> "%LOG_FILE%"
for %%S in (WU.ps1 WGET.ps1 MSO_UPDATE.ps1) do (
    if exist "%SCRIPT_DIR%\%%S" del /q "%SCRIPT_DIR%\%%S" >> "%LOG_FILE%" 2>&1
)

echo [%date% %time%] Temporary script folder (excluding logs) remains. >> "%LOG_FILE%"

:: Delete this batch file using delayed deletion
start "" cmd /c "ping 127.0.0.1 -n 3 >nul && del \"%~f0\""
exit /b 0

:: =================== ERROR HANDLERS ===================
:error_provider
echo [%date% %time%] Failed to install NuGet provider. >> "%LOG_FILE%"
goto error_common

:error_download
echo [%date% %time%] A file download encountered an error. >> "%LOG_FILE%"
goto error_common

:error_script_execution
echo [%date% %time%] One or more scripts encountered an error during execution. >> "%LOG_FILE%"
goto error_common

:error_common
echo [%date% %time%] Resetting Execution Policy to default... >> "%LOG_FILE%"
powershell.exe -NoProfile -Command "Set-ExecutionPolicy Restricted -Scope Process -Force" >> "%LOG_FILE%" 2>&1
echo [%date% %time%] Keeping downloaded files for debugging. (Scripts and batch file will not be deleted on error.) >> "%LOG_FILE%"
pause
exit /b 1
