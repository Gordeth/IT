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
$teamViewerPaths = @(
    "C:\Program Files\TeamViewer",
    "C:\Program Files (x86)\TeamViewer"
)
$tvInstalled = $false
foreach ($path in $teamViewerPaths) {
    if (Test-Path $path) {
        $tvInstalled = $true
        break
    }
}

if ($tvInstalled) {
    Log "TeamViewer is already installed. Skipping installation."
} else {
    Log "TeamViewer not found. Proceeding with installation..."
    # --- Example install using winget ---
    try {
        winget install --id=TeamViewer.TeamViewerHost --silent --accept-package-agreements --accept-source-agreements
        Log "TeamViewer Host installed successfully."
    } catch {
        Log "Failed to install TeamViewer Host: $_"
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
# ================== 4. Check if WGET.ps1 is available ==================
$WUPath = Join-Path $ScriptDir "WGET.ps1"
if (-not (Test-Path $WUPath)) {
    Log "WU.ps1 not found. Downloading..."
    $WUUrl = "$ScriptDir/WGET.ps1"
    try {
        Invoke-WebRequest -Uri $WUUrl -OutFile $WUPath -UseBasicParsing | Out-Null
        Log "WU.ps1 downloaded successfully."
    } catch {
        Log "Failed to download WGET.ps1: $_"
        Exit 1
    }
} else {
    Log "WU.ps1 already exists. Skipping download."
}
# ================== 5. Run WGET.ps1 ==================
Log "Running WGET.ps1..."
try {
    if ($VerboseMode) {
        & $WUPath
    } else {
        & $WUPath | Out-Null
    }
    Log "WGET.ps1 executed successfully."
} catch {
    Log "Error during execution of WGET.ps1: $_"
    Exit 1
}
# ================== 6. Install Default Apps ==================
$apps = @(
    @{ Name = "7-Zip"; Id = "7zip.7zip" },
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Adobe Acrobat Reader 64-bit"; Id = "Adobe.Acrobat.Reader.64-bit" }
)

foreach ($app in $apps) {
    $installed = winget list --name $app.Name -e | Where-Object { $_ }
    if ($installed) {
        Log "$($app.Name) is already installed. Skipping installation."
    } else {
        Log "$($app.Name) not found. Installing..."
        try {
            winget install --id=$($app.Id) -e --silent --accept-package-agreements --accept-source-agreements
            Log "$($app.Name) installed successfully."
        } catch {
            Log "Failed to install $($app.Name): $_"
            # continue to next app without exiting
        }
    }
}
