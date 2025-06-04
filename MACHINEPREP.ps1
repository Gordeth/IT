# MACHINEPREP.ps1
# ================== LOG FUNCTION ==================
function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File $LogFile -Append
    if ($VerboseMode) {
        Write-Host "$timestamp $Message"
    }
}

# ================== 1. Check if TeamViewer is installed ==================
Log "Checking if TeamViewer is installed..."
$tvInstalled = Get-ItemProperty -Path "HKLM:\Software\WOW6432Node\TeamViewer" -ErrorAction SilentlyContinue
if ($tvInstalled) {
    Log "TeamViewer is already installed. Skipping installation."
} else {
    Log "TeamViewer not found. Proceeding with installation..."
    Write-Host "Installing TeamViewer Host using winget..."
try {
    winget install --id=TeamViewer.TeamViewer.Host -e --accept-package-agreements --accept-source-agreements
    Write-Host "TeamViewer Host installed successfully."
} catch {
    Write-Host "Failed to install TeamViewer Host: $_"
    Exit 1
    }
}
# ================== 2. Check if WU.ps1 is available ==================
$WUPath = Join-Path $ScriptDir "WU.ps1"
if (-not (Test-Path $WUPath)) {
    Log "WU.ps1 not found. Downloading..."
    $WUUrl = "$ScriptDir/WU.ps1"
    try {
        Invoke-WebRequest -Uri $WUUrl -OutFile $WUPath -UseBasicParsing | Out-Null
        Log "WU.ps1 downloaded successfully."
    } catch {
        Log "Failed to download WU.ps1: $_"
        Exit 1
    }
} else {
    Log "WU.ps1 already exists. Skipping download."
}
# ================== 3. Run WU.ps1 ==================
Log "Running WU.ps1..."
try {
    if ($VerboseMode) {
        & $WUPath
    } else {
        & $WUPath | Out-Null
    }
    Log "WU.ps1 executed successfully."
} catch {
    Log "Error during execution of WU.ps1: $_"
    Exit 1
}

