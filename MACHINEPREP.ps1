# MACHINEPREP.ps1
# ================== LOG FUNCTION ==================
param (
    [switch]$VerboseMode = $false
)

function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File "$env:TEMP\ITScripts\Log\MACHINEPREP_log.txt" -Append
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
$WGETPath = Join-Path $ScriptDir "WGET.ps1"
if (-not (Test-Path $WGETPath)) {
    Log "WGET.ps1 not found. Downloading..."
    $WGETUrl = "$BaseUrl/WGET.ps1"
    try {
        Invoke-WebRequest -Uri $WGETUrl -OutFile $WGETPath -UseBasicParsing | Out-Null
        Log "WGET.ps1 downloaded successfully."
    } catch {
        Log "Failed to download WGET.ps1: $_"
        Exit 1
    }
} else {
    Log "WGET.ps1 already exists. Skipping download."
}
# ================== 5. Run WGET.ps1 ==================
Log "Running WGET.ps1..."
try {
    if ($VerboseMode) {
        & $WGETPath
    } else {
        & $WGETPath | Out-Null
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
# ================== 7. Ask to install OpenVPN Connect ==================
Log "Prompting for OpenVPN Connect installation..."
$openvpnChoice = Read-Host "Do you want to install OpenVPN Connect? (Y/N)"
if ($openvpnChoice -match '^(?i)y(es)?$') {
    Log "User chose to install OpenVPN Connect. Installing..."
    try {
        winget install --id=OpenVPNTechnologies.OpenVPN -e --scope machine --silent --accept-package-agreements --accept-source-agreements
        Log "OpenVPN Connect installed successfully."
    } catch {
        Log "Failed to install OpenVPN Connect: $_"
    }
} else {
    Log "User chose not to install OpenVPN Connect. Skipping installation."
}
# ================== 8. Install Driver Update App based on machine brand ==================
try {
    Log "Detecting machine brand..."
    $brand = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    Log "Detected manufacturer: $brand"

    switch -Wildcard ($brand) {
        "*Lenovo*" {
            Log "Installing Lenovo Vantage..."
            winget install --id=9WZDNCRFJ4MV -e --silent --accept-package-agreements --accept-source-agreements
            Log "Lenovo Vantage installed successfully."
        }
        "*HP*" {
            Log "Installing HP Support Assistant..."
            winget install --id=9NBB0P7HPH4S -e --silent --accept-package-agreements --accept-source-agreements
            Log "HP Support Assistant installed successfully."
        }
        "*Dell*" {
            Log "Installing Dell Command Update..."
            winget install --id=Dell.CommandUpdate -e --silent --accept-package-agreements --accept-source-agreements
            Log "Dell Command Update installed successfully."
        }
        default {
            Log "No specific driver update app found for $brand. Skipping..."
        }
    }
} catch {
    Log "Error during driver update app installation: $_"
}
   # ================== 9. Install Disk Management App based on disk brand ==================
try {
    Log "Detecting disk brand..."
    $disk = Get-WmiObject Win32_DiskDrive | Select-Object -First 1
    $diskBrand = $disk.Manufacturer
    if (-not $diskBrand) {
        $diskBrand = $disk.Model
    }
    if (-not $diskBrand) {
        $diskBrand = $disk.Caption
    }

    Log "Raw disk object: $($disk | Out-String)"
    Log "Detected disk brand/model: $diskBrand"

    # Extract brand from string
    if ($diskBrand -match "Samsung|Kingston|Crucial|Western Digital|Intel|SanDisk") {
        $diskBrand = $matches[0]
    } else {
        # Default to first word
        $diskBrand = $diskBrand.Split(" ")[0]
    }

    Log "Parsed disk brand: $diskBrand"

    switch -Wildcard ($diskBrand) {
        "*Samsung*" {
            Log "Installing Samsung Magician..."
            winget install --id=Samsung.SamsungMagician -e --silent --accept-package-agreements --accept-source-agreements
            Log "Samsung Magician installed successfully."
        }
        "*Kingston*" {
            Log "Installing Kingston SSD Manager..."
            winget install --id=Kingston.SSDManager -e --silent --accept-package-agreements --accept-source-agreements
            Log "Kingston SSD Manager installed successfully."
        }
        "*Crucial*" {
            Log "Installing Crucial Storage Executive..."
            winget install --id=Micron.CrucialStorageExecutive -e --silent --accept-package-agreements --accept-source-agreements
            Log "Crucial Storage Executive installed successfully."
        }
        "*Western Digital*" {
            Log "Installing Western Digital Dashboard..."
            winget install --id=WesternDigital.WDSSDDashboard -e --silent --accept-package-agreements --accept-source-agreements
            Log "WD SSD Dashboard installed successfully."
        }
        "*Intel*" {
            Log "Installing Intel Memory and Storage Tool..."
            winget install --id=Intel.MemoryAndStorageTool -e --silent --accept-package-agreements --accept-source-agreements
            Log "Intel Memory and Storage Tool installed successfully."
        }
        "*SanDisk*" {
            Log "Installing SanDisk SSD Dashboard..."
            winget install --id=SanDisk.SSDDashboard -e --silent --accept-package-agreements --accept-source-agreements
            Log "SanDisk SSD Dashboard installed successfully."
        }
        default {
            Log "No specific disk management app found for $diskBrand. Skipping..."
        }
    }
} catch {
    Log "Error during disk management app installation: $_"
}
