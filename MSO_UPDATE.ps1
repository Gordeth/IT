param (
    [switch]$VerboseMode = $false
)

function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File "$env:TEMP\ITScripts\Log\MSO_UPDATE.txt" -Append
    if ($VerboseMode) {
        Write-Host "$timestamp $Message"
    }
}

if (-not $VerboseMode) {
    $VerbosePreference = "SilentlyContinue"
    $InformationPreference = "SilentlyContinue"
    $ProgressPreference = "SilentlyContinue"
    $WarningPreference = "SilentlyContinue"
    $ErrorActionPreference = "SilentlyContinue"
    $DebugPreference = "SilentlyContinue"
}

Log "Starting Office update..."

try {
    $OfficeClient = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    if (Test-Path $OfficeClient) {
        Log "Launching Office update silently..."
        Start-Process -FilePath $OfficeClient -ArgumentList "/update user forceappshutdown=true" -WindowStyle Hidden -Wait
        Log "Office update launched."
    } else {
        Log "OfficeC2RClient.exe not found."
    }
} catch {
    Log "Failed to launch Office update: $_"
}
