<#
.SYNOPSIS
    Performs system cleanup tasks using modern Windows StorageSense cmdlets.
.DESCRIPTION
    This script cleans up system files. It offers two modes:
    - Light: Cleans up temporary system files.
    - Full: Performs a light cleanup and also empties the Recycle Bin.
    This script avoids using the legacy 'cleanmgr.exe' to prevent disruptive UI pop-ups.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
.PARAMETER LogDir
    The full path to the log directory where script actions will be recorded.
.PARAMETER CleanupMode
    Specifies the cleanup intensity. Accepts 'Light' or 'Full'.
.NOTES
    Script: CLEANUP.ps1
    Version: 1.0.0
    Dependencies:
        - PowerShell 5.1 or later on Windows 10/11.
#>
param (
  [switch]$VerboseMode = $false,
  [Parameter(Mandatory=$true)]
  [string]$LogDir,
  [Parameter(Mandatory=$true)]
  [ValidateSet('Light', 'Full')]
  [string]$CleanupMode
)

# ==================== Setup ====================
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../modules/Functions.ps1"
$LogFile = Join-Path $LogDir "CLEANUP.txt"
if (-not (Test-Path $LogFile)) {
    "Log file created by CLEANUP.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution ====================
Log "Starting CLEANUP.ps1 script in '$CleanupMode' mode..." "INFO"

try {
    Log "Running Storage Sense to clean up temporary files. This may take a moment..." "INFO"
    # This cmdlet cleans up temporary files, similar to a basic disk cleanup.
    Start-StorageSense
    Log "Temporary file cleanup completed." "INFO"

    if ($CleanupMode -eq 'Full') {
        Log "Full mode selected. Emptying the Recycle Bin..." "INFO"
        # Clear the recycle bin for all users on all drives.
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Log "Recycle Bin has been emptied." "INFO"
    }
} catch {
    Log "An error occurred during the cleanup process: $_" "ERROR"
}

Log "==== CLEANUP Script Completed ===="
