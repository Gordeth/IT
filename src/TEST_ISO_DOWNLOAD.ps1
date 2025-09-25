<#
.SYNOPSIS
    Tests the guided download of a Windows ISO by spoofing a browser user agent.
.DESCRIPTION
    This script provides a dedicated way to test the manual ISO download fallback. It opens
    the Microsoft software download page in Edge with a spoofed Mac user agent, which
    tricks the site into providing a direct download link. It then prompts the user to
    paste this link to complete a test download.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
.NOTES
    Script: TEST_ISO_DOWNLOAD.ps1
    Version: 1.0.0
    Dependencies:
        - PowerShell 5.1 or later.
        - Microsoft Edge browser.
        - Internet connectivity.
    Changelog:
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

$LogFile = Join-Path $LogDir "TEST_ISO_DOWNLOAD.txt"

if (-not (Test-Path $LogFile)) {
    "Log file created by TEST_ISO_DOWNLOAD.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution ====================
Log "Starting TEST_ISO_DOWNLOAD.ps1 script..." "INFO"

$uupDumpDir = Join-Path $PSScriptRoot "..\UUP_Dump"
$uupScriptPath = Join-Path $uupDumpDir "uup-dump-get-windows-iso.ps1"
$isoDir = Join-Path $uupDumpDir "ISO"

try {
    Log "Testing fully automated ISO download via UUP Dump API..." "INFO"
    New-Item -ItemType Directory -Path $uupDumpDir -Force | Out-Null
    New-Item -ItemType Directory -Path $isoDir -Force | Out-Null

    $uupScriptUrl = "https://raw.githubusercontent.com/rgl/uup-dump-get-windows-iso/master/uup-dump-get-windows-iso.ps1"
    Log "Downloading UUP Dump script from '$uupScriptUrl'..." "INFO"
    Invoke-WebRequest -Uri $uupScriptUrl -OutFile $uupScriptPath

    if (Test-Path $uupScriptPath) {
        Log "UUP Dump script downloaded. Determining OS target..." "INFO"
        $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
        $targetName = if ($osVersion -like "10.0.22*") { "windows-11" } else { "windows-10" }
        Log "OS target set to '$targetName'." "INFO"

        $commandString = "& `"$uupScriptPath`" -windowsTargetName `"$targetName`" -windowsEditionName `"Pro`" -destinationDirectory `"$isoDir`""
        $scriptBlock = [scriptblock]::Create($commandString)
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock.ToString()))
        
        Log "Executing UUP Dump script. This will take a long time as it downloads and builds the ISO..." "INFO"
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encodedCommand" -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            throw "UUP Dump script process exited with non-zero code: $($process.ExitCode)"
        }

        $isoFile = Get-ChildItem -Path $isoDir -Filter "*.iso" | Select-Object -First 1
        if ($isoFile) {
            Log "Test successful. ISO created at '$($isoFile.FullName)'." "INFO"
        } else {
            Log "Test failed. UUP Dump script completed but no ISO file was found in '$isoDir'." "ERROR"
        }
    } else {
        Log "Failed to download the UUP Dump script. Aborting test." "ERROR"
    }
} catch {
    Log "An error occurred during the ISO download test process: $_" "ERROR"
} finally {
    Log "Cleaning up test files..." "INFO"
    if (Test-Path $uupDumpDir) { Remove-Item $uupDumpDir -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned up UUP Dump directory and its contents." "INFO" }
}

Log "==== TEST_ISO_DOWNLOAD Script Completed ===="