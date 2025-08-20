# INSTALL-UNIFI-SERVER.ps1
# Version: 1.0.1
#
# UNIFI NETWORK SERVER INSTALLATION SCRIPT (DYNAMIC & UPGRADE-READY)
# THIS SCRIPT IS INTENDED FOR WINDOWS 10/11 (DESKTOP) ONLY, NOT SERVER VERSIONS.

# --- Step 1: Define Variables and Check for Existing Installation ---
Write-Host "Starting UniFi Network Server installation process..."

$tempPath = [System.IO.Path]::GetTempPath()
$unifiInstallerName = "UniFi-installer.exe"
$unifiInstallerPath = Join-Path -Path $tempPath -ChildPath $unifiInstallerName
$unifiDir = "$env:UserProfile\Ubiquiti UniFi"
$aceJarPath = Join-Path -Path $unifiDir -ChildPath "lib\ace.jar"

# Check if UniFi is already installed
if (Test-Path -Path $aceJarPath) {
    Write-Host "Existing UniFi installation found at '$unifiDir'." -ForegroundColor Yellow
    Write-Host "Initiating upgrade procedure..." -ForegroundColor Yellow
    Write-Host "NOTE: Please ensure you have a backup of your UniFi Network Server configuration before proceeding." -ForegroundColor Cyan

    # Change directory and uninstall the existing service
    try {
        Set-Location -Path $unifiDir
        Write-Host "Uninstalling existing UniFi service..."
        Start-Process -FilePath "java" -ArgumentList "-jar lib\ace.jar uninstallsvc" -Wait
        Write-Host "Service uninstallation complete."
    } catch {
        Write-Host "WARNING: Failed to uninstall the old service. The upgrade may still proceed." -ForegroundColor Yellow
    }
} else {
    Write-Host "No existing UniFi installation found. Proceeding with a new installation." -ForegroundColor Green
}

# --- Step 2: Find and Download Latest UniFi and Java Versions ---
# Find the latest UniFi version
Write-Host "Searching for the latest UniFi Network Server version..."
try {
    $unifiDownloadsPage = Invoke-WebRequest -Uri "https://ui.com/download/releases/network-server" -UseBasicParsing
    $latestUnifiVersion = ($unifiDownloadsPage.Links | Where-Object { $_.innerText -like "*UniFi Network Application*Windows*" } | Select-Object -First 1).innerText -split ' ' | Select-Object -Last 1
    $latestUnifiVersion = $latestUnifiVersion.Replace('V', '')
    $unifiInstallerUrl = "https://dl.ui.com/unifi/$latestUnifiVersion/$unifiInstallerName"
    Write-Host "Found latest UniFi version: $latestUnifiVersion"
} catch {
    Write-Host "ERROR: Failed to find the latest UniFi version. Using default URL." -ForegroundColor Red
    $unifiInstallerUrl = "https://dl.ui.com/unifi/9.3.45/UniFi-installer.exe"
}

# Find the latest Java 17 JRE MSI
Write-Host "Searching for the latest Java 17 JRE installer..."
try {
    $javaDownloadsPage = Invoke-WebRequest -Uri "https://www.azul.com/downloads/?version=java-17-lts" -UseBasicParsing
    $latestJavaVersion = ($javaDownloadsPage.Links | Where-Object { $_.outerHTML -like "*download*.msi*" -and $_.outerHTML -like "*java-17-lts*" } | Select-Object -First 1).href
    $javaInstallerUrl = $latestJavaVersion
    $javaInstallerName = $javaInstallerUrl.Substring($javaInstallerUrl.LastIndexOf('/') + 1)
    $javaInstallerPath = Join-Path -Path $tempPath -ChildPath $javaInstallerName
    Write-Host "Found latest Java 17 JRE: $javaInstallerName"
} catch {
    Write-Host "ERROR: Failed to find the latest Java version. Using default URL." -ForegroundColor Red
    $javaInstallerUrl = "https://cdn.azul.com/zulu/bin/zulu17.48.15-sa-jre17.0.10-win_x64.msi"
    $javaInstallerName = "zulu17.48.15-sa-jre17.0.10-win_x64.msi"
    $javaInstallerPath = Join-Path -Path $tempPath -ChildPath $javaInstallerName
}

# --- Step 3: Install Java and UniFi ---
Write-Host "Downloading and installing Java 17 JRE..."
try {
    Invoke-WebRequest -Uri $javaInstallerUrl -OutFile $javaInstallerPath -UseBasicParsing
    Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$javaInstallerPath`" /qn ADDLOCAL=ALL" -Wait
    Write-Host "Java installation complete."
} catch {
    Write-Host "ERROR: Failed to download or install Java." -ForegroundColor Red
    exit
}

Write-Host "Downloading and installing UniFi Network Server..."
try {
    Invoke-WebRequest -Uri $unifiInstallerUrl -OutFile $unifiInstallerPath -UseBasicParsing
    Start-Process -FilePath $unifiInstallerPath -ArgumentList "/S" -Wait
    Write-Host "UniFi installation complete. Waiting 10 seconds for services to initialize."
    Start-Sleep -Seconds 10
} catch {
    Write-Host "ERROR: Failed to download or install UniFi." -ForegroundColor Red
    exit
}

# --- Step 4: Add Firewall Rules ---
Write-Host "Configuring firewall rules..."
$ports = @(
    @{Port=8080; Protocol="TCP"; Name="UniFi-8080-Inform"},
    @{Port=8843; Protocol="TCP"; Name="UniFi-8443-HTTPS"},
    @{Port=10001; Protocol="UDP"; Name="UniFi-10001-STUN"},
    @{Port=3478; Protocol="UDP"; Name="UniFi-3478-STUN-Server"}
)
foreach ($port in $ports) {
    if (-not (Get-NetFirewallRule -DisplayName $port.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $port.Name -Direction Inbound -LocalPort $port.Port -Protocol $port.Protocol -Action Allow -Profile Any | Out-Null
        Write-Host "  - Rule created for $($port.Name)."
    } else {
        Write-Host "  - Rule for $($port.Name) already exists. Skipping."
    }
}

# --- Step 5: Install and Start the Service ---
Write-Host "Installing UniFi as a Windows service..."
if (Test-Path -Path $aceJarPath) {
    Set-Location -Path $unifiDir
    Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" installsvc" -Wait
    Write-Host "UniFi service installed. Starting the service..."
    Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" startsvc" -Wait
    Write-Host "UniFi service started."
} else {
    Write-Host "ERROR: 'ace.jar' file not found. Service cannot be created." -ForegroundColor Red
}

# --- Step 6: Cleanup ---
Write-Host "Cleaning up temporary installation files..."
if (Test-Path -Path $unifiInstallerPath) { Remove-Item -Path $unifiInstallerPath -Force }
if (Test-Path -Path $javaInstallerPath) { Remove-Item -Path $javaInstallerPath -Force }
Write-Host "Cleanup complete."

Write-Host "Script finished! UniFi Network Server is now installed and configured."