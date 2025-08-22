<#
.SYNOPSIS
    Automates initial setup and preparation of a Windows machine.
.DESCRIPTION
    This script automates the initial setup and preparation of a Windows machine.
    It includes tasks such as installing essential software (TeamViewer, common apps),
    ensuring related scripts (WUA.ps1, WGET.ps1) are present and executed,
    configuring system settings (OneDrive, File Explorer, desktop icons),
    and installing brand-specific utilities (driver update tools, disk management apps).
.PARAMETER VerboseMode
    If specified, enables detailed logging output to the console.
    Otherwise, only ERROR level messages are displayed on the console.
.PARAMETER LogDir
    The full path to the log directory where all script actions will be recorded.
    This parameter is mandatory.
.NOTES
    Script: MACHINEPREP.ps1
    Version: 1.0.6
    Dependencies:
        - winget (Windows Package Manager) must be installed and configured.
        - Internet connectivity for downloading files and installing packages.
        - Optional: Chocolatey (will be installed by this script if needed)
    Changelog:
        v1.0.6
        - Added changelog.
        - Updated TeamViewer installation to use --accept-package-agreements and --accept-source-agreements.
        - Updated winget install commands to include --accept-package-agreements and --accept-source-agreements.
        - Improved HP Support Assistant installation logic to check for existing installation more robustly.
        - Added more robust checks for existing installations of Lenovo Vantage and Dell Command Update.
        - Refined disk management application installation to avoid duplicates and handle unsupported Samsung models.
        - Added Chocolatey uninstallation at the end of the script.        v1.0.5
        - Added Chocolatey installation and uninstallation logic.
        - Improved driver update application installation for HP (using Chocolatey) and Dell/Lenovo (using winget).
        - Enhanced disk management application installation to support more brands (Kingston, Crucial, WD, Intel, SanDisk) and avoid re-installation.
        - Added robust checks for existing installations of applications.
        - Refined logging and error handling.
        v1.0.4
        - Added logic to install brand-specific driver update applications (Lenovo Vantage, HP Support Assistant, Dell Command Update).
        - Added logic to install disk management applications (e.g., Samsung Magician) based on detected disk manufacturer.
        - Improved error handling and logging for various sections.
        v1.0.3
        - Integrated WGET.ps1 execution for winget package updates.
        - Added installation of standard applications (7-Zip, Chrome, Adobe Reader).
        - Included an interactive prompt for OpenVPN Connect installation.
        - Enhanced logging with more specific messages.
        v1.0.2
        - Integrated WUA.ps1 execution for Windows Updates.
        - Added TeamViewer Host installation.
        - Implemented OneDrive autostart disabling.
        - Configured File Explorer to open to 'This PC'.
        - Set common desktop icons (This PC, Network, Control Panel, User's Files).
        - Improved logging and error handling.
        v1.0.1
        - Initial release with basic structure and logging.
#>

param (
    # Parameter passed from the orchestrator script (WUH.ps1) to control console verbosity.
  [switch]$VerboseMode = $false,
  # Parameter passed from the orchestrator script (WUH.ps1) for centralized logging.
  [Parameter(Mandatory=$true)]
  [string]$LogDir
)

# ==================== Preference Variables ====================
# Set common preference variables for consistent script behavior.
$ErrorActionPreference = 'Stop' # Stop on any error
$WarningPreference = 'Continue' # Display warnings but continue
$VerbosePreference = 'Continue' # Display verbose messages

# ==================== Module Imports / Dot Sourcing ====================
# --- IMPORTANT: Sourcing the Functions.ps1 module to make the Log function available.
# The path is relative to the location of this script (which should be the 'src' folder).
# This ensures that the Log function is available in the scope of this script.
. "$PSScriptRoot/../modules/Functions.ps1"

# ==================== Global Variable Initialization & Log Setup ====================
# Add a check to ensure the log directory path was provided.
if (-not $LogDir) {
    Write-Host "ERROR: The LogDir parameter is mandatory and cannot be empty." -ForegroundColor Red
    exit 1
}

# --- Construct the dedicated log file path for this script ---
# This script will now create its own file named MACHINEPREP.txt inside the provided log directory.
$LogFile = Join-Path $LogDir "MACHINEPREP.txt"


# Create a new log file or append to the existing one.
if (-not (Test-Path $LogFile)) {
    "Log file created by MACHINEPREP.ps1." | Out-File $LogFile -Append
}


# ==================== Script Execution Start ====================
Log "Starting MACHINEPREP.ps1 script." "INFO"

# ================== 1. Check if TeamViewer is Installed ==================
#
# This section checks for the presence of TeamViewer Host on the system.
# If not found, it proceeds with its installation using `winget`.
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
        Log "TeamViewer is already installed. Skipping installation."
    } else {
        Log "Installing TeamViewer Host..."
        # Use winget to install TeamViewer Host silently.
        # `--id`: Specifies the package ID.
        # `--silent`: Performs a silent installation without user interaction.
        # `--accept-package-agreements`: Automatically accepts package agreements.
        # `--accept-source-agreements`: Automatically accepts source agreements.
        winget install --id=TeamViewer.TeamViewerHost --silent --accept-package-agreements --accept-source-agreements
        Log "TeamViewer Host installed successfully."
    }
} catch {
    # Catch and log any errors that occur during the TeamViewer check or installation.
    Log "Error installing TeamViewer: $_" -Level "ERROR"
}

# ================== 2. Execute WUA.ps1 to Perform Windows Updates ==================
#
# This section executes the `WUA.ps1` script to perform Windows updates.
# It assumes the WUA.ps1 script is present in the same directory.
#
try {
    # Construct the full path to the WUA.ps1 script.
    $WUAPath = Join-Path $PSScriptRoot "WUA.ps1"
    
    Log "Executing WUA.ps1..."
    # Execute the WUA.ps1 script, passing verbosity and the log file path.
    # The LogFile parameter has now been removed from WUA.ps1 as per the new logging structure.
    & $WUAPath -VerboseMode:$VerboseMode
    Log "WUA.ps1 executed successfully."
} catch {
    # Catch and log any errors encountered while executing WUA.ps1.
    Log "Error with WUA.ps1: $_" -Level "ERROR"
}

# ================== 3. Execute WGET.ps1 to Update winget packages ==================
#
# This section executes the `WGET.ps1` script to update installed packages.
# It assumes the WGET.ps1 script is present in the same directory.
#
try {
    # Construct the full path to the WGET.ps1 script.
    $WGETPath = Join-Path $PSScriptRoot "WGET.ps1"

    Log "Executing WGET.ps1..."
    # Execute the WGET.ps1 script, passing verbosity and the log file path.
    # The LogFile parameter has now been removed from WGET.ps1 as per the new logging structure.
    & $WGETPath -VerboseMode:$VerboseMode
    Log "WGET.ps1 executed successfully."
} catch {
    # Catch and log any errors related to WGET.ps1.
    Log "Error with WGET.ps1: $_" -Level "ERROR"
}

# ================== 4. Install Standard Applications ==================
#
# This section defines a list of common and essential applications and ensures
# they are installed on the system using `winget`.
# It checks for existing installations to avoid unnecessary re-installations.
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
        # `-e` ensures an exact match. `| Where-Object { $_ }` checks if any output exists.
        $installed = winget list --name $app.Name -e | Where-Object { $_ }
        
        if ($installed) {
            Log "$($app.Name) is already installed. Skipping."
        } else {
            Log "Installing $($app.Name)..."
            # Install the application using its winget ID.
            # `-e`: Ensures exact match of the ID.
            # `--silent`: Suppresses the installation UI.
            # `--accept-package-agreements` and `--accept-source-agreements`: Automatically accept necessary agreements.
            winget install --id=$($app.Id) -e --silent --accept-package-agreements --accept-source-agreements
            Log "$($app.Name) installed successfully."
        }
    } catch {
        # Log any errors encountered during a specific app's installation.
        Log "Error installing $($app.Name): $_" -Level "ERROR"
    }
}

# ================== 5. Prompt for OpenVPN Connect ==================
#
# This section provides an interactive prompt to the user, asking if they would like
# to install OpenVPN Connect. If the user confirms, it proceeds with the installation.
#
try {
    # Prompt for user input and store their response.
    $openvpnChoice = Read-Host "Do you want to install OpenVPN Connect? (Y/N)"
    
    # Use a regex match to check if the response is 'y' or 'yes' (case-insensitive).
    if ($openvpnChoice -match '^(?i)y(es)?') {
        Log "Installing OpenVPN Connect..."
        # Install OpenVPN Connect using winget.
        # `--scope machine`: Installs for all users on the machine.
        winget install --id=OpenVPNTechnologies.OpenVPNConnect -e --scope machine --silent --accept-package-agreements --accept-source-agreements
        Log "OpenVPN Connect installed successfully."
    } else {
        Log "OpenVPN Connect installation skipped."
    }
} catch {
    # Log any errors during the OpenVPN Connect installation process.
    Log "Error installing OpenVPN Connect: $_" -Level "ERROR"
}

# ================== 6. Install Driver Update Application ==================
#
# This section automatically detects the computer's manufacturer (e.g., Lenovo, HP, Dell)
# and installs the corresponding official driver update utility.
# This helps ensure drivers are always up-to-date. The script now checks if the application
# is already installed before attempting to install it.
#
# Note: The 'Install-Chocolatey' function is assumed to be available
# from an external script or module.
#
try {
    # Retrieve the system manufacturer from the computer using WMI.
    # Remove any whitespace and convert to lowercase for reliable comparison.
    $brand = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer.Trim().ToLower()
    Write-Host "Detected manufacturer: $brand" -ForegroundColor Cyan

    # Use a wildcard switch statement to identify the brand
    # and install the appropriate driver update application.
    switch -Wildcard ($brand) {
        "*lenovo*" {
            Write-Host "Found Lenovo brand. Checking for Lenovo Vantage..."
            $lenovoVantage = winget list "Lenovo Vantage" | Where-Object { $_.Name -like "*Lenovo Vantage*" }
            if ($lenovoVantage) {
                Write-Host "Lenovo Vantage is already installed. Skipping." -ForegroundColor Yellow
            } else {
                try {
                    Write-Host "Lenovo Vantage not found. Attempting installation via winget..."
                    $package = winget search "Lenovo Vantage" | Where-Object { $_.Name -like "*Lenovo Vantage*" } | Select-Object -First 1

                    if ($package) {
                        $packageId = $package.Id
                        winget install --id=$packageId -e --silent --accept-package-agreements --accept-source-agreements
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Lenovo Vantage installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "Failed to install Lenovo Vantage. Winget exit code: $LASTEXITCODE." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Lenovo Vantage package not found in winget repository. Skipping installation." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "An error occurred while trying to install Lenovo Vantage: $_" -ForegroundColor Red
                }
            }
        }
        "*hp*" {
            Write-Host "Found HP brand. Checking for HP Support Assistant..."
            
            # This is the new, more robust check. We pipe the output to Out-String
            # to treat it as a single block of text, then search for the
            # "HP Support Assistant" string, which is always present in the output
            # when the app is installed.
            $wingetOutput = winget list "HP Support Assistant" | Out-String
            if ($wingetOutput -like "*HP Support Assistant*") {
                Write-Host "HP Support Assistant is already installed. Skipping." -ForegroundColor Yellow
            } else {
                # Attempt to install Chocolatey (function call from an external script)
                if (Install-Chocolatey) {
                    try {
                        Write-Host "HP Support Assistant not found. Attempting installation via Chocolatey..."
                        choco install hpsupportassistant --force -y
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "HP Support Assistant installed successfully." -ForegroundColor Green
                        } elseif ($LASTEXITCODE -ne 0) {
                            Write-Host "HP Support Assistant installation via Chocolatey failed with exit code $LASTEXITCODE. Check Chocolatey logs." -ForegroundColor Red
                        }
                    } catch {
                        Write-Host "Error during HP Support Assistant installation via Chocolatey: $_" -ForegroundColor Red
                    }
                } else {
                    Log "Chocolatey installation failed, skipping HP Support Assistant." -ForegroundColor Red
                }
            }
        }
        "*hewlett-packard*" {
            Write-Host "Found Hewlett-Packard brand. Checking for HP Support Assistant..."
            
            # This is the new, more robust check. We pipe the output to Out-String
            # to treat it as a single block of text, then search for the
            # "HP Support Assistant" string, which is always present in the output
            # when the app is installed.
            $wingetOutput = winget list "HP Support Assistant" | Out-String
            if ($wingetOutput -like "*HP Support Assistant*") {
                Write-Host "HP Support Assistant is already installed. Skipping." -ForegroundColor Yellow
            } else {
                # Attempt to install Chocolatey (function call from an external script)
                if (Install-Chocolatey) {
                    try {
                        Write-Host "HP Support Assistant not found. Attempting installation via Chocolatey..."
                        choco install hpsupportassistant --force -y
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "HP Support Assistant installed successfully." -ForegroundColor Green
                        } elseif ($LASTEXITCODE -ne 0) {
                            Write-Host "HP Support Assistant installation via Chocolatey failed with exit code $LASTEXITCODE. Check Chocolatey logs." -ForegroundColor Red
                        }
                    } catch {
                        Write-Host "Error during HP Support Assistant installation via Chocolatey: $_" -ForegroundColor Red
                    }
                } else {
                    Log "Chocolatey installation failed, skipping HP Support Assistant." -ForegroundColor Red
                }
            }
        }
        "*dell*" {
            Write-Host "Found Dell brand. Checking for Dell Command Update..."
            $dellCommand = winget list "Dell Command Update" | Where-Object { $_.Name -like "*Dell Command Update*" }
            if ($dellCommand) {
                Write-Host "Dell Command Update is already installed. Skipping." -ForegroundColor Yellow
            } else {
                try {
                    Write-Host "Dell Command Update not found. Attempting installation via winget..."
                    $package = winget search "Dell Command Update" | Where-Object { $_.Name -like "*Dell Command Update*" } | Select-Object -First 1

                    if ($package) {
                        $packageId = $package.Id
                        winget install --id=$packageId -e --silent --accept-package-agreements --accept-source-agreements
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Dell Command Update installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "Failed to install Dell Command Update. Winget exit code: $LASTEXITCODE." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Dell Command Update package not found in winget repository. Skipping installation." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "An error occurred while trying to install Dell Command Update: $_" -ForegroundColor Red
                }
            }
        }
        default {
            Write-Host "No brand-specific driver update app detected for '$brand'. Skipping." -ForegroundColor Yellow
        }
    }
} catch {
    # Log any errors that occur during driver update app detection or installation.
    Write-Host "Error installing driver update app: $_" -Level "ERROR"
}


# ================== 7. Install Disk Management Application ==================
#
# This section attempts to identify the manufacturer of *all* internal storage disks (SSD/HDD)
# and install the corresponding manufacturer-specific utility (e.g., Samsung Magician).
# These tools often provide firmware updates, health monitoring, and performance optimization.
#
try {
    Log "Starting disk management application installation..." "INFO"

    # Use a variable to track which applications have already been installed to avoid duplicates.
    $installedDiskApps = @()

    # Get all physical disks, but filter out ones that are external (e.g., USB drives).
    # Common internal bus types are SATA, NVMe, SAS, and SCSI.
    # We'll exclude disks with a 'BusType' of 'USB' to ignore external hard drives.
    $internalDisks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'USB' }

    if (-not $internalDisks) {
        Log "No internal physical disks found with recognized bus types (SATA, NVMe, etc.)." "WARN"
    }
    
    # Iterate through each internal disk found on the system.
    foreach ($disk in $internalDisks) {
        # Determine the disk's brand, prioritizing the Manufacturer property.
        $diskBrand = if ($disk.Manufacturer) {
            $disk.Manufacturer
        } else {
            # Fall back to the Model if Manufacturer is not available.
            $disk.Model
        }

        # Sanitize the disk brand string by removing special characters for better matching.
        $diskBrand = $diskBrand.ToUpper() -replace '[^A-Z0-9]', ''
        Log "Processing disk with normalized brand: $diskBrand"

        # Use a regex switch to normalize the brand name to a consistent string.
        switch -Regex ($diskBrand) {
            'SAMSUNG'     { $diskBrand = "Samsung" }
            'KINGSTON'    { $diskBrand = "Kingston" }
            'CRUCIAL'     { $diskBrand = "Crucial" }
            'WDC|WESTERN' { $diskBrand = "WesternDigital" }
            'INTEL'       { $diskBrand = "Intel" }
            'SANDISK'     { $diskBrand = "SanDisk" }
            default       { $diskBrand = "Other" } # Set to a default string if no match
        }

        # Check if we've already installed an app for this brand.
        if ($installedDiskApps -contains $diskBrand) {
            Log "Disk management app for '$diskBrand' is already installed. Skipping." "INFO"
            continue # Skip to the next disk in the loop
        }

        # Use a switch statement to install the appropriate disk management tool.
        # This part has been updated to use separate cases for clarity, just like the previous fix.
        switch -Wildcard ($diskBrand) {
            "*Samsung*" {
                Log "Samsung disk model detected: $($disk.Model). Attempting to install Samsung Magician." "INFO"
                # Check for specific unsupported disk model
                if ($disk.Model -eq "SAMSUNG MZALQ256HAJD-000L2") {
                    Log "Samsung disk model $($disk.Model) detected which is not supported by Samsung Magician. Skipping installation." "INFO"
                } else {
                    if (Install-Chocolatey) {
                        try {
                            Log "Installing Samsung Magician via Chocolatey..." "INFO"
                            choco install samsung-magician --force -y
                            if ($LASTEXITCODE -eq 0) {
                                Log "Samsung Magician installed successfully via Chocolatey." "INFO"
                                $installedDiskApps += "Samsung"
                            } elseif ($LASTEXITCODE -eq 1) {
                                Log "Samsung Magician installation via Chocolatey finished with a known issue (e.g., already installed, reboot required). Check Chocolatey logs." "WARN"
                            }
                        } catch {
                            Log "Error during Samsung Magician installation via Chocolatey: $_" -Level "ERROR"
                        }
                    } else {
                        Log "Chocolatey installation failed, skipping Samsung Magician." "ERROR"
                    }
                }
            }
            "*Kingston*" { 
                winget install --id=Kingston.SSDManager -e --silent --accept-package-agreements --accept-source-agreements
                Log "Kingston SSD Manager installed." "INFO"
                $installedDiskApps += "Kingston"
            }
            "*Crucial*" { 
                winget install --id=Micron.CrucialStorageExecutive -e --silent --accept-package-agreements --accept-source-agreements
                Log "Crucial Storage Executive installed." "INFO"
                $installedDiskApps += "Crucial"
            }
            "*WesternDigital*" {
                if (Install-Chocolatey) {
                    try {
                        Log "Installing Western Digital Dashboard via Chocolatey..." "INFO"
                        choco install wd-dashboard --force -y
                        if ($LASTEXITCODE -eq 0) {
                            Log "Western Digital Dashboard installed successfully via Chocolatey." "INFO"
                            $installedDiskApps += "WesternDigital"
                        } elseif ($LASTEXITCODE -eq 1) {
                            Log "Western Digital Dashboard installation via Chocolatey finished with a known issue. Check Chocolatey logs." "WARN"
                        }
                    } catch {
                        Log "Error during Western Digital Dashboard installation via Chocolatey: $_" -Level "ERROR"
                    }
                } else {
                    Log "Chocolatey installation failed, skipping Western Digital Dashboard." "ERROR"
                }
            }
            "*Intel*" {
                winget install --id=Intel.MemoryAndStorageTool -e --silent --accept-package-agreements --accept-source-agreements
                Log "Intel Memory and Storage Tool installed." "INFO"
                $installedDiskApps += "Intel"
            }
            "*SanDisk*" {
                winget install --id=SanDisk.Dashboard -e --silent --accept-package-agreements --accept-source-agreements
                Log "SanDisk SSD Dashboard installed." "INFO"
                $installedDiskApps += "SanDisk"
            }
            default { Log "No specific disk management app needed for this disk, or none found via winget." }
        }
    }
} catch {
    # Log any errors during disk detection or management app installation.
    Log "Error installing disk management app: $_" -Level "ERROR"
}


# ================== 8. Disable OneDrive Autostart ==================
#
# This section configures OneDrive to prevent it from automatically starting with Windows.
# This is often desired in corporate or managed environments to reduce resource usage
# or enforce alternative cloud solutions.
#
try {
    Log "Disabling OneDrive autostart..."
    
    # Define the scheduled task name associated with OneDrive updates/startup.
    $taskName = "OneDrive Standalone Update Task"
    # Attempt to get the scheduled task. `-ErrorAction SilentlyContinue` prevents the script from stopping if it's not found.
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        # If the task exists, disable it.
        Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Log "OneDrive scheduled task disabled."
    } else {
        Log "OneDrive scheduled task not found. It may already be disabled or not present."
    }

    # Define the registry path for OneDrive Group Policy settings.
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    # Create the OneDrive policy key if it doesn't exist. `-Force` allows creation of parent keys.
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    # Set the `DisableFileSyncNGSC` DWORD value to 1. This Group Policy setting prevents
    # OneDrive (Next Generation Sync Client) from starting automatically when a user logs on.
    New-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWORD -Force | Out-Null
    Log "Group Policy key set to disable OneDrive autostart."
} catch {
    # Log any errors encountered while trying to disable OneDrive autostart.
    Log "Error disabling OneDrive autostart: $_" -Level "ERROR"
}

# ================== 9. Set File Explorer to Default to 'This PC' ==================
#
# This section modifies a registry setting to change the default view in File Explorer.
# By default, File Explorer often opens to 'Quick access'. This changes it to 'This PC'.
#
try {
    Log "Configuring File Explorer to open to 'This PC' by default..."
    # Define the registry key path for File Explorer advanced settings.
    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    # Set the 'LaunchTo' value to 1, which corresponds to 'This PC'.
    # A value of 2 corresponds to 'Quick access'.
    Set-ItemProperty -Path $explorerKey -Name 'LaunchTo' -Value 1
    Log "File Explorer successfully set to open to 'This PC' by default."
} catch {
    # Log any errors during the configuration of the default File Explorer view.
    Log "Failed to set default File Explorer view: $_" -Level "ERROR"
}

# ================== 10. Set Desktop Icons ==================
#
# This section ensures that common system icons (This PC, Network, Control Panel, User's Files)
# are visible on the desktop. These are often hidden by default in modern Windows versions.
#
try {
    Log "Setting common desktop icons (This PC, Network, Control Panel, User's Files)..."

    # Registry path to manage desktop icon visibility.
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

    Log "Desktop icons set successfully."
} catch {
    # Log any errors that prevent setting desktop icon visibility.
    Log "Failed to set desktop icons: $_" -Level "ERROR"
}
# ==================== Final Cleanup ====================
# Uninstall Chocolatey if it was installed by this script and is no longer needed.
if (Uninstall-Chocolatey) {
    Log "Chocolatey uninstallation completed."
} else {
    Log "Chocolatey uninstallation failed or was skipped." "WARN"
}
# ================== End of script ==================
#
# This final log entry marks the successful completion of the MACHINEPREP script's execution.
#
Log "==== MACHINEPREP Script Completed ===="