# INSTALL-UNIFI-SERVER.ps1
# Version: 1.0.3
#
# UNIFI NETWORK SERVER INSTALLATION SCRIPT (DYNAMIC & UPGRADE-READY)
# THIS SCRIPT IS INTENDED FOR WINDOWS 10/11 (DESKTOP) ONLY, NOT SERVER VERSIONS.

# Parameters:
#   -VerboseMode (switch): If specified, enables detailed logging output to the console.
#                        Otherwise, only ERROR level messages are displayed on the console.
#   -LogDir (string): The full path to the log directory where script logs will be created.
#                    This parameter is mandatory.
param (
  # Parameter passed from the orchestrator script (WUH.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Parameter passed from the orchestrator script (WUH.ps1) for centralized logging.
  [string]$LogFile
)

# ==================== Setup Paths and Global Variables ====================
#
# This section initializes essential paths and variables used throughout the script,
# ensuring proper file locations for logging and script execution.
#
# --- IMPORTANT: Dot-source the Functions.ps1 module to make the Log function available.
# The path is relative to this script's location (which should be the 'src' folder).
# This ensures that the Log function is available in this script's scope.
. "$PSScriptRoot/../modules/Functions.ps1"

# Add a check to ensure a log file path was provided.
if (-not $LogFile) {
  Write-Host "ERROR: The LogFile parameter is required and cannot be empty." -ForegroundColor Red
  exit 1
}

# --- Construct the dedicated log file path for this script ---
# This script will now create its own file named INSTALL-UNIFI-SERVER.txt within the provided log directory.
$LogFile = Join-Path $LogDir "INSTALL-UNIFI-SERVER.txt"

# ==================== Begin Script Execution ====================
Log "Starting UniFi Network Server installation process..." "INFO"

# --- Step 1: Define Variables and Check for Existing Installation ---
Log "Defining variables and checking for existing installation..." "INFO"

$tempPath = [System.IO.Path]::GetTempPath()
$unifiInstallerName = "UniFi-installer.exe"
$unifiInstallerPath = Join-Path -Path $tempPath -ChildPath $unifiInstallerName
$unifiDir = "$env:UserProfile\Ubiquiti UniFi"
$aceJarPath = Join-Path -Path $unifiDir -ChildPath "lib\ace.jar"

# Check if UniFi is already installed
if (Test-Path -Path $aceJarPath) {
  Log "Existing UniFi installation found at '$unifiDir'." "WARN"
  Log "Initiating upgrade procedure..." "INFO"
  Log "NOTE: Please ensure you have a backup of your UniFi Network Server configuration before proceeding." "INFO"

  # Change directory and uninstall the existing service
  try {
    Set-Location -Path $unifiDir
    Log "Uninstalling existing UniFi service..." "INFO"
    Start-Process -FilePath "java" -ArgumentList "-jar lib\ace.jar uninstallsvc" -Wait
    Log "Service uninstallation complete." "INFO"
  } catch {
    Log "WARNING: Failed to uninstall the old service. The upgrade may still proceed." "WARN"
  }
} else {
  Log "No existing UniFi installation found. Proceeding with a new installation." "INFO"
}

# --- Step 2: Find and Download Latest UniFi and Java Versions ---
# Find the latest UniFi version
Log "Searching for the latest UniFi Network Server version..." "INFO"
try {
  $unifiApiUrl = "https://fw-update.ui.com/firmware.json"
  $firmwareData = Invoke-WebRequest -Uri $unifiApiUrl -UseBasicParsing | ConvertFrom-Json
  $latestUnifiVersion = ($firmwareData.unifi_os_firmware | Where-Object { $_.file -like "*UniFi-installer.exe" } | Sort-Object -Property version -Descending | Select-Object -First 1).version
  $unifiInstallerUrl = "https://dl.ui.com/unifi/$latestUnifiVersion/$unifiInstallerName"
  Log "Found latest UniFi version: $latestUnifiVersion" "INFO"
} catch {
  Log "ERROR: Failed to find the latest UniFi version. Using default URL." "ERROR"
  $unifiInstallerUrl = "https://dl.ui.com/unifi/9.3.45/UniFi-installer.exe"
}

# Find the latest Java 17 JRE MSI
Log "Searching for the latest Java 17 JRE installer..." "INFO"
try {
  $azulApiUrl = "https://api.azul.com/zulu/download/community/v1.0/packages/latest?os=windows&architecture=x64&archive_type=zip&java_package=jre&release_status=ga&jvm_type=hotspot&jdk_version=17&ext=msi"
  $azulData = Invoke-RestMethod -Uri $azulApiUrl
  $javaInstallerUrl = $azulData.download_url
  $javaInstallerName = $javaInstallerUrl.Substring($javaInstallerUrl.LastIndexOf('/') + 1)
  $javaInstallerPath = Join-Path -Path $tempPath -ChildPath $javaInstallerName
  Log "Found latest Java 17 JRE: $javaInstallerName" "INFO"
} catch {
  Log "ERROR: Failed to find the latest Java version. Using default URL." "ERROR"
  $javaInstallerUrl = "https://cdn.azul.com/zulu/bin/zulu17.48.15-sa-jre17.0.10-win_x64.msi"
  $javaInstallerName = "zulu17.48.15-sa-jre17.0.10-win_x64.msi"
  $javaInstallerPath = Join-Path -Path $tempPath -ChildPath $javaInstallerName
}

# --- Step 3: Install Java and UniFi ---
Log "Downloading and installing Java 17 JRE..." "INFO"
try {
  Invoke-WebRequest -Uri $javaInstallerUrl -OutFile $javaInstallerPath -UseBasicParsing
  Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$javaInstallerPath`" /qn ADDLOCAL=ALL" -Wait
  Log "Java installation complete." "INFO"
} catch {
  Log "ERROR: Failed to download or install Java." "ERROR"
  exit
}

Log "Downloading and installing UniFi Network Server..." "INFO"
try {
  Invoke-WebRequest -Uri $unifiInstallerUrl -OutFile $unifiInstallerPath -UseBasicParsing
  Start-Process -FilePath $unifiInstallerPath -ArgumentList "/S" -Wait
  Log "UniFi installation complete. Waiting 10 seconds for services to initialize." "INFO"
  Start-Sleep -Seconds 10
} catch {
  Log "ERROR: Failed to download or install UniFi." "ERROR"
  exit
}

# --- Step 4: Add Firewall Rules ---
Log "Configuring firewall rules..." "INFO"
$ports = @(
  @{Port=8080; Protocol="TCP"; Name="UniFi-8080-Inform"},
  @{Port=8843; Protocol="TCP"; Name="UniFi-8443-HTTPS"},
  @{Port=10001; Protocol="UDP"; Name="UniFi-10001-STUN"},
  @{Port=3478; Protocol="UDP"; Name="UniFi-3478-STUN-Server"}
)
foreach ($port in $ports) {
  if (-not (Get-NetFirewallRule -DisplayName $port.Name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $port.Name -Direction Inbound -LocalPort $port.Port -Protocol $port.Protocol -Action Allow -Profile Any | Out-Null
    Log "  - Rule created for $($port.Name)." "INFO"
  } else {
    Log "  - Rule for $($port.Name) already exists. Skipping." "INFO"
  }
}

# --- Step 5: Install and Start the Service ---
Log "Installing UniFi as a Windows service..." "INFO"
if (Test-Path -Path $aceJarPath) {
  Set-Location -Path $unifiDir
  Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" installsvc" -Wait
  Log "UniFi service installed. Starting the service..." "INFO"
  Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" startsvc" -Wait
  Log "UniFi service started." "INFO"
} else {
  Log "ERROR: 'ace.jar' file not found. Service cannot be created." "ERROR"
}

# --- Step 6: Cleanup ---
Log "Cleaning up temporary installation files..." "INFO"
if (Test-Path -Path $unifiInstallerPath) { Remove-Item -Path $unifiInstallerPath -Force }
if (Test-Path -Path $javaInstallerPath) { Remove-Item -Path $javaInstallerPath -Force }
Log "Cleanup complete." "INFO"

Log "Script finished! UniFi Network Server is now installed and configured." "INFO"