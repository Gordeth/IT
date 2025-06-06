# ==================== Define Log Function ====================
function Log {
    param (
        [string]$Message
    )
    $Timestamp = "[{0}]" -f (Get-Date)
    "$Timestamp $Message" | Out-File $LogFile -Append
    Write-Host "$Timestamp $Message"
}

# ==================== Setup Paths ====================
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptRoot "Log"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}
$LogFile = Join-Path $LogDir "WU.txt"

Log "WU.ps1 Script started."

$ScriptPath = $MyInvocation.MyCommand.Path
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WU.lnk"

# ==================== Save Original Execution Policy ====================
$OriginalPolicy = Get-ExecutionPolicy
Log "Original Execution Policy: $OriginalPolicy"

# ==================== Set Execution Policy ====================
Log "Setting execution policy to RemoteSigned for this session..."
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# ==================== Ensure NuGet Provider ====================
Log "Checking for NuGet provider..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Log "NuGet provider not found. Installing..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Log "NuGet provider installed successfully."
} else {
    Log "NuGet provider already installed."
}

# ==================== Ensure PSWindowsUpdate Module ====================
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Log "PSWindowsUpdate module not found. Installing..."
    try {
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -AllowClobber
        Log "PSWindowsUpdate module installed successfully."
    } catch {
        Log "Failed to install PSWindowsUpdate module: $_"
        exit 1
    }
} else {
    Log "PSWindowsUpdate module already installed."
}

Import-Module PSWindowsUpdate -Force
Log "PSWindowsUpdate module imported."

# ==================== Check for Updates ====================
Log "Checking for Windows updates..."
$UpdateList = Get-WindowsUpdate -MicrosoftUpdate -Verbose

if ($UpdateList) {
    Log "Updates found: $($UpdateList.Count)."

    # Create Restore Point
    try {
        Log "Creating system restore point..."
        Set-Service -Name 'VSS' -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name 'VSS' -ErrorAction SilentlyContinue
        Enable-ComputerRestore -Drive "C:\"
        Log "Enabled VSS and System Restore."
        Checkpoint-Computer -Description "Pre-WindowsUpdateScript" -RestorePointType "MODIFY_SETTINGS"
        Log "Restore point created successfully."
    } catch {
        Log "Failed to create restore point: $_"
    }

    # Add to Startup if not already
    if (-not (Test-Path $StartupShortcut)) {
        try {
            Log "Adding script shortcut to Startup folder."
            $WScriptShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
            $Shortcut.TargetPath = "powershell.exe"
            $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
            $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
            $Shortcut.Save()
            Log "Shortcut added successfully."
        } catch {
            Log "Failed to add Startup shortcut: $_"
        }
    }

    # Install updates
    try {
        Log "Installing updates..."
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose
        Log "Update installation completed (system may have rebooted)."
    } catch {
        Log "Error during update installation: $_"
    }
} else {
    Log "No updates found."

    # Clean up: remove startup shortcut if it exists
    if (Test-Path $StartupShortcut) {
        try {
            Log "Removing script shortcut from Startup folder."
            Remove-Item $StartupShortcut -Force
            Log "Shortcut removed successfully."
        } catch {
            Log "Failed to remove Startup shortcut: $_"
        }
    }
}

# ==================== Restore Execution Policy ====================
Log "Restoring Execution Policy..."
try {
    if ($OriginalPolicy -ne "Restricted") {
        Log "Original policy was $OriginalPolicy; resetting to Restricted."
        Set-ExecutionPolicy Restricted -Scope Process -Force -ErrorAction SilentlyContinue
        Log "Execution Policy set to Restricted."
    } else {
        Log "Original policy was Restricted; no change needed."
    }
} catch {
    Log "Failed to restore Execution Policy: $_"
}

Log "Script execution completed."