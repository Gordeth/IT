@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator access...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Download the latest script from GitHub
set SCRIPT_URL=https://raw.githubusercontent.com/Gordeth/IT/main/WindowsUpdateScript.ps1
set SCRIPT_PATH=%TEMP%\WindowsUpdateScript.ps1

echo Downloading latest script from GitHub...
powershell -Command "Invoke-WebRequest -Uri %SCRIPT_URL% -OutFile %SCRIPT_PATH%"

:: Run the downloaded script
echo Running the PowerShell script...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"

pause
