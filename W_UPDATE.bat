# WindowsUpdateScript.ps1

# Define log file location
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptRoot "Log"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}
$LogFile = Join-Path $LogDir "update_log-windowsupdate.txt"

# Write-Log function
function Write-Log {
    param (
        [string]$Message,
        [string]$Color = "White"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] $Message"
    Add-Content -Path $LogFile -Value $Entry
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Script started." "Yellow"

$ScriptPath = $MyInvocation.MyCommand.Path
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WindowsUpdateScript.lnk"

# Set execution policy
Write-Log "Setting execution policy to RemoteSigned for this session..." "Yellow"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# Ensure NuGet is installed
Write-Host "Checking for NuGet provider..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "NuGet provider not found. Installing..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Ensure the PSWindowsUpdate module is installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Log "PSWindowsUpdate module not found. Installing..." "Yellow"
    try {
        Install-Module -Name PSWindowsUpdate -Scope CurrentUser -Force -AllowClobber
        Write-Log "PSWindowsUpdate module installed successfully." "Green"
    } catch {
        Write-Log "Failed to install PSWindowsUpdate module: $_" "Red"
    }
} else {
    Write-Log "PSWindowsUpdate module already installed." "Green"
}

# Import the module
Import-Module PSWindowsUpdate -Force
Write-Log "PSWindowsUpdate module imported." "Green"

# Check for available updates
Write-Log "Checking for Windows updates..." "Cyan"
$Updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose | Tee-Object -Variable UpdateList

if ($UpdateList) {
    Write-Log "Updates found: $($UpdateList.Count)." "Yellow"

    # Create a restore point
    Write-Log "Creating system restore point..." "Cyan"
    try {
        Checkpoint-Computer -Description "Pre-WindowsUpdateScript" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "Restore point created successfully." "Green"
    } catch {
        Write-Log "Failed to create restore point: $_" "Red"
    }

    # Add to Startup if not already
    if (-not (Test-Path $StartupShortcut)) {
        Write-Log "Adding script shortcut to Startup folder." "Gray"
        try {
            $WScriptShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
            $Shortcut.TargetPath = "powershell.exe"
            $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
            $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
            $Shortcut.Save()
            Write-Log "Shortcut added successfully." "Green"
        } catch {
            Write-Log "Failed to add Startup shortcut: $_" "Red"
        }
    }

    # Install updates
    Write-Log "Installing updates..." "Green"
    try {
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose
        Write-Log "Update installation completed (system may have rebooted)." "Green"
    } catch {
        Write-Log "Error during update installation: $_" "Red"
    }
} else {
    Write-Log "No updates found." "Green"

    # Clean up: remove startup shortcut if it exists
    if (Test-Path $StartupShortcut) {
        Write-Log "Removing script shortcut from Startup folder." "Gray"
        try {
            Remove-Item $StartupShortcut -Force
            Write-Log "Shortcut removed successfully." "Green"
        } catch {
            Write-Log "Failed to remove Startup shortcut: $_" "Red"
        }
    }
}

Write-Log "Script execution completed." "Yellow"