# winget-upgrade.ps1

Write-Host "Checking for package updates with winget..." -ForegroundColor Cyan
try {
    winget upgrade --all --silent
    Write-Host "All packages updated successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to update packages. Error: $_" -ForegroundColor Red
}
