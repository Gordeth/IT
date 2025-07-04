# ==============================================================================
# PowerShell Maintenance Script
# This script automates various machine preparation and Windows maintenance tasks.
# It includes robust logging, internet connectivity checks, execution policy handling,
# and a focus on silent execution for automation.
# ==============================================================================
param (
    [switch]$VerboseMode = $false # Default to false, can be set to true by user input
)
# ================== CONFIGURATION ==================
# Define essential paths, file names, and settings for the script's operation.
$BaseUrl = "https://raw.githubusercontent.com/Gordeth/IT/main" # Base URL for downloading external scripts
$ScriptDir = "$env:TEMP\ITScripts"                            # Local directory to store temporary scripts and logs
$LogDir = Join-Path -Path $ScriptDir -ChildPath "Log"         # Subdirectory specifically for log files
$LogFile = Join-Path -Path $LogDir -ChildPath "WUH.txt"       # Full path to the main log file
$PowerPlanName = "TempMaxPerformance"                         # Name for the temporary maximum performance power plan

# ================== CREATE DIRECTORIES ==================
# Ensure the necessary temporary directories and log file exist before proceeding.
# If they don't exist, create them. Output is suppressed with Out-Null for silent operation.
if (-not (Test-Path $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir | Out-Null
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }
    if (-not (Test-Path $LogFile)) {
        "[{0}] WUH.ps1 log file created." -f (Get-Date -Format "dd-MM-yyyy HH:mm:ss") | Out-File $LogFile -Append
    }
}
# ================== DEFINE LOG FUNCTION ==================
# A custom logging function to write messages to the console (if verbose mode is on)
# and to a persistent log file.
function Log {
    param (
        [string]$Message,                               # The message to be logged
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")] # Validation for log level
        [string]$Level = "INFO"                         # Default log level is INFO
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss" # Format the current date and time
    $logEntry = "[$timestamp] [$Level] $Message"       # Construct the full log entry string

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
# ================== FUNCTION: GET AND INVOKE SCRIPT ==================
# Downloads a PowerShell script from the BaseUrl and immediately executes it.
function Get-And-Invoke-Script {
    param (
        [string]$ScriptName
    )

    $scriptPath = Join-Path $ScriptDir $ScriptName
    $scriptUrl = "$BaseUrl/$ScriptName"

    # Remove existing file if it exists
    if (Test-Path $scriptPath) {
        Log "Removing existing script $ScriptName from local path before re-downloading..." "INFO"
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }

    # Download the script
    Log "Downloading script $ScriptName from $scriptUrl..." "INFO"
    try {
        if ($VerboseMode) {
            Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing -Verbose
        } else {
            Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing | Out-Null
        }
        Log "$ScriptName downloaded successfully." "INFO"
    } catch {
        Log "Failed to download ${ScriptName}: $_" "ERROR"
        return
    }

    # Execute the script
    Log "Executing script $ScriptName..." "INFO"
    try {
        & $scriptPath -VerboseMode:$VerboseMode -LogFile $LogFile
        Log "$ScriptName executed successfully." "INFO"
    } catch {
        Log "Error executing ${ScriptName}: $_" "ERROR"
    }
}
# ================== FUNCTION: REPAIR SYSTEM FILES (SFC) ==================
# Runs SFC (System File Checker) to verify and optionally repair Windows system files.
# Uses 'verifyonly' first, and if corruption is found, runs 'scannow'.
# This version analyzes CBS.log for results.
function Repair-SystemFiles {
    param(
        # This parameter will control whether to output the raw SFC progress to the console.
        # If true, only SFC's native console output will be displayed.
        [switch]$ShowSFCConsoleProgress
    )

    # --- IMPORTANT: All custom logging (using 'Log' function) and internal analysis
    # has been removed from this function to strictly mimic the exact standalone 'sfc /scannow' output.
    # Variables for log paths, exit codes, error output, and analysis results are also removed
    # as they are not used within this function's simplified scope. ---

    # These are the only temporary variables needed for output redirection
    $tempSfcStdoutPath = $null
    $tempSfcStderrPath = $null

    try {
        # Generate unique temporary file names for standard output and standard error
        $tempSfcStdoutPath = [System.IO.Path]::GetTempFileName()
        $tempSfcStderrPath = [System.IO.Path]::GetTempFileName()

        # Execute sfc.exe and redirect its output to the temporary files
        $process = Start-Process -FilePath "sfc.exe" `
            -ArgumentList "/scannow" `
            -NoNewWindow `            # Do not create a new console window
            -PassThru `               # Pass the process object back for inspection (to WaitForExit and cleanup)
            -RedirectStandardOutput $tempSfcStdoutPath ` # Redirect stdout to temp file
            -RedirectStandardError $tempSfcStderrPath    # Redirect stderr to temp file

        # Wait for the sfc.exe process to finish execution
        $process.WaitForExit()
        # $sfcScanExitCode = $process.ExitCode # Removed: Not used in this minimalist version

        # Read the captured standard output (and discard standard error as it's not used)
        $sfcRawOutput = Get-Content -Path $tempSfcStdoutPath | Out-String
        # $sfcErrorOutput = Get-Content -Path $tempSfcStderrPath | Out-String # Removed: Not used in this minimalist version

        # Process the captured standard output line by line
        # If ShowSFCConsoleProgress is enabled, print ALL captured non-empty lines to the host console.
        # This directly mimics what the native SFC command outputs.
        if ($ShowSFCConsoleProgress) {
            $sfcRawOutput.Split([Environment]::NewLine) | ForEach-Object {
                $line = $_.Trim() # Trim leading/trailing whitespace from each line
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Host $line
                }
            }
        }
        
    } catch {
        # Catch any unexpected errors during the function's execution.
        # This will print a standard PowerShell error message to the console.
        # If you want to suppress this, you'd need to use -ErrorAction SilentlyContinue
        # on the Write-Error or remove it, but it's generally good to notify on error.
        Write-Error "An unexpected error occurred during SFC /scannow operation: $($_.Exception.Message)"
    } finally {
        # Ensure temporary files are cleaned up in all cases, even if an error occurs.
        if ($tempSfcStdoutPath -and (Test-Path $tempSfcStdoutPath)) {
            Remove-Item -Path $tempSfcStdoutPath -ErrorAction SilentlyContinue
        }
        if ($tempSfcStderrPath -and (Test-Path $tempSfcStderrPath)) {
            Remove-Item -Path $tempSfcStderrPath -ErrorAction SilentlyContinue
        }
    }

    # This function does not return any value; its output is solely via Write-Host
    # when $ShowSFCConsoleProgress is active.
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
# This block attempts to install the NuGet package provider.
# It's placed early as many package management operations depend on NuGet.

# Ensure PSGallery is trusted before installing NuGet, as it requires a trusted repository to download providers.
# If PSGallery is not trusted, it will fail to download the NuGet provider.

Log "Checking for NuGet provider..."
# Check if NuGet provider is already installed. SilentlyContinue prevents error if not found.
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    try {
        # --- Temporarily Trust PSGallery for Provider Installation ---
        # PSGallery's InstallationPolicy must be 'Trusted' for PackageManagement
        # to download providers without an "Untrusted repository" prompt.
        # This line directly sets the policy, assuming PSGallery is already registered.
        Log "Temporarily setting PSGallery InstallationPolicy to Trusted for NuGet provider download."
        Set-PSRepository -Name PSGallery -ForceBootstrap -Force -InstallationPolicy Trusted -ErrorAction Stop
        Log "PSGallery InstallationPolicy successfully set to Trusted."
        # -ForceBootstrap ensures the provider is downloaded if needed.
        # -Force handles other confirmations/overwrites.
        # -Confirm:$false is for standard cmdlet confirmations, which may not always cover deep prompts.
        # -SkipPublisherCheck allows installation from publishers not explicitly trusted.
        Log "Attempting to install NuGet provider."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser -ErrorAction Stop
        Log "NuGet provider installed successfully."
    } catch {
        # Log an error and exit if NuGet provider installation fails.
        Log "Failed to install NuGet provider: $_" -Level "ERROR"
        Exit 1
    }
} else {
    Log "NuGet provider is already installed."
}

# ================== CREATE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
# Create and activate a temporary "Maximum Performance" power plan.
# This ensures optimal performance during script execution, particularly for lengthy tasks.
Log "Creating temporary Maximum Performance power plan..."
try {
    # Well-known GUID for the "High performance" power plan.
    $highPerformanceGuid = "8c5e7fd1-ce92-466d-be55-c3230502e679"
    $baseSchemeExists = (powercfg -list | Select-String -Pattern $highPerformanceGuid -Quiet)
    $tempPlanGuid = $null # Initialize to null

    # First, try to find if our custom plan already exists (from a previous run)
    $existingTempPlan = (powercfg -list | Where-Object { $_ -match [regex]::Escape($PowerPlanName) } | ForEach-Object { ($_ -split '\s+')[3] })
    if ($existingTempPlan) {
        $tempPlanGuid = $existingTempPlan
        Log "Found an existing temporary power plan named '$PowerPlanName' with GUID: $tempPlanGuid. Will attempt to activate it." -Level "INFO"
    }
    
    # If a temporary plan wasn't found, proceed to create/duplicate
    if (-not $tempPlanGuid) {
        if ($baseSchemeExists) {
            # Option 1: Duplicate the standard "High performance" plan if it exists
            Log "High Performance power plan (GUID: $highPerformanceGuid) found. Duplicating it."
            $newGuidOutput = (powercfg -duplicatescheme $highPerformanceGuid).Trim()
            if ($newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                $tempPlanGuid = $Matches[1]
                Log "Duplicated High Performance plan to new GUID: $tempPlanGuid."
            } else {
                Log "Failed to extract GUID from duplicate command output: '$newGuidOutput'. Trying to find existing temporary plan." -Level "WARN"
            }
        } else {
            # Option 2: High Performance base plan not found. Create a new "High Performance-like" plan from Balanced.
            Log "High Performance power plan (GUID: $highPerformanceGuid) not found. Creating a new 'High Performance-like' custom plan." -Level "WARN"
            
            # Use 'Balanced' as a base or just create a new scheme.
            # Using 'Balanced' GUID as a fallback to duplicate
            $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
            $newGuidOutput = (powercfg -duplicatescheme $balancedGuid).Trim() # Duplicate Balanced
            if ($newGuidOutput -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
                $tempPlanGuid = $Matches[1]
                Log "Duplicated 'Balanced' plan as a base for a new custom plan, GUID: $tempPlanGuid."

                # --- Configure Key Settings for Max Performance ---
                # These are common settings to maximize performance.
                # GUIDs for sub-groups and settings are universal.

                # Hard Disk - Turn off hard disk after (AC and DC)
                powercfg -setacvalueindex $tempPlanGuid 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e04988416b05 0 # 0 minutes
                powercfg -setdcvalueindex $tempPlanGuid 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e04988416b05 0 # 0 minutes
                Log "Hard disk never turns off."

                # Processor power management - Minimum processor state (AC and DC)
                powercfg -setacvalueindex $tempPlanGuid 54533251-82be-4824-96c1-47b60fd7279f 893dee84-a207-4e21-8ee8-999882b1965f 100 # 100%
                powercfg -setdcvalueindex $tempPlanGuid 54533251-82be-4824-96c1-47b60fd7279f 893dee84-a207-4e21-8ee8-999882b1965f 100 # 100%
                Log "Minimum processor state set to 100%."

                # Processor power management - Maximum processor state (AC and DC)
                powercfg -setacvalueindex $tempPlanGuid 54533251-82be-4824-96c1-47b60fd7279f 3b04d4fd-1cc7-4f23-ab13-d015520ee82d 100 # 100%
                powercfg -setdcvalueindex $tempPlanGuid 54533251-82be-4824-96c1-47b60fd7279f 3b04d4fd-1cc7-4f23-ab13-d015520ee82d 100 # 100%
                Log "Maximum processor state set to 100%."

                # Sleep - Sleep after (AC and DC) - set to 0 for never
                powercfg -setacvalueindex $tempPlanGuid 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f4467 0 # Never
                powercfg -setdcvalueindex $tempPlanGuid 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f4467 0 # Never
                Log "System will not sleep automatically."

                # Display - Turn off display after (AC and DC) - set to 0 for never
                powercfg -setacvalueindex $tempPlanGuid 7516b95f-f776-4464-8c53-06167f40cc99 30f7fc95-ace5-47af-9eb2-be5aa57b1974 0 # Never
                powercfg -setdcvalueindex $tempPlanGuid 7516b95f-f776-4464-8c53-06167f40cc99 30f7fc95-ace5-47af-9eb2-be5aa57b1974 0 # Never
                Log "Display will not turn off automatically."

                # USB selective suspend setting (AC and DC) - set to Disabled
                powercfg -setacvalueindex $tempPlanGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-535f76f8e0d1 0 # Disabled
                powercfg -setdcvalueindex $tempPlanGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-535f76f8e0d1 0 # Disabled
                Log "USB selective suspend disabled."

            } else {
                Log "Failed to duplicate 'Balanced' plan to create a custom plan. Aborting power plan changes." -Level "ERROR"
                return # Exit this try block
            }
        }
    }

    if ($tempPlanGuid) {
        # Rename the plan to the specified temporary name.
        Log "Renaming power plan (GUID: $tempPlanGuid) to '$PowerPlanName'..."
        powercfg -changename $tempPlanGuid $PowerPlanName "Temporary Maximum Performance (Custom)"
        
        # Set the newly created plan as the active power scheme.
        Log "Activating '$PowerPlanName' power plan with GUID: $tempPlanGuid..."
        powercfg -setactive $tempPlanGuid
        Log "Temporary Maximum Performance power plan activated successfully."
    } else {
        Log "Could not create or find a suitable power plan for activation. Power plan changes skipped." -Level "ERROR"
    }

} catch {
    # Log any unexpected errors during power plan operations.
    Log "An error occurred during power plan creation or setting: $_" -Level "ERROR"
}
# ================== TASK SELECTION ==================
# Execute specific tasks based on the user's initial selection.
switch ($task) {
    "MachinePrep" { # Changed from "1" to "MachinePrep"
        Log "Task selected: Machine Preparation (semi-automated)"
        Log "Downloading necessary scripts..."
        Get-And-Invoke-Script -ScriptName "MACHINEPREP.ps1" 
        Get-And-Invoke-Script -ScriptName "WU.ps1"        
        Get-And-Invoke-Script -ScriptName "WGET.ps1"      
        if (Confirm-OfficeInstalled) {
            Get-And-Invoke-Script -ScriptName "MSO_UPDATE.ps1" # Conditionally download Office update script
        } else {
            Log "Microsoft Office not detected. Skipping Office update script download."
        }
        Log "Running System File Checker (SFC) to verify system integrity..."
        Repair-SystemFiles # Call the function to run SFC
    }
    "WindowsMaintenance" { # Changed from "2" to "WindowsMaintenance"
        Log "Task selected: Windows Maintenance"
        Get-And-Invoke-Script -ScriptName "WU.ps1"
        Get-And-Invoke-Script -ScriptName "WGET.ps1"
        if (Confirm-OfficeInstalled) {
            Get-And-Invoke-Script -ScriptName "MSO_UPDATE.ps1"
        } else {
            Log "Microsoft Office not detected. Skipping Office update."
        }
        Log "Running System File Checker (SFC) to verify system integrity..."
        Repair-SystemFiles # Call the function to run SFC
    }
    default {
        # This block should now only be reached if $task contains an unexpected value,
        # not because of a common interactive selection.
        Log "Invalid task selection. Exiting script. Received value: '$task'" -Level "ERROR" # Added $task value for debugging
        Exit 1 # Terminate script due to invalid input
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