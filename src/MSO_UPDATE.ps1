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

# ==================== Define Log Function ====================
#
# Function: Log
# Description: A centralized logging utility designed to record script events.
#              It writes timestamped messages to a designated log file and, conditionally,
#              to the console, allowing for clear tracking of script execution.
#              The function supports various log levels for categorization and filtering.
#
# Parameters:
#   -Message (string): The textual content of the message to be logged.
#   -Level (string): Defines the severity or type of the log entry.
#                    Valid options are "INFO" (general information), "WARN" (potential issues),
#                    "ERROR" (critical failures), and "DEBUG" (detailed troubleshooting info).
#                    Defaults to "INFO" if not specified.
#
# Console Output Logic:
#   - All log entries are always appended to the file specified by the `$LogFile` parameter.
#   - Messages classified as "ERROR" will always be displayed on the console (in red)
#     to ensure immediate visibility of critical problems, regardless of `$VerboseMode`.
#   - Messages with "INFO", "WARN", or "DEBUG" levels are displayed on the console
#     only if the `$VerboseMode` switch parameter was set to `$true` when the script was launched.
#
# Error Handling:
#   - Includes a `try-catch` block to handle potential issues during the file writing operation
#     (e.g., file access permissions, file locks). If an error occurs, a fallback message
#     is printed directly to the console.
#
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Generate a timestamp in "dd-MM-yyyy HH:mm:ss" format for the log entry.
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    
    # Construct the complete log entry string by combining the timestamp, log level, and message.
    $logEntry = "[$timestamp] [$Level] $Message"

    # Attempt to append the `$logEntry` string to the specified `$LogFile`.
    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If an error occurs during file writing (e.g., permissions issue),
        # output an error message directly to the console in red.
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # Conditional console output based on `$VerboseMode` and log `$Level`.
    # Display the message if `$VerboseMode` is true OR if the log `$Level` is "ERROR".
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Determine the appropriate console foreground color based on the log level.
        $color = switch ($Level) {
            "INFO"  { "White" }   # Standard informational messages.
            "WARN"  { "Yellow" }  # Warnings, indicating potential issues.
            "ERROR" { "Red" }     # Critical errors.
            "DEBUG" { "Gray" }    # Debugging information.
            default { "White" }   # Fallback for any unhandled log level.
        }
        # Write the log entry to the console with the selected color.
        Write-Host $logEntry -ForegroundColor $color
    }
}

# ==================== Configure PowerShell Preferences (if not Verbose) ====================
#
# This section adjusts PowerShell's built-in preference variables.
# If `$VerboseMode` is NOT enabled (i.e., the user did not specify `-VerboseMode`),
# these preferences are set to `SilentlyContinue` to suppress most native PowerShell output,
# ensuring that only messages from the custom `Log` function are shown (and errors if they occur).
# This provides a cleaner console experience for non-verbose runs.
#
if (-not $VerboseMode) {
    # Suppress verbose stream output from cmdlets.
    $VerbosePreference = "SilentlyContinue"
    # Suppress informational stream output.
    $InformationPreference = "SilentlyContinue"
    # Suppress progress bar output.
    $ProgressPreference = "SilentlyContinue"
    # Suppress warning messages.
    $WarningPreference = "SilentlyContinue"
    # Suppress non-terminating errors; errors will still be caught by try-catch.
    $ErrorActionPreference = "SilentlyContinue"
    # Suppress debug stream output.
    $DebugPreference = "SilentlyContinue"
}

# ==================== Start Office Update Process ====================
#
# This section initiates the update process for Microsoft Office installations that
# use the Click-to-Run (C2R) technology. It locates the OfficeC2RClient.exe and
# executes it with specific arguments to force an update.
#
Log "Updating Microsoft Office..." "INFO"

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