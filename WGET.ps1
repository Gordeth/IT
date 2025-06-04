param (
    [switch]$VerboseMode = $false
)

function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File "$env:TEMP\ITScripts\Log\WGET_log.txt" -Append
    if ($VerboseMode) {
        Write-Host "$timestamp $Message"
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
