@echo off
:: Check for admin permissions
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator access...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Run the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Filipe\Desktop\Scripts_PS\WindowsUpdateScript.ps1"
pause
