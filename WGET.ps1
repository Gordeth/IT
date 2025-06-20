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

# ==================== Define Log Function ====================
#
# Function: Log
# Description: This function is responsible for writing timestamped messages to a
#              specified log file and, based on configuration, to the console.
#              It supports different levels of logging (INFO, WARN, ERROR, DEBUG)
#              to categorize messages and control their visibility.
#
# Parameters:
#   -Message (string): The actual text string that needs to be logged.
#   -Level (string): Defines the severity or type of the log entry.
#                    Valid options are "INFO", "WARN", "ERROR", "DEBUG".
#                    Defaults to "INFO" if not explicitly provided.
#
# Console Output Behavior:
#   - Every log entry is always written to the file specified by the `$LogFile` parameter.
#   - Log entries with an "ERROR" level will always be displayed on the console,
#     regardless of the `$VerboseMode` setting, to ensure critical issues are visible.
#   - Other log entries (INFO, WARN, DEBUG) are displayed on the console only if the
#     `$VerboseMode` switch parameter is set to `$true` when the script is executed.
#
# Error Handling:
#   - Includes a `try-catch` block to gracefully handle potential failures during
#     the file writing process (e.g., file locks, insufficient permissions).
#     If file writing fails, an error message is printed directly to the console.
#
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Generate the current date and time, formatted as "day-month-year hour:minute:second",
    # to serve as a timestamp for the log entry.
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    
    # Concatenate the timestamp, log level, and message into a single string
    # that will be written to the log file and potentially the console.
    $logEntry = "[$timestamp] [$Level] $Message"

    # Attempt to append the `$logEntry` string to the file specified by `$LogFile`.
    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If an error occurs during file writing (e.g., file access denied),
        # print a descriptive error message to the console in red.
        Write-Host "Failed to write to log file '$LogFile': $_" -ForegroundColor Red
    }

    # Conditional console output:
    # Check if `$VerboseMode` is enabled OR if the current log `$Level` is "ERROR".
    # If either condition is true, the log entry will be displayed on the console.
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Use a `switch` statement to determine the appropriate console text color
        # based on the `$Level` of the log entry.
        $color = switch ($Level) {
            "INFO"  { "White" }   # Standard informational messages.
            "WARN"  { "Yellow" }  # Warnings, indicating potential non-critical issues.
            "ERROR" { "Red" }     # Critical errors, requiring immediate attention.
            "DEBUG" { "Gray" }    # Detailed debug messages, typically for troubleshooting.
            default { "White" }   # Default color if the level is not recognized.
        }
        # Write the formatted log entry to the console using the chosen foreground color.
        Write-Host $logEntry -ForegroundColor $color
    }
}

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