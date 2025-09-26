<#
.SYNOPSIS
    Performs system cleanup using temporary file removal and the modern Storage Sense feature.
.DESCRIPTION
    This script automates common system cleanup procedures. It clears temporary files
    from the main Windows temp folder and the current user's temp folder. In 'Full' mode,
    it also runs the built-in Windows Storage Sense cleanup for a more comprehensive cleanup.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER CleanupMode
    Specifies the intensity of the cleanup.
    'Light' performs quick cleanup of temp folders.
    'Full' (default) performs all cleanup tasks, including running Storage Sense.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: CLEANUP.ps1
    Version: 1.1.0
    Dependencies:
        - PowerShell 5.1 or later.
        - `Invoke-CommandWithLogging` function from `Functions.ps1`
    Changelog:
        v1.2.3
        - Replaced 'Full' mode logic with `Start-StorageSense` cmdlet to use the modern, built-in Windows cleanup feature.
        v1.2.1
        - Removed Downloads folder cleanup and DISM component cleanup from 'Full' mode to avoid deleting potentially important user files and to reduce script runtime.
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

# ================== 3. Clear Browser Caches (Edge & Chrome) ==================
try {
    Log "Checking for running browser processes (Edge, Chrome)..." "INFO"
    $runningBrowsers = Get-Process -Name "msedge", "chrome" -ErrorAction SilentlyContinue
    if ($runningBrowsers) {
        Log "One or more browser processes are running. Some cache files may be locked and cannot be deleted. For a full cleanup, please close all browser windows." "WARN"
    }

    # Helper function to clean a browser's cache directories
    function Clear-BrowserCache {
        param(
            [string]$BrowserName,
            [string]$UserDataPath
        )
        if (Test-Path $UserDataPath) {
            Log "Found $BrowserName user data at '$UserDataPath'. Searching for profiles..." "INFO"
            # Find all profile directories (e.g., 'Default', 'Profile 1', 'Profile 2', etc.)
            $profileDirs = Get-ChildItem -Path $UserDataPath -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
            if (-not $profileDirs) {
                Log "No profile directories found for $BrowserName." "INFO"
                return
            }

            foreach ($profileDir in $profileDirs) {
                $cachePath = Join-Path $profileDir.FullName "Cache"
                if (Test-Path $cachePath) {
                    Log "Clearing $BrowserName cache for profile '$($profileDir.Name)'..." "INFO"
                    Get-ChildItem -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                        } catch {
                            Log "Could not remove '$($_.FullName)'. It may be in use." "WARN"
                        }
                    }
                }
            }
        }
    }

    # Clean caches for Edge and Chrome
    Clear-BrowserCache -BrowserName "Microsoft Edge" -UserDataPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    Clear-BrowserCache -BrowserName "Google Chrome" -UserDataPath "$env:LOCALAPPDATA\Google\Chrome\User Data"
} catch {
    Log "An error occurred during browser cache cleanup: $_" "WARN"
}

# ================== 4. Perform Full Cleanup (Storage Sense) ==================
if ($CleanupMode -eq 'Full') {
    try {
        Log "Performing full system cleanup by running Storage Sense..." "INFO"
        Log "This will use the current user's Storage Sense settings from the Windows Settings app." "INFO"

        # Define the script block to be executed.
        $storageSenseBlock = {
            # The variables are passed in via ArgumentList from Start-Job.
            param($functions, $LogDir, $VerboseMode, $LogFile)

            # This command runs the configured Storage Sense cleanup tasks immediately.
            Start-StorageSense
        }
        # Use the new spinner function to provide visual feedback during this long, silent operation.
        Invoke-TaskWithSpinner -ScriptBlock $storageSenseBlock -Activity "Running Storage Sense Cleanup" -VerboseMode:$VerboseMode
        Log "Storage Sense cleanup task finished." "INFO"
    } catch {
        Log "Failed to run Storage Sense. This command may not be available on older versions of Windows. Error: $_" -Level "ERROR"
    }
}

# ================== End of script ==================
Log "==== CLEANUP Script Completed ===="