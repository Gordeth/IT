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
    # Attempt to download Fido.ps1. If the primary Save-File (curl) fails,
    # it might be due to User-Agent blocking. We'll add a fallback.
    $fidoDownloaded = Save-File -Url $fidoUrl -OutputPath $fidoPath
    if (-not $fidoDownloaded) {
        Log "Primary download method (curl) failed. Retrying with a basic WebClient..." "WARN"
        try {
            (New-Object System.Net.WebClient).DownloadFile($fidoUrl, $fidoPath)
            $fidoDownloaded = $true
        } catch {
            Log "Fallback download method also failed. Error: $_" "ERROR"
        }
    }
    if ($fidoDownloaded) {
        Log "Fido.ps1 downloaded. Running it to download the ISO..." "INFO"
        
        $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
        $osLang = (Get-Culture).Name
        $osArch = if ((Get-CimInstance Win32_Processor).AddressWidth -eq 64) { "x64" } else { "x86" }

        # Fido.ps1 compatibility fix: it expects 'pt-br' for Portuguese, not 'pt-PT'.
        if ($osLang -eq 'pt-PT') {
            Log "OS language is 'pt-PT'. Using 'pt-br' for Fido.ps1 compatibility." "INFO"
            $osLang = 'pt-br'
        }
        $fidoVersionArg = if ($osVersion -like "10.0.22*") { "-Win11" } else { "-Win10" }
        $fidoArgs = "$fidoVersionArg -Latest -Arch $osArch -Language `"$osLang`""
        
        # Reverting to the -OutFile method as it's more resilient to Microsoft's server-side blocking.
        # We will run the command directly in a new process and wait for it to complete.
        Log "Launching Fido to retrieve ISO download URL..." "INFO"
        
        # To avoid complex quoting issues, we build a script block and pass it as a Base64 encoded command.
        # This is the most reliable way to run complex commands in a new process.
        $scriptBlock = [scriptblock]::Create("& `"$fidoPath`" $fidoArgs -OutFile `"$isoPath`"")
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock.ToString()))
        
        $fidoProcess = Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encodedCommand" -Wait -PassThru -NoNewWindow
        if ($fidoProcess.ExitCode -ne 0) {
            throw "Fido.ps1 process exited with non-zero code: $($fidoProcess.ExitCode)"
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
