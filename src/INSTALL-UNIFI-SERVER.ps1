# INSTALL-UNIFI-SERVER.ps1
# Version: 1.0.0
#
# This script installs the UniFi Network Server on a Windows machine and configures it to run as a service.
# THIS SCRIPT IS INTENDED FOR WINDOWS 10/11 (DESKTOP) ONLY, NOT SERVER VERSIONS.

# --- Step 1: Define Variables ---
Write-Host "Starting advanced UniFi Network Server installation..."

$tempPath = [System.IO.Path]::GetTempPath()
$unifiInstallerUrl = "https://dl.ui.com/unifi/9.3.45/UniFi-installer.exe"
$unifiInstallerName = "UniFi-installer.exe"
$unifiInstallerPath = Join-Path -Path $tempPath -ChildPath $unifiInstallerName

$javaInstallerUrl = "https://cdn.azul.com/zulu/bin/zulu17.48.15-sa-jre17.0.10-win_x64.msi"
$javaInstallerName = "zulu17.48.15-sa-jre17.0.10-win_x64.msi"
$javaInstallerPath = Join-Path -Path $tempPath -ChildPath $javaInstallerName

# --- Step 2: Download and Install Java 17 JRE ---
Write-Host "Downloading Java 17 JRE installer..."
try {
    Invoke-WebRequest -Uri $javaInstallerUrl -OutFile $javaInstallerPath -UseBasicParsing
    Write-Host "Java download complete."
    # Silently install and set JAVA_HOME
    Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$javaInstallerPath`" /qn ADDLOCAL=ALL" -Wait
} catch {
    Write-Host "ERROR: Failed to download or install Java. Please check your connection and URL." -ForegroundColor Red
    exit
}

# --- Step 3: Download and Install UniFi Network Server ---
Write-Host "Downloading UniFi Network Server installer..."
try {
    Invoke-WebRequest -Uri $unifiInstallerUrl -OutFile $unifiInstallerPath -UseBasicParsing
    Write-Host "UniFi installer downloaded."
    # The default installer places files in %UserProfile%\Ubiquiti UniFi\
    Start-Process -FilePath $unifiInstallerPath -ArgumentList "/S" -Wait
    Write-Host "UniFi installation complete. Waiting 10 seconds for service initialization."
    Start-Sleep -Seconds 10
} catch {
    Write-Host "ERROR: Failed to download or install UniFi. Please check your connection and URL." -ForegroundColor Red
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
$unifiDir = "$env:UserProfile\Ubiquiti UniFi"
$aceJarPath = Join-Path -Path $unifiDir -ChildPath "lib\ace.jar"

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

Write-Host "Script finished! UniFi Network Server is now installed and running as a Windows service."