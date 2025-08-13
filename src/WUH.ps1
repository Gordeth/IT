# ==============================================================================
# PowerShell Maintenance Script
# Version: 1.0.1
# This script automates various machine preparation and Windows maintenance tasks.
# It includes robust logging, internet connectivity checks, execution policy handling,
# and a focus on silent execution for automation.
# ==============================================================================
param (
    [switch]$VerboseMode = $false # Default to false, can be set to true by user input
)

# ================== CONFIGURATION ==================
# Using the built-in variable $PSScriptRoot is the most reliable way to get the script's directory.
# This avoids issues with hardcoded paths that may change.
$ScriptDir = $PSScriptRoot
# The logging and script directories are now consistently based on $PSScriptRoot.
$LogDir = Join-Path $ScriptDir "Log"
$LogFile = Join-Path $LogDir "WUH.txt"

# --- Set the working location to the script's root ---
Set-Location -Path $ScriptDir

# ================== CREATE DIRECTORIES ==================
# Create the log directory if it doesn't exist.
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created." | Out-File $LogFile -Append
}

# ================== LOAD FUNCTIONS MODULE ==================
# This line makes all the functions in your separate Functions.ps1 script available.
# The path is relative to this script's location ($PSScriptRoot).
. "$PSScriptRoot/../modules/Functions.ps1"

# ================== FUNCTION: CHECK IF OFFICE IS INSTALLED ==================
# Helper function to confirm if Microsoft Office is installed on the system.
# This is used to conditionally download/run Office-related update scripts.
function Confirm-OfficeInstalled {
    # Define common installation paths for Microsoft Office (32-bit and 64-bit).
    $officePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Office", # Common 32-bit path on 64-bit OS
        "${env:ProgramFiles}\Microsoft Office",       # Common 64-bit path
        "${env:ProgramW6432}\Microsoft Office"        # Alternative 64-bit path
    )
    # Iterate through the paths to check for existence.
    foreach ($path in $officePaths) {
        if (Test-Path $path) {
            return $true # Return true if any Office path is found
        }
    }
    return $false # Return false if no Office paths are found
}
# ================== FUNCTION: REPAIR SYSTEM FILES (SFC) ==================
# Runs SFC (System File Checker) to verify and optionally repair Windows system files.
# Uses 'verifyonly' first, and if corruption is found, runs 'scannow'.
# This version analyzes CBS.log for results.
function Repair-SystemFiles {
    try {
        Log "Starting System File Checker (SFC) scan. This may take some time..." "INFO"

        $sfcArgs = "/scannow"
        
        if ($VerboseMode) { # Check the main script's $VerboseMode
            Log "Displaying SFC console progress." "INFO"
            # Execute sfc.exe normally; its output will stream live to the console
            sfc.exe $sfcArgs
            $sfcExitCode = $LASTEXITCODE
            Log "SFC scan finished with exit code: $sfcExitCode" "INFO"
        } else {
            Log "Running SFC scan silently in a hidden window..." "INFO"
            
            # Define the PowerShell command to execute sfc.exe
            # We use a script block to ensure sfc.exe's exit code is captured.
            $command = "& sfc.exe /scannow; exit `$LASTEXITCODE"
            
            # Set up process information to start a new, hidden PowerShell window
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "powershell.exe"
            # Pass arguments to PowerShell: no profile, bypass execution policy, hidden window, execute command
            $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$command`""
            $processInfo.UseShellExecute = $false # Crucial for redirecting output
            $processInfo.RedirectStandardOutput = $true # Attempt to redirect stdout
            $processInfo.RedirectStandardError = $true  # Attempt to redirect stderr

            # Create and start the process
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null # Start the process and suppress its immediate output to console
            
            $process.WaitForExit() # Wait for the hidden PowerShell process to complete
            $sfcExitCode = $process.ExitCode
            
            # Read and log any captured output from stdout/stderr of the hidden process.
            # While sfc.exe's live progress often bypasses these, final summaries or errors might be here.
            $sfcOutput = $process.StandardOutput.ReadToEnd()
            $sfcError = $process.StandardError.ReadToEnd()
            
            if (-not [string]::IsNullOrWhiteSpace($sfcOutput)) {
                Log "SFC Standard Output (from hidden process): `n$sfcOutput" -Level "DEBUG"
            }
            if (-not [string]::IsNullOrWhiteSpace($sfcError)) {
                Log "SFC Standard Error (from hidden process): `n$sfcError" -Level "ERROR"
            }

            Log "SFC scan finished silently with exit code: $sfcExitCode" "INFO"
        }
        
    } catch {
        # Catch any unexpected errors during the function's execution
        Log "An unexpected error occurred during SFC /scannow operation: $($_.Exception.Message)" -Level "ERROR"
    }
}
# Log the initial message indicating the script has started, using the Log function.
Log "WUH Script started."
# ================== SAVE ORIGINAL EXECUTION POLICY ==================
# Store the current PowerShell execution policy to restore it later.
# This is crucial for maintaining system security posture after script execution.
$OriginalPolicy = Get-ExecutionPolicy

# ================== ASK FOR MODE ==================
# Prompt the user to select between silent (logs only) or verbose (console and logs) mode.
# Define $VerboseMode at the script scope, allowing it to be modified by user input.
Write-Host ""
Write-Host "Select Mode:"
Write-Host "[S] Silent (logs only)"
Write-Host "[V] Verbose (console and logs)"
$mode = Read-Host "Choose mode [S/V]" # Read user input
if ($mode.ToUpper() -eq "V") {
    $VerboseMode = $true # Set internal flag for console output
    Log "Verbose mode selected."
} else {
    $VerboseMode = $false # Set internal flag to suppress console output
    Log "Silent mode selected."
    # Suppress various PowerShell preference variables for silent operation.
    # This prevents non-essential output like progress bars, information streams, and warnings.
    $VerbosePreference = "SilentlyContinue"
    $InformationPreference = "SilentlyContinue"
    $ProgressPreference = "SilentlyContinue"
    $WarningPreference = "SilentlyContinue"
}
# ================== ASK FOR TASK==================
# This section now handles task selection interactively. If running
# non-interactively and no task is specified, the script will exit.

# --- Existing mode selection (S/V) would go here, if it's still needed ---
# For example, before this 'Ask for Task' section.
# $mode = Read-Host "Choose mode [S/V]"
# if ($mode.ToUpper() -eq "V") { $VerboseMode = $true } else { $VerboseMode = $false }
# Log "Mode selected."

# Initialize $task variable (it will be set by user input)
$task = ''

# Always prompt for task selection
Write-Host ""
Write-Host "Select Task:"
Write-Host "[1] Machine Preparation (semi-automated)"
Write-Host "[2] Windows Maintenance"

$isValidInput = $false
while (-not $isValidInput) {
    $taskInput = Read-Host "Choose task [1/2]"
    switch ($taskInput) {
        "1" { $task = "MachinePrep"; $isValidInput = $true }
        "2" { $task = "WindowsMaintenance"; $isValidInput = $true }
        default { Write-Host "Invalid input. Please choose 1 or 2." -ForegroundColor Red }
    }
}
Log "User interactively selected task: $task"

# ================== CHECK INTERNET CONNECTIVITY ==================
# Verify that the system has active internet connectivity before attempting downloads.
Log "Checking internet connectivity..."
try {
    # Attempt to invoke a web request to a reliable Microsoft URL.
    # UseBasicParsing is faster and avoids parsing HTML. TimeoutSec prevents indefinite hang.
    $null = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10
    Log "Internet connectivity check passed."
} catch {
    # Log an error and exit if connectivity fails.
    Log "Internet connectivity check failed. Please check your network connection." -Level "ERROR"
    Exit 1 # Terminate script execution upon critical failure
}


# ================== SET EXECUTION POLICY ==================
# Temporarily set the execution policy for the current process to Bypass.
# This allows unsigned scripts (like those downloaded from GitHub) to run without prompts.
# -Force suppresses prompts for this action, -ErrorAction SilentlyContinue prevents breaking if already set.
Log "Setting Execution Policy to Bypass..."
Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

# ================== INSTALL NUGET PROVIDER ==================
Install-NuGetProvider

# ================== CREATE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
# Create and activate a temporary "Maximum Performance" power plan.
# This ensures optimal performance during script execution, particularly for lengthy tasks.
Log "Creating temporary Maximum Performance power plan..."
try {
    # Well-known GUID for the "High performance" power plan.
    $highPerformanceGuid = "8c5e7fd1-ce92-466d-be55-c3230502e679"
    $baseSchemeExists = (powercfg -list | Select-String -Pattern $highPerformanceGuid -Quiet)
    $tempPlanGuid = $null # Initialize to null
    $PowerPlanName = "TempMaxPerformance" # Assuming this is defined elsewhere, or define it here if it's a script-level variable.

    # First, try to find if our custom plan already exists (from a previous run)
    # Using -match for GUID in case of trailing spaces, and split for name.
    $existingTempPlanLine = (powercfg -list | Where-Object { $_ -match "$highPerformanceGuid" -and $_ -match [regex]::Escape($PowerPlanName) } | Select-Object -First 1)
    if ($existingTempPlanLine) {
        $tempPlanGuid = ($existingTempPlanLine -split '\s+')[3] # Extract GUID from line
        Log "Found an existing temporary power plan named '$PowerPlanName' with GUID: $tempPlanGuid. Will attempt to activate it." -Level "INFO"
    }
    
    # If a temporary plan wasn't found, proceed to create/duplicate
    if (-not $tempPlanGuid) {
        if ($baseSchemeExists) {
            # Option 1: Duplicate the standard "High performance" plan if it exists
            Log "High Performance power plan (GUID: $highPerformanceGuid) found. Duplicating it." -Level "INFO"
            $newGuidOutput = (powercfg -duplicatescheme $highPerformanceGuid 2>&1).Trim()
            if ($LASTEXITCODE -eq 0 -and $newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                $tempPlanGuid = $Matches[1]
                Log "Duplicated High Performance plan to new GUID: $tempPlanGuid." -Level "INFO"
            } else {
                Log "Failed to duplicate High Performance plan. Output: '$newGuidOutput', Exit Code: $LASTEXITCODE. Trying to find existing temporary plan, or creating from Balanced." -Level "WARN"
            }
        } 
        
        # Fallback if High Performance didn't exist or duplication failed
        if (-not $tempPlanGuid) {
            Log "Creating a new 'High Performance-like' custom plan from 'Balanced'." -Level "WARN"
            
            # Using 'Balanced' GUID as a fallback to duplicate
            $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
            $newGuidOutput = (powercfg -duplicatescheme $balancedGuid 2>&1).Trim() # Duplicate Balanced, capture errors
            if ($LASTEXITCODE -eq 0 -and $newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                $tempPlanGuid = $Matches[1]
                Log "Duplicated 'Balanced' plan as a base for a new custom plan, GUID: $tempPlanGuid." -Level "INFO"

                # --- Configure Key Settings for Max Performance ---
                # Define a helper function/script block for setting power options and logging results
                $SetPowerSetting = {
                    param($planGuid, $subgroupGuid, $settingGuid, $value, $description)
                    
                    $acResult = (powercfg -setacvalueindex $planGuid $subgroupGuid $settingGuid $value 2>&1)
                    $acExitCode = $LASTEXITCODE

                    $dcResult = (powercfg -setdcvalueindex $planGuid $subgroupGuid $settingGuid $value 2>&1)
                    $dcExitCode = $LASTEXITCODE

                    # The error message is: "The power scheme, subgroup or setting specified does not exist."
                    $commonErrorPattern = "The power scheme, subgroup or setting specified does not exist"
                    
                    $acAppliedSuccessfully = ($acExitCode -eq 0 -and -not ($acResult -match $commonErrorPattern))
                    $dcAppliedSuccessfully = ($dcExitCode -eq 0 -and -not ($dcResult -match $commonErrorPattern))

                    if ($acAppliedSuccessfully -and $dcAppliedSuccessfully) {
                        Log "$description (AC & DC) set successfully." -Level "INFO"
                    } elseif ($acAppliedSuccessfully -and -not $dcAppliedSuccessfully) {
                        Log "$description (AC) set successfully, but (DC) failed. Output: '$dcResult', Exit Code: $dcExitCode" -Level "WARN"
                    } elseif (-not $acAppliedSuccessfully -and $dcAppliedSuccessfully) {
                        Log "$description (DC) set successfully, but (AC) failed. Output: '$acResult', Exit Code: $acExitCode" -Level "WARN"
                    } else {
                        Log "$description (AC & DC) failed. AC Output: '$acResult', AC Exit Code: $acExitCode. DC Output: '$dcResult', DC Exit Code: $dcExitCode." -Level "WARN"
                    }
                }

                # Apply settings using the helper, allowing individual failures without stopping
                # Updated Setting GUIDs based on your powercfg -q output
                & $SetPowerSetting $tempPlanGuid "0012ee47-9041-4b5d-9b77-535fba8b1442" "6738e2c4-e8a5-4a42-b16a-e040e769756e" 0 "Hard disk never turns off" # Updated Setting GUID
                & $SetPowerSetting $tempPlanGuid "54533251-82be-4824-96c1-47b60b740d00" "893dee8e-2bef-41e0-89c6-b55d0929964c" 100 "Minimum processor state set to 100%" # Updated Subgroup and Setting GUID
                & $SetPowerSetting $tempPlanGuid "54533251-82be-4824-96c1-47b60b740d00" "bc5038f7-23e0-4960-96da-33abaf5935ec" 100 "Maximum processor state set to 100%" # Updated Subgroup and Setting GUID
                & $SetPowerSetting $tempPlanGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" 0 "System will not sleep automatically" # Updated Setting GUID
                & $SetPowerSetting $tempPlanGuid "7516b95f-f776-4464-8c53-06167f40cc99" "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" 0 "Display will not turn off automatically" # Updated Setting GUID
                & $SetPowerSetting $tempPlanGuid "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0 "USB selective suspend disabled" # Updated Setting GUID

            } else {
                Log "Failed to duplicate 'Balanced' plan to create a custom plan. Output: '$newGuidOutput', Exit Code: $LASTEXITCODE. Aborting power plan changes." -Level "ERROR"
                return # Exit this try block
            }
        }
    }

    if ($tempPlanGuid) {
        # Rename the plan to the specified temporary name.
        Log "Renaming power plan (GUID: $tempPlanGuid) to '$PowerPlanName'..." -Level "INFO"
        $renameResult = (powercfg -changename $tempPlanGuid $PowerPlanName "Temporary Maximum Performance (Custom)" 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Log "Power plan renamed successfully." -Level "INFO"
        } else {
            Log "Failed to rename power plan (GUID: $tempPlanGuid) to '$PowerPlanName'. Output: '$renameResult', Exit Code: $LASTEXITCODE." -Level "WARN"
        }
        
        # Set the newly created plan as the active power scheme.
        Log "Activating '$PowerPlanName' power plan with GUID: $tempPlanGuid..." -Level "INFO"
        $activateResult = (powercfg -setactive $tempPlanGuid 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Log "Temporary Maximum Performance power plan activated successfully." -Level "INFO"
        } else {
            Log "Failed to activate '$PowerPlanName' power plan (GUID: $tempPlanGuid). Output: '$activateResult', Exit Code: $LASTEXITCODE." -Level "ERROR"
        }
    } else {
        Log "Could not create or find a suitable power plan for activation. Power plan changes skipped." -Level "ERROR"
    }

} catch {
    # Log any unexpected errors during power plan operations.
    Log "An error occurred during power plan creation or setting: $_" -Level "ERROR"
}
# ================== TASK SELECTION ==================
switch ($task) {
    "MachinePrep" {
        Log "Task selected: Machine Preparation (semi-automated)"
        Log "Executing scripts from local path..."
        & (Join-Path $ScriptDir "MACHINEPREP.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        & (Join-Path $ScriptDir "WU.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        & (Join-Path $ScriptDir "WGET.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        if (Confirm-OfficeInstalled) {
            & (Join-Path $ScriptDir "MSO_UPDATE.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        } else {
            Log "Microsoft Office not detected. Skipping Office update script."
        }
        Log "Running System File Checker (SFC) to verify system integrity..."
        Repair-SystemFiles
    }
    "WindowsMaintenance" {
        Log "Task selected: Windows Maintenance"
        Log "Executing scripts from local path..."
        & (Join-Path $ScriptDir "WU.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        & (Join-Path $ScriptDir "WGET.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        if (Confirm-OfficeInstalled) {
            & (Join-Path $ScriptDir "MSO_UPDATE.ps1") -Verbose:$VerboseMode -LogFile $LogFile
        } else {
            Log "Microsoft Office not detected. Skipping Office update."
        }
        Log "Running System File Checker (SFC) to verify system integrity..."
        Repair-SystemFiles
    }
    default {
        Log "Invalid task selection. Exiting script. Received value: '$task'" -Level "ERROR"
        Exit 1
    }
}

# ================== RESET POWER PLAN TO BALANCED ==================
# Restore the system's power plan to the default 'Balanced' scheme.
# This reverts changes made earlier for temporary performance boost.
Log "Resetting power plan to Balanced..."
try {
    powercfg -restoredefaultschemes # Restores default power schemes, effectively recreating Balanced.
    Log "Power plan schemes restored to default."
    powercfg -setactive SCHEME_BALANCED # Activates the Balanced power plan.
    Log "Power plan reset to Balanced."
} catch {
    Log "Failed to reset power plan to Balanced: $_" -Level "ERROR"
}
# ================== REMOVE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
Log "Attempting to remove temporary Maximum Performance power plan..."
try {
    # Find the GUID of the temporary power plan by its name.
    # We use regex::Escape to ensure special characters in $PowerPlanName are treated literally.
    $tempPlanGuid = (powercfg -list | Where-Object { $_ -match [regex]::Escape($PowerPlanName) } | ForEach-Object { ($_ -split '\s+')[3] })
    
    if ($tempPlanGuid) {
        Log "Found temporary power plan '$PowerPlanName' with GUID: $tempPlanGuid. Deleting it."
        powercfg -delete $tempPlanGuid -Force # Use -Force to suppress any confirmation prompts
        Log "Temporary Maximum Performance power plan removed."
    } else {
        Log "Temporary Maximum Performance power plan '$PowerPlanName' not found, no deletion needed." -Level "INFO"
    }
} catch {
    Log "Failed to remove temporary power plan: $_" -Level "ERROR"
}
# ================== RESTORE PSGALLERY TRUST POLICY ==================
# This block attempts to reset the PSGallery InstallationPolicy back to Untrusted.
# It ensures the system's security posture is restored after the script's operations,
# regardless of whether PSGallery was initially registered by this script or existed.
Log "Restoring PSGallery InstallationPolicy to Untrusted if it exists..."
try {
    # Check if PSGallery exists before attempting to set its policy.
    # SilentlyContinue prevents an error if the repository is not found, allowing the 'if' condition to handle it.
    if (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue) {
        # Set the InstallationPolicy back to Untrusted. SilentlyContinue prevents prompt if already untrusted.
        Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted -ErrorAction SilentlyContinue
        Log "PSGallery InstallationPolicy reset to Untrusted."
    } else {
        Log "PSGallery repository not found, skipping InstallationPolicy reset." -Level "WARN"
    }
} catch {
    # Log a warning if resetting the policy fails but do not exit, as it might be a minor issue.
    Log "Failed to reset PSGallery InstallationPolicy: $_" -Level "WARN"
}
# ================== RESTORE EXECUTION POLICY ==================
# Revert the PowerShell execution policy for the current process to its original state.
# This is a critical security measure to return the system to its pre-script security level.
Log "Restoring Execution Policy..."
try {
    # Check if the original policy was not "Restricted". If it was, no change is needed for this scope.
    # The script explicitly sets Process scope to Bypass, so restoring to Restricted is a safe default
    # for the process after script execution, unless the original policy was already Restricted.
    if ($OriginalPolicy -ne "Restricted") {
        Log "Original policy was $OriginalPolicy; resetting to Restricted for the current process scope."
        # Set to Restricted for the current process scope. -Force suppresses prompts.
        Set-ExecutionPolicy Restricted -Scope Process -Force -ErrorAction SilentlyContinue
        Log "Execution Policy set to Restricted."
    } else {
        Log "Original policy was Restricted; no change needed for the current process scope."
    }
} catch {
    # Log an error if restoring the execution policy fails.
    Log "Failed to restore Execution Policy: $_" -Level "ERROR"
}
# ================== SCRIPT COMPLETION ===================
# Final log entry indicating successful script completion.
Log "Script completed successfully."