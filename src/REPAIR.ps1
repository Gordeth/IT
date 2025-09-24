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

# Define paths to system executables.
$sfcPath = "$env:windir\System32\sfc.exe"

# --- Step 1: Run SFC in verification mode and parse console output ---
try {
    Log "Running System File Checker (SFC) in verification-only mode..." "INFO"
    # Use the centralized logging function for consistent real-time output and logging.
    Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/verifyonly" -LogName "SFC_Verify" -LogDir $LogDir -VerboseMode:$VerboseMode
    
    $sfcVerifyLog = Join-Path $LogDir "SFC_Verify.log"
    $sfcVerifyOutput = Get-Content -Path $sfcVerifyLog -Raw
    
    $normalizedOutput = ($sfcVerifyOutput -replace '[^a-zA-Z0-9]').ToLower()
    $successPattern = "windowsresourceprotectiondidnotfindanyintegrityviolations"
    $foundPattern = "windowsresourceprotectionfoundintegrityviolations"
    $couldnotPattern = "windowsresourceprotectioncouldnotperformtherequestedoperation"

    if ($normalizedOutput -match $successPattern) {
        Log "SFC verification completed. No integrity violations found. System files are healthy." "INFO"
        Log "==== REPAIR Script Completed ===="; exit 0
    } elseif ($normalizedOutput -match $foundPattern) {
        Log "SFC verification found integrity violations. A repair will be initiated." "WARN"
    } elseif ($normalizedOutput -match $couldnotPattern) {
        Log "SFC could not perform the requested operation. Proceeding with repair." "WARN"
    } else {
        Log "SFC output could not be parsed reliably. Proceeding with repair as a precaution." "WARN"
    }
} catch {
    Log "An unexpected error occurred during SFC /verifyonly operation: $($_.Exception.Message)" "ERROR"
    Log "Assuming a repair is needed due to the error." "WARN"
}

# --- Step 2: Confirm with user if in verbose mode. ---
$proceedWithRepair = if ($VerboseMode) {
    $choice = Read-Host "SFC found potential issues. Do you wish to run a full repair (SFC /scannow)? (Y/N)"
    $choice -match '^(?i)y(es)?$'
} else {
    Log "Silent mode enabled. Proceeding with repair automatically." "INFO"; $true
}

if (-not $proceedWithRepair) {
    Log "User chose not to proceed with the system file repair. Skipping." "INFO"
    Log "==== REPAIR Script Completed ===="; exit 0
}

# --- Step 3: Create System Restore Point before repair ---
New-SystemRestorePoint -Description "Pre-System_Repair"

# --- Step 4: Run SFC in repair mode and handle reboot ---
$rebootRequired = $false
try {
    Log "Running System File Checker (SFC) in repair mode (scannow)..." "INFO"
    # First SFC run
    Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan_1" -LogDir $LogDir -VerboseMode:$VerboseMode
    
    $sfcScanLog1 = Join-Path $LogDir "SFC_Scan_1.log"
    if (Test-Path $sfcScanLog1) {
        $sfcScanOutput1 = Get-Content -Path $sfcScanLog1 -Raw
        $normalizedOutput1 = ($sfcScanOutput1 -replace '[^a-zA-Z0-9]').ToLower()

        # Define patterns for different outcomes
        $sfcSuccessRepairedPattern = "windowsresourceprotectionfoundintegrityviolationsandsuccessfullyrepairedthem"
        $sfcFailureUnableToFixPattern = "windowsresourceprotectionfoundintegrityviolationsbutwasunabletofixsomeofthem"
        $sfcFailureCouldNotPerformPattern = "windowsresourceprotectioncouldnotperformtherequestedoperation"
        $sfcSuccessNoViolationsPattern = "windowsresourceprotectiondidnotfindanyintegrityviolations"
        $sfcRebootRequiredPattern = "repairstotakeeffect"

        if ($normalizedOutput1 -match $sfcSuccessRepairedPattern) {
            Log "SFC /scannow completed and successfully repaired system files." "INFO"
            $rebootRequired = $true
        } elseif ($normalizedOutput1 -match $sfcFailureUnableToFixPattern -or $normalizedOutput1 -match $sfcFailureCouldNotPerformPattern) {
            Log "SFC /scannow could not repair all files. Attempting to repair the Windows Component Store with DISM." "WARN"
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
                    Log "DISM /RestoreHealth failed with exit code $dismRestoreHealthExitCode. Manual intervention may be required." "ERROR"
                    $dismFailed = $true
                }
            } catch {
                Log "A critical error occurred during the DISM repair sequence: $($_.Exception.Message)" "ERROR"
                $dismFailed = $true
            }

            if (-not $dismFailed) {
                Log "DISM repair sequence completed. Running SFC /scannow again to finalize repairs." "INFO"
                # Second SFC run
                Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan_2" -LogDir $LogDir -VerboseMode:$VerboseMode

                $sfcScanLog2 = Join-Path $LogDir "SFC_Scan_2.log"
                if (Test-Path $sfcScanLog2) {
                    $sfcScanOutput2 = Get-Content -Path $sfcScanLog2 -Raw
                    $normalizedOutput2 = ($sfcScanOutput2 -replace '[^a-zA-Z0-9]').ToLower()

                    if ($normalizedOutput2 -match $sfcSuccessRepairedPattern) {
                        Log "SFC (second run) successfully repaired remaining system files." "INFO"
                        $rebootRequired = $true
                    } elseif ($normalizedOutput2 -match $sfcSuccessNoViolationsPattern) {
                        Log "SFC (second run) completed and found no integrity violations. The system is now healthy." "INFO"
                    } else {
                        Log "SFC (second run) still reports errors. Manual intervention is required. Review CBS.log and all DISM logs." "ERROR"
                    }
                    if ($normalizedOutput2 -match $sfcRebootRequiredPattern) { $rebootRequired = $true }
                }
            } else {
                Log "The DISM repair process failed. Skipping the second SFC scan. Manual intervention is required. Review all DISM logs in '$LogDir'." "ERROR"
            }
        } elseif ($normalizedOutput1 -match $sfcSuccessNoViolationsPattern) {
            Log "SFC /scannow completed and found no integrity violations." "INFO"
        } else {
            Log "SFC /scannow completed with an unparsed result. Review SFC_Scan_1.log for details." "WARN"
        }

        if ($normalizedOutput1 -match $sfcRebootRequiredPattern) { $rebootRequired = $true }
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