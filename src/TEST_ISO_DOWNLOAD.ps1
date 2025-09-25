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

$isoDownloaded = $false
$isoPath = Join-Path $LogDir "Windows_Test.iso" # Default to temp folder for API download

try {
    # --- Tier 1: Attempt automated download via TechBench API ---
    Log "Attempting automated ISO download via TechBench API..." "INFO"
    try {
        $edition = (Get-CimInstance -Class Win32_OperatingSystem).Caption -replace "Microsoft Windows ", ""
        $language = (Get-Culture).Name
        $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        $version = if ($edition -like "*11*") { "Windows 11" } else { "Windows 10" }

        $params = @{
            type     = "Windows"
            version  = $version
            edition  = $edition
            language = $language
            arch     = $arch
        }
        $query = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join "&"
        $apiUrl = "https://tb.rg-adguard.net/api/GetFiles?$query"

        Log "Querying TechBench API: $apiUrl" "INFO"
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $isoLinks = ($response.Content | ConvertFrom-Json).files | Where-Object { $_.url -like "*.iso" }
        $isoUrl = $isoLinks[0].url

        if ($isoUrl -match '^https?://') {
            Log "API returned a valid URL. Starting download..." "INFO"
            if (Save-File -Url $isoUrl -OutputPath $isoPath) {
                $isoDownloaded = $true
                Log "Test successful. ISO downloaded via API to '$isoPath'." "INFO"
            }
        }
    } catch {
        Log "Automated ISO download via TechBench API failed: $_. Falling back to manual method." "WARN"
    }

    # --- Tier 2: Guided manual download via Media Creation Tool ---
    if (-not $isoDownloaded) {
        $mctPath = Join-Path $LogDir "MediaCreationTool.exe"
        $isoDir = Join-Path $PSScriptRoot "ISO"
        $isoPath = Join-Path $isoDir "Windows.iso" # Overwrite path to the correct final location for MCT
        try {
            New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
            $mctUrl = "https://go.microsoft.com/fwlink/?LinkId=691209"
            if (Save-File -Url $mctUrl -OutputPath $mctPath) {
                Log "Media Creation Tool downloaded. Launching now..." "INFO"
                Write-Host "INSTRUCTIONS:" -ForegroundColor Yellow
                Write-Host "1. The Media Creation Tool will now open."
                Write-Host "2. When prompted, choose 'Create installation media (USB flash drive, DVD, or ISO file)'."
                Write-Host "3. On the next screen, choose 'ISO file'."
                Write-Host "4. When asked where to save the file, navigate to the following folder and save it as 'Windows.iso':"
                Write-Host "   $isoDir" -ForegroundColor Cyan
                Write-Host "5. After the ISO is created, close the tool. The script will then resume."
                Write-Host ""
                Start-Process -FilePath $mctPath -Wait
                if (Test-Path $isoPath) {
                    $isoDownloaded = $true
                    Log "Test successful. ISO was created via MCT at '$isoPath'." "INFO"
                }
            }
        } finally {
            if (Test-Path $mctPath) { Remove-Item $mctPath -Force -ErrorAction SilentlyContinue }
        }
    }
} catch {
    Log "An error occurred during the ISO download test process: $_" "ERROR"
} finally {
    Log "Cleaning up test files..." "INFO"
    # Universal cleanup for any ISO file created by either method
    if ($isoDownloaded -and (Test-Path $isoPath)) { Remove-Item -Path $isoPath -Force -ErrorAction SilentlyContinue; Log "Cleaned up downloaded/created ISO file." "INFO" }
    $isoDir = Join-Path $PSScriptRoot "ISO" # Path for MCT folder
    if (Test-Path $isoDir) { Remove-Item $isoDir -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned up ISO creation directory." "INFO" }
}

Log "==== TEST_ISO_DOWNLOAD Script Completed ===="