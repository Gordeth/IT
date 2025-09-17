<#
.SYNOPSIS
    Orchestrates various machine preparation and Windows maintenance tasks.
.DESCRIPTION
    This script acts as a central orchestrator for automating machine setup, Windows maintenance, and UniFi server management.
    It features robust logging, internet connectivity checks, dynamic execution policy handling, and offers interactive task selection for silent or verbose operation.
    It can perform tasks such as system file repair, power plan optimization, and execution of child scripts like MACHINEPREP.ps1, WUA.ps1, WGET.ps1, MSO_UPDATE.ps1, and IUS.ps1.
.NOTES
    Script: TO.ps1
    Version: 1.0.4
        Dependencies:
        - Internet connectivity for various operations.
        - modules/Functions.ps1 for logging and other utility functions.
        - Child scripts: MACHINEPREP.ps1, WUA.ps1, WGET.ps1, MSO_UPDATE.ps1, IUS.ps1 (located in the same directory or relative paths).
    Change Log:
        Version 1.0.4: Refactored power plan management to use functions from Functions.ps1.
        Version 1.0.0: Initial release.
        Version 1.0.1: Added support for new child scripts.
        Version 1.0.2: Improved logging and error handling.
        Version 1.0.3: Updated script descriptions and metadata.
#>

param (
    [switch]$VerboseMode = $false # Default to false, can be set to true by user input
)

# ================== CONFIGURATION ==================
# Using the built-in variable $PSScriptRoot is the most reliable way to get the script's directory.
# This avoids issues with hardcoded paths that may change.
$ScriptDir = $PSScriptRoot
# The logging and script directories are now consistently based on $PSScriptRoot.
$LogDir = Join-Path $ScriptDir "Log"
# Define the log file specifically for this orchestrator script.
$LogFile = Join-Path $LogDir "TO.txt"

# --- Set the working location to the script's root ---
Set-Location -Path $ScriptDir

# ================== CREATE DIRECTORIES AND LOG FILE ==================
# This section ensures the logging environment is set up correctly before any
# other scripts are called or logging is performed.
# =====================================================================

# Create the log directory if it doesn't exist.
if (-not (Test-Path $LogDir)) {
    Write-Host "Creating log directory: $LogDir"
    try {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    } catch {
        Write-Host "ERROR: Failed to create log directory. $_" -ForegroundColor Red
        # Exit the script if the log directory cannot be created.
        exit 1
    }
}

# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created." | Out-File $LogFile -Append
}

# ================== LOAD FUNCTIONS MODULE ==================
# This line makes all the functions in your separate Functions.ps1 script available.
# The path is relative to this script's location ($PSScriptRoot).
. "$PSScriptRoot/../modules/Functions.ps1"

# ================== INVOKE SCRIPT FUNCTION ==================
# Updated to pass key parameters like VerboseMode and LogFile to child scripts.
function Invoke-Script {
    param (
        [string]$ScriptName,
        [switch]$VerboseMode, # Parameter to receive VerboseMode
        [string]$LogDir      # Parameter to receive LogDir path
    )
    $scriptPath = Join-Path $ScriptDir $ScriptName
    Log "Running $ScriptName..."
    try {
        # Pass the parameters to the child script
        & $scriptPath -VerboseMode:$VerboseMode -LogDir:$LogDir -ErrorAction Stop
        Log "$ScriptName executed successfully."
    } catch {
        Log "Error during execution of ${ScriptName}: $_"
    }
}
# ================== FUNCTION: CHECK IF OFFICE IS INSTALLED ==================
# Helper function to confirm if Microsoft Office is installed on the system.
# This is used to conditionally download/run Office-related update scripts.
function Confirm-OfficeInstalled {
    # Define common installation paths for Microsoft Office (32-bit and 64-bit).
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
            $processInfo.RedirectStandardError = $true # Attempt to redirect stderr

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
Log "Starting Task Orchestrator script v1.0.4..." "INFO"
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
Write-Host "[3] Install/Upgrade UniFi Server"

$isValidInput = $false
while (-not $isValidInput) {
    $taskInput = Read-Host "Choose task [1/2/3]"
    switch ($taskInput) {
        "1" { $task = "MachinePrep"; $isValidInput = $true }
        "2" { $task = "WindowsMaintenance"; $isValidInput = $true }
        "3" { $task = "InstallUpgradeUniFiServer"; $isValidInput = true }
        default { Write-Host "Invalid input. Please choose 1, 2, or 3." -ForegroundColor Red }
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
# Verify if NuGet is installed before proceeding

# ================== CREATE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
# This is now handled by a function from Functions.ps1.
# It creates and activates the plan, and returns the original and temporary plan info.
$powerPlanInfo = Set-TemporaryMaxPerformancePlan
# ================== TASK SELECTION ==================
switch ($task) {
    "MachinePrep" {
        Log "Task selected: Machine Preparation (semi-automated)"
        Log "Executing scripts from local path..."
        Invoke-Script -ScriptName "MACHINEPREP.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
        Repair-SystemFiles
        if (Confirm-OfficeInstalled) {
            Invoke-Script -ScriptName "MSO_UPDATE.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
        } else {
            Log "Microsoft Office not detected. Skipping Office update script."
        }
        
    }
    "WindowsMaintenance" {
        Log "Task selected: Windows Maintenance"
        Log "Executing scripts from local path..."
        Invoke-Script -ScriptName "WUA.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
        Repair-SystemFiles
        Invoke-Script -ScriptName "WGET.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
        if (Confirm-OfficeInstalled) {
            Invoke-Script -ScriptName "MSO_UPDATE.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
        } else {
            Log "Microsoft Office not detected. Skipping Office update."
        }
        
    }
    "InstallUpgradeUniFiServer" {
        Log "Task selected: Install/Upgrade UniFi Server"
        Log "Executing IUS.ps1 from local path..."
        Invoke-Script -ScriptName "IUS.ps1" -LogDir $LogDir -VerboseMode $VerboseMode
    }
    default {
        Log "Invalid task selection. Exiting script. Received value: '$task'" -Level "ERROR"
        Exit 1
    }
}

# ================== RESTORE AND CLEANUP POWER PLAN ==================
# This is now handled by a function from Functions.ps1.
# It restores the original plan and deletes the temporary one.
Restore-PowerPlan -PowerPlanInfo $powerPlanInfo

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