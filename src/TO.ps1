<#
.SYNOPSIS
    Orchestrates various machine preparation and Windows maintenance tasks.
.DESCRIPTION
    This script acts as a central orchestrator for automating machine setup, Windows maintenance, and UniFi server management.
    It features a nested menu for bundled and individual tasks, robust logging, internet connectivity checks, dynamic execution policy handling, and offers interactive task selection for silent or verbose operation.
    It can perform bundled tasks (Machine Preparation, Windows Maintenance) or individual actions like system file repair, power plan optimization, and execution of child scripts.
.NOTES
    Script: TO.ps1
    Version: 1.0.8
        Dependencies:
        - Internet connectivity for various operations.
        - modules/Functions.ps1 for logging and other utility functions.
        - Child scripts: MACHINEPREP.ps1, WUA.ps1, WGET.ps1, MSO_UPDATE.ps1, IUS.ps1, CLEANUP.ps1 (located in the same directory or relative paths).
    Change Log:
        Version 1.0.8:
        - Modified bundled tasks (Machine Prep, Windows Maintenance) to run a 'Light' cleanup at the beginning to free up space, and a 'Full' cleanup at the end to complete all tasks.
        - Updated `Invoke-Script` calls to use the new `-ScriptParameters` argument for passing custom parameters to child scripts.
        Version 1.0.7:
        - Refactored the script by moving local helper functions (`Invoke-Script`, `Confirm-OfficeInstalled`, `Repair-SystemFiles`) to the central `modules/Functions.ps1` module.
        - Updated calls to `Invoke-Script` to align with its new definition in the functions module.
        - Added a new `CLEANUP.ps1` script and integrated it into tasks.
        Version 1.0.6:
        - Implemented a nested menu structure with a main menu and a sub-menu for "Individual Tasks" for better organization.
        - Added individual tasks for running specific maintenance actions (Windows Update, Winget Update, Office Update, System Repair, Chocolatey management).
        - Optimized power plan management to only activate for long-running bundled tasks, improving efficiency for smaller, individual tasks.
        Version 1.0.4: Refactored power plan management to use functions from Functions.ps1.
        Version 1.0.3: Updated script descriptions and metadata.
        Version 1.0.2: Improved logging and error handling.
        Version 1.0.1: Added support for new child scripts.
        Version 1.0.0: Initial release.
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
# Log the initial message indicating the script has started, using the Log function.
Log "Starting Task Orchestrator script v1.0.8..." "INFO"
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
 
# ================== MAIN MENU LOOP ==================
:MainMenu while ($true) {
    Write-Host ""
    Write-Host "--- Main Menu ---"
    Write-Host "Select a task to perform:"
    Write-Host ""
    Write-Host "--- Bundled Tasks ---"
    Write-Host "[1] Machine Preparation (Full setup for new machines)"
    Write-Host "[2] Windows Maintenance (Comprehensive update and health check)"
    Write-Host "[3] Install/Upgrade UniFi Server"
    Write-Host ""
    Write-Host "--- Other Options ---"
    Write-Host "[4] Run Individual Tasks..."
    Write-Host "[Q] Quit"
    Write-Host ""

    $mainChoice = Read-Host "Choose an option"

    switch ($mainChoice.ToUpper()) {
        '1' {
            Log "Task selected: Machine Preparation (semi-automated)"
            $powerPlanInfo = Set-TemporaryMaxPerformancePlan
            try {
                Invoke-Script -ScriptName "CLEANUP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{ CleanupMode = 'Light' }
                Invoke-Script -ScriptName "MACHINEPREP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                Invoke-Script -ScriptName "REPAIR.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                if (Confirm-OfficeInstalled) {
                    Invoke-Script -ScriptName "MSO_UPDATE.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                } else {
                    Log "Microsoft Office not detected. Skipping Office update script."
                }
                Invoke-Script -ScriptName "CLEANUP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{ CleanupMode = 'Full' }
            } finally {
                Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
            }
        }
        '2' {
            Log "Task selected: Windows Maintenance"
            $powerPlanInfo = Set-TemporaryMaxPerformancePlan
            try {
                Invoke-Script -ScriptName "CLEANUP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{ CleanupMode = 'Light' }
                Invoke-Script -ScriptName "WUA.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                Invoke-Script -ScriptName "REPAIR.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                Invoke-Script -ScriptName "WGET.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                if (Confirm-OfficeInstalled) {
                    Invoke-Script -ScriptName "MSO_UPDATE.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                } else {
                    Log "Microsoft Office not detected. Skipping Office update."
                }
                Invoke-Script -ScriptName "CLEANUP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{ CleanupMode = 'Full' }
            } finally {
                Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
            }
        }
        '3' {
            Log "Task selected: Install/Upgrade UniFi Server"
            Invoke-Script -ScriptName "IUS.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
        }
        '4' {
            # --- INDIVIDUAL TASKS SUB-MENU ---
            :SubMenu while ($true) {
                Write-Host ""
                Write-Host "--- Individual Tasks Menu ---"
                Write-Host "[A] Run Windows Updates"
                Write-Host "[B] Update Applications (Winget)"
                Write-Host "[C] Update Microsoft Office" # This line seems to have a typo in the original file, but I'll leave it as is.
                Write-Host "[D] Repair System Files (SFC & DISM)"
                Write-Host "[E] Install Chocolatey"
                Write-Host "[F] Uninstall Chocolatey"
                Write-Host "[G] System Cleanup"
                Write-Host "[M] Back to Main Menu"
                Write-Host ""

                $subChoice = Read-Host "Choose an individual task [A-G, M]"

                switch ($subChoice.ToUpper()) {
                    'A' {
                        Log "Individual Task: Run Windows Updates"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            Invoke-Script -ScriptName "WUA.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'B' {
                        Log "Individual Task: Update Applications (Winget)"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            Invoke-Script -ScriptName "WGET.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'C' {
                        Log "Individual Task: Update Microsoft Office"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            if (Confirm-OfficeInstalled) { Invoke-Script -ScriptName "MSO_UPDATE.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{} }
                            else { Log "Microsoft Office not detected. Skipping." }
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'D' {
                        Log "Individual Task: Repair System Files"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            Invoke-Script -ScriptName "REPAIR.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{}
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'E' {
                        Log "Individual Task: Install Chocolatey"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            Install-Chocolatey
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'F' {
                        Log "Individual Task: Uninstall Chocolatey"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            Uninstall-Chocolatey
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'G' {
                        Log "Individual Task: System Cleanup"
                        $powerPlanInfo = Set-TemporaryMaxPerformancePlan
                        try {
                            $cleanupChoice = Read-Host "Choose cleanup mode: [L]ight or [F]ull"
                            $cleanupMode = if ($cleanupChoice.ToUpper() -eq 'L') { 'Light' } else { 'Full' }
                            Log "Selected cleanup mode: $cleanupMode"
                            Invoke-Script -ScriptName "CLEANUP.ps1" -ScriptDir $ScriptDir -LogDir $LogDir -VerboseMode $VerboseMode -ScriptParameters @{ CleanupMode = $cleanupMode }
                        } finally {
                            Restore-PowerPlan -PowerPlanInfo $powerPlanInfo
                        }
                    }
                    'M' { Log "Returning to Main Menu..."; break SubMenu }
                    default { Write-Host "Invalid input. Please choose a valid option." -ForegroundColor Red }
                }
            }
        }
        'Q' {
            Log "User chose to quit. Exiting script."
            break MainMenu # Exit the main menu loop
        }
        default { Write-Host "Invalid input. Please choose a valid option from the menu." -ForegroundColor Red }
    }
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