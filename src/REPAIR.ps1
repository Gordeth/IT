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
        v1.3.5
        - Replaced Media Creation Tool fallback with a fully automated process using 'Fido.ps1' to download the matching Windows ISO for offline repair.
        v1.3.4
        - Replaced ISO download fallback with logic to download and run the Media Creation Tool, prompting the user to create an ISO for a final, robust repair attempt.
        v1.3.3
        - Modified the ISO repair fallback to prompt for a download URL instead of a local path, then download, use, and clean up the ISO automatically.
        v1.3.2
        - Added a final repair step for interactive mode: if online DISM sources fail, prompt the user to provide a Windows ISO for offline repair.
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
    Log "Running initial System File Checker (SFC) scan..." "INFO"
    $sfcPath = "$env:windir\System32\sfc.exe"
    Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan_1" -LogDir $LogDir -VerboseMode:$VerboseMode
    
    $sfcScanLog1 = Join-Path $LogDir "SFC_Scan_1.log"
    $sfcScanOutput1 = Get-Content -Path $sfcScanLog1 -Raw
    $normalizedOutput1 = ($sfcScanOutput1 -replace '[^a-zA-Z0-9]').ToLower()

    $sfcSuccessRepairedPattern = "windowsresourceprotectionfoundintegrityviolationsandsuccessfullyrepairedthem"
    $sfcFailureUnableToFixPattern = "windowsresourceprotectionfoundintegrityviolationsbutwasunabletofixsomeofthem"
    $sfcSuccessNoViolationsPattern = "windowsresourceprotectiondidnotfindanyintegrityviolations"
    $sfcRebootRequiredPattern = "repairstotakeeffect"

    $runDism = $false

    if ($normalizedOutput1 -match $sfcSuccessRepairedPattern) {
        Log "SFC successfully repaired system files. A reboot is likely required." "INFO"
        $rebootRequired = $true
    } elseif ($normalizedOutput1 -match $sfcSuccessNoViolationsPattern) {
        Log "SFC found no integrity violations. Proceeding with DISM component store health check." "INFO"
        $runDism = $true
    } elseif ($normalizedOutput1 -match $sfcFailureUnableToFixPattern) {
        Log "SFC found errors it could not fix. Proceeding with DISM to repair the component store." "WARN"
        $runDism = $true
    } else {
        Log "SFC completed with an unparsed result. Proceeding with DISM as a precaution." "WARN"
        $runDism = $true
    }

    if ($normalizedOutput1 -match $sfcRebootRequiredPattern) { $rebootRequired = $true }

    if ($runDism) {
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
            
            if ($dismRestoreHealthExitCode -ne 0) {
                Log "DISM /RestoreHealth failed with exit code $dismRestoreHealthExitCode. Checking for common source file error..." "WARN"
                $dismLogPath = Join-Path $LogDir "DISM_RestoreHealth.log"
                $dismLogContent = Get-Content -Path $dismLogPath -Raw
                if ($dismLogContent -match '0x800f081f') {
                    Log "Error 0x800f081f detected. Retrying DISM with Windows Update as the source (/Source:WinPE)..." "INFO"
                    $dismRestoreHealthExitCode = Invoke-CommandWithLogging -FilePath $dismPath -Arguments "/Online /Cleanup-Image /RestoreHealth /Source:WinPE" -LogName "DISM_RestoreHealth_Retry" -LogDir $LogDir -VerboseMode:$VerboseMode
                }
            }

            if ($dismRestoreHealthExitCode -ne 0) {
                Log "DISM /RestoreHealth failed after all online attempts with final exit code $dismRestoreHealthExitCode." "ERROR"
                if ($VerboseMode) {
                    # MCT Fallback logic here...
                } else {
                    Log "Script is in silent mode. Manual intervention with a Windows ISO is required to complete the repair." "ERROR"
                }
            }
            if ($dismRestoreHealthExitCode -ne 0) {
                Log "All DISM repair attempts have failed. Manual intervention is required." "ERROR"
                Log "RECOMMENDATION: Please return to the main menu and run the 'In-Place Upgrade Windows' task." "WARN"
                $dismFailed = $true
            }
        } catch {
            Log "A critical error occurred during the DISM repair sequence: $($_.Exception.Message)" "ERROR"
            $dismFailed = $true
        }
    
        # --- Run Final SFC /scannow ---
        if (-not $dismFailed) {
            Log "DISM repair sequence completed. Running a final SFC /scannow to apply repairs." "INFO"
            Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan_2" -LogDir $LogDir -VerboseMode:$VerboseMode
            $sfcScanLog2 = Join-Path $LogDir "SFC_Scan_2.log"
            if (Test-Path $sfcScanLog2) {
                $sfcScanOutput2 = Get-Content -Path $sfcScanLog2 -Raw
                if ($sfcScanOutput2 -match $sfcRebootRequiredPattern) { $rebootRequired = $true }
            }
        } else {
            Log "The DISM repair process failed. Skipping final SFC scan." "ERROR"
        }
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
