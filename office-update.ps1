# office-update.ps1

Write-Host "Updating Microsoft Office..." -ForegroundColor Cyan
try {
    & "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe" /update user forceappshutdown=true
    Write-Host "Microsoft Office update triggered successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to update Microsoft Office. Error: $_" -ForegroundColor Red
}
