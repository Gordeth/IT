param (
    [switch]$VerboseMode = $false
)

function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File "$env:TEMP\ITScripts\Log\MSO_UPDATE_log.txt" -Append
    if ($VerboseMode) {
        Write-Host "$timestamp $Message"
    }
}

Log "Starting Office update..."

try {
    $OfficeClient = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    if (Test-Path $OfficeClient) {
        if ($VerboseMode) {
            & $OfficeClient /update user forceappshutdown=true
        } else {
            & $OfficeClient /update user forceappshutdown=true | Out-Null
        }
        Log "Office update initiated. Please wait until it finishes."
    } else {
        Log "OfficeC2RClient.exe not found."
    }
} catch {
    Log "Failed to initiate Office update: $_"
}
