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

$isoPath = Join-Path $LogDir "Windows_Test.iso"

try {
    # Determine which download page to open based on the OS version and language.
    $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
    $osLang = (Get-Culture).Name.ToLower() # e.g., 'en-us', 'pt-pt'

    $downloadPageUrl = if ($osVersion -like "10.0.22*") {
        "https://www.microsoft.com/$osLang/software-download/windows11?ua=mac"
    } else {
        "https://www.microsoft.com/$osLang/software-download/windows10?ua=mac"
    }

    Log "Opening the Microsoft ISO download page in your browser..." "INFO"
    Write-Host "INSTRUCTIONS:" -ForegroundColor Yellow
    Write-Host "1. A browser window will open to the Microsoft download page."
    Write-Host "2. Select your Windows edition, language, and architecture (64-bit)."
    Write-Host "3. After you confirm, the page will generate a direct download link."
    Write-Host "4. Right-click the 'Download' button and select 'Copy link'."
    Write-Host "5. Paste the copied link into the prompt below and press Enter."
    Start-Process "msedge.exe" $downloadPageUrl

    $isoUrl = Read-Host "Please paste the direct download link for the Windows ISO file here"
    if ($isoUrl -match '^https?://') {
        Log "Downloading ISO to temporary path: $isoPath..." "INFO"
        if (Save-File -Url $isoUrl -OutputPath $isoPath) {
            Log "Test download successful. ISO created at '$isoPath'." "INFO"
        }
    } else {
        Log "Invalid URL provided. Skipping download." "ERROR"
    }
} catch {
    Log "An error occurred during the ISO download test process: $_" "ERROR"
} finally {
    Log "Cleaning up test files..." "INFO"
    if (Test-Path $isoPath) { Remove-Item $isoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up downloaded test ISO file." "INFO" }
}

Log "==== TEST_ISO_DOWNLOAD Script Completed ===="