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
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: CLEANUP.ps1
    Version: 1.0.0
    Dependencies:
        - PowerShell 5.1 or later.
    Changelog:
        v1.0.0
        - Initial release with functionality to clear system temp, user temp, and empty the Recycle Bin.
#>
param (
  # Parameter passed from the orchestrator script (TO.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
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
Log "Starting CLEANUP.ps1 script v1.0.0" "INFO"

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
    $projectFolderName = "IAP"
    Log "Clearing current user's temporary files from '$userTempPath', excluding the project folder '$projectFolderName'..."

    # Get all child items directly in the temp folder, excluding the project folder itself, then delete them recursively.
    # This is safer than a blanket `Get-ChildItem -Recurse` which would try to delete the running scripts.
    Get-ChildItem -Path $userTempPath -Exclude $projectFolderName -Force -ErrorAction SilentlyContinue | ForEach-Object {
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

# ================== 3. Empty Recycle Bin ==================
try {
    Log "Emptying the current user's Recycle Bin..."
    # This cmdlet is available in PowerShell 5.1+ and is the most reliable method.
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log "Recycle Bin emptied successfully."
} catch {
    # This catch block might not be hit if -ErrorAction is SilentlyContinue, but it's good practice.
    Log "An error occurred while trying to empty the Recycle Bin: $_" -Level "WARN"
}

# ================== End of script ==================
Log "==== CLEANUP Script Completed ===="