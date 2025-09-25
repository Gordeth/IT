<#
.SYNOPSIS
    Performs a guided in-place upgrade of Windows.
.DESCRIPTION
    This script automates the process of performing an in-place upgrade of Windows.
    It downloads and launches the Media Creation Tool (MCT), guides the user to create
    a Windows ISO, and then uses that ISO to run a silent, unattended in-place upgrade.
    This is a powerful repair method that keeps user files and applications.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
.NOTES
    Script: UW.ps1
    Version: 1.0.1
    Dependencies:
        - PowerShell 5.1 or later.
        - Internet connectivity.
    Changelog:
        v1.0.1
        - Renamed script from UPGRADE_WIN.ps1 to UW.ps1.
        v1.0.0
        - Initial release.
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

$LogFile = Join-Path $LogDir "UW.txt"

if (-not (Test-Path $LogFile)) {
    "Log file created by UW.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution ====================
Log "Starting UW.ps1 script..." "INFO"

$mctPath = Join-Path $LogDir "MediaCreationTool.exe"
$isoDir = Join-Path $PSScriptRoot "ISO"
$isoPath = Join-Path $isoDir "Windows.iso"
$mountResult = $null

try {
    New-Item -ItemType Directory -Path $isoDir -Force | Out-Null

    $mctUrl = "https://go.microsoft.com/fwlink/?LinkId=691209"
    Log "Downloading Media Creation Tool..." "INFO"
    if (Save-File -Url $mctUrl -OutputPath $mctPath) {
        Log "Media Creation Tool downloaded. Launching now..." "INFO"
        Write-Host "INSTRUCTIONS:" -ForegroundColor Yellow
        Write-Host "1. The Media Creation Tool will now open."
        Write-Host "2. When prompted, choose 'Create installation media (USB flash drive, DVD, or ISO file)'."
        Write-Host "3. On the next screen, choose 'ISO file'."
        Write-Host "4. When asked where to save the file, navigate to the following folder and save it as 'Windows.iso':"
        Write-Host "   $isoDir" -ForegroundColor Cyan
        Write-Host "5. After the ISO is created, close the tool. The script will then resume to start the upgrade."
        Write-Host ""
        Start-Process -FilePath $mctPath -Wait

        if (Test-Path $isoPath) {
            Log "ISO created. Mounting it to begin the in-place upgrade..." "INFO"
            $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
            $driveLetter = ($mountResult | Get-Volume).DriveLetter
            $setupPath = Join-Path "${driveLetter}:\" "setup.exe"
            if (Test-Path $setupPath) {
                Log "Starting Windows in-place upgrade. This will take a significant amount of time and the system will reboot." "INFO"
                $upgradeArgs = "/auto upgrade /quiet /compat IgnoreWarning /showoobe none /noreboot"
                Invoke-CommandWithLogging -FilePath $setupPath -Arguments $upgradeArgs -LogName "InPlace_Upgrade" -LogDir $LogDir -VerboseMode:$VerboseMode
            }
        } else {
            Log "ISO file was not found at the expected path. Aborting upgrade." "ERROR"
        }
    }
} catch {
    Log "An error occurred during the in-place upgrade process: $_" "ERROR"
} finally {
    Log "Cleaning up..." "INFO"
    if ($mountResult) { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue }
    if (Test-Path $mctPath) { Remove-Item $mctPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $isoDir) { Remove-Item $isoDir -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned up ISO creation directory." "INFO" }
}

Log "==== UW Script Completed ===="