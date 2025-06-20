param (
    [switch]$VerboseMode = $false,
    [string]$LogFile
)

# ==================== Validate LogFile ====================
if (-not $LogFile -or $LogFile.Trim() -eq "") {
    Write-Host "ERROR: LogFile path is not defined or is empty." -ForegroundColor Red
    exit 1
}

# ==================== Define Log Function ====================
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
        Write-Host "Failed to write to log file '$LogFile': $_" -ForegroundColor Red
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

# ==================== Begin Script Execution ====================
Log "Starting WGET.ps1 script. VerboseMode=$VerboseMode"
Log "Checking for package updates with winget..."

try {
    if ($VerboseMode) {
        winget upgrade --all
    } else {
        winget upgrade --all | Out-Null
    }
    Log "All packages updated successfully."
} catch {
    Log "Failed to update packages: $_" "ERROR"
}
