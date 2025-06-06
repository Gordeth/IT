# MACHINEPREP.ps1

param (
    [switch]$VerboseMode = $false
)

# ================== LOG FUNCTION ==================
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "dd-MM-yyyyHH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
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

# ================== SCRIPT START ==================
Log "==== MACHINEPREP Script Started ===="

# ========== 1. Check if TeamViewer is installed ==========
try {
    Log "Checking for TeamViewer installation..."
    $teamViewerPaths = @(
        "C:\Program Files\TeamViewer",
        "C:\Program Files (x86)\TeamViewer"
    )
    $tvInstalled = $teamViewerPaths | Where-Object { Test-Path $_ }

    if ($tvInstalled) {
        Log "TeamViewer already installed. Skipping installation."
    } else {
        Log "Installing TeamViewer Host..."
        winget install --id=TeamViewer.TeamViewerHost --silent --accept-package-agreements --accept-source-agreements
        Log "TeamViewer Host installed successfully."
    }
} catch {
    Log "Error installing TeamViewer: $_"
}

# ========== 2. Ensure WU.ps1 is present ==========
try {
    $WUPath = Join-Path $ScriptDir "WU.ps1"
    if (-not (Test-Path $WUPath)) {
        Log "WU.ps1 not found. Downloading..."
        $WUUrl = "$ScriptDir/WU.ps1"
        Invoke-WebRequest -Uri $WUUrl -OutFile $WUPath -UseBasicParsing | Out-Null
        Log "WU.ps1 downloaded successfully."
    } else {
        Log "WU.ps1 already exists. Skipping download."
    }

    Log "Running WU.ps1..."
    & $WUPath | Out-Null
    Log "WU.ps1 executed successfully."
} catch {
    Log "Error with WU.ps1: $_"
}

# ========== 3. Ensure WGET.ps1 is present ==========
try {
    $WGETPath = Join-Path $ScriptDir "WGET.ps1"
    if (-not (Test-Path $WGETPath)) {
        Log "WGET.ps1 not found. Downloading..."
        $WGETUrl = "$BaseUrl/WGET.ps1"
        Invoke-WebRequest -Uri $WGETUrl -OutFile $WGETPath -UseBasicParsing | Out-Null
        Log "WGET.ps1 downloaded successfully."
    } else {
        Log "WGET.ps1 already exists. Skipping download."
    }

    Log "Running WGET.ps1..."
    & $WGETPath | Out-Null
    Log "WGET.ps1 executed successfully."
} catch {
    Log "Error with WGET.ps1: $_"
}

# ========== 4. Install Default Apps ==========
$apps = @(
    @{ Name = "7-Zip"; Id = "7zip.7zip" },
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Adobe Acrobat Reader 64-bit"; Id = "Adobe.Acrobat.Reader.64-bit" }
)

foreach ($app in $apps) {
    try {
        $installed = winget list --name $app.Name -e | Where-Object { $_ }
        if ($installed) {
            Log "$($app.Name) already installed. Skipping."
        } else {
            Log "Installing $($app.Name)..."
            winget install --id=$($app.Id) -e --silent --accept-package-agreements --accept-source-agreements
            Log "$($app.Name) installed successfully."
        }
    } catch {
        Log "Error installing $($app.Name): $_"
    }
}

# ========== 5. Prompt for OpenVPN Connect ==========
try {
    $openvpnChoice = Read-Host "Do you want to install OpenVPN Connect? (Y/N)"
    if ($openvpnChoice -match '^(?i)y(es)?$') {
        Log "Installing OpenVPN Connect..."
        winget install --id=OpenVPNTechnologies.OpenVPNConnect -e --scope machine --silent --accept-package-agreements --accept-source-agreements
        Log "OpenVPN Connect installed successfully."
    } else {
        Log "Skipped OpenVPN Connect installation."
    }
} catch {
    Log "Error installing OpenVPN Connect: $_"
}

# ========== 6. Install Driver Update App ==========
try {
    $brand = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    Log "Detected manufacturer: $brand"

    switch -Wildcard ($brand) {
        "*Lenovo*" {
            winget install --id=9WZDNCRFJ4MV -e --silent --accept-package-agreements --accept-source-agreements
            Log "Lenovo Vantage installed."
        }
        "*HP*" {
            winget install --id=9NBB0P7HPH4S -e --silent --accept-package-agreements --accept-source-agreements
            Log "HP Support Assistant installed."
        }
        "*Dell*" {
            winget install --id=Dell.CommandUpdate -e --silent --accept-package-agreements --accept-source-agreements
            Log "Dell Command Update installed."
        }
        default {
            Log "No driver update app needed for this brand."
        }
    }
} catch {
    Log "Error installing driver update app: $_"
}

# ========== 7. Install Disk Management App ==========
try {
    $disk = Get-PhysicalDisk | Select-Object -First 1 FriendlyName, Manufacturer, Model
    if (-not $disk) {
        $disk = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -First 1 Model, Manufacturer
    }

    if ($disk.Manufacturer) {
        $diskBrand = $disk.Manufacturer
    } else {
        $diskBrand = $disk.Model
    }

    $diskBrand = $diskBrand -replace '\(.*?\)|\[.*?\]', '' -replace '\s+', '' -replace '-', ''
    Log "Detected disk brand: $diskBrand"

    switch -Wildcard ($diskBrand) {
        "*Samsung*" { winget install --id=Samsung.SamsungMagician -e --silent --accept-package-agreements --accept-source-agreements; Log "Samsung Magician installed." }
        "*Kingston*" { winget install --id=Kingston.SSDManager -e --silent --accept-package-agreements --accept-source-agreements; Log "Kingston SSD Manager installed." }
        "*Crucial*" { winget install --id=Micron.CrucialStorageExecutive -e --silent --accept-package-agreements --accept-source-agreements; Log "Crucial Storage Executive installed." }
        "*WesternDigital*" { winget install --id=WesternDigital.WDSSDDashboard -e --silent --accept-package-agreements --accept-source-agreements; Log "WD SSD Dashboard installed." }
        "*Intel*" { winget install --id=Intel.MemoryAndStorageTool -e --silent --accept-package-agreements --accept-source-agreements; Log "Intel Memory and Storage Tool installed." }
        "*SanDisk*" { winget install --id=SanDisk.Dashboard -e --silent --accept-package-agreements --accept-source-agreements; Log "SanDisk SSD Dashboard installed." }
        default { Log "No disk management app needed for this brand." }
    }
} catch {
    Log "Error installing disk management app: $_"
}
# ========== 8. Disable OneDrive Auto-Start ==========
try {
    Log "Disabling OneDrive auto-start..."
    $taskName = "OneDrive Standalone Update Task"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Log "Disabled OneDrive scheduled task."
    } else {
        Log "OneDrive scheduled task not found."
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    New-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWORD -Force | Out-Null
    Log "Set Group Policy key to disable OneDrive auto-start."
} catch {
    Log "Error disabling OneDrive auto-start: $_"
}
# ================== 9. Set File Explorer to open 'This PC' by default ==================
try {
    Log "Configuring File Explorer to open 'This PC' by default..."
    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-ItemProperty -Path $explorerKey -Name 'LaunchTo' -Value 1
    Log "File Explorer set to open 'This PC' by default successfully."
} catch {
    Log "Failed to set File Explorer default view: $_"
}
# ================== 10. Define Desktop Items ==================
try {
    Log "Defining common desktop items (This PC, Network, Control Panel, User's Files)..."

    # Enable 'This PC'
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0
    # Enable 'Network'
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" -Value 0
    # Enable 'Control Panel'
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" -Value 0
    # Enable 'User's Files'
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{59031A47-3F72-44A7-89C5-5595FE6B30EE}" -Value 0

    Log "Desktop items defined successfully."
} catch {
    Log "Failed to define desktop items: $_"
}

# ================== End of script ==================
Log "==== MACHINEPREP Script Completed ===="