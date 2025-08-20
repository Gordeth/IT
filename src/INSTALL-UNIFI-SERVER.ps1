# INSTALL-UNIFI-SERVER.ps1
# Version: 1.0.0
#
# This script installs the UniFi Network Server on a Windows machine and configures it to run as a service.


# Define variables
$tempPath = [System.IO.Path]::GetTempPath()
$installerName = "UniFi-installer.exe"
$installerPath = Join-Path -Path $tempPath -ChildPath $installerName
$unifiDownloadUrl = "https://dl.ui.com/unifi/9.3.45/UniFi-installer.exe"
$unifiInstallDir = "$env:ProgramData\Ubiquiti UniFi"

# --- Step 1: Download the latest UniFi Network Server installer ---
Write-Host "Downloading the UniFi Network Server installer..."
try {
    Invoke-WebRequest -Uri $unifiDownloadUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "Download complete. Installer saved to: $installerPath"
} catch {
    Write-Host "ERROR: Failed to download the installer. Please check the URL and your internet connection." -ForegroundColor Red
    exit
}

# --- Step 2: Install UniFi silently ---
Write-Host "Starting silent installation of UniFi..."
Start-Process -FilePath $installerPath -ArgumentList "/S /D=$unifiInstallDir" -Wait

# Wait a moment to ensure the installation process has completed
Start-Sleep -Seconds 10

# --- Step 3: Add Firewall Rules for necessary ports ---
Write-Host "Configuring Windows Firewall rules..."

# Define ports to open
$ports = @(
    @{Port=8080; Protocol="TCP"; Name="UniFi-8080-Inform"},
    @{Port=8443; Protocol="TCP"; Name="UniFi-8443-HTTPS"},
    @{Port=10001; Protocol="UDP"; Name="UniFi-10001-STUN"},
    @{Port=3478; Protocol="UDP"; Name="UniFi-3478-STUN-Server"}
)

foreach ($port in $ports) {
    # Check if rule exists before creating
    $ruleExists = Get-NetFirewallRule -DisplayName $port.Name -ErrorAction SilentlyContinue
    if (-not $ruleExists) {
        Write-Host "  - Creating firewall rule for $($port.Name)..."
        New-NetFirewallRule -DisplayName $port.Name -Direction Inbound -LocalPort $port.Port -Protocol $port.Protocol -Action Allow -Profile Any
    } else {
        Write-Host "  - Firewall rule for $($port.Name) already exists. Skipping."
    }
}

# --- Step 4: Install UniFi as a Windows Service ---
Write-Host "Installing UniFi as a Windows service..."
$unifiLibPath = Join-Path -Path $unifiInstallDir -ChildPath "lib"
$unifiJarPath = Join-Path -Path $unifiLibPath -ChildPath "ace.jar"

if (Test-Path -Path $unifiJarPath) {
    try {
        Start-Process -FilePath "java" -ArgumentList "-jar `"$unifiJarPath`" installsvc" -Wait
        Write-Host "UniFi service installation complete. You may need to manually start the service."
    } catch {
        Write-Host "ERROR: Failed to install UniFi as a service. Please check Java installation and permissions." -ForegroundColor Red
    }
} else {
    Write-Host "ERROR: UniFi installation directory not found. Service cannot be created." -ForegroundColor Red
}

# --- Step 5: Clean up the installer file ---
Write-Host "Cleaning up temporary files..."
if (Test-Path -Path $installerPath) {
    Remove-Item -Path $installerPath -Force
    Write-Host "Installer file deleted successfully."
}

Write-Host "Script finished. UniFi is now installed and configured as a service."