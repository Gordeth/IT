<#
.SYNOPSIS
    Automates system file integrity checks and repairs.
.DESCRIPTION
    This script runs the System File Checker (SFC) to verify and repair Windows system files.
    It first runs a verification-only scan. If corruption is found, it prompts the user,
    creates a system restore point, and then runs a full repair scan. It analyzes the
    results and can initiate a reboot if required.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
.NOTES
    Script: REPAIR.ps1
    Version: 1.2.0
    Dependencies:
        - PowerShell 5.1 or later.
    Changelog:
        v1.3.1
        - Added logic to detect DISM error 0x800f081f and automatically retry with `/Source:WinPE` to use Windows Update as a repair source.
        v1.3.0
        - Changed repair sequence to run the full DISM repair process first, followed by SFC /scannow, for a more robust repair strategy.
        v1.2.0
        - Expanded DISM repair sequence to include CheckHealth, ScanHealth, and StartComponentCleanup before RestoreHealth.
        v1.1.0
        - Added DISM repair logic when SFC /scannow fails to repair files.
        v1.0.0
        - Initial release. Logic moved from Functions.ps1/Repair-SystemFiles.
        - Added reboot handling.
#>
param (
  [switch]$VerboseMode = $false,
  [Parameter(Mandatory=$true)]
  [string]$LogDir
)

# ==================== Setup ====================
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'

. "$PSScriptRoot/../modules/Functions.ps1"

if (-not $LogDir) {
    Write-Host "ERROR: The LogDir parameter is mandatory." -ForegroundColor Red
    exit 1
}

$LogFile = Join-Path $LogDir "REPAIR.txt"

if (-not (Test-Path $LogFile)) {
    "Log file created by REPAIR.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution ====================
Log "Starting REPAIR.ps1 script v1.2.0..." "INFO"

Log "Starting system file integrity check and repair process..." "INFO"

# --- Step 1: Confirm with user if in verbose mode. ---
$proceedWithRepair = if ($VerboseMode) {
    $choice = Read-Host "This will run a full system repair with DISM and SFC. Do you wish to proceed? (Y/N)"
    $choice -match '^(?i)y(es)?$'
} else {
    Log "Silent mode enabled. Proceeding with repair automatically." "INFO"; $true
}

if (-not $proceedWithRepair) {
    Log "User chose not to proceed with the system file repair. Exiting." "INFO"
    Log "==== REPAIR Script Completed ===="; exit 0
}

# --- Step 2: Create System Restore Point before repair ---
New-SystemRestorePoint -Description "Pre-System_Repair"

# --- Step 3: Run DISM and SFC repair sequence ---
$rebootRequired = $false
try {
     # --- Run DISM Repair Sequence ---
     Log "Attempting to repair the Windows Component Store with DISM." "INFO"
     $dismPath = "$env:windir\System32\dism.exe"
     $dismFailed = $false
 
     try {
         Log "Running DISM /Online /Cleanup-Image /CheckHealth..." "INFO"
         Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /CheckHealth" -LogName "DISM_CheckHealth" -LogDir $LogDir -VerboseMode:$VerboseMode
 
         Log "Running DISM /Online /Cleanup-Image /ScanHealth. This may take some time..." "INFO"
         Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /ScanHealth" -LogName "DISM_ScanHealth" -LogDir $LogDir -VerboseMode:$VerboseMode
 
         Log "Running DISM /Online /Cleanup-Image /StartComponentCleanup. This may take some time..." "INFO"
         Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /StartComponentCleanup" -LogName "DISM_StartComponentCleanup" -LogDir $LogDir -VerboseMode:$VerboseMode
 
         Log "Running DISM /Online /Cleanup-Image /RestoreHealth. This may take a long time..." "INFO"
         $dismRestoreHealthExitCode = Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /RestoreHealth" -LogName "DISM_RestoreHealth" -LogDir $LogDir -VerboseMode:$VerboseMode
         
         # Check if the first attempt failed.
         if ($dismRestoreHealthExitCode -ne 0) {
             Log "DISM /RestoreHealth failed with exit code $dismRestoreHealthExitCode. Checking for common source file error..." "WARN"
             $dismLogPath = Join-Path $LogDir "DISM_RestoreHealth.log"
             $dismLogContent = Get-Content -Path $dismLogPath -Raw

             # If error 0x800f081f (source files not found) is detected, retry with an explicit online source.
             if ($dismLogContent -match '0x800f081f') {
                 Log "Error 0x800f081f detected. Retrying DISM with Windows Update as the source (/Source:WinPE)..." "INFO"
                 $dismRestoreHealthExitCode = Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /RestoreHealth /Source:WinPE" -LogName "DISM_RestoreHealth_Retry" -LogDir $LogDir -VerboseMode:$VerboseMode
             }
         }

         if ($dismRestoreHealthExitCode -ne 0) { # Check the final exit code
             Log "DISM /RestoreHealth failed after all attempts with final exit code $dismRestoreHealthExitCode. Manual intervention may be required." "ERROR"
             $dismFailed = $true
         }
     } catch {
         Log "A critical error occurred during the DISM repair sequence: $($_.Exception.Message)" "ERROR"
         $dismFailed = $true
     }
 
     # --- Run SFC /scannow ---
     if (-not $dismFailed) {
         Log "DISM repair sequence completed. Running SFC /scannow to finalize repairs." "INFO"
         $sfcPath = "$env:windir\System32\sfc.exe"
         Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan" -LogDir $LogDir -VerboseMode:$VerboseMode
 
         $sfcScanLog = Join-Path $LogDir "SFC_Scan.log"
         if (Test-Path $sfcScanLog) {
             $sfcScanOutput = Get-Content -Path $sfcScanLog -Raw
             $normalizedOutput = ($sfcScanOutput -replace '[^a-zA-Z0-9]').ToLower()
 
             $sfcSuccessRepairedPattern = "windowsresourceprotectionfoundintegrityviolationsandsuccessfullyrepairedthem"
             $sfcSuccessNoViolationsPattern = "windowsresourceprotectiondidnotfindanyintegrityviolations"
             $sfcRebootRequiredPattern = "repairstotakeeffect"
 
             if ($normalizedOutput -match $sfcSuccessRepairedPattern) {
                 Log "SFC /scannow completed and successfully repaired system files." "INFO"
                 $rebootRequired = $true
             } elseif ($normalizedOutput -match $sfcSuccessNoViolationsPattern) {
                 Log "SFC /scannow completed and found no integrity violations. The system is now healthy." "INFO"
             } else {
                 Log "SFC /scannow still reports errors after DISM repair. Manual intervention is required. Review CBS.log and all DISM logs." "ERROR"
             }
             if ($normalizedOutput -match $sfcRebootRequiredPattern) { $rebootRequired = $true }
         }
     } else {
         Log "The DISM repair process failed. Skipping SFC scan. Manual intervention is required. Review all DISM logs in '$LogDir'." "ERROR"
     }
} catch {
    Log "An unexpected error occurred during the repair process: $($_.Exception.Message)" "ERROR"
}

if ($rebootRequired) {
    Log "A reboot is required to complete the repairs." "WARN"
    $proceedWithReboot = if ($VerboseMode) { (Read-Host "A reboot is required. Reboot now? (Y/N)").ToUpper() -eq 'Y' } else { $true }
    if ($proceedWithReboot) {
        Log "Initiating restart..."; Restart-Computer -Force
    } else {
        Log "User denied reboot. Please reboot later to complete repairs."
    }
}

Log "==== REPAIR Script Completed ===="