# INSTALLUNIFISERVER.ps1
# Version: 2.10.2
#
# UNIFI NETWORK SERVER INSTALLATION SCRIPT (DYNAMIC & UPGRADE-READY)
# THIS SCRIPT IS INTENDED FOR WINDOWS 10/11 (DESKTOP) ONLY, NOT SERVER VERSIONS.
#
# CHANGELOG:
#   - 2.10.2: Implemented Java version check and conditional installation of Java 21.
#   - 2.10.1: Increased initial UniFi application startup sleep duration and fixed Java version mismatch for service installation.
#   - 2.10.0: Use the command from the shortcut to start the UniFi application.
#   - 2.9.0: Added a check to ensure the UniFi process started correctly before attempting to stop it.
#   - 2.8.0: Correctly start the UniFi application using ace.jar before installing the service.
#   - 2.7.0: Added a step to kill existing UniFi processes before installation.
#   - 2.6.0: Added a step to start the UniFi Network Application once before installing it as a service.
#   - 2.5.0: Switched to curl for downloading to provide progress indication.
#   - 2.4.0: Switched to a static download link to avoid parsing issues.
#   - 2.3.0: Added verbose logging to debug download link parsing.
#   - 2.2.0: Switched to curl with a user-agent to fix dynamic URL retrieval.
#   - 2.1.0: Replaced hardcoded download URL with dynamic URL retrieval.

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

Log "Running INSTALL-UNIFI-SERVER script Version: 2.10.2" "INFO"
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

# --- Step 2: Check for Java and Install if Necessary ---
Log "Checking for Java installation..." "INFO"
$javaInstalled = $false
$javaMajorVersion = 0
try {
    $javaVersionOutput = java -version 2>&1
    if ($javaVersionOutput) {
        Log "Java is already installed." "INFO"
        Log "Detected Java version output: $($javaVersionOutput)" "INFO"

        # Extract major version number
        if ($javaVersionOutput -match 'version `"(?:1\.)?(\d+)(?:\.\d+)*`"') {
            $javaMajorVersion = [int]$Matches[1]
        }

        Log "Detected Java major version: $($javaMajorVersion)" "INFO"

        if ($javaMajorVersion -ge 21) {
            $javaInstalled = $true
            Log "Installed Java version ($($javaMajorVersion)) is 21 or newer. No new installation needed." "INFO"
        } else {
            Log "Installed Java version ($($javaMajorVersion)) is older than 21. Proceeding with Java 21 installation." "INFO"
        }
    }
}
catch {
    Log "Java not found or error checking version, proceeding with installation." "WARN"
}

if (-not $javaInstalled) {
    Log "Downloading and installing Java 21..." "INFO"
    $downloadUrl = "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse"
    $outputFile = "$env:TEMP\openjdk.msi"

    try {
        C:\Windows\System32\curl.exe -# -L $downloadUrl -o $outputFile
        # The Adoptium MSI installer typically sets JAVA_HOME by default.
        Start-Process msiexec.exe -ArgumentList "/i `"$outputFile`" /qn" -Wait
        Remove-Item $outputFile
        Log "Java 21 installation complete." "INFO"
        # Re-check Java version after installation
        $javaVersionOutputAfterInstall = java -version 2>&1
        Log "Java version after installation: $($javaVersionOutputAfterInstall)" "INFO"
    } catch {
        Log "ERROR: Failed to install Java 21." "ERROR"
        exit 1
    }
}

# --- Step 2.5: Kill Existing UniFi Process ---
Log "Checking for existing UniFi Network Application process..." "INFO"
$unifiProcesses = Get-WmiObject -Class Win32_Process | Where-Object {$_.CommandLine -like "*ace.jar*"}
if ($unifiProcesses) {
    Log "Found running UniFi Network Application process(es). Killing it/them..." "INFO"
    foreach ($process in $unifiProcesses) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Log "Killed process with ID: $($process.ProcessId) and command line: $($process.CommandLine)" "INFO"
    }
    Log "UniFi Network Application process(es) killed." "INFO"
} else {
    Log "No running UniFi Network Application process found." "INFO"
}

# --- Step 3: Download and Install UniFi Network Server ---
Log "Downloading and installing UniFi Network Server..." "INFO"

# --- Statically set the UniFi Network Server download URL ---
$unifiDownloadUrl = "https://dl.ui.com/unifi/9.3.45/UniFi-installer.exe"
Log "Using static download link: $unifiDownloadUrl" "INFO"

$unifiInstaller = "$env:TEMP\UniFi-installer.exe"

try {
    C:\Windows\System32\curl.exe -# -L $unifiDownloadUrl -o $unifiInstaller
    Start-Process -FilePath $unifiInstaller -ArgumentList "/S" -Wait
    Remove-Item $unifiInstaller
    Log "UniFi Network Server installation complete." "INFO"
} catch {
    Log "ERROR: Failed to download or install UniFi Network Server." "ERROR"
exit
}

# --- Step 3.5: Start UniFi Network Application for the first time ---
Log "Starting UniFi Network Application for the first time..." "INFO"

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
    $javawExe = Join-Path -Path $unifiDir -ChildPath "jre\bin\javaw.exe"
    $aceJarPath = Join-Path -Path $unifiDir -ChildPath "lib\ace.jar"
    Log "Found javaw.exe at: $javawExe" "INFO"
    Log "Found ace.jar at: $aceJarPath" "INFO"
    $arguments = "--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.time=ALL-UNNAMED --add-opens java.base/sun.security.util=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.rmi/sun.rmi.transport=ALL-UNNAMED -jar `"$aceJarPath`" ui"
    $process = Start-Process -FilePath $javawExe -ArgumentList $arguments -PassThru
    if ($process) {
        Log "UniFi Network Application process started with ID: $($process.Id)" "INFO"
        Log "Waiting for UniFi Network Application to initialize..." "INFO"
        Start-Sleep -Seconds 90
        Log "Stopping UniFi Network Application..." "INFO"
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Log "UniFi Network Application stopped." "INFO"
    } else {
        Log "ERROR: Failed to start UniFi Network Application process." "ERROR"
    }
} else {
    Log "WARNING: ace.jar not found in any of the possible locations. Skipping first start." "WARN"
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
    $javaExe = Join-Path -Path $unifiDir -ChildPath "jre\bin\java.exe"
    Start-Process -FilePath $javaExe -ArgumentList "-jar `"$aceJarPath`" installsvc" -Wait
    Log "UniFi service installed. Starting the service..." "INFO"
    Start-Process -FilePath $javaExe -ArgumentList "-jar `"$aceJarPath`" startsvc" -Wait
    Log "UniFi service started." "INFO"
} else {
    Log "ERROR: 'ace.jar' file not found in any of the possible locations. Service cannot be created." "ERROR"
}

Log "Script finished! UniFi Network Server is now installed and configured." "INFO"
