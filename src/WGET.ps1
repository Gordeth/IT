<#
.SYNOPSIS
    Automates winget package updates.
.DESCRIPTION
    This script automates the update of all installed packages using the winget package manager.
    It provides options for verbose logging and specifies a log file for detailed activity tracking.
    The script ensures the logging environment is set up correctly before execution and handles
    the winget upgrade process with error handling.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: WGET.ps1
    Version: 1.0
    Dependencies:
        - winget (Windows Package Manager) must be installed and configured.
        - Internet connectivity
    Changelog:
        v1.0
        - Initial release.
        - Implemented winget upgrade --all with verbose and logging options.
        - Added log directory and file creation.
        - Integrated with Functions.ps1 for logging.
#>
param (
  # Parameter passed from the orchestrator script (WUH.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Parameter passed from the orchestrator script (WUH.ps1) for centralized logging.
  [Parameter(Mandatory=$true)]
  [string]$LogDir
)

# ==================== Preference Variables ====================
# Set common preference variables for consistent script behavior.
$ErrorActionPreference = 'Stop' # Stop on any error

# ==================== Module Imports ====================
. "$PSScriptRoot/../modules/Functions.ps1"

# ==================== Log Setup ====================
$LogFile = Join-Path $LogDir "WGET.txt"
if (-not (Test-Path $LogFile)) {
    "Log file created by WGET.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution Start ====================
Log "Starting WGET.ps1 script." "INFO"
# Log the action of checking for available package updates with winget.
Log "Checking for package updates with winget..."

# Attempt to execute the `winget upgrade --all` command to update all installed packages.
# A `try-catch` block is used to gracefully handle success or failure of the update process.
try {
    # If `$VerboseMode` is enabled, run the `winget` command directly, allowing its
    # native output to be displayed on the console.
    if ($VerboseMode) {
        winget upgrade --all --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "Winget exited with code $LASTEXITCODE." }
    } else {
        # If `$VerboseMode` is not enabled, run the `winget` command and redirect
        # its console output to `Out-Null` to suppress it, keeping the console clean.
        # This means only messages from the `Log` function will appear.
        winget upgrade --all --accept-source-agreements --accept-package-agreements | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Winget exited with code $LASTEXITCODE." }
    }
    # If `winget` command completes without throwing a PowerShell error, log success.
    Log "All packages updated successfully."
} catch {
    # If the `winget` command encounters an error (e.g., winget not found, update failure),
    # or if it returns a non-zero exit code, log the error message.
    Log "Failed to update packages with winget. Error: $_" "ERROR"
}