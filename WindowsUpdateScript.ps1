# WindowsUpdateScript.ps1

$ScriptPath = $MyInvocation.MyCommand.Path
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WindowsUpdateScript.lnk"


Write-Log "Setting execution policy..."
Write-Host "Setting execution policy..." -ForegroundColor Yellow
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

# Ensure the PSWindowsUpdate module is installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Log "Installing PSWindowsUpdate module..."
    Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Yellow
    Install-Module -Name PSWindowsUpdate -Scope CurrentUser -Force
}

# Import the module
Import-Module PSWindowsUpdate

# Show available updates
Write-Log "Checking for updates..."
Write-Host "Checking for updates..." -ForegroundColor Cyan
$Updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose

if ($Updates) {
    Write-Log "Updates found."
    Write-Host "Updates found." -ForegroundColor Yellow

    # Create a restore point
    Write-Log "Creating a restore point before installing updates..."
    Write-Host "Creating a restore point before installing updates..." -ForegroundColor Cyan
    try {
        Checkpoint-Computer -Description "Pre-WindowsUpdateScript" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "Restore point created successfully."
        Write-Host "Restore point created successfully." -ForegroundColor Green
    } catch {
        Write-Log "Failed to create restore point."
        Write-Host "Failed to create restore point. Error: $_" -ForegroundColor Red
    }

    # Set script to run at startup (if not already)
    if (-not (Test-Path $StartupShortcut)) {
        Write-Log "Adding script to Startup folder..."
        Write-Host "Adding script to Startup folder..." -ForegroundColor Gray
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
        $Shortcut.Save()
    }

    # Install updates and reboot
    Write-Log "Installing updates..."
    Write-Host "Installing updates..." -ForegroundColor Green
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose
}
else {
    Write-Log "No more updates found."
    Write-Host "No more updates found." -ForegroundColor Green

    # Clean up: remove startup shortcut if it exists
    if (Test-Path $StartupShortcut) {
        Write-Log "Removing script from Startup..."
        Write-Host "Removing script from Startup..." -ForegroundColor Gray
        Remove-Item $StartupShortcut -Force
    }
}
