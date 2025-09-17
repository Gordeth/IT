<#
.SYNOPSIS
    Automates Microsoft Office updates.
.DESCRIPTION
    This script automates the update process for Microsoft Office installations using the Click-to-Run (C2R) technology.
    It locates the `OfficeC2RClient.exe` and executes it to force an update, logging the process and handling potential issues.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: MSO_UPDATE.ps1
    Version: 1.0
    Dependencies:
        - Microsoft Office (Click-to-Run installation)
    Changelog:
        v1.0
        - Initial release.
#>

param (
  # Parameter passed from the orchestrator script (WUH.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Parameter passed from the orchestrator script (WUH.ps1) for centralized logging.
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
# This script will now create its own file named MSO_UPDATE.txt inside the provided log directory.
$LogFile = Join-Path $LogDir "MSO_UPDATE.txt"


# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created by MSO_UPDATE.ps1." | Out-File $LogFile -Append
}


# ==================== Script Execution Start ====================
Log "Starting MSO_UPDATE.ps1 script." "INFO"

try {
    # Define the typical path to the Office Click-to-Run client executable.
    $OfficeClient = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"

    # Check if the Office Click-to-Run client executable exists at the defined path.
    if (Test-Path $OfficeClient) {
        Log "Office Click-to-Run client found. Launching update..." "INFO"

        # Start the Office update process.
        # -FilePath: Specifies the path to the executable.
        # -ArgumentList: Provides arguments to the executable.
        #    "/update user": Instructs the client to perform an update for the current user.
        #    "forceappshutdown=true": Forces Office applications to close if they are open, to allow update.
        # -WindowStyle Hidden: Runs the process without displaying a visible window.
        # -Wait: Pauses the PowerShell script execution until the Office update process completes.
        # -PassThru: Returns a Process object, allowing access to its properties like ExitCode.
        $process = Start-Process -FilePath $OfficeClient `
                                 -ArgumentList "/update user forceappshutdown=true" `
                                 -WindowStyle Hidden `
                                 -Wait `
                                 -PassThru

        # Log the exit code of the Office update process for diagnostic purposes.
        Log "Office update process exited with code $($process.ExitCode)." "INFO"

        # Check the exit code to determine the success or failure of the update.
        if ($process.ExitCode -eq 0) {
            Log "Office update completed successfully." "INFO"
        } else {
            # If the exit code is not 0, it indicates a non-successful update.
            Log "Office update exited with code $($process.ExitCode). Review logs for more info." "WARN"
        }
    } else {
        # If the OfficeC2RClient.exe is not found, it suggests Office might not be installed
        # or it's an MSI-based installation, not Click-to-Run.
        Log "OfficeC2RClient.exe not found. Microsoft Office (Click-to-Run) may not be installed on this system." "WARN"
    }
} catch {
    # Catch and log any PowerShell errors that occur during the attempt to launch the Office update process.
    Log "Failed to launch Office update: $_" "ERROR"
}

# ==================== Script Completion ====================
#
# Log a final message to indicate that the MSO_UPDATE script has finished its execution.
#
Log "MSO_UPDATE script completed."