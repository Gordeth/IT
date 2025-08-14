# ==================================================
# Functions.ps1
# Version: 1.0.1
# Contains reusable functions for the IT maintenance project.
# ==================================================

# ================== DEFINE LOG FUNCTION ==================
# A custom logging function to write messages to the console (if verbose mode is on)
# and to a persistent log file.
function Log {
    param (
        [string]$Message,                               # The message to be logged
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")] # Validation for log level
        [string]$Level = "INFO"                         # Default log level is INFO
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss" # Format the current date and time
    $logEntry = "[$timestamp] [$Level] $Message"       # Construct the full log entry string

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
# Silently downloads and registers the NuGet provider using a robust, non-interactive method.
# =================================================================================
function Install-NuGetProvider {
    Log "Ensuring NuGet provider is installed and ready..."

    try {
        # This is a robust and non-interactive way to install the NuGet provider.
        # It's idempotent, meaning it won't fail if the provider is already installed.
        # We use -Force to handle updates and -ErrorAction Stop to catch any critical failures.
        # The addition of -Confirm:$false ensures no interactive prompts are shown.
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force -Confirm:$false -ErrorAction Stop
        
        Log "Install-PackageProvider command executed successfully. Waiting for installation to complete..."
        
        # Adding a short delay helps prevent race conditions where the provider
        # might not be immediately ready for use by the parent script.
        Start-Sleep -Seconds 5
        
        Log "NuGet provider installed and verified."
    } catch {
        # This try/catch block will now catch any errors from the installation command itself.
        Log "FATAL ERROR: Failed to install or verify NuGet provider: $($_.Exception.Message)" -Level "ERROR"
        # Since this is a critical dependency, we exit the script if it fails.
        exit 1
    }
}

# ==================== Helper Function: Install Chocolatey ====================
#
# Function: Install-Chocolatey
# Description: Checks if Chocolatey is installed and, if not, installs it.
#              This function is critical for installing software packages not
#              available via Winget.
#
# Prerequisites:
#   - Internet connectivity.
#   - PowerShell Execution Policy set to Bypass (handled by WUH.ps1 or temporarily here).
#
# Returns:
#   - $true if Chocolatey is successfully installed or already present.
#   - $false if Chocolatey installation fails.
#
function Install-Chocolatey {
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

# ==================== Helper Function: Uninstall Chocolatey ====================
#
# Function: Uninstall-Chocolatey
# Description: Uninstalls Chocolatey from the system. This is intended for cleanup
#              if Chocolatey was only needed temporarily for machine preparation.
#
# Returns:
#   - $true if Chocolatey is successfully uninstalled or not found.
#   - $false if Chocolatey uninstallation fails.
#
function Uninstall-Chocolatey {
    Log "Checking for Chocolatey to uninstall..." "INFO"
    $chocoInstallPath = "$env:ProgramData\chocolatey" # Default Chocolatey installation path

    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        Log "Chocolatey found. Attempting to uninstall Chocolatey..." "INFO"
        try {
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
                return $true
            } catch {
                Log "Failed to delete lingering Chocolatey installation folder: $_" "ERROR"
                return $false
            }
        } else {
            Log "Chocolatey installation folder not found. No deletion needed." "INFO"
            return $true
        }
    }
}