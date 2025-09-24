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
    Version: 1.1.1
    Dependencies:
        - PSWindowsUpdate module (will be installed if needed)
        - Internet connectivity
    Changelog:
        v1.1.1
        - Fixed major update detection to be language-independent by using CategoryIDs.
        v1.1.0
        - Implemented conditional System Restore Point creation, skipping it for minor security/definition updates.
        v1.0.9
        - Refactored System Restore Point creation to be more robust by temporarily bypassing the creation frequency limit.
        v1.0.8
        - Added explicit output of found updates when running in verbose mode.
        v1.0.7
        - Suppressed verbose output from Get-Module to clean up logs.
        v1.0.6
        - Fixed post-reboot script failure by passing the LogDir parameter to the startup shortcut.
        v1.0.5
        - Fixed a bug in restore point creation where the system drive was not correctly identified.
        v1.0.4
        - Changed startup shortcut path to the system-wide 'All Users' folder for multi-user reliability.
        v1.0.3
        - Refactored reboot logic to be more robust and avoid double prompts.
        - Moved startup shortcut creation to only occur when a reboot is required.
        - Ensured the post-reboot script runs with administrator privileges.
        - Made the post-reboot script window visible for better monitoring.
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

# ==================== Module Imports ====================
. "$PSScriptRoot/../modules/Functions.ps1"

# ==================== Log Setup ====================
$LogFile = Join-Path $LogDir "WUA.txt"

# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created by WUA.ps1." | Out-File $LogFile -Append
}

# Get the full path of the current script, which is needed for creating the startup shortcut.
$ScriptPath = $MyInvocation.MyCommand.Path

# Define the target path for the startup shortcut. This shortcut ensures the script
# can re-run automatically after a system reboot if updates require it.
$StartupShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\WUA.lnk"



# Log the initial message indicating the script has started, using the Log function.
Log "Starting Windows Update Automation script v1.1.1..." "INFO"

# ==================== Ensure PSWindowsUpdate Module ====================
#
# This section verifies the presence of the `PSWindowsUpdate` module, which is crucial
# for interacting with Windows Update services. If it's missing, the script attempts to install it.
#
Log "Checking for PSWindowsUpdate module..."
$moduleExists = $false
$originalGetModuleVerbosePreference = $VerbosePreference
try {
    $VerbosePreference = 'SilentlyContinue'
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        $moduleExists = $true
    }
} finally {
    $VerbosePreference = $originalGetModuleVerbosePreference
}
if (-not $moduleExists) {
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
# We temporarily set VerbosePreference to 'SilentlyContinue' to prevent the module's own
# verbose loading messages from cluttering the console, regardless of the script's -VerboseMode setting.
$originalImportVerbosePreference = $VerbosePreference
try {
    $VerbosePreference = 'SilentlyContinue'
    # `-Force` ensures it's imported even if already present or if there are version conflicts.
    Import-Module PSWindowsUpdate -Force
} finally {
    $VerbosePreference = $originalImportVerbosePreference
}
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
        # In VerboseMode, explicitly display the found updates on the console for better visibility.
        $UpdateList | Out-Host
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

    # --- Create Restore Point (if needed) and Install Updates ---
    try {
        # Define GUIDs for update categories.
        # This is language-independent and more robust than checking category names.
        $majorUpdateCategoryIDs = @(
            'e6cf1350-c01b-414d-a695-b0dfb59300f3', # Updates (includes Cumulative Updates)
            'cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83', # Update Rollups
            'b54e7d24-7add-428f-8b75-90a396fa584b', # Service Packs
            '28bc880e-0592-4cbf-8f95-c79b17911d5f', # Feature Packs
            'ebfc1fc5-a0a5-4add-a84a-65a443d2420f'  # Drivers
        )

        # Check if a restore point is needed. An update is considered "major" if it has at least one category
        # that IS in our list of major categories.
        Log "Checking if updates include major changes requiring a restore point..."
        $majorUpdate = $UpdateList | Where-Object {
            # Get all category IDs for the current update.
            $updateCategories = $_.Categories.CategoryID
            # Check if any of the update's categories match our list of major categories.
            $isMajor = $updateCategories | Where-Object { $majorUpdateCategoryIDs -contains $_ }
            # Return true if a match was found.
            $isMajor -ne $null
        } | Select-Object -First 1

        if ($majorUpdate) {
            Log "Major update found ('$($majorUpdate.Title)'). A system restore point will be created."
            # Call the centralized function to create a restore point.
            New-SystemRestorePoint -Description "Pre-WUA_Script"
        } else {
            Log "No major updates (like Cumulative, Feature Packs, etc.) found. Skipping system restore point creation."
        }

        Log "Installing updates..."
        # Save the current $VerbosePreference to restore it later
        $originalVerbosePreference = $VerbosePreference
        try {
            $InstallationResult = $null # Initialize variable to hold results
            # Conditionally apply -Verbose and capture the output of Install-WindowsUpdate
            if ($VerboseMode) {
                # -IgnoreReboot prevents the module from prompting, allowing our custom logic below to handle it.
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose -IgnoreReboot
            } else {
                # Temporarily set $VerbosePreference to suppress verbose output
                $VerbosePreference = 'SilentlyContinue'
                # -IgnoreReboot prevents the module from prompting, allowing our custom logic below to handle it.
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
            }
        } finally {
            # Always restore the original $VerbosePreference
            $VerbosePreference = $originalVerbosePreference
        }
        
        # --- Check for pending reboot after installation based on installation results ---
        Log "Update installation completed. Checking if a reboot is needed based on installation results..."
        
        $rebootPending = $false
        # Check if any of the installation results require a reboot.
        if ($InstallationResult.RebootRequired -contains $true) {
            $rebootPending = $true
        }

        if ($rebootPending) {
            Log "Reboot is required to complete Windows Updates." -Level "WARN" 
            
            if (-not (Test-Path $StartupShortcut)) {
                Log "Adding script shortcut to Startup folder to continue after reboot."
                $WScriptShell = New-Object -ComObject WScript.Shell
                $Shortcut = $WScriptShell.CreateShortcut($StartupShortcut)
                $Shortcut.TargetPath = "powershell.exe"
                $argumentList = "-ExecutionPolicy Bypass -File \""$ScriptPath\"" -LogDir \""$LogDir\"""
                $command = "Start-Process PowerShell.exe -ArgumentList '$argumentList' -Verb RunAs"
                $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
                $encodedCommand = [Convert]::ToBase64String($bytes)
                $Shortcut.Arguments = "-NoProfile -EncodedCommand $encodedCommand"
                $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
                $Shortcut.Save()
                Log "Shortcut added successfully."
            }

            $proceedWithReboot = $false
            if (-not $VerboseMode) {
                $proceedWithReboot = $true # Silent mode, always reboot.
            } else {
                $confirmReboot = Read-Host "A reboot is required to complete updates. Reboot now? (Y/N)"
                if ($confirmReboot.ToUpper() -eq 'Y') {
                    $proceedWithReboot = $true
                }
            }

            if ($proceedWithReboot) {
                Log "Initiating restart..."
                Restart-Computer -Force
                exit # Exit the script after initiating the reboot
            } else {
                Log "User denied reboot. The script will exit. Please reboot the machine later to complete updates."
                exit # Exit to preserve the startup shortcut for the next manual reboot.
            }
        }
        
        Log "No reboot required. Script execution will continue to cleanup."
    } catch {
        Log "An error occurred during the update process: $_" -Level "ERROR"
    }
} else {
    Log "No pending updates found."
}

# ==================== Script Completion and Cleanup ====================
#
# This final section is reached only if no updates were found, or if updates
# were installed and no reboot was required. It removes the startup shortcut
# as it is no longer needed.
#
if (Test-Path $StartupShortcut) {
    try {
        Log "Update process complete. Removing script shortcut from Startup folder."
        Remove-Item $StartupShortcut -Force # Force removal without prompt.
        Log "Shortcut removed successfully."
    } catch {
        # Log any errors encountered while trying to remove the shortcut.
        Log "Failed to remove Startup shortcut: $_" -Level "ERROR"
    }
}

# Log a final message indicating the script has finished its execution.
Log "Script execution completed."
