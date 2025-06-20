param (
    [switch]$VerboseMode = $false,
    [string]$LogFile
)
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
Log "Fetching list of upgradeable packages..."

try {
    $packages = winget upgrade --source winget --accept-source-agreements --output json | ConvertFrom-Json

    if (-not $packages) {
        Log "No upgradable packages found."
    } else {
        foreach ($pkg in $packages) {
            $name = $pkg.Name
            $id = $pkg.Id

            Log "Upgrading: $name ($id)..."

            try {
                $proc = Start-Process -FilePath "winget" -ArgumentList "upgrade --id `"$id`" --silent --accept-package-agreements" -Wait -PassThru -NoNewWindow
                $proc.WaitForExit()
                Log "$name upgraded successfully."
            } catch {
                Log "Failed to upgrade $name ($id): $_" "ERROR"
            }
        }
    }
} catch {
    Log "Failed to fetch or process winget packages: $_" "ERROR"
}

Log "WGET.ps1 script completed successfully."