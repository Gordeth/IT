# WindowsUpdateScript.ps1

$ScriptPath = $MyInvocation.MyCommand.Path
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WindowsUpdateScript.lnk"

# Ensure NuGet provider is installed *before* using Install-Module
Write-Host "Ensuring NuGet provider is installed..." -ForegroundColor Yellow
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    try {
        $ConfirmPreference = "None"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser
        $ConfirmPreference = "High" # Reset to default after the command (optional but good practice)
        Write-Host "NuGet provider installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install NuGet provider. Error: $_" -ForegroundColor Red
    }
}

# Ensure the PSWindowsUpdate module is installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Yellow
    Install-Module -Name PSWindowsUpdate -Force -Scope Process
}

# Import the module
Import-Module PSWindowsUpdate

# Show available updates
Write-Host "Checking for updates..." -ForegroundColor Cyan
$Updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose

if ($Updates) {
    Write-Host "Updates found." -ForegroundColor Yellow

    # Create a restore point
    Write-Host "Creating a restore point before installing updates..." -ForegroundColor Cyan
    try {
        Checkpoint-Computer -Description "Pre-WindowsUpdateScript" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "Restore point created successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to create restore point. Error: $_" -ForegroundColor Red
    }

    # Set script to run at startup (if not already)
    if (-not (Test-Path $StartupShortcut)) {
        Write-Host "Adding script to Startup folder..." -ForegroundColor Gray
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
        $Shortcut.Save()
    }

    # Install updates and reboot
    Write-Host "Installing updates..." -ForegroundColor Green
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose
}
else {
    Write-Host "No more updates found." -ForegroundColor Green

    # Clean up: remove startup shortcut if it exists
    if (Test-Path $StartupShortcut) {
        Write-Host "Removing script from Startup..." -ForegroundColor Gray
        Remove-Item $StartupShortcut -Force
    }
}
