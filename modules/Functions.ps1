# ================================================== 
# Functions.ps1
# Version: 1.0.18
# Contains reusable functions for the IT maintenance project.
# ================================================== 
#
# ================== Change Log ================== 
#
# V 1.0.19
# - Moved the `Repair-SystemFiles` function to a new standalone script, `src/REPAIR.ps1`, to better handle reboots.
#
# V 1.0.18
# - Updated `Invoke-Script` to accept a hashtable of parameters (`$ScriptParameters`) for more flexible child script execution.
# V 1.0.17
# - Moved `Invoke-Script`, `Confirm-OfficeInstalled`, and `Repair-SystemFiles` functions from TO.ps1 to this module for better centralization and reusability.
# - Adapted `Invoke-Script` to accept a `$ScriptDir` parameter.
# V 1.0.16
# - Cleaned up and fixed logic in `Restore-PowerPlan` to prevent errors when the original plan is the same as the temporary plan.
# V 1.0.15
# - Refactored power plan logic into `Set-TemporaryMaxPerformancePlan` and `Restore-PowerPlan` functions.
# - Fixed bug in `Restore-PowerPlan` that caused an error message when deleting the temporary plan.
# V 1.0.14
# - Updated `Install-NuGetProvider` to use a non-interactive check for the provider.
# V 1.0.13
# - Fixed error in `Install-NuGetProvider` when registry key is missing.
# V 1.0.12
# - Refactored `Uninstall-Chocolatey` to remove duplicate code and fixed syntax errors.
# V 1.0.11
# - Updated logging and module installation.
# V 1.0.10
# - Reverted debug logging from Log function.
# V 1.0.9
# - Added debug logging to Log function for troubleshooting.
# V 1.0.8
# - Improved logging and module installation robustness.
# V 1.0.7
# - Updated Save-File to show download speed
# V 1.0.6
# - Initial Release
#
# ================================================== 

# ================== DEFINE LOG FUNCTION ================== 
# A custom logging function to write messages to the console (if verbose mode is on)
# and to a persistent log file.
function Log {
    param (
        [string]$Message,                                     # The message to be logged
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")] # Validation for log level
        [string]$Level = "INFO"                               # Default log level is INFO
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss" # Format the current date and time
    $logEntry = "[$timestamp] [$Level] $Message"      # Construct the full log entry string

    try {
        # Attempt to append the log entry to the specified log file.
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If writing to the log file fails, output an error to the console.
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # If VerboseMode is enabled or the log level is ERROR, also output to the console.
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Determine the console foreground color based on the log level.
        $color = switch ($Level) {
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Gray" }
            default { "White" } # Default color if level is not recognized
        }
        Write-Host $logEntry -ForegroundColor $color # Output the log entry to the console
    }
}

# =================================================================================
# Install-NuGetProvider
# Checks if the NuGet provider is installed. If not, it silently downloads and 
# registers it using a robust, non-interactive method.
# =================================================================================
function Install-NuGetProvider {
    Log "Checking for existing NuGet provider..."

    # List all available package providers and filter for 'NuGet'.
    # This is a non-interactive way to check if the provider is installed,
    # avoiding any potential automatic installation prompts.
    $provider = Get-PackageProvider -ListAvailable | Where-Object { $_.Name -eq 'NuGet' }

    # Check if a provider was found. If not, proceed with installation.
    if (-not $provider) {
        Log "NuGet provider not found. Beginning installation..."
        try {
            # Use -Force and -Confirm:$false to ensure a non-interactive installation.
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force -Confirm:$false -ErrorAction Stop
            
            Log "NuGet provider installation successful."
            
        } catch {
            Log "FATAL ERROR: Failed to install NuGet provider: $($_.Exception.Message)" -Level "ERROR"
            exit 1
        }
    } else {
        # This branch will execute if the provider was successfully found.
        Log "NuGet provider is already installed. Continuing."
    }
}


# ==================== Helper Function: Install Chocolatey ====================
#
# Function: Install-Chocolatey
# Description: Checks if Chocolatey is installed and, if not, installs it.
#              This function is critical for installing software packages not
#              available via Winget.
#
# Prerequisites:
#   - Internet connectivity.
#   - PowerShell Execution Policy set to Bypass (handled by WUH.ps1 or temporarily here).
#
# Returns:
#   - $true if Chocolatey is successfully installed or already present.
#   - $false if Chocolatey installation fails.
#
function Install-Chocolatey {
    Log "Checking for Chocolatey installation..." "INFO"
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Log "Chocolatey not found. Attempting to install Chocolatey..." "INFO"
        try {
            # Temporarily set execution policy to Bypass for the current process
            # to allow the Chocolatey installation script to run.
            # This is safer than modifying global policy.
            $originalProcessPolicy = Get-ExecutionPolicy -Scope Process
            Set-ExecutionPolicy Bypass -Scope Process -Force

            # Ensure TLS1.2 is enabled for the download.
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

            # Download and execute the Chocolatey installation script.
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

            # Check if choco.exe is now available to confirm installation.
            if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
                Log "Chocolatey installed successfully." "INFO"
                return $true
            } else {
                Log "Chocolatey installation completed, but choco.exe not found. Something went wrong." "ERROR"
                return $false
            }
        } catch {
            Log "Failed to install Chocolatey: $_" "ERROR"
            return $false
        } finally {
            # Restore the execution policy for the current process.
            Set-ExecutionPolicy $originalProcessPolicy -Scope Process -Force
        }
    } else {
        Log "Chocolatey is already installed." "INFO"
        return $true
    }
}

# ==================== Helper Function: Uninstall Chocolatey ====================
#
# Function: Uninstall-Chocolatey
# Description: Uninstalls Chocolatey from the system. This is intended for cleanup
#              if Chocolatey was only needed temporarily for machine preparation.
#
# Returns:
#   - $true if Chocolatey is successfully uninstalled or not found.
#   - $false if Chocolatey uninstallation fails.
#
function Uninstall-Chocolatey {
    Log "Checking for Chocolatey to uninstall..." "INFO"
    $chocoInstallPath = "$env:ProgramData\chocolatey" # Default Chocolatey installation path
    $chocoTempPath = "$env:TEMP\chocolatey"           # Temporary Chocolatey folder

    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        Log "Chocolatey found. Attempting to uninstall Chocolatey..." "INFO"
        try {
            # === NEW: Terminate any processes that might be locking files ===
            Log "Checking for and stopping any running Chocolatey processes..." "INFO"
            $chocoProcesses = Get-Process -Name "choco*" -ErrorAction SilentlyContinue
            if ($chocoProcesses) {
                foreach ($process in $chocoProcesses) {
                    Log "Stopping process '$($process.ProcessName)' with ID $($process.Id)." "INFO"
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            } else {
                Log "No Chocolatey-related processes found." "INFO"
            }
            
            # Attempt to uninstall Chocolatey package
            choco uninstall chocolatey -y
        } catch {
            Log "Failed during Chocolatey uninstallation: $_" "ERROR"
        }
    } else {
        Log "Chocolatey is not installed. No uninstallation needed for the package." "INFO"
    }

    # Perform additional cleanup for Chocolatey-related directories and environment variables
    # This block runs regardless of whether choco.exe was found, to clean up any lingering files.
    Log "Performing cleanup for Chocolatey directories and environment variables." "INFO"

    try {
        # Delete ChocolateyBinRoot if it exists and unset its environment variable
        if ($env:ChocolateyBinRoot -ne '' -and $null -ne $env:ChocolateyBinRoot -and (Test-Path "$env:ChocolateyBinRoot")) {
            Log "Deleting ChocolateyBinRoot: $($env:ChocolateyBinRoot)" "INFO"
            Remove-Item -Recurse -Force "$env:ChocolateyBinRoot" -ErrorAction SilentlyContinue
            [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'Machine') # Unset machine-wide
            [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'User')    # Unset user-specific
        }

        # Delete ChocolateyToolsRoot if it exists and unset its environment variable
        if ($env:ChocolateyToolsRoot -ne '' -and $null -ne $env:ChocolateyToolsRoot -and (Test-Path "$env:ChocolateyToolsRoot")) {
            Log "Deleting ChocolateyToolsRoot: $($env:ChocolateyToolsRoot)" "INFO"
            Remove-Item -Recurse -Force "$env:ChocolateyToolsRoot" -ErrorAction SilentlyContinue
            [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'Machine') # Unset machine-wide
            [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'User')    # Unset user-specific
        }

        # Check and delete the main Chocolatey installation folder if it still exists
        if (Test-Path $chocoInstallPath) {
            Log "Main Chocolatey installation folder still exists: $chocoInstallPath. Deleting it." "INFO"
            Remove-Item -Path $chocoInstallPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Delete the temporary Chocolatey folder
        if (Test-Path $chocoTempPath) {
            Log "Deleting temporary Chocolatey folder: $chocoTempPath." "INFO"
            Remove-Item -Path $chocoTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Final verification if choco.exe is gone
        if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
            Log "Chocolatey cleanup completed successfully." "INFO"
            return $true
        } else {
            Log "Chocolatey cleanup completed, but choco.exe still present. Manual check may be required." "WARN"
            return $false
        }
    } catch {
        Log "An error occurred during Chocolatey cleanup: $_" "ERROR"
        return $false
    }
}


# ==================== Helper Function: Save-File ====================
#
# Function: Save-File
# Description: Downloads a file from a URL and saves it to a specified path.
#
# Parameters:
#   - Url (string): The URL of the file to download.
#   - OutputPath (string): The path to save the file to.
#
# Returns:
#   - $true if the file is downloaded successfully.
#   - $false if the download fails.
#
function Save-File {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    Log "Downloading $Url to $OutputPath..." "INFO"
    try {
        C:\Windows\System32\curl.exe -L --output $OutputPath --write-out "Downloaded %{filename_effective} in %{time_total}s, Average Speed: %{speed_download} B/s\n" $Url
        Log "Successfully downloaded $Url." "INFO"
        return $true
    } catch {
        Log "ERROR: Failed to download $Url. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# =================================================================================
# Set-TemporaryMaxPerformancePlan
# Creates and activates a temporary "Maximum Performance" power plan.
# Returns a hashtable with original and temporary plan details.
# =================================================================================
function Set-TemporaryMaxPerformancePlan {
    param(
        [string]$TempPlanName = "TempMaxPerformance"
    )

    # --- Store the currently active power plan to restore it later ---
    $originalActivePlanGuid = $null
    try {
        $originalActivePlanGuid = (powercfg -getactivescheme).Split(' ')[3]
        Log "Original active power plan GUID captured: $originalActivePlanGuid" "INFO"
    } catch {
        Log "Could not capture the original active power plan. Will default to 'Balanced' on exit." "WARN"
    }

    Log "Creating temporary Maximum Performance power plan..."
    $tempPlanGuid = $null
    try {
        # Well-known GUID for the "High performance" power plan.
        $highPerformanceGuid = "8c5e7fd1-ce92-466d-be55-c3230502e679"
        $baseSchemeExists = (powercfg -list | Select-String -Pattern $highPerformanceGuid -Quiet)

        # First, try to find if our custom plan already exists (from a previous run)
        $existingTempPlanLine = (powercfg -list | Where-Object { $_ -match [regex]::Escape($TempPlanName) } | Select-Object -First 1)
        if ($existingTempPlanLine) {
            $tempPlanGuid = ($existingTempPlanLine -split '\s+')[3] # Extract GUID from line
            Log "Found an existing temporary power plan named '$TempPlanName' with GUID: $tempPlanGuid. Will attempt to activate it." "INFO"
        }
        
        # If a temporary plan wasn't found, proceed to create/duplicate
        if (-not $tempPlanGuid) {
            if ($baseSchemeExists) {
                # Option 1: Duplicate the standard "High performance" plan if it exists
                Log "High Performance power plan (GUID: $highPerformanceGuid) found. Duplicating it." "INFO"
                $newGuidOutput = (powercfg -duplicatescheme $highPerformanceGuid 2>&1).Trim()
                if ($LASTEXITCODE -eq 0 -and $newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                    $tempPlanGuid = $Matches[1]
                    Log "Duplicated High Performance plan to new GUID: $tempPlanGuid." "INFO"
                } else {
                    Log "Failed to duplicate High Performance plan. Output: '$newGuidOutput', Exit Code: $LASTEXITCODE. Trying to find existing temporary plan, or creating from Balanced." "WARN"
                }
            } 
            
            # Fallback if High Performance didn't exist or duplication failed
            if (-not $tempPlanGuid) {
                Log "Creating a new 'High Performance-like' custom plan from 'Balanced'." "WARN"
                
                $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
                $newGuidOutput = (powercfg -duplicatescheme $balancedGuid 2>&1).Trim()
                if ($LASTEXITCODE -eq 0 -and $newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                    $tempPlanGuid = $Matches[1]
                    Log "Duplicated 'Balanced' plan as a base for a new custom plan, GUID: $tempPlanGuid." "INFO"

                    # --- Configure Key Settings for Max Performance ---
                    $SetPowerSetting = {
                        param($planGuid, $subgroupGuid, $settingGuid, $value, $description)
                        
                        $acResult = (powercfg -setacvalueindex $planGuid $subgroupGuid $settingGuid $value 2>&1)
                        $acExitCode = $LASTEXITCODE

                        $dcResult = (powercfg -setdcvalueindex $planGuid $subgroupGuid $settingGuid $value 2>&1)
                        $dcExitCode = $LASTEXITCODE

                        $commonErrorPattern = "The power scheme, subgroup or setting specified does not exist"
                        
                        $acAppliedSuccessfully = ($acExitCode -eq 0 -and -not ($acResult -match $commonErrorPattern))
                        $dcAppliedSuccessfully = ($dcExitCode -eq 0 -and -not ($dcResult -match $commonErrorPattern))

                        if ($acAppliedSuccessfully -and $dcAppliedSuccessfully) {
                            Log "$description (AC & DC) set successfully." "INFO"
                        } elseif ($acAppliedSuccessfully -and -not $dcAppliedSuccessfully) {
                            Log "$description (AC) set successfully, but (DC) failed. Output: '$dcResult', Exit Code: $dcExitCode" "WARN"
                        } elseif (-not $acAppliedSuccessfully -and $dcAppliedSuccessfully) {
                            Log "$description (DC) set successfully, but (AC) failed. Output: '$acResult', Exit Code: $acExitCode" "WARN"
                        } else {
                            Log "$description (AC & DC) failed. AC Output: '$acResult', AC Exit Code: $acExitCode. DC Output: '$dcResult', DC Exit Code: $dcExitCode." "WARN"
                        }
                    }

                    & $SetPowerSetting $tempPlanGuid "0012ee47-9041-4b5d-9b77-535fba8b1442" "6738e2c4-e8a5-4a42-b16a-e040e769756e" 0 "Hard disk never turns off"
                    & $SetPowerSetting $tempPlanGuid "54533251-82be-4824-96c1-47b60b740d00" "893dee8e-2bef-41e0-89c6-b55d0929964c" 100 "Minimum processor state set to 100%"
                    & $SetPowerSetting $tempPlanGuid "54533251-82be-4824-96c1-47b60b740d00" "bc5038f7-23e0-4960-96da-33abaf5935ec" 100 "Maximum processor state set to 100%"
                    & $SetPowerSetting $tempPlanGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" 0 "System will not sleep automatically"
                    & $SetPowerSetting $tempPlanGuid "7516b95f-f776-4464-8c53-06167f40cc99" "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" 0 "Display will not turn off automatically"
                    & $SetPowerSetting $tempPlanGuid "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0 "USB selective suspend disabled"

                } else {
                    Log "Failed to duplicate 'Balanced' plan to create a custom plan. Output: '$newGuidOutput', Exit Code: $LASTEXITCODE. Aborting power plan changes." "ERROR"
                    return $null
                }
            }
        }

        if ($tempPlanGuid) {
            Log "Renaming power plan (GUID: $tempPlanGuid) to '$TempPlanName'..." "INFO"
            $renameResult = (powercfg -changename $tempPlanGuid $TempPlanName "Temporary Maximum Performance (Custom)" 2>&1)
            if ($LASTEXITCODE -ne 0) {
                Log "Failed to rename power plan (GUID: $tempPlanGuid) to '$TempPlanName'. Output: '$renameResult', Exit Code: $LASTEXITCODE." "WARN"
            }
            
            Log "Activating '$TempPlanName' power plan with GUID: $tempPlanGuid..." "INFO"
            $activateResult = (powercfg -setactive $tempPlanGuid 2>&1)
            if ($LASTEXITCODE -ne 0) {
                Log "Failed to activate '$TempPlanName' power plan (GUID: $tempPlanGuid). Output: '$activateResult', Exit Code: $LASTEXITCODE." "ERROR"
            }
        } else {
            Log "Could not create or find a suitable power plan for activation. Power plan changes skipped." "ERROR"
        }

    } catch {
        Log "An unexpected error occurred during power plan creation or setting: $($_.Exception.Message)" "ERROR"
    }

    return @{
        OriginalPlanGuid = $originalActivePlanGuid
        TempPlanGuid     = $tempPlanGuid
        TempPlanName     = $TempPlanName
    }
}

# =================================================================================
# Restore-PowerPlan
# Restores the original power plan and deletes the temporary one.
# =================================================================================
function Restore-PowerPlan {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PowerPlanInfo
    )

    # --- Restore Original Power Plan ---
    Log "Restoring original power plan..."
    try {
        # If the original plan is valid and different from the temp plan, restore it.
        if ($PowerPlanInfo.OriginalPlanGuid -and ($PowerPlanInfo.OriginalPlanGuid -ne $PowerPlanInfo.TempPlanGuid)) {
            powercfg -setactive $PowerPlanInfo.OriginalPlanGuid
            Log "Successfully restored original power plan (GUID: $($PowerPlanInfo.OriginalPlanGuid))."
        } else {
            # Otherwise, switch to the 'Balanced' plan. This ensures we are not on the temporary plan
            # before attempting to delete it, preventing the "cannot delete active scheme" error.
            Log "Original plan not available or is the same as the temp plan. Setting to 'Balanced' before cleanup." "WARN"
            powercfg -setactive "381b4222-f694-41f0-9685-ff5bb260df2e" # SCHEME_BALANCED
            Log "Power plan reset to Balanced."
        }
    } catch {
        Log "Failed to restore the original power plan. Error: $_" "ERROR"
    }

    # --- Remove Temporary Power Plan ---
    Log "Attempting to remove temporary Maximum Performance power plan..."
    try {
        $tempPlanNameToFind = $PowerPlanInfo.TempPlanName
        # Find all GUIDs matching the temporary plan name.
        $guidsToDelete = (powercfg -list | Where-Object { $_ -match [regex]::Escape($tempPlanNameToFind) } | ForEach-Object { ($_ -split '\s+')[3] })
        
        if ($guidsToDelete) {
            # Ensure it's an array and loop through
            foreach ($guid in @($guidsToDelete)) {
                Log "Found temporary power plan '$tempPlanNameToFind' with GUID: $guid. Deleting it."
                powercfg -delete $guid
                if ($LASTEXITCODE -eq 0) {
                    Log "Temporary Maximum Performance power plan removed."
                } else {
                    Log "Failed to remove temporary power plan '$tempPlanNameToFind' (GUID: $guid). Powercfg exited with code $LASTEXITCODE." "WARN"
                }
            }
        } else {
            Log "Temporary Maximum Performance power plan '$tempPlanNameToFind' not found, no deletion needed." "INFO"
        }
    } catch {
        Log "Failed to remove temporary power plan: $_" "ERROR"
    }
}

# =================================================================================
# New-SystemRestorePoint
# Creates a system restore point, temporarily bypassing the creation frequency limit.
# =================================================================================
function New-SystemRestorePoint {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Description
    )

    Log "Attempting to create a system restore point with description: '$Description'..." "INFO"
    $restorePointRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $restorePointFrequencyValueName = "SystemRestorePointCreationFrequency"
    $originalFrequencyValue = $null
    $frequencyValueExisted = $false
    $registryWasAdjusted = $false

    try {
        # Temporarily bypass the default system restore point creation frequency.
        Log "Temporarily adjusting system restore point frequency..." "INFO"
        if (Test-Path $restorePointRegistryPath) {
            $property = Get-ItemProperty -Path $restorePointRegistryPath -Name $restorePointFrequencyValueName -ErrorAction SilentlyContinue
            if ($null -ne $property) {
                $frequencyValueExisted = $true
                $originalFrequencyValue = $property.$restorePointFrequencyValueName
            }
        } else {
            New-Item -Path $restorePointRegistryPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $restorePointRegistryPath -Name $restorePointFrequencyValueName -Value 0 -Type DWord -Force
        $registryWasAdjusted = $true
        Log "System restore point frequency set to 0 to allow immediate creation." "INFO"

        # Enable restore and create the checkpoint.
        Set-Service -Name 'VSS' -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name 'VSS' -ErrorAction SilentlyContinue
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS"
        Log "Restore point '$Description' created successfully." "INFO"
        return $true
    } catch {
        Log "Failed to create a system restore point. Error: $($_.Exception.Message)" "ERROR"
        return $false
    } finally {
        # Restore the default system restore point creation frequency.
        if ($registryWasAdjusted) {
            Log "Restoring original system restore point frequency setting..." "INFO"
            if ($frequencyValueExisted) {
                Set-ItemProperty -Path $restorePointRegistryPath -Name $restorePointFrequencyValueName -Value $originalFrequencyValue -Type DWord -Force
            } else {
                Remove-ItemProperty -Path $restorePointRegistryPath -Name $restorePointFrequencyValueName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# =================================================================================
# Test-FreeDiskSpace
# Tests if there is a minimum amount of free disk space on a specified drive.
# =================================================================================
function Test-FreeDiskSpace {
    param (
        [string]$Drive = "$env:SystemDrive",
        [int]$MinimumFreeGB = 20
    )

    try {
        $driveLetter = $Drive.Trim(":")
        $driveInfo = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        $freeSpaceGB = [Math]::Round($driveInfo.Free / 1GB, 2)

        if ($freeSpaceGB -lt $MinimumFreeGB) {
            Log "WARNING: Low disk space on $($Drive): $($freeSpaceGB) GB free, less than $($MinimumFreeGB) GB required." "WARN"
            return $false
        } else {
            Log "Sufficient disk space on $($Drive): $($freeSpaceGB) GB free." "INFO"
            return $true
        }
    } catch {
        Log "ERROR: Unable to check free disk space on $($Drive): $($_.Exception.Message)" "ERROR"
        return $false
    }
}





# =================================================================================
# Invoke-CommandWithLogging
# Executes an external command, captures all output to a log file, and optionally
# displays it in real-time to the console. This is a robust replacement for
# simple Start-Process calls, ensuring no output is ever lost.
# =================================================================================
function Invoke-CommandWithLogging {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [Parameter(Mandatory=$true)][string]$LogName,
        [Parameter(Mandatory=$true)][string]$LogDir,
        [switch]$VerboseMode
    )

    Log "Executing: $FilePath $Arguments" "INFO"
    $commandLogFile = Join-Path $LogDir "$LogName.log"
    Log "Output for this command will be logged to '$($commandLogFile)'" "INFO"
    if ($VerboseMode) {
        Log "The output of this command will be displayed directly in the console for real-time progress." "INFO"
    }

    $exitCode = -1
    try {
        # Start-Transcript captures all console output to a file.
        Start-Transcript -Path $commandLogFile -Append -Force

        # Execute the command directly in the current console using the call operator (&).        
        # This ensures its output is captured by Start-Transcript.
        # We redirect stderr (2) to stdout (1) to capture everything.
        & $FilePath $Arguments 2>&1 | Out-Null

        # Capture the exit code of the last external command.
        $exitCode = $LASTEXITCODE
    } finally {
        # Stop the transcript to finalize the log file.
        Stop-Transcript

        # In non-verbose mode, the transcript includes PowerShell command prompts.
        # This section cleans them up for a cleaner log file.
        if (-not $VerboseMode) {
            $content = Get-Content $commandLogFile -Raw
            # Remove the PowerShell prompt lines and the Stop-Transcript line.
            $cleanedContent = $content -replace '(?m)^PS .*>.*\r?\n' -replace '(?m)^\s*Transcript stopped.*\r?\n'
            Set-Content -Path $commandLogFile -Value $cleanedContent.Trim()
        }
    }

    Log "$LogName process finished with exit code: $exitCode." "INFO"
    return $exitCode
}

# ================== INVOKE SCRIPT FUNCTION ==================
# A centralized function to execute child scripts, passing necessary parameters.
function Invoke-Script {
    param (
        [string]$ScriptName,
        [string]$ScriptDir,
        [switch]$VerboseMode,
        [string]$LogDir,
        [hashtable]$ScriptParameters = @{} # Optional hashtable for additional script parameters.
    )
    $scriptPath = Join-Path $ScriptDir $ScriptName
    Log "Running $ScriptName..."
    try {
        # Combine standard parameters with any custom ones provided.
        $allParams = $ScriptParameters
        $allParams['VerboseMode'] = $VerboseMode
        $allParams['LogDir'] = $LogDir
        $allParams['ErrorAction'] = 'Stop'

        # Use splatting to execute the child script with the combined parameters.
        & $scriptPath @allParams
        Log "$ScriptName executed successfully."
    } catch {
        Log "Error during execution of '$ScriptName': $($_.Exception.Message)" -Level "ERROR"
    }
}

# ================== FUNCTION: CHECK IF OFFICE IS INSTALLED ==================
# Helper function to confirm if Microsoft Office is installed on the system.
function Confirm-OfficeInstalled {
    # Define common installation paths for Microsoft Office (32-bit and 64-bit). Use braces for variable names with special characters.
    $officePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Office", # Common 32-bit path on 64-bit OS
        "${env:ProgramFiles}\Microsoft Office",# Common 64-bit path
        "${env:ProgramW6432}\Microsoft Office"# Alternative 64-bit path
    )
    # Iterate through the paths to check for existence.
    foreach ($path in $officePaths) {
        if (Test-Path $path) {
            return $true # Return true if any Office path is found
        }
    }
    return $false # Return false if no Office paths are found
}
