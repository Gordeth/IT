<#
.SYNOPSIS
    Tests the automated download of a Windows ISO using Fido.ps1.
.DESCRIPTION
    This script provides a dedicated way to test the Fido.ps1 integration. It downloads Fido,
    then uses it to download the latest matching Windows ISO for the current system, and finally
    cleans up the downloaded files. This is used to verify the fallback repair mechanism without
    running a full system repair.
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
.NOTES
    Script: TEST_FIDO.ps1
    Version: 1.0.0
    Dependencies:
        - PowerShell 5.1 or later.
        - Internet connectivity.
    Changelog:
        v1.0.0
        - Initial release. Logic extracted from REPAIR.ps1's -TestFido mode.
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

$LogFile = Join-Path $LogDir "TEST_FIDO.txt"

if (-not (Test-Path $LogFile)) {
    "Log file created by TEST_FIDO.ps1." | Out-File $LogFile -Append
}

# ==================== Script Execution ====================
Log "Starting TEST_FIDO.ps1 script..." "INFO"

Log "Running Fido ISO download test. This will download Fido.ps1 and a Windows ISO." "INFO"
$fidoUrl = "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1"

$fidoDir = Join-Path $PSScriptRoot "..\Fido"
New-Item -ItemType Directory -Path $fidoDir -Force | Out-Null
$fidoPath = Join-Path $fidoDir "Fido.ps1"

$isoDir = Join-Path $fidoDir "ISO"
New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
$isoPath = Join-Path $isoDir "Windows.iso"

try {
    if (Save-File -Url $fidoUrl -OutputPath $fidoPath) {
        Log "Fido.ps1 downloaded. Running it to download the ISO..." "INFO"
        
        $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
        $osLang = (Get-Culture).Name
        $osArch = if ((Get-CimInstance Win32_Processor).AddressWidth -eq 64) { "x64" } else { "x86" }
        $fidoVersionArg = if ($osVersion -like "10.0.22*") { "-Win11" } else { "-Win10" }
        $fidoArgs = "$fidoVersionArg -Latest -Arch $osArch -Language `"$osLang`""

        # Use Fido to get the download URL, then use our own robust download function.
        # This avoids issues where Fido exits before its background download completes.
        $processArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$fidoPath`" $fidoArgs -GetUrl"
        Log "Launching Fido to retrieve ISO download URL..." "INFO"
        $isoUrl = (Start-Process powershell.exe -ArgumentList $processArgs -Wait -NoNewWindow -PassThru | Get-Process).StandardOutput.ReadToEnd().Trim()

        if ($isoUrl -match '^https?://') {
            Log "ISO URL retrieved successfully. Starting download..." "INFO"
            if (-not (Save-File -Url $isoUrl -OutputPath $isoPath)) {
                throw "Failed to download the ISO file from the retrieved URL."
            }
        } else {
            throw "Failed to retrieve a valid download URL from Fido.ps1. Output: $isoUrl"
        }
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
    if (Test-Path $fidoDir) { Remove-Item $fidoDir -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned up Fido directory and its contents." "INFO" }
}

Log "==== TEST_FIDO Script Completed ===="
