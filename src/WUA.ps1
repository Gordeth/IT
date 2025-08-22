<#
.SYNOPSIS
    Automates Windows Update tasks.
.DESCRIPTION
    This script automates the process of checking for, downloading, and installing Windows updates.
    It ensures the `PSWindowsUpdate` module is present, creates a system restore point before updates,
    and handles reboots as necessary.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: WUA.ps1
    Version: 1.0.2
    Dependencies:
        - PSWindowsUpdate module (will be installed if needed)
        - Internet connectivity
    Changelog:
        v1.0.2
        - Added changelog.
        v1.0.1
        - Initial Release.
#>
param (
  # Parameter passed from the orchestrator script (TO.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Parameter passed from the orchestrator script (TO.ps1) for centralized logging.
  [Parameter(Mandatory=$true)]
  [string]$LogDir
)

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
# This script will now create its own file named WUA.txt inside the provided log directory.
$LogFile = Join-Path $LogDir "WUA.txt"


# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created by WUA.ps1." | Out-File $LogFile -Append
}

# Get the full path of the current script, which is needed for creating the startup shortcut.
$ScriptPath = $MyInvocation.MyCommand.Path

# Define the target path for the startup shortcut. This shortcut ensures the script
# can re-run automatically after a system reboot if updates require it.
$StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WUA.lnk"



# Log the initial message indicating the script has started, using the Log function.
Log "Starting Windows Update Automation script v1.0.2..." "INFO"

# ==================== Ensure PSWindowsUpdate Module ====================
#
# This section verifies the presence of the `PSWindowsUpdate` module, which is crucial
# for interacting with Windows Update services. If it's missing, the script attempts to install it.
#
Log "Checking for PSWindowsUpdate module..."
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Log "PSWindowsUpdate module not found. Installing..."
    try {
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
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
        
        # Enable system restore on the system drive.
        $SystemDrive = (Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Root -eq "$env:SystemDrive\"}).Name
        Enable-ComputerRestore -Drive "$SystemDrive\"
        Log "Enabled VSS and System Restore."
        
        # Create the actual restore point with a descriptive name.
        # `RestorePointType "MODIFY_SETTINGS"` is appropriate for system changes.
        Checkpoint-Computer -Description "Pre-WUA_Script" -RestorePointType "MODIFY_SETTINGS"
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
            Log "Reboot is required to complete Windows Updates." -Level "WARN" 
            
            if ($VerboseMode) {
                # In verbose mode, ask for explicit user confirmation before rebooting.
                $confirmReboot = Read-Host "A reboot is required to complete updates. Reboot now? (Y/N)"
                if ($confirmReboot.ToUpper() -eq 'Y') {
                    Log "User confirmed reboot. Initiating restart..."
                    Restart-Computer -Force
                    exit # Exit the script after initiating the reboot
                } else {
                    # User denied reboot. The script will continue to the next block.
                    Log "User denied reboot. Script will continue without restarting."
                }
            } else {
                # In silent mode, proceed with the reboot without user confirmation.
                Log "Initiating silent reboot..."
                Restart-Computer -Force
                exit # Exit the script after initiating the reboot
            }
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
