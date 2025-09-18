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
        Log "Error during execution of '$ScriptName': $($_.Exception.Message)" -Level "ERROR"
    }
}
# ================== FUNCTION: CHECK IF OFFICE IS INSTALLED ==================
# Helper function to confirm if Microsoft Office is installed on the system.
# This is used to conditionally download/run Office-related update scripts.
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
# 1. Runs SFC in verify-only mode first.
# 2. If corruption is found, runs DISM to ensure the component store is healthy.
# 3. Runs SFC in scan-and-repair mode to fix the files.
# The function analyzes the CBS.log to provide a detailed result of the scans.
function Repair-SystemFiles {
    Log "Starting system file integrity check and repair process..." "INFO"

    # Internal helper to run external commands, respecting the VerboseMode switch.
    function Invoke-ElevatedCommand {
        param(
            [string]$FilePath,
            [string]$Arguments,
            [string]$LogName
        )

        Log "Executing: $FilePath $Arguments" "INFO"
        Log "The output of this command will be displayed directly in the console for real-time progress." "INFO"

        # Execute the command directly in the current console.
        # This provides real-time progress for console applications like SFC and DISM.
        # We lose the ability to capture the stdout/stderr stream for logging here,
        # but the exit code is captured, and for these specific tools, dedicated log files
        # (like CBS.log) are more important.
        # Using Start-Process with -NoNewWindow and -Wait is the most reliable way to run a console
        # application in the current window and see its real-time output, especially in silent mode
        # where PowerShell's own output streams are suppressed. This bypasses PowerShell's stream
        # handling for the external process.
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode

        Log "$LogName process finished with exit code: $exitCode" "INFO"
        return $exitCode
    }

    # Internal helper to get the result from the last SFC session in CBS.log
    function Get-SfcLastSessionResult {
        param ([string]$CbsLogPath)
        if (-not (Test-Path $CbsLogPath)) {
            Log "CBS.log not found at '$CbsLogPath'." "WARN"
            return "LogNotFound"
        }

        # Add a small delay to ensure the log file is flushed before reading.
        Start-Sleep -Seconds 5

        # Find the line number of the last session start marker.
        $sessionStart = Select-String -Path $CbsLogPath -Pattern '\[SR\] Beginning Verify and Repair transaction' | Select-Object -Last 1
        
        if (-not $sessionStart) {
            Log "Could not find any SFC session start in CBS.log." "WARN"
            return "NoSessionFound"
        }

        # Get content from that line number to the end of the file.
        $lastSessionContent = Get-Content $CbsLogPath | Select-Object -Skip ($sessionStart.LineNumber - 1)

        # Check for key phrases in the log output in order of severity.
        if ($lastSessionContent -match "Cannot repair member file") {
            return "CannotRepair"
        } elseif ($lastSessionContent -match "Repairing and verifying") {
            return "Repaired"
        } elseif ($lastSessionContent -match "found integrity violations") {
            return "CorruptionFound"
        } elseif ($lastSessionContent -match "did not find any integrity violations" -or $lastSessionContent -match "found no integrity violations") {
            return "NoViolations"
        } else {
            return "Unknown"
        }
    }

    # --- Step 1: Run SFC in verification mode ---
    try {
        Log "Running System File Checker (SFC) in verification-only mode..." "INFO"
        $sfcExitCode = Invoke-ElevatedCommand -FilePath "sfc.exe" -Arguments "/verifyonly" -LogName "SFC Verify"
        if ($sfcExitCode -eq 0) {
            Log "SFC verification completed with exit code 0. No integrity violations found. System files are healthy." "INFO"
            return # Exit the function as no repair is needed.
        } else {
            # A non-zero exit code indicates that integrity violations were found.
            Log "SFC verification found integrity violations (Exit Code: $sfcExitCode). Proceeding with repair." "WARN"
        }
    } catch {
        Log "An unexpected error occurred during SFC /verifyonly operation: $($_.Exception.Message)" "ERROR"
        Log "Attempting to run full repair scan despite verification error." "WARN"
    }

    # --- Step 2: Run DISM to ensure the component store is healthy ---
    try {
        Log "Running DISM to check and repair the Windows Component Store. This may take a long time..." "INFO"
        $dismExitCode = Invoke-ElevatedCommand -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth" -LogName "DISM"

        if ($dismExitCode -eq 0) {
            Log "DISM completed successfully. The component store is healthy." "INFO"
        } else {
            Log "DISM finished with a non-zero exit code ($dismExitCode). The component store may have issues. See DISM logs for details." "WARN"
        }
    } catch {
        Log "An unexpected error occurred while running DISM: $($_.Exception.Message)" "ERROR"
        Log "Proceeding to SFC despite DISM error." "WARN"
    }

    # --- Step 3: Run SFC in repair mode (if needed) ---
    try {
        Log "Running System File Checker (SFC) in repair mode (scannow)..." "INFO"
        Invoke-ElevatedCommand -FilePath "sfc.exe" -Arguments "/scannow" -LogName "SFC Scan"

        $cbsLogPath = "$env:windir\Logs\CBS\CBS.log"
        $repairResult = Get-SfcLastSessionResult -CbsLogPath $cbsLogPath

        switch ($repairResult) {
            "Repaired" { Log "SFC Result: Found and successfully repaired system file corruption." "INFO" }
            "CannotRepair" { Log "SFC Result: Found corrupt files but was unable to fix some of them. Manual intervention may be required." "ERROR" }
            "NoViolations" { Log "SFC Result: Repair scan completed and found no integrity violations (possibly fixed by DISM)." "INFO" }
            default { Log "SFC repair scan completed, but the result could not be definitively determined from the log ('$repairResult')." "WARN" }
        }
    } catch {
        Log "An unexpected error occurred during SFC /scannow operation: $($_.Exception.Message)" "ERROR"
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