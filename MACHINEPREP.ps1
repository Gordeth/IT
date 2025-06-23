# MACHINEPREP.ps1
#
# This script automates the initial setup and preparation of a Windows machine.
# It includes tasks such as installing essential software (TeamViewer, common apps),
# ensuring related scripts (WU.ps1, WGET.ps1) are present and executed,
# configuring system settings (OneDrive, File Explorer, desktop icons),
# and installing brand-specific utilities (driver update tools, disk management apps).
#
# Execution: This script should be run with Administrator privileges.
#
# Parameters:
#   -VerboseMode (switch): If specified, enables detailed logging output to the console.
#                          Otherwise, only ERROR level messages are displayed on the console.
#   -LogFile (string): The full path to the log file where all script actions will be recorded.
#                      This parameter is mandatory.
#
# Dependencies:
#   - winget (Windows Package Manager) must be installed and configured.
#   - Internet connectivity for downloading files and installing packages.
#   - Assumes WU.ps1 and WGET.ps1 are available at a specified `$ScriptDir` and `$BaseUrl`.
#
# Author: Your Name/Organization (Optional)
# Date: June 23, 2025 (Adjust as needed)
# Version: 1.0 (Optional)

param (
    # Parameter: VerboseMode
    # Type: [switch]
    # Description: Controls the verbosity of console output.
    #              When present (`-VerboseMode`), all log levels (INFO, WARN, ERROR, DEBUG)
    #              will be displayed on the console. If omitted, only ERROR messages appear.
    [switch]$VerboseMode = $false,
    
    # Parameter: LogFile
    # Type: [string]
    # Description: Specifies the absolute path to the log file. All script activities,
    #              successes, and failures will be appended to this file.
    #              This parameter is required for the logging mechanism to function.
    [string]$LogFile
)

# ================== LOG FUNCTION ==================
#
# Function: Log
# Description: Centralized logging function used throughout the script. It appends
#              timestamped messages to a specified log file and can also output them
#              to the console with color-coding, depending on the message level
#              and the global `$VerboseMode` setting.
#
# Parameters:
#   -Message (string): The text content of the log entry.
#   -Level (string): The severity level of the message. Valid values are:
#                    "INFO" (informational), "WARN" (warning), "ERROR" (critical error),
#                    "DEBUG" (detailed debugging information). Defaults to "INFO".
#
# Console Output Logic:
#   - All log entries are persistently stored in the file specified by `$LogFile`.
#   - "ERROR" level messages are always displayed on the console (in red).
#   - Other message levels (INFO, WARN, DEBUG) are displayed on the console only if
#     the `$VerboseMode` script parameter is set to `$true`.
#
# Error Handling:
#   - Includes a `try-catch` block to handle potential issues when writing to the log file
#     (e.g., file locking, permission issues), providing a console fallback error message.
#
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Generate a formatted timestamp (e.g., "23-06-2025 14:44:21") for the log entry.
    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    
    # Combine the timestamp, log level, and message into a single log entry string.
    $logEntry = "[$timestamp] [$Level] $Message"

    # Attempt to append the `$logEntry` to the designated log file.
    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If writing to the log file fails, output an error directly to the console.
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # Conditional console output: Display the message if VerboseMode is true OR if the level is ERROR.
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Determine the console foreground color based on the log entry's level.
        $color = switch ($Level) {
            "INFO"  { "White" }   # Default color for general information.
            "WARN"  { "Yellow" }  # Indicates a potential issue that might not be critical.
            "ERROR" { "Red" }     # Signifies a critical failure.
            "DEBUG" { "Gray" }    # For detailed troubleshooting information.
            default { "White" }   # Fallback color for unrecognized levels.
        }
        # Write the log entry to the console with the determined color.
        Write-Host $logEntry -ForegroundColor $color
    }
}

# Assume $ScriptDir and $BaseUrl are defined globally or passed somehow
# For this script, these variables are not explicitly defined in the provided snippet.
# In a full script, they would typically be defined near the top or passed as parameters.
# Example:
# $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# $BaseUrl = "https://your-repo.com/scripts" # Example URL where WU.ps1/WGET.ps1 might be hosted

# ================== 1. Check if TeamViewer is installed ==================
#
# This section verifies the presence of TeamViewer Host on the system.
# If not found, it proceeds to install it using `winget`.
# TeamViewer Host is a common remote access tool for support.
#
try {
    Log "Checking for TeamViewer installation..."
    # Define common installation paths for TeamViewer.
    $teamViewerPaths = @(
        "C:\Program Files\TeamViewer",
        "C:\Program Files (x86)\TeamViewer"
    )
    # Check if any of the defined TeamViewer installation paths exist.
    $tvInstalled = $teamViewerPaths | Where-Object { Test-Path $_ }

    if ($tvInstalled) {
        Log "TeamViewer already installed. Skipping installation."
    } else {
        Log "Installing TeamViewer Host..."
        # Use winget to silently install TeamViewer Host.
        # `--id`: Specifies the package ID.
        # `--silent`: Performs a quiet installation without user interaction.
        # `--accept-package-agreements`: Automatically accepts package agreements.
        # `--accept-source-agreements`: Automatically accepts source agreements.
        winget install --id=TeamViewer.TeamViewerHost --silent --accept-package-agreements --accept-source-agreements
        Log "TeamViewer Host installed successfully."
    }
} catch {
    # Catch and log any errors that occur during the TeamViewer check or installation.
    Log "Error installing TeamViewer: $_" -Level "ERROR"
}

# ================== 2. Ensure WU.ps1 is present ==================
#
# This section checks for the presence of the `WU.ps1` script (Windows Update script).
# If it's not found in the expected directory, it attempts to download it.
# Afterwards, it executes `WU.ps1` to perform Windows updates.
#
try {
    # Construct the full path to the WU.ps1 script.
    # Note: `$ScriptDir` needs to be defined globally or passed as a parameter to MACHINEPREP.ps1.
    $WUPath = Join-Path $ScriptDir "WU.ps1"
    
    if (-not (Test-Path $WUPath)) {
        Log "WU.ps1 not found. Downloading..."
        # Construct the URL from which to download WU.ps1.
        # Note: `$ScriptDir` is used here as a base URL, which might be incorrect if it's a local path.
        # It's more common to have a separate `$BaseUrl` for downloads.
        $WUUrl = "$ScriptDir/WU.ps1" 
        # Download the script using Invoke-WebRequest and save it to `$WUPath`.
        # `-UseBasicParsing` is for compatibility; `| Out-Null` suppresses download progress output.
        Invoke-WebRequest -Uri $WUUrl -OutFile $WUPath -UseBasicParsing | Out-Null
        Log "WU.ps1 downloaded successfully."
    } else {
        Log "WU.ps1 already exists. Skipping download."
    }

    Log "Running WU.ps1..."
    # Execute the WU.ps1 script.
    # `-VerboseMode:$VerboseMode` passes the current script's verbosity setting to WU.ps1.
    # `-LogFile $LogFile` passes the current script's log file path to WU.ps1, allowing
    # WU.ps1 to log to the same file.
    & $WUPath -VerboseMode:$VerboseMode -LogFile $LogFile
    Log "WU.ps1 executed successfully."
} catch {
    # Catch and log any errors encountered while checking, downloading, or running WU.ps1.
    Log "Error with WU.ps1: $_" -Level "ERROR"
}

# ================== 3. Ensure WGET.ps1 is present ==================
#
# Similar to WU.ps1, this section checks for `WGET.ps1` (winget update script).
# It downloads the script if missing and then executes it to update installed packages.
#
try {
    # Construct the full path to the WGET.ps1 script.
    # Note: `$ScriptDir` needs to be defined globally or passed as a parameter.
    $WGETPath = Join-Path $ScriptDir "WGET.ps1"
    
    if (-not (Test-Path $WGETPath)) {
        Log "WGET.ps1 not found. Downloading..."
        # Construct the URL from which to download WGET.ps1.
        # Note: `$BaseUrl` needs to be defined globally or passed as a parameter.
        $WGETUrl = "$BaseUrl/WGET.ps1"
        # Download the script.
        Invoke-WebRequest -Uri $WGETUrl -OutFile $WGETPath -UseBasicParsing | Out-Null
        Log "WGET.ps1 downloaded successfully."
    } else {
        Log "WGET.ps1 already exists. Skipping download."
    }

    Log "Running WGET.ps1..."
    # Execute the WGET.ps1 script, passing through verbosity and the log file path.
    & $WGETPath -VerboseMode:$VerboseMode -LogFile $LogFile
    Log "WGET.ps1 executed successfully."
} catch {
    # Catch and log any errors related to WGET.ps1.
    Log "Error with WGET.ps1: $_" -Level "ERROR"
}

# ================== 4. Install Default Apps ==================
#
# This section defines a list of common, essential applications and ensures
# they are installed on the system using `winget`. It checks for existing
# installations to avoid unnecessary re-installation.
#
$apps = @(
    @{ Name = "7-Zip"; Id = "7zip.7zip" },
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Adobe Acrobat Reader 64-bit"; Id = "Adobe.Acrobat.Reader.64-bit" }
)

# Iterate through each application defined in the `$apps` array.
foreach ($app in $apps) {
    try {
        # Check if the application is already installed by listing winget packages by name.
        # `-e` ensures exact match. `| Where-Object { $_ }` checks if any output exists.
        $installed = winget list --name $app.Name -e | Where-Object { $_ }
        
        if ($installed) {
            Log "$($app.Name) already installed. Skipping."
        } else {
            Log "Installing $($app.Name)..."
            # Install the application using its winget ID.
            # `-e`: Ensures exact ID match.
            # `--silent`: Suppresses installation UI.
            # `--accept-package-agreements` and `--accept-source-agreements`: Auto-accepts necessary agreements.
            winget install --id=$($app.Id) -e --silent --accept-package-agreements --accept-source-agreements
            Log "$($app.Name) installed successfully."
        }
    } catch {
        # Log any errors encountered during the installation of a specific application.
        Log "Error installing $($app.Name): $_" -Level "ERROR"
    }
}

# ================== 5. Prompt for OpenVPN Connect ==================
#
# This section provides an interactive prompt to the user, asking if they wish
# to install OpenVPN Connect. If the user confirms, it proceeds with the installation.
#
try {
    # Prompt the user for input and store their response.
    $openvpnChoice = Read-Host "Do you want to install OpenVPN Connect? (Y/N)"
    
    # Use a regex match to check if the response is 'y' or 'yes' (case-insensitive).
    if ($openvpnChoice -match '^(?i)y(es)?$') {
        Log "Installing OpenVPN Connect..."
        # Install OpenVPN Connect using winget.
        # `--scope machine`: Installs for all users on the machine.
        winget install --id=OpenVPNTechnologies.OpenVPNConnect -e --scope machine --silent --accept-package-agreements --accept-source-agreements
        Log "OpenVPN Connect installed successfully."
    } else {
        Log "Skipped OpenVPN Connect installation."
    }
} catch {
    # Log any errors during the OpenVPN Connect installation process.
    Log "Error installing OpenVPN Connect: $_" -Level "ERROR"
}

# ================== 6. Install Driver Update App ==================
#
# This section automatically detects the computer's manufacturer (e.g., Lenovo, HP, Dell)
# and installs the corresponding official driver update utility using `winget`.
# This helps ensure drivers are kept up-to-date.
#
try {
    # Retrieve the manufacturer of the computer system using WMI.
    $brand = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
    Log "Detected manufacturer: $brand"

    # Use a switch statement with wildcard matching to identify the brand
    # and install the appropriate driver update application.
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
            Log "No specific driver update app found for this brand via winget."
        }
    }
} catch {
    # Log any errors that occur during the detection or installation of driver update apps.
    Log "Error installing driver update app: $_" -Level "ERROR"
}

# ================== 7. Install Disk Management App ==================
#
# This section attempts to identify the manufacturer of the primary storage disk (SSD/HDD)
# and install the corresponding manufacturer-specific utility tool (e.g., Samsung Magician).
# These tools often provide firmware updates, health monitoring, and performance optimization.
#
try {
    # Attempt to get disk information using `Get-PhysicalDisk` (more modern cmdlets).
    # Selects the first physical disk found and its FriendlyName, Manufacturer, Model.
    $disk = Get-PhysicalDisk | Select-Object -First 1 FriendlyName, Manufacturer, Model
    
    # If `Get-PhysicalDisk` doesn't return anything (e.g., older OS), try `Get-CimInstance`.
    if (-not $disk) {
        $disk = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -First 1 Model, Manufacturer
    }

    # Determine the disk brand, prioritizing Manufacturer property.
    if ($disk.Manufacturer) {
        $diskBrand = $disk.Manufacturer
    } else {
        # Fallback to Model if Manufacturer is not available.
        $diskBrand = $disk.Model
    }

    # Clean up the disk brand string by removing parenthesized text, brackets, spaces, and hyphens
    # to facilitate better wildcard matching against known brand names.
    $diskBrand = $diskBrand -replace '\(.*?\)|\[.*?\]', '' -replace '\s+', '' -replace '-', ''
    Log "Detected disk brand: $diskBrand"

    # Use a switch statement with wildcard matching to install the appropriate disk management tool.
    switch -Wildcard ($diskBrand) {
        "*Samsung*" { winget install --id=Samsung.SamsungMagician -e --silent --accept-package-agreements --accept-source-agreements; Log "Samsung Magician installed." }
        "*Kingston*" { winget install --id=Kingston.SSDManager -e --silent --accept-package-agreements --accept-source-agreements; Log "Kingston SSD Manager installed." }
        "*Crucial*" { winget install --id=Micron.CrucialStorageExecutive -e --silent --accept-package-agreements --accept-source-agreements; Log "Crucial Storage Executive installed." }
        "*WesternDigital*" { winget install --id=WesternDigital.WDSSDDashboard -e --silent --accept-package-agreements --accept-source-agreements; Log "WD SSD Dashboard installed." }
        "*Intel*" { winget install --id=Intel.MemoryAndStorageTool -e --silent --accept-package-agreements --accept-source-agreements; Log "Intel Memory and Storage Tool installed." }
        "*SanDisk*" { winget install --id=SanDisk.Dashboard -e --silent --accept-package-agreements --accept-source-agreements; Log "SanDisk SSD Dashboard installed." }
        default { Log "No specific disk management app needed for this brand or none found via winget." }
    }
} catch {
    # Log any errors during disk detection or management app installation.
    Log "Error installing disk management app: $_" -Level "ERROR"
}

# ================== 8. Disable OneDrive Auto-Start ==================
#
# This section configures OneDrive to prevent it from automatically starting with Windows.
# This is often desired in corporate or managed environments to reduce resource usage
# or enforce alternative cloud solutions.
#
try {
    Log "Disabling OneDrive auto-start..."
    
    # Define the name of the scheduled task associated with OneDrive updates/startup.
    $taskName = "OneDrive Standalone Update Task"
    # Attempt to retrieve the scheduled task. `-ErrorAction SilentlyContinue` prevents breaking if not found.
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        # If the task exists, disable it.
        Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Log "Disabled OneDrive scheduled task."
    } else {
        Log "OneDrive scheduled task not found. It may already be disabled or not present."
    }

    # Define the registry path for OneDrive group policy settings.
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    # Create the OneDrive policy key if it doesn't exist. `-Force` allows creation of parent keys.
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    # Set the `DisableFileSyncNGSC` DWORD value to 1. This Group Policy setting prevents
    # OneDrive (Next Generation Sync Client) from starting automatically when a user logs in.
    New-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWORD -Force | Out-Null
    Log "Set Group Policy key to disable OneDrive auto-start."
} catch {
    # Log any errors encountered while attempting to disable OneDrive auto-start.
    Log "Error disabling OneDrive auto-start: $_" -Level "ERROR"
}

# ================== 9. Set File Explorer to open 'This PC' by default ==================
#
# This section modifies a registry setting to change the default view in File Explorer.
# By default, File Explorer often opens to 'Quick Access'. This changes it to 'This PC'.
#
try {
    Log "Configuring File Explorer to open 'This PC' by default..."
    # Define the registry key path for File Explorer advanced settings.
    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    # Set the 'LaunchTo' value to 1, which corresponds to 'This PC'.
    # A value of 2 corresponds to 'Quick Access'.
    Set-ItemProperty -Path $explorerKey -Name 'LaunchTo' -Value 1
    Log "File Explorer set to open 'This PC' by default successfully."
} catch {
    # Log any errors during the File Explorer default view configuration.
    Log "Failed to set File Explorer default view: $_" -Level "ERROR"
}

# ================== 10. Define Desktop Items ==================
#
# This section ensures that common system icons (This PC, Network, Control Panel, User's Files)
# are visible on the desktop. These are often hidden by default in modern Windows versions.
#
try {
    Log "Defining common desktop items (This PC, Network, Control Panel, User's Files)..."

    # Registry path for managing desktop icon visibility.
    $hideDesktopIconsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    # Set the value for each specific desktop icon's GUID to 0 to make it visible.
    # Enable 'This PC' (GUID: {20D04FE0-3AEA-1069-A2D8-08002B30309D})
    Set-ItemProperty -Path $hideDesktopIconsPath -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0
    # Enable 'Network' (GUID: {F02C1A0D-BE21-4350-88B0-7367FC96EF3C})
    Set-ItemProperty -Path $hideDesktopIconsPath -Name "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" -Value 0
    # Enable 'Control Panel' (GUID: {5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0})
    Set-ItemProperty -Path $hideDesktopIconsPath -Name "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" -Value 0
    # Enable 'User's Files' (GUID: {59031A47-3F72-44A7-89C5-5595FE6B30EE})
    Set-ItemProperty -Path $hideDesktopIconsPath -Name "{59031A47-3F72-44A7-89C5-5595FE6B30EE}" -Value 0

    Log "Desktop items defined successfully."
} catch {
    # Log any errors that prevent setting desktop icon visibility.
    Log "Failed to define desktop items: $_" -Level "ERROR"
}

# ================== End of script ==================
#
# This final log entry marks the successful completion of the MACHINEPREP script's execution.
#
Log "==== MACHINEPREP Script Completed ===="