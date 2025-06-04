# MACHINEPREP.ps1
# ============================================
# Prepares the machine by installing TeamViewer Host.
# ============================================

Write-Host "Installing TeamViewer Host using winget..."
try {
    winget install --id=TeamViewer.TeamViewer.Host -e --accept-package-agreements --accept-source-agreements
    Write-Host "TeamViewer Host installed successfully."
} catch {
    Write-Host "Failed to install TeamViewer Host: $_"
    Exit 1
}

Log "Running Windows Update..."
$WUPath = "$env:TEMP\ITScripts\WU.ps1"
if (Test-Path $WUPath) {
    Log "Running Windows Update script..."
    try {
        & $WUPath *>&1 | Out-Null
        Log "Windows Update script completed successfully."
    } catch {
        Log "Error running Windows Update script: $_"
    }
} else {
    Log "WU.ps1 not found. Skipping Windows Update."
}

