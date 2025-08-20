# INSTALLUNIFISERVER.ps1
# Version: 1.0.9
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
Log "Running INSTALL-UNIFI-SERVER script Version: 1.0.9" "INFO"
Log "Starting UniFi Network Server installation process..." "INFO"

# --- Step 1: Define Variables and Check for Existing Installation ---
Log "Defining variables and checking for existing installation..." "INFO"

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

# --- Step 2: Install Chocolatey ---
Log "Ensuring Chocolatey is installed..." "INFO"
Install-Chocolatey

# --- Step 3: Install UniFi and Java Dependencies via Chocolatey ---
Log "Installing/Updating UniFi Network Server and Java... (using Chocolatey)" "INFO"
try {
    # UniFi Network Server requires Java. Chocolatey package will handle dependencies.
    choco install ubiquiti-unifi-controller -y
    Log "UniFi Network Server and Java installation/update complete." "INFO"
    Start-Sleep -Seconds 10 # Wait for services to initialize
} catch {
    Log "ERROR: Failed to install UniFi Network Server via Chocolatey." "ERROR"
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

$possiblePaths = @(
    "$env:UserProfile\Ubiquiti UniFi",
    "$env:ProgramData\Ubiquiti UniFi",
    "C:\Windows\SysWOW64\config\systemprofile\Ubiquiti UniFi"
)

$unifiDir = $null
foreach ($path in $possiblePaths) {
    if (Test-Path -Path (Join-Path -Path $path -ChildPath "lib\ace.jar")) {
        $unifiDir = $path
        break
    }
}

if ($unifiDir) {
    $aceJarPath = Join-Path -Path $unifiDir -ChildPath "lib\ace.jar"
    Log "Found UniFi installation at: $unifiDir" "INFO"
    Set-Location -Path $unifiDir
    Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" installsvc" -Wait
    Log "UniFi service installed. Starting the service..." "INFO"
    Start-Process -FilePath "java" -ArgumentList "-jar `"$aceJarPath`" startsvc" -Wait
    Log "UniFi service started." "INFO"
} else {
    Log "ERROR: 'ace.jar' file not found in any of the possible locations. Service cannot be created." "ERROR"
}

# --- Step 6: Cleanup ---
Log "Uninstalling Chocolatey..." "INFO"
Uninstall-Chocolatey

Log "Script finished! UniFi Network Server is now installed and configured." "INFO"
