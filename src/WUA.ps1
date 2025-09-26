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

# --- Cleanup from previous runs ---
# Always attempt to remove the startup shortcut at the beginning of a run.
# This ensures that if the script is running after a reboot, it cleans up after itself.
if (Test-Path $StartupShortcut) {
    Log "Found existing startup shortcut. Removing it to prevent re-execution loops."
    Remove-Item $StartupShortcut -Force -ErrorAction SilentlyContinue
}


# ==================== Ensure PSWindowsUpdate Module ====================
#
# This section verifies the presence of the `PSWindowsUpdate` module, which is crucial
# for interacting with Windows Update services. If it's missing, the script attempts to install it.
#
Log "Checking for PSWindowsUpdate module..."
# Use Get-Command for a much faster check. If a key command from the module exists, the module is installed.
if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
    Log "PSWindowsUpdate module already installed."
} else {
    Log "PSWindowsUpdate module not found. Installing..."
    try {
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
        Log "PSWindowsUpdate module installed successfully."
    } catch {
        # If module installation fails, log an error and terminate the script.
        Log "Failed to install PSWindowsUpdate module: $_" -Level "ERROR"
        exit 1 # Exit with a non-zero code to indicate an error state.
    }
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
            'ebfc1fc5-a0a5-4add-a84a-65a443d2420f', # Drivers
            'f183b99b-5587-4282-928c-a24351336e68'  # Firmware
        )

        $minorUpdateCategoryIDs = @(
            'e0789628-ce08-4437-be74-2495b842f43b', # Definition Updates
            '0fa1201d-4330-4fa8-8ae9-b877473b6441'  # Security Intelligence Updates
        )

        # Check if a restore point is needed. An update is considered "major" if it has at least one category
        # that IS in our list of major categories OR if its title indicates it's a cumulative update.
        Log "Checking if updates include major changes requiring a restore point..."
        $majorUpdate = $UpdateList | Where-Object {
            # Get all category IDs for the current update.
            $updateCategories = $_.Categories.CategoryID

            # --- Check 1: Exclude if it's explicitly a minor update category ---
            $isMinorUpdate = ($updateCategories | Where-Object { $minorUpdateCategoryIDs -contains $_ }) -ne $null
            if ($isMinorUpdate) { return $false } # Immediately exclude definition/security intelligence updates

            # --- Check 2: Is it in a major category? ---
            $isMajorByCategory = ($updateCategories | Where-Object { $majorUpdateCategoryIDs -contains $_ }) -ne $null
            
            # --- Check 3: Does the title contain a KB number? (Language-independent) ---
            # This is a reliable way to catch cumulative updates, rollups, etc., regardless of language.
            $hasKbNumber = $_.Title -match '\(KB\d{6,}\)'

            # Return true if it's a major category or has a KB number.
            $isMajorByCategory -or $hasKbNumber
        } | Select-Object -First 1

        if ($majorUpdate) {
            Log "Major update found ('$($majorUpdate.Title)'). A system restore point will be created."
            # Call the centralized function to create a restore point.
            New-SystemRestorePoint -Description "Pre-WUA_Script"
        } else {
            Log "No major updates (like Cumulative, Feature Packs, etc.) found. Skipping system restore point creation."
        }

        # --- Check for sufficient disk space before proceeding with download ---
        if (-not (Test-FreeDiskSpace -MinimumFreeGB 20)) {
            Log "Insufficient disk space to download updates. Skipping Windows Updates. Please free up disk space and try again." -Level "WARN"
            Log "==== WUA Script Completed ===="
            # Using 'return' here to exit the script gracefully from within the try block.
            return
        }

        Log "Downloading updates... This may take some time."
        if ($VerboseMode) {
            Log "Verbose mode enabled. Displaying detailed download progress." "INFO"
            $UpdateSession = New-Object -ComObject "Microsoft.Update.Session"
            $UpdateDownloader = $UpdateSession.CreateUpdateDownloader()
            $UpdateDownloader.Updates = $UpdateList
            $DownloadJob = $UpdateDownloader.BeginDownload({ Write-Host "Download callback invoked." }, { Write-Host "Download state changed." }, $null)

            while (-not $DownloadJob.IsCompleted) {
                $downloadProgress = $DownloadJob.GetProgress()
                $currentUpdateIndex = $downloadProgress.CurrentUpdateIndex + 1
                $currentUpdate = $UpdateList[$downloadProgress.CurrentUpdateIndex]
                $percentComplete = $downloadProgress.PercentComplete

                # Calculate progress for the current update
                $currentUpdateBytesDownloaded = $downloadProgress.CurrentUpdateBytesDownloaded / 1MB
                $currentUpdateBytesToDownload = $downloadProgress.CurrentUpdateBytesToDownload / 1MB
                $currentUpdatePercent = 0
                if ($currentUpdateBytesToDownload -gt 0) {
                    $currentUpdatePercent = ($currentUpdateBytesDownloaded / $currentUpdateBytesToDownload) * 100
                }

                # Display detailed progress
                $status = "Overall: $percentComplete% | Current ($currentUpdateIndex of $($UpdateList.Count)): {0:N2} MB / {1:N2} MB" -f $currentUpdateBytesDownloaded, $currentUpdateBytesToDownload
                Write-Progress -Activity "Downloading Windows Updates" -Status $status -Id 1 -PercentComplete $percentComplete
                Write-Progress -Activity "Downloading: $($currentUpdate.Title)" -ParentId 1 -Id 2 -PercentComplete $currentUpdatePercent

                Start-Sleep -Milliseconds 500
            }
            # Finalize the download job
            $UpdateDownloader.EndDownload($DownloadJob) | Out-Null
            Write-Progress -Activity "Downloading Windows Updates" -Completed -Id 1
        } else {
            # Original behavior for silent mode
            $originalVerbosePreference = $VerbosePreference
            try {
                $VerbosePreference = 'SilentlyContinue'
                Download-WindowsUpdate -MicrosoftUpdate -AcceptAll
            } finally {
                $VerbosePreference = $originalVerbosePreference
            }
        }
        Log "Update download completed."

        Log "Installing downloaded updates..."
        $originalVerbosePreference = $VerbosePreference
        try {
            $InstallationResult = $null # Initialize variable to hold results
            # Step 2: Install the already downloaded updates.
            if ($VerboseMode) {
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose -IgnoreReboot
            } else {
                $VerbosePreference = 'SilentlyContinue'
                $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
            }
        } finally {
            $VerbosePreference = $originalVerbosePreference
        }

        # --- Verify that updates were actually installed ---
        # We use the original $UpdateList to check status, as Install-WindowsUpdate may not return objects when installing pre-downloaded updates.
        $successfullyInstalledCount = ($UpdateList | Where-Object { $_.IsInstalled }).Count
        $totalUpdatesAttempted = $UpdateList.Count

        # If some or all updates failed to install, attempt a repair and retry.
        if ($successfullyInstalledCount -lt $totalUpdatesAttempted) {
            $failedUpdates = $UpdateList | Where-Object { -not $_.IsInstalled }
            if ($failedUpdates) {
                Log "The following updates failed to install on the first attempt:" "WARN"
                foreach ($update in $failedUpdates) {
                    Log "  - $($update.Title)" "WARN"
                }
            }

            Log "Initial update installation failed for one or more updates. Attempting system repair before retrying." "WARN"
            
            # Invoke the REPAIR.ps1 script.
            Invoke-Script -ScriptName "REPAIR.ps1" -ScriptDir $PSScriptRoot -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}

            Log "Retrying installation of downloaded updates after repair attempt..." "INFO"
            $originalVerbosePreference = $VerbosePreference
            try {
                if ($VerboseMode) {
                    $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose -IgnoreReboot
                } else {
                    $VerbosePreference = 'SilentlyContinue'
                    $InstallationResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
                }
            } finally {
                $VerbosePreference = $originalVerbosePreference
            }
        }

        # --- Final check for pending reboot and installation status ---
        Log "Update installation process completed. Checking final status and if a reboot is needed..."
        # Re-check the count after a potential retry.
        $finalInstalledCount = ($UpdateList | Where-Object { $_.IsInstalled }).Count
        if ($finalInstalledCount -eq 0 -and $totalUpdatesAttempted -gt 0) {
            Log "The PSWindowsUpdate module reported that 0 updates were successfully installed. The installation may have failed silently." "ERROR"
            Log "Please check the Windows Update logs for more details (e.g., in Event Viewer or C:\Windows\WindowsUpdate.log)." "ERROR"
        }

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

                # Build the argument list for the post-reboot script, including VerboseMode if it was originally set.
                $postRebootArgs = "-ExecutionPolicy Bypass -File `"$ScriptPath`" -LogDir `"$LogDir`""
                if ($VerboseMode) {
                    $postRebootArgs += " -VerboseMode"
                }

                $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
                # Use -Command to wrap the execution. This is simpler and more reliable than Base64 encoding.
                $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& { Start-Process powershell.exe -ArgumentList '$postRebootArgs' -Verb RunAs }`""
                $Shortcut.WorkingDirectory = Split-Path -Path $ScriptPath
                $Shortcut.Description = "Continues Windows Update script after reboot."
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
        Log "An error occurred during the update installation or reboot handling: $_" -Level "ERROR"
    }
} else {
    Log "No pending updates found."
}

# Log a final message indicating the script has finished its execution.
Log "Script execution completed."
