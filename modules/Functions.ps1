<#
.SYNOPSIS
    A collection of reusable helper functions for the IT Automation Project.
.DESCRIPTION
    This script contains shared helper functions used by other scripts in the project, such as logging, package manager setup (NuGet, Chocolatey), and file downloads.
    It is not meant to be run directly but dot-sourced by other scripts.
.NOTES
    Script: Functions.ps1
    Version: 1.0.11
    Changelog:
        v1.0.11
        - Updated logging and module installation.
        v1.0.10
        - Reverted debug logging from Log function.
        v1.0.9
        - Added debug logging to Log function for troubleshooting.
        v1.0.8
        - Improved logging and module installation robustness.
        v1.0.7
        - Updated Save-File to show download speed
        v1.0.6
        - Initial Release
#>

# ================== DEFINE LOG FUNCTION ================== 
# A custom logging function to write messages to the console (if verbose mode is on)
# and to a persistent log file.
function Log {
<#
.SYNOPSIS
    Writes a formatted log message to a file and optionally to the console.
.DESCRIPTION
    A custom logging function that writes a timestamped and leveled message to a log file defined by the global $LogFile variable.
    If the global $VerboseMode switch is enabled or the level is 'ERROR', the message is also written to the console with appropriate coloring.
.PARAMETER Message
    The message string to be logged.
.PARAMETER Level
    The severity level of the message. Valid options are "INFO", "WARN", "ERROR", "DEBUG". Defaults to "INFO".
.EXAMPLE
    Log "Starting process..."
.EXAMPLE
    Log "Could not find file." -Level "WARN"
#>
    param (
        [string]$Message,                                     # The message to be logged
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")] # Validation for log level
        [string]$Level = "INFO"                               # Default log level is INFO
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss" # Format the current date and time
    $logEntry = "[$timestamp] [$Level] $Message"      # Construct the full log entry string

    try {
        # Attempt to append the log entry to the specified log file.
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        # If writing to the log file fails, output an error to the console.
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    # If VerboseMode is enabled or the log level is ERROR, also output to the console.
    if ($VerboseMode -or $Level -eq "ERROR") {
        # Determine the console foreground color based on the log level.
        $color = switch ($Level) {
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Gray" }
            default { "White" } # Default color if level is not recognized
        }
        Write-Host $logEntry -ForegroundColor $color # Output the log entry to the console
    }
}

# =================================================================================
# Install-NuGetProvider
# Checks if the NuGet provider is installed. If not, it silently downloads and 
# registers it using a robust, non-interactive method.
# =================================================================================
function Install-NuGetProvider {
<#
.SYNOPSIS
    Installs the NuGet package provider if it is not already installed.
.DESCRIPTION
    Checks if the NuGet package provider is available for PowerShell. If not, it installs it non-interactively for all users.
    This is a prerequisite for installing modules from the PowerShell Gallery. The script will exit with an error if the installation fails.
.NOTES
    Requires administrator privileges to install the provider for AllUsers.
.EXAMPLE
    Install-NuGetProvider
#>
    Log "Checking for existing NuGet provider..."

    # Attempt to get the NuGet provider and store the result.
    # The -ErrorAction SilentlyContinue is crucial here.
    # $provider = Get-PackageProvider -Name 'NuGet' -ErrorAction SilentlyContinue
    $provider = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\PowerShell\3\PackagingProviders").NuGetProviderInstalled

    # Check if a provider was found. If not, proceed with installation.
    if (-not $provider) {
        Log "NuGet provider not found. Beginning installation..."
        try {
            # Use -Force and -Confirm:$false to ensure a non-interactive installation.
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force -Confirm:$false -ErrorAction Stop
            
            Log "NuGet provider installation successful."
            
        } catch {
            Log "FATAL ERROR: Failed to install NuGet provider: $($_.Exception.Message)" -Level "ERROR"
            exit 1
        }
    } else {
        # This branch will execute if the provider was successfully found.
        Log "NuGet provider version $($provider.Version) is already installed. Continuing."
    }
}


function Install-Chocolatey {
<#
.SYNOPSIS
    Installs the Chocolatey package manager if it is not already installed.
.DESCRIPTION
    Checks for the presence of 'choco.exe'. If not found, it downloads and executes the official Chocolatey installation script.
    It temporarily sets the process execution policy to Bypass to allow the script to run.
.NOTES
    Requires an active internet connection.
.RETURNS
    Returns $true if Chocolatey is successfully installed or was already present.
    Returns $false if the installation fails.
.EXAMPLE
    if (Install-Chocolatey) { Log "Ready to use Chocolatey." }
#>
    Log "Checking for Chocolatey installation..." "INFO"
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Log "Chocolatey not found. Attempting to install Chocolatey..." "INFO"
        try {
            # Temporarily set execution policy to Bypass for the current process
            # to allow the Chocolatey installation script to run.
            # This is safer than modifying global policy.
            $originalProcessPolicy = Get-ExecutionPolicy -Scope Process
            Set-ExecutionPolicy Bypass -Scope Process -Force

            # Ensure TLS1.2 is enabled for the download.
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

            # Download and execute the Chocolatey installation script.
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

            # Check if choco.exe is now available to confirm installation.
            if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
                Log "Chocolatey installed successfully." "INFO"
                return $true
            } else {
                Log "Chocolatey installation completed, but choco.exe not found. Something went wrong." "ERROR"
                return $false
            }
        } catch {
            Log "Failed to install Chocolatey: $_" "ERROR"
            return $false
        } finally {
            # Restore the execution policy for the current process.
            Set-ExecutionPolicy $originalProcessPolicy -Scope Process -Force
        }
    } else {
        Log "Chocolatey is already installed." "INFO"
        return $true
    }
}

function Uninstall-Chocolatey {
<#
.SYNOPSIS
    Uninstalls Chocolatey and performs a thorough cleanup.
.DESCRIPTION
    This function completely removes Chocolatey from the system. It stops running choco processes, runs the official uninstaller,
    and then manually removes leftover directories and environment variables to ensure a clean state.
.RETURNS
    Returns $true if Chocolatey is successfully uninstalled or was not present.
    Returns $false if the uninstallation or cleanup fails.
.EXAMPLE
    Uninstall-Chocolatey
#>
    Log "Checking for Chocolatey to uninstall..." "INFO"
    $chocoInstallPath = "$env:ProgramData\chocolatey" # Default Chocolatey installation path
    $chocoTempPath = "$env:TEMP\chocolatey"           # Temporary Chocolatey folder

    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        Log "Chocolatey found. Attempting to uninstall Chocolatey..." "INFO"
        try {
            # === NEW: Terminate any processes that might be locking files ===
            Log "Checking for and stopping any running Chocolatey processes..." "INFO"
            $chocoProcesses = Get-Process -Name "choco*" -ErrorAction SilentlyContinue
            if ($chocoProcesses) {
                foreach ($process in $chocoProcesses) {
                    Log "Stopping process '$($process.ProcessName)' with ID $($process.Id)." "INFO"
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            } else {
                Log "No Chocolatey-related processes found." "INFO"
            }
            
            # Attempt to uninstall Chocolatey package
            choco uninstall chocolatey -y
            
            # Perform additional cleanup for Chocolatey-related directories and environment variables
            Log "Performing additional cleanup for Chocolatey directories and environment variables." "INFO"

            # Delete ChocolateyBinRoot if it exists and unset its environment variable
            if ($env:ChocolateyBinRoot -ne '' -and $null -ne $env:ChocolateyBinRoot -and (Test-Path "$env:ChocolateyBinRoot")) {
                Log "Deleting ChocolateyBinRoot: $($env:ChocolateyBinRoot)" "INFO"
                Remove-Item -Recurse -Force "$env:ChocolateyBinRoot" -ErrorAction SilentlyContinue
                [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'Machine') # Unset machine-wide
                [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'User')    # Unset user-specific
            }

            # Delete ChocolateyToolsRoot if it exists and unset its environment variable
            if ($env:ChocolateyToolsRoot -ne '' -and $null -ne $env:ChocolateyToolsRoot -and (Test-Path "$env:ChocolateyToolsRoot")) {
                Log "Deleting ChocolateyToolsRoot: $($env:ChocolateyToolsRoot)" "INFO"
                Remove-Item -Recurse -Force "$env:ChocolateyToolsRoot" -ErrorAction SilentlyContinue
                [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'Machine') # Unset machine-wide
                [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'User')    # Unset user-specific
            }

            # Check and delete the main Chocolatey installation folder if it still exists
            if (Test-Path $chocoInstallPath) {
                Log "Main Chocolatey installation folder still exists: $chocoInstallPath. Deleting it." "INFO"
                Remove-Item -Path $chocoInstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # === NEW: Delete the temporary Chocolatey folder ===
            if (Test-Path $chocoTempPath) {
                Log "Deleting temporary Chocolatey folder: $chocoTempPath." "INFO"
                Remove-Item -Path $chocoTempPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Final verification if choco.exe is gone
            if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
                Log "Chocolatey uninstalled and directories cleaned successfully." "INFO"
                return $true
            } else {
                Log "Chocolatey uninstallation completed, but choco.exe still present despite cleanup attempts. Check logs." "WARN"
                return $false
            }
        } catch {
            Log "Failed during Chocolatey uninstallation or cleanup: $_" "ERROR"
            return $false
        }
    } else {
        Log "Chocolatey is not installed. No uninstallation needed for the package." "INFO"
        # If choco.exe is not found, perform cleanup for lingering folders/environment variables.
        Log "Chocolatey executable not found, performing cleanup for lingering folders and environment variables." "INFO"

        # Delete ChocolateyBinRoot if it exists and unset its environment variable
        if ($env:ChocolateyBinRoot -ne '' -and $null -ne $env:ChocolateyBinRoot -and (Test-Path "$env:ChocolateyBinRoot")) {
            Log "Deleting lingering ChocolateyBinRoot: $($env:ChocolateyBinRoot)" "INFO"
            Remove-Item -Recurse -Force "$env:ChocolateyBinRoot" -ErrorAction SilentlyContinue
            [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'Machine')
            [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'User')
        }

        # Delete ChocolateyToolsRoot if it exists and unset its environment variable
        if ($env:ChocolateyToolsRoot -ne '' -and $null -ne $env:ChocolateyToolsRoot -and (Test-Path "$env:ChocolateyToolsRoot")) {
            Log "Deleting lingering ChocolateyToolsRoot: $($env:ChocolateyToolsRoot)" "INFO"
            Remove-Item -Recurse -Force "$env:ChocolateyToolsRoot" -ErrorAction SilentlyContinue
            [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'Machine')
            [System.Environment]::SetEnvironmentVariable("ChocolateyToolsRoot", $null, 'User')
        }

        # Delete main Chocolatey install path if it exists
        if (Test-Path $chocoInstallPath) {
            Log "Lingering Chocolatey installation folder exists: $chocoInstallPath. Deleting it." "INFO"
            try {
                Remove-Item -Path $chocoInstallPath -Recurse -Force -ErrorAction Stop
                Log "Chocolatey installation folder deleted successfully." "INFO"
            } catch {
                Log "Failed to delete lingering Chocolatey installation folder: $_" "ERROR"
                return $false
            }
        } else {
            Log "Chocolatey installation folder not found. No deletion needed." "INFO"
        }
        
        # === NEW: Delete the temporary Chocolatey folder ===
        if (Test-Path $chocoTempPath) {
            Log "Deleting temporary Chocolatey folder: $chocoTempPath." "INFO"
            Remove-Item -Path $chocoTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $true
    }
}


function Save-File {
<#
.SYNOPSIS
    Downloads a file from a URL and saves it to a specified path.
.DESCRIPTION
    Uses the native Windows curl.exe to download a file, providing progress and speed information in the console output.
.PARAMETER Url
    The URL of the file to download.
.PARAMETER OutputPath
    The local file path where the downloaded file will be saved.
.RETURNS
    Returns $true on successful download, $false on failure.
.NOTES
    This function has a hardcoded dependency on 'C:\Windows\System32\curl.exe'.
.EXAMPLE
    Save-File -Url "https://example.com/installer.exe" -OutputPath "$env:TEMP\installer.exe"
#>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    Log "Downloading $Url to $OutputPath..." "INFO"
    try {
        C:\Windows\System32\curl.exe -L --output $OutputPath --write-out "Downloaded %{filename_effective} in %{time_total}s, Average Speed: %{speed_download} B/s\n" $Url
        Log "Successfully downloaded $Url." "INFO"
        return $true
    } catch {
        Log "ERROR: Failed to download $Url. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
