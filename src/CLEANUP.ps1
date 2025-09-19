<#
.SYNOPSIS
    Performs various system cleanup tasks to free up disk space.
.DESCRIPTION
    This script automates common system cleanup procedures. It clears temporary files
    from the main Windows temp folder and the current user's temp folder. It also
    empties the current user's Recycle Bin.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER CleanupMode
    Specifies the intensity of the cleanup.
    'Light' performs quick cleanup of temp folders.
    'Full' (default) performs all cleanup tasks, including the time-consuming Windows Disk Cleanup.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: CLEANUP.ps1
    Version: 1.1.0
    Dependencies:
        - PowerShell 5.1 or later.
    Changelog:
        v1.1.0
        - Added `CleanupMode` parameter ('Light', 'Full') to differentiate between quick temp file cleaning and a full system cleanup including `cleanmgr.exe`.
        v1.0.5
        - Modified `cleanmgr.exe` execution to run minimized (`-WindowStyle 7`) as it appears to resist being fully hidden.
        v1.0.4
        - Replaced `Start-Process` with `WScript.Shell` COM object to run `cleanmgr.exe` to ensure the window is reliably hidden.
        v1.0.3
        - Modified `cleanmgr.exe` execution to run with a hidden window and display an indeterminate progress bar in verbose mode for a better user experience.
        v1.0.2
        - Enhanced cleanup to include running the built-in Windows Disk Cleanup tool (cleanmgr.exe) in an automated mode for more thorough cleaning.
        - Removed the dedicated 'Empty Recycle Bin' step as it is now handled by cleanmgr.
        v1.0.1
        - Updated user temp file cleanup to exclude `bootstrapper.ps1` to prevent errors when run via the one-liner.
        v1.0.0
        - Initial release with functionality to clear system temp, user temp, and empty the Recycle Bin.
#>
param (
  # Parameter passed from the orchestrator script (TO.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Specifies the cleanup mode. 'Light' for temp files only, 'Full' for all tasks.
  [ValidateSet('Light', 'Full')]
  [string]$CleanupMode = 'Full',
  # Parameter passed from the orchestrator script (TO.ps1) for centralized logging.
  [Parameter(Mandatory=$true)]
  [string]$LogDir
)

# ==================== Setup Paths and Global Variables ====================
# ==================== Preference Variables ====================
# Set common preference variables for consistent script behavior.
$ErrorActionPreference = 'Stop' # Stop on any error
$WarningPreference = 'Continue' # Display warnings but continue
$VerbosePreference = 'Continue' # Display verbose messages

# ==================== Module Imports / Dot Sourcing ====================
# --- IMPORTANT: Sourcing the Functions.ps1 module to make the Log function available.
# The path is relative to the location of this script (which should be the 'src' folder).
# This ensures that the Log function is available in the scope of this script.
. "$PSScriptRoot/../modules/Functions.ps1"

# ==================== Global Variable Initialization & Log Setup ====================
# Add a check to ensure the log directory path was provided.
if (-not $LogDir) {
    Write-Host "ERROR: The LogDir parameter is mandatory and cannot be empty." -ForegroundColor Red
    exit 1
}

# --- Construct the dedicated log file path for this script ---
# This script will now create its own file named CLEANUP.txt inside the provided log directory.
$LogFile = Join-Path $LogDir "CLEANUP.txt"


# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created by CLEANUP.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution Start ====================
Log "Starting CLEANUP.ps1 script v1.1.0 in '$CleanupMode' mode." "INFO"

# ================== 1. Clear System Temporary Files ==================
try {
    $systemTempPath = "$env:windir\Temp"
    Log "Clearing system temporary files from '$systemTempPath'..."
    # Get child items and pipe them to Remove-Item to handle potential errors on individual files (e.g., in use).
    Get-ChildItem -Path $systemTempPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Log "Could not remove '$($_.FullName)'. It may be in use." -Level "WARN"
        }
    }
    Log "System temporary files cleanup attempt finished."
} catch {
    Log "An error occurred while accessing the system temporary files directory: $_" -Level "WARN"
}

# ================== 2. Clear User Temporary Files ==================
try {
    $userTempPath = "$env:TEMP"
    # IMPORTANT: The bootstrapper places the project in a folder named 'IAP' inside the temp directory.
    # We must exclude this folder to avoid self-deletion.
    $exclusions = @("IAP", "bootstrapper.ps1")
    Log "Clearing current user's temporary files from '$userTempPath', excluding project files: $($exclusions -join ', ')..."

    # Get all child items directly in the temp folder, excluding the project folder itself, then delete them recursively.
    # This is safer than a blanket `Get-ChildItem -Recurse` which would try to delete the running scripts.
    Get-ChildItem -Path $userTempPath -Exclude $exclusions -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Log "Could not remove '$($_.FullName)'. It may be in use." -Level "WARN"
        }
    }
    Log "User temporary files cleanup attempt finished."
} catch {
    Log "An error occurred while accessing the user temporary files directory: $_" -Level "WARN"
}

# ================== 3. Run Windows Disk Cleanup (cleanmgr.exe) ==================
if ($CleanupMode -eq 'Full') {
    try {
        Log "Configuring and running Windows Disk Cleanup utility (cleanmgr.exe)..." "INFO"
        $sagesetNumber = 99
        $sagesetRegValue = "StateFlags" + $sagesetNumber.ToString("0000")
        $volumeCachesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

        # List of cleanup handlers to enable. These are the names of the registry keys.
        $handlersToEnable = @(
            "Active Setup Temp Folders",
            "Downloaded Program Files",
            "Internet Cache Files",
            "Recycle Bin",
            "Temporary Files",
            "Thumbnails",
            "Update Cleanup", # This is equivalent to Component Store Cleanup (WinSxS)
            "Windows Error Reporting Files",
            "Windows Upgrade Log Files",
            "Delivery Optimization Files"
        )

        Log "Enabling the following cleanup handlers for sageset ${sagesetNumber}: $($handlersToEnable -join ', ')" "INFO"

        foreach ($handler in $handlersToEnable) {
            $handlerPath = Join-Path $volumeCachesPath $handler
            if (Test-Path $handlerPath) {
                try {
                    Set-ItemProperty -Path $handlerPath -Name $sagesetRegValue -Value 2 -Type DWord -Force -ErrorAction Stop
                    Log "Enabled handler: $handler" "INFO"
                } catch {
                    Log "Failed to enable handler '$handler'. Error: $_" "WARN"
                }
            } else {
                Log "Cleanup handler key not found: $handler. Skipping." "WARN"
            }
        }

        try {
            Log "Running cleanmgr.exe with sageset $sagesetNumber. This may take a long time, especially the 'Update Cleanup'..." "INFO"
            
            # In verbose mode, show an indeterminate progress bar since cleanmgr can take a long time.
            if ($VerboseMode) {
                Write-Progress -Activity "Running Windows Disk Cleanup" -Status "This may take a long time..." -PercentComplete -1
            }

            # Use WScript.Shell for a more reliable hidden window.
            # Start-Process -WindowStyle Hidden can be ignored by some applications like cleanmgr.exe.
            $WshShell = New-Object -ComObject WScript.Shell
            # The 'Run' method parameters are: (command, windowStyle, waitOnReturn)
            # WindowStyle 7 runs the program minimized.
            $exitCode = $WshShell.Run("cleanmgr.exe /sagerun:$sagesetNumber", 7, $true)

            Log "Windows Disk Cleanup completed with exit code: $exitCode." "INFO"
        } finally {
            # Ensure the progress bar is always closed, even if the process is interrupted.
            if ($VerboseMode) {
                Write-Progress -Activity "Running Windows Disk Cleanup" -Status "Completed." -Completed
            }
        }
    } catch {
        # This outer catch will handle errors from the registry configuration part.
        Log "An error occurred during the Windows Disk Cleanup process: $_" "ERROR"
    }
}

# ================== End of script ==================
Log "==== CLEANUP Script Completed ===="