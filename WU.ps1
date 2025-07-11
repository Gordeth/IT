param (
    [switch]$VerboseMode = $false,
    [string]$LogFile
)
# ==================== Define Log Function ====================
#
# Function: Log
# Description: Writes a timestamped message to a designated log file and,
#              optionally, to the console. It supports different log levels
#              (INFO, WARN, ERROR, DEBUG) for categorization and display control.
#
# Parameters:
#   -Message (string): The text string to be recorded in the log.
#   -Level (string): Specifies the severity or type of the log entry.
#                    Valid values are "INFO", "WARN", "ERROR", "DEBUG".
#                    Defaults to "INFO" if not specified.
#
# Console Output Logic:
#   - All log entries are written to the file specified by the global variable `$LogFile`.
#   - Messages with a "ERROR" level are *always* displayed on the console.
#   - Other messages (INFO, WARN, DEBUG) are displayed on the console only if
#     the global variable `$VerboseMode` is set to `$true`.
#
# Error Handling:
#   - Includes a `try-catch` block to handle potential issues when writing to the log file,
#     displaying a console error if logging to file fails.
#
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Generate a formatted timestamp (day-month-year hour:minute:second) for the log entry.
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    
    # Construct the complete log entry string, including timestamp and log level.
    $logEntry = "[$timestamp] [$Level] $Message"

    # Attempt to append the log entry to the specified log file.
    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If writing to the log file fails (e.g., file lock, permissions),
        # output an error message directly to the console in red.
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # Determine if the log entry should also be output to the console.
    # It will be displayed if `$VerboseMode` is enabled OR if the log level is "ERROR".
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Select the console color based on the log entry's level.
        $color = switch ($Level) {
            "INFO"  { "White" }   # Standard informational messages
            "WARN"  { "Yellow" }  # Warnings indicating potential issues
            "ERROR" { "Red" }     # Critical errors
            "DEBUG" { "Gray" }    # Detailed debug information
            default { "White" }   # Fallback color
        }
        # Write the log entry to the console with the chosen color.
        Write-Host $logEntry -ForegroundColor $color
    }
}

# ==================== Setup Paths and Global Variables ====================
#
# This section initializes essential paths and variables used throughout the script,
# ensuring proper file locations for logging and script execution.
#
# Log the initial message indicating the script has started, using the `Log` function.
Log "WU Script started." "INFO"

# Get the full path of the current script, which is needed for creating the startup shortcut.
$ScriptPath = $MyInvocation.MyCommand.Path

# Define the target path for the startup shortcut. This shortcut ensures the script
# can re-run automatically after a system reboot if updates require it.
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WU.lnk"

# ==================== Ensure PSWindowsUpdate Module ====================
#
# This section verifies the presence of the `PSWindowsUpdate` module, which is crucial
# for interacting with Windows Update services. If it's missing, the script attempts to install it.
#
Log "Checking for PSWindowsUpdate module..."
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Log "PSWindowsUpdate module not found. Installing..."
    try {
        # Attempt to install the PSWindowsUpdate module from PowerShell Gallery.
        # `-Force` to overwrite existing files, `-SkipPublisherCheck` to bypass certificate warnings,
        # `-AllowClobber` to allow cmdlets with the same names as existing ones.
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -AllowClobber
        Log "PSWindowsUpdate module installed successfully."
    } catch {
        # If module installation fails, log an error and terminate the script.
        Log "Failed to install PSWindowsUpdate module: $_" -Level "ERROR"
        exit 1 # Exit with a non-zero code to indicate an error state.
    }
} else {
    Log "PSWindowsUpdate module already installed."
}

# Import the PSWindowsUpdate module into the current session, making its cmdlets available.
# `-Force` ensures it's imported even if already present or if there are version conflicts.
Import-Module PSWindowsUpdate -Force
Log "PSWindowsUpdate module imported."

# ==================== Check for Updates ====================
#
# This core section initiates the check for pending Windows updates.
#
Log "Checking for Windows updates..."

# Save the current $VerbosePreference to restore it later
$originalVerbosePreference = $VerbosePreference
try {
    # Conditionally apply -Verbose and suppress console output when not in VerboseMode.
    if ($VerboseMode) {
        $UpdateList = Get-WindowsUpdate -MicrosoftUpdate -Verbose
    } else {
        # Temporarily set $VerbosePreference to suppress verbose output
        $VerbosePreference = 'SilentlyContinue'
        # Capture the objects into $UpdateList, but discard the console display of these objects.
        [void]($UpdateList = Get-WindowsUpdate -MicrosoftUpdate)
    }
} finally {
    # Always restore the original $VerbosePreference
    $VerbosePreference = $originalVerbosePreference
}

# ==================== Handle Update Scenarios ====================
#
# This block manages the logic based on whether updates are found or not.
# It covers creating restore points, adding/removing startup shortcuts, and installing updates.
#
if ($UpdateList) {
    # If `$UpdateList` contains objects, it means updates were found.
    Log "Updates found: $($UpdateList.Count)."

    # --- Create Restore Point ---
    # It's good practice to create a system restore point before applying major system changes
    # like updates, providing a rollback option in case of issues.
    try {
        Log "Creating system restore point..."
        # Ensure the Volume Shadow Copy (VSS) service is enabled and started, as it's
        # a prerequisite for creating restore points. `-ErrorAction SilentlyContinue`
        # prevents script termination if the service is already running or cannot be changed.
        Set-Service -Name 'VSS' -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name 'VSS' -ErrorAction SilentlyContinue
        
        # Enable system restore on the C: drive. This command can be idempotent.
        Enable-ComputerRestore -Drive "C:\"
        Log "Enabled VSS and System Restore."
        
        # Create the actual restore point with a descriptive name.
        # `RestorePointType "MODIFY_SETTINGS"` is appropriate for system changes.
        Checkpoint-Computer -Description "Pre-WindowsUpdateScript" -RestorePointType "MODIFY_SETTINGS"
        Log "Restore point created successfully."
    } catch {
        # Log any errors encountered during restore point creation.
        Log "Failed to create restore point: $_" -Level "ERROR"
    }

    # --- Add to Startup if not already present ---
    # If updates are found, a shortcut is added to the Startup folder. This ensures
    # the script runs again automatically after any reboots triggered by updates,
    # allowing it to complete the update process (e.g., post-reboot installations)
    # or clean up.
    if (-not (Test-Path $StartupShortcut)) {
        try {
            Log "Adding script shortcut to Startup folder."
            # Create a COM object for Windows Script Host Shell to manage shortcuts.
            $WScriptShell = New-Object -ComObject WScript.Shell
            # Create a new shortcut object at the defined startup path.
            $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
            
            # Point the shortcut to `powershell.exe`.
            $Shortcut.TargetPath = "powershell.exe"
            # Define arguments for PowerShell: bypass execution policy, hide window,
            # and run the script file. Quotes around `$ScriptPath` handle spaces.
            $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
            # Set the working directory for the shortcut.
            $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
            # Save the shortcut file to disk.
            $Shortcut.Save()
            Log "Shortcut added successfully."
        } catch {
            # Log any errors during the creation of the startup shortcut.
            Log "Failed to add Startup shortcut: $_" -Level "ERROR"
        }
    }

    # --- Install updates ---
    # Proceed with the actual installation of the detected Windows updates.
    try {
        Log "Installing updates..."
        # Save the current $VerbosePreference to restore it later
        $originalVerbosePreference = $VerbosePreference
        try {
            $InstallationResult = $null # Initialize variable to hold results
            # Conditionally apply -Verbose and capture the output of Install-WindowsUpdate
            if ($VerboseMode) {
                # Removed -AutoReboot to handle reboots explicitly
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose
            } else {
                # Temporarily set $VerbosePreference to suppress verbose output
                $VerbosePreference = 'SilentlyContinue'
                # Execute the installation and capture its output.
                # Removed -AutoReboot to handle reboots explicitly
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll
            }
        } finally {
            # Always restore the original $VerbosePreference
            $VerbosePreference = $originalVerbosePreference
        }
        
        # --- Check for pending reboot after installation based on installation results ---
        Log "Update installation completed. Checking if a reboot is needed based on installation results..."
        
        $rebootPending = $false
        # Iterate through the results to see if any installed update requires a reboot
        foreach ($result in $InstallationResult) {
            if ($result.RebootRequired -eq $true) {
                $rebootPending = $true
                break # Found one, no need to check further
            }
        }

        if ($rebootPending) {
            Log "Reboot is required to complete Windows Updates. Initiating reboot..." -Level "WARN"
            # The script will stop here as the system restarts. The startup shortcut will handle re-execution.
            Restart-Computer -Force
            exit # Exit the script
        } else {
            Log "No reboot required. Script execution will continue."
        }
    } catch {
        # Log any errors that occur during the update installation process.
        Log "Error during update installation: $_" -Level "ERROR"
    }

    # --- Clean up: remove startup shortcut if it exists ---
    # If no updates were found, or if the script has run post-reboot and completed
    # the update process, the startup shortcut is no longer needed and should be removed
    # to prevent unnecessary future executions.
    if (Test-Path $StartupShortcut) {
        try {
            Log "Removing script shortcut from Startup folder."
            Remove-Item $StartupShortcut -Force # Force removal without prompt.
            Log "Shortcut removed successfully."
        } catch {
            # Log any errors encountered while trying to remove the shortcut.
            Log "Failed to remove Startup shortcut: $_" -Level "ERROR"
        }
    }
}

# ==================== Script Completion and Cleanup ====================
#
# This final section performs necessary cleanup, like restoring the execution policy,
# and logs the script's completion.
#

# Log a final message indicating the script has finished its execution.
Log "Script execution completed."