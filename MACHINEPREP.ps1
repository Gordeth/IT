# MachinePrep.ps1
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
