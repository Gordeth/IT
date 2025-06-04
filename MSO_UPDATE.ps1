# office-update.ps1

$OfficeUpdatePath = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
$UpdateArgs = "/update user forceappshutdown=true"

Log "Starting Microsoft Office update..."
try {
    Start-Process -FilePath $OfficeUpdatePath -ArgumentList $UpdateArgs -Wait
    Log "Microsoft Office update completed."
} catch {
    Log "Error during Microsoft Office update: $_"
}
