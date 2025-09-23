# ================================================== 
# Functions.ps1
# Version: 1.0.18
# Contains reusable functions for the IT maintenance project.
# ================================================== 
#
# ================== Change Log ================== 
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

# ================== FUNCTION: REPAIR SYSTEM FILES (SFC & DISM) ==================
# Runs SFC and DISM to check for and repair Windows system file corruption.
function Repair-SystemFiles {
    Log "Starting system file integrity check and repair process..." "INFO"

    # --- Define paths to system executables, handling 32/64-bit redirection ---
    $sfcPath = ""
    $dismPath = ""
    # Check if running as a 32-bit process on a 64-bit OS (WoW64)
    if ($env:PROCESSOR_ARCHITECTURE -eq 'x86' -and $env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
        Log "Detected 32-bit PowerShell on 64-bit Windows. Using Sysnative path for system tools." "DEBUG"
        $sfcPath = "$env:windir\Sysnative\sfc.exe"
        $dismPath = "$env:windir\Sysnative\dism.exe"
    } else {
        Log "Detected 64-bit PowerShell or 32-bit on 32-bit Windows. Using System32 path." "DEBUG"
        $sfcPath = "$env:windir\System32\sfc.exe"
        $dismPath = "$env:windir\System32\dism.exe"
    }

    # Verify that the executables can be found at the determined paths.
    if (-not (Test-Path $sfcPath)) {
        Log "Could not find sfc.exe at the expected path: $sfcPath. This can happen if the script is run in a 32-bit PowerShell console on a 64-bit system. Please use a 64-bit PowerShell console. Aborting." "ERROR"
        return
    }

    # --- Step 1: Run SFC in verification mode and parse console output ---
    try {
        Log "Running System File Checker (SFC) in verification-only mode..." "INFO"
        # Use the .NET Process class for robust output handling and real-time display.
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $sfcPath
        $pinfo.Arguments = "/verifyonly"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        # sfc.exe outputs Unicode, so we must specify the encoding to read it correctly.
        $pinfo.StandardOutputEncoding = [System.Text.Encoding]::Unicode
        $pinfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo

        # Use a synchronized list to store output from multiple event handler threads.
        $outputLines = [System.Collections.ArrayList]::Synchronized( (New-Object System.Collections.ArrayList) )

        # Register event handlers to capture output data as it is generated.
        # Use .GetNewClosure() to ensure the event handler scriptblocks can access local variables ($outputLines, $VerboseMode).
        $outputHandler = {
            param($source, $e)
            if ($e.Data) {
                [void]$outputLines.Add($e.Data)
                if ($VerboseMode) { Write-Host $e.Data } # Display in real-time if in verbose mode.
            }
        }.GetNewClosure()

        $errorHandler = {
            param($source, $e)
            if ($e.Data) {
                [void]$outputLines.Add($e.Data)
                if ($VerboseMode) { Write-Host $e.Data -ForegroundColor Yellow } # Display errors in real-time.
            }
        }.GetNewClosure()

        # Explicitly create the delegate types from the script blocks.
        # This makes the intent clear and can provide better errors if the script block is incompatible.
        $outputDelegate = [System.Diagnostics.DataReceivedEventHandler]$outputHandler
        $errorDelegate = [System.Diagnostics.DataReceivedEventHandler]$errorHandler

        # Use the add_EventName syntax to subscribe to the events using the created delegates.
        $p.add_OutputDataReceived($outputDelegate)
        $p.add_ErrorDataReceived($errorDelegate)

        try {
            $p.Start() | Out-Null
            $p.BeginOutputReadLine()
            $p.BeginErrorReadLine()

            $p.WaitForExit()
            $exitCode = $p.ExitCode
        } finally {
            # Unsubscribe from events to prevent potential memory leaks.
            $p.remove_OutputDataReceived($outputDelegate)
            $p.remove_ErrorDataReceived($errorDelegate)
        }
        Log "SFC /verifyonly process completed with exit code: $exitCode." "DEBUG"

        $sfcOutputText = $outputLines -join [System.Environment]::NewLine

        # For troubleshooting, save the raw output to a more permanent temp file.
        $sfcLogPath = "$env:TEMP\SFC_VerifyOnly.log"
        $sfcOutputText | Out-File -FilePath $sfcLogPath -Encoding UTF8
        Log "Raw SFC output saved to $sfcLogPath for review." "DEBUG"

        # Normalize the output to handle potential encoding issues from sfc.exe (e.g., extra spaces/nulls).
        # We remove all non-alphanumeric characters and convert to lowercase for a reliable match.
        $normalizedOutput = ($sfcOutputText -replace '[^a-zA-Z0-9]').ToLower()
        Log "Normalized SFC output for parsing: $normalizedOutput" "DEBUG"

        # Define spaceless, lowercase patterns for matching. These are robust against the encoding issues.
        $successPattern = "windowsresourceprotectiondidnotfindanyintegrityviolations"
        $foundPattern = "windowsresourceprotectionfoundintegrityviolations"
        $couldnotPattern = "windowsresourceprotectioncouldnotperformtherequestedoperation"

        if ($normalizedOutput -match $successPattern) {
            Log "SFC verification completed. No integrity violations found. System files are healthy." "INFO"
            return
        } elseif ($normalizedOutput -match $foundPattern) {
            Log "SFC verification found integrity violations. A repair will be initiated." "WARN"
        } elseif ($normalizedOutput -match $couldnotPattern) {
            Log "SFC could not perform the requested operation. Proceeding with repair." "WARN"
        } else {
            # This catches other messages or errors, ensuring we proceed with repair as a safe default.
            Log "SFC output could not be parsed reliably. Proceeding with repair as a precaution. Full output: $sfcOutputText" "WARN"
        }
    } catch {
        Log "An unexpected error occurred during SFC /verifyonly operation: $($_.Exception.Message)" "ERROR"
        Log "Assuming a repair is needed due to the error." "WARN"
    }

    # --- Step 2: If we reached this point, a repair is needed. Confirm with user if in verbose mode. ---
    $proceedWithRepair = $false
    if ($VerboseMode) {
        # Interactive mode: Ask the user.
        $choice = Read-Host "SFC found potential issues. Do you wish to run a full repair (DISM & SFC /scannow)? (Y/N)"
        if ($choice -match '^(?i)y(es)?$') {
            $proceedWithRepair = $true
        }
    } else {
        # Silent mode: Proceed automatically.
        Log "Silent mode enabled. Proceeding with repair automatically." "INFO"
        $proceedWithRepair = $true
    }

    if (-not $proceedWithRepair) {
        Log "User chose not to proceed with the system file repair. Skipping." "INFO"
        return
    }

    # Internal helper to run external commands, respecting the VerboseMode switch.
    # Defined here so it's only created if a repair is actually running.
    $InvokeElevatedCommand = {
        param(
            [string]$FilePath,
            [string]$Arguments,
            [string]$LogName
        )

        Log "Executing: $FilePath $Arguments" "INFO"
        # In verbose mode, show real-time output. Otherwise, just run it.
        if ($VerboseMode) {
            Log "The output of this command will be displayed directly in the console for real-time progress." "INFO"
            $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
            $exitCode = $process.ExitCode
        } else {
            $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
            $exitCode = $process.ExitCode
        }
        Log "$LogName process finished with exit code: $exitCode." "INFO"
        return $exitCode
    }

    # --- Step 3: Run DISM to ensure the component store is healthy ---
    try {
        Log "Running DISM to check and repair the Windows Component Store. This may take a long time..." "INFO"
        $dismExitCode = & $InvokeElevatedCommand -FilePath $dismPath -Arguments "/Online /Cleanup-Image /RestoreHealth" -LogName "DISM"

        if ($dismExitCode -eq 0) {
            Log "DISM completed successfully. The component store is healthy." "INFO"
        } else {
            Log "DISM finished with a non-zero exit code ($dismExitCode). The component store may have issues. See DISM logs for details." "WARN"
        }
    } catch {
        Log "An unexpected error occurred while running DISM: $($_.Exception.Message)" "ERROR"
        Log "Proceeding to SFC despite DISM error." "WARN"
    }

    # --- Step 4: Run SFC in repair mode ---
    try {
        Log "Running System File Checker (SFC) in repair mode (scannow)..." "INFO"
        & $InvokeElevatedCommand -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC Scan"
        Log "SFC /scannow process completed. Please review the output above for results." "INFO"
    } catch {
        Log "An unexpected error occurred during SFC /scannow operation: $($_.Exception.Message)" "ERROR"
    }
}
