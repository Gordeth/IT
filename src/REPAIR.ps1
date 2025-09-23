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
    Version: 1.0.0
    Dependencies:
        - PowerShell 5.1 or later.
    Changelog:
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
Log "Starting REPAIR.ps1 script v1.0.0..." "INFO"

Log "Starting system file integrity check and repair process..." "INFO"

# Define paths to system executables.
$sfcPath = "$env:windir\System32\sfc.exe"

# --- Step 1: Run SFC in verification mode and parse console output ---
try {
    Log "Running System File Checker (SFC) in verification-only mode..." "INFO"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $sfcPath
    $pinfo.Arguments = "/verifyonly"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::Unicode
    $pinfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode

    $sfcOutputText = ""
    try {
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $output = $p.StandardOutput.ReadToEnd()
        $errors = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $sfcOutputText = $output + $errors
    } finally {
        if ($p) { $p.Dispose() }
    }

    $normalizedOutput = ($sfcOutputText -replace '[^a-zA-Z0-9]').ToLower()
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
    Invoke-CommandWithLogging -FilePath $sfcPath -Arguments "/scannow" -LogName "SFC_Scan" -LogDir $LogDir -VerboseMode:$VerboseMode
    
    $sfcScanLog = Join-Path $LogDir "SFC_Scan.log"
    if (Test-Path $sfcScanLog) {
        $sfcScanOutput = Get-Content -Path $sfcScanLog -Raw
        $normalizedOutput = ($sfcScanOutput -replace '[^a-zA-Z0-9]').ToLower()

        if ($normalizedOutput -match "windowsresourceprotectionfoundintegrityviolationsandsuccessfullyrepairedthem") {
            Log "SFC /scannow completed and successfully repaired system files." "INFO"
        } elseif ($normalizedOutput -match "windowsresourceprotectionfoundintegrityviolationsbutwasunabletofixsomeofthem") {
            Log "SFC /scannow found corrupt files but was UNABLE to fix them. Manual review of CBS.log is required (C:\Windows\Logs\CBS\CBS.log)." "ERROR"
        } elseif ($normalizedOutput -match "windowsresourceprotectioncouldnotperformtherequestedoperation") {
            Log "SFC /scannow could not perform the repair. Manual review of CBS.log is required." "ERROR"
        }

        if ($normalizedOutput -match "repairstotakeeffect") {
            Log "A system reboot is required to complete the file repairs." "WARN"; $rebootRequired = $true
        }
    }
} catch {
    Log "An unexpected error occurred during SFC /scannow operation: $($_.Exception.Message)" "ERROR"
}

if ($rebootRequired) {
    $proceedWithReboot = if ($VerboseMode) { (Read-Host "A reboot is required. Reboot now? (Y/N)").ToUpper() -eq 'Y' } else { $true }
    if ($proceedWithReboot) {
        Log "Initiating restart..."; Restart-Computer -Force
    } else {
        Log "User denied reboot. Please reboot later to complete repairs."
    }
}

Log "==== REPAIR Script Completed ===="