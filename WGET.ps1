param (
    [switch]$VerboseMode = $false
)
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

Log "Checking for package updates with winget..."
try {
    if ($VerboseMode) {
        winget upgrade --all
    } else {
        winget upgrade --all | Out-Null
    }
    Log "All packages updated successfully."
} catch {
    Log "Failed to update packages: $_"
}
