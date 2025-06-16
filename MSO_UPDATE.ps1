function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    if ($VerboseMode -or $Level -eq "ERROR") {
        $color = switch ($Level) {
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
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
