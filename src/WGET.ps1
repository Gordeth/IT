# WGET.ps1
# Version: 1.0

# Description: This script automates the update of all installed packages using the winget package manager.
#              It provides options for verbose logging and specifies a log file for detailed activity tracking.
#              The script ensures the logging environment is set up correctly before execution and handles
#              the winget upgrade process with error handling.
#
# Changelog:
# ---------------------------------------------------------------------------------------------------
# Version 1.0 - 2025-08-22
#   - Initial release.
#   - Implemented winget upgrade --all with verbose and logging options.
#   - Added log directory and file creation.
#   - Integrated with Functions.ps1 for logging.
# ---------------------------------------------------------------------------------------------------

param (
    # Parameter: VerboseMode
    # Type: Switch (boolean)
    # Default: $false
    # Description: When specified, enables detailed console output for log messages.
    #              If omitted, only ERROR level messages will be shown on the console.
    [switch]$VerboseMode = $false,

    # Parameter: LogFile
    # Type: String
    # Description: Specifies the full path to the log file where script activities
    #              will be recorded. This parameter is mandatory for logging.
    [string]$LogFile
)

# ================== CONFIGURATION ==================
# Using the built-in variable $PSScriptRoot is the most reliable way to get the script's directory.
# This avoids issues with hardcoded paths that may change.
$ScriptDir = $PSScriptRoot
# The logging and script directories are now consistently based on $PSScriptRoot.
$LogDir = Join-Path $ScriptDir "Log"
# Define the log file specifically for this orchestrator script.
$LogFile = Join-Path $LogDir "WGET.txt"

# --- Set the working location to the script's root ---
Set-Location -Path $ScriptDir

# ================== CREATE DIRECTORIES AND LOG FILE ==================
# This section ensures the logging environment is set up correctly before any
# other scripts are called or logging is performed.
# =====================================================================

# Create the log directory if it doesn't exist.
if (-not (Test-Path $LogDir)) {
    Write-Host "Creating log directory: $LogDir"
    try {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    } catch {
        Write-Host "ERROR: Failed to create log directory. $_" -ForegroundColor Red
        # Exit the script if the log directory cannot be created.
        exit 1
    }
}

# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created." | Out-File $LogFile -Append
}

# ================== LOAD FUNCTIONS MODULE ==================
# This line makes all the functions in your separate Functions.ps1 script available.
# The path is relative to this script's location ($PSScriptRoot).
. "$PSScriptRoot/../modules/Functions.ps1"

# ==================== Begin Script Execution ====================
#
# This section marks the main execution flow of the WGET.ps1 script.
# It uses the `Log` function to track progress and handle package updates via winget.
#

# Log an informational message indicating the start of the script.
Log "Starting WGET.ps1 script."

# Log the action of checking for available package updates using winget.
Log "Checking for package updates with winget..."

# Attempt to execute the `winget upgrade --all` command to update all installed packages.
# A `try-catch` block is used to gracefully handle success or failure of the update process.
try {
    # If `$VerboseMode` is enabled, run the `winget` command directly, allowing its
    # native output to be displayed on the console.
    if ($VerboseMode) {
        winget upgrade --all --accept-source-agreements --accept-package-agreements
    } else {
        # If `$VerboseMode` is not enabled, run the `winget` command and redirect
        # its console output to `Out-Null` to suppress it, keeping the console clean.
        # This means only messages from the `Log` function will appear.
        winget upgrade --all --accept-source-agreements --accept-package-agreements | Out-Null
    }
    # If `winget` command completes without throwing a PowerShell error, log success.
    Log "All packages updated successfully."
} catch {
    # If the `winget` command encounters an error (e.g., winget not found, update failure),
    # log the error message using the "ERROR" level, ensuring it's always displayed.
    Log "Failed to update packages: $_" "ERROR"
}