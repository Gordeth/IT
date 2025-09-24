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
  [string]$LogDir,
  [switch]$TestFido = $false
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

# --- Fido Test Mode ---
if ($TestFido) {
    Log "Running in Fido Test Mode. This will only test the ISO download functionality." "INFO"
    $fidoUrl = "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1"
    
    # Create a dedicated directory for the Fido script at the project root
    $fidoDir = Join-Path $PSScriptRoot "..\Fido"
    New-Item -ItemType Directory -Path $fidoDir -Force | Out-Null
    $fidoPath = Join-Path $fidoDir "Fido.ps1"

    # Create a dedicated directory for the ISO inside the Fido folder
    $isoDir = Join-Path $fidoDir "ISO"
    New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
    $isoPath = Join-Path $isoDir "Windows.iso"
    try {
        if (Save-File -Url $fidoUrl -OutputPath $fidoPath) {
            Log "Fido.ps1 downloaded. Running it to download the ISO..." "INFO"
            
            # Determine current Windows version to pass to Fido
            $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
            $osLang = (Get-Culture).Name
            $osArch = if ((Get-CimInstance Win32_Processor).AddressWidth -eq 64) { "x64" } else { "x86" }

            $fidoVersionArg = if ($osVersion -like "10.0.22*") { "-Win11" } else { "-Win10" }

            # Construct fully non-interactive arguments for Fido.ps1
            $fidoArgs = "$fidoVersionArg -Latest -Arch $osArch -Language `"$osLang`""
            
            # Execute Fido.ps1 in a new process to prevent its 'exit' command from closing the main script.
            # We can't pipe input to Start-Process, so we rely on Fido's non-interactive parameters.
            # The -OutFile parameter makes Fido non-interactive and automatically downloads the latest version.
            $processArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$fidoPath`" $fidoArgs -OutFile `"$isoPath`""
            Log "Launching Fido in a new process with arguments: $processArgs" "INFO"
            $fidoProcess = Start-Process powershell.exe -ArgumentList $processArgs -Wait -PassThru
            if ($fidoProcess.ExitCode -ne 0) { throw "Fido.ps1 process exited with non-zero code: $($fidoProcess.ExitCode)" }

            if (Test-Path $isoPath) {
                Log "Fido ISO download test successful. ISO created at '$isoPath'." "INFO"
            } else {
                Log "Fido ISO download test failed. ISO file was not created." "ERROR"
            }
        }
    } catch {
        Log "An error occurred during the Fido.ps1 test process: $_" "ERROR"
    } finally {
        Log "Cleaning up Fido test files..." "INFO"
        if (Test-Path $fidoPath) { Remove-Item $fidoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up Fido.ps1." "INFO" }
        if (Test-Path $isoPath) { Remove-Item $isoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up downloaded ISO file." "INFO" }
    }
    Log "==== REPAIR Script (Fido Test Mode) Completed ===="
    exit 0
}


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

         # Check the final exit code after online attempts.
         if ($dismRestoreHealthExitCode -ne 0) {
             Log "DISM /RestoreHealth failed after all online attempts with final exit code $dismRestoreHealthExitCode." "ERROR"
             
             # --- Final Fallback: Use Fido.ps1 to download a matching ISO automatically ---
             Log "Attempting final repair by downloading a matching Windows ISO using Fido.ps1..." "INFO"
             $fidoUrl = "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1"
             
             # Create a dedicated directory for the Fido script at the project root
             $fidoDir = Join-Path $PSScriptRoot "..\Fido"
             New-Item -ItemType Directory -Path $fidoDir -Force | Out-Null
             $fidoPath = Join-Path $fidoDir "Fido.ps1"

             # Create a dedicated directory for the ISO inside the Fido folder
             $isoDir = Join-Path $fidoDir "ISO"
             New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
             $isoPath = Join-Path $isoDir "Windows.iso"
             try {
                 if (Save-File -Url $fidoUrl -OutputPath $fidoPath) {
                     Log "Fido.ps1 downloaded. Running it to download the ISO..." "INFO"
                     
                     # Determine current Windows version to pass to Fido
                     $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
                     $osLang = (Get-Culture).Name
                     $osArch = if ((Get-CimInstance Win32_Processor).AddressWidth -eq 64) { "x64" } else { "x86" }

                     $fidoVersionArg = if ($osVersion -like "10.0.22*") { "-Win11" } else { "-Win10" }

                     # Construct fully non-interactive arguments for Fido.ps1
                     $fidoArgs = "$fidoVersionArg -Latest -Arch $osArch -Language `"$osLang`""
                     
                     # Execute Fido.ps1 in a new process to prevent its 'exit' command from closing the main script.
                     # We can't pipe input to Start-Process, so we rely on Fido's non-interactive parameters.
                     # The -OutFile parameter makes Fido non-interactive and automatically downloads the latest version.
                     $processArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$fidoPath`" $fidoArgs -OutFile `"$isoPath`""
                     Log "Launching Fido in a new process with arguments: $processArgs" "INFO"
                     $fidoProcess = Start-Process powershell.exe -ArgumentList $processArgs -Wait -PassThru
                     if ($fidoProcess.ExitCode -ne 0) { throw "Fido.ps1 process exited with non-zero code: $($fidoProcess.ExitCode)" }

                     Log "Attempting to repair using downloaded ISO: $isoPath" "INFO"
                     $mountResult = $null
                     try {
                         $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
                         $driveLetter = ($mountResult | Get-Volume).DriveLetter
                         $wimPath = Join-Path "${driveLetter}:\" "sources\install.wim"
                         $esdPath = Join-Path "${driveLetter}:\" "sources\install.esd"
                         $sourceFile = if (Test-Path $wimPath) { $wimPath } elseif (Test-Path $esdPath) { $esdPath } else { $null }

                         if ($sourceFile) {
                             $sourceType = if ($sourceFile -like "*.wim") { "wim" } else { "esd" }
                             $dismArgs = "/Online /Cleanup-Image /RestoreHealth /Source:${sourceType}:${sourceFile}:1 /LimitAccess"
                             Log "Running DISM with offline source: $dismArgs" "INFO"
                             $dismRestoreHealthExitCode = Invoke-CommandWithLogging -FilePath $dismPath -Arguments $dismArgs -LogName "DISM_RestoreHealth_ISO" -LogDir $LogDir -VerboseMode:$VerboseMode
                         } else {
                             Log "Could not find install.wim or install.esd in the downloaded ISO. Skipping offline repair." "ERROR"
                         }
                     } finally {
                         if ($mountResult) { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue }
                     }
                 }
             } catch {
                 Log "An error occurred during the Fido.ps1/ISO repair process: $_" "ERROR"
             } finally {
                 if (Test-Path $fidoPath) { Remove-Item $fidoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up Fido.ps1." "INFO" }
                 if (Test-Path $isoPath) { Remove-Item $isoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up downloaded ISO file." "INFO" }
             }
         }
         if ($dismRestoreHealthExitCode -ne 0) { # Final check after all possible attempts
             Log "All DISM repair attempts have failed. Manual intervention is required." "ERROR"
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