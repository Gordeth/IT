# ==================================================
# Functions.ps1
# Version: 1.0.0
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

# ==================================================
# Install-NuGetProvider
# Silently downloads and registers the NuGet provider.
# ==================================================
function Install-NuGetProvider {
    Log "Checking for NuGet provider..."

    # --- Import the PackageManagement module ---
    # This ensures cmdlets like Register-PackageProvider are available.
    try {
        Import-Module PackageManagement -Force -ErrorAction Stop
    } catch {
        Log "Failed to load PackageManagement module. Please ensure it is installed." -Level "ERROR"
        exit 1
    }

    # --- A more robust check for the NuGet provider ---
    # This checks for the provider by checking for the physical file path.
    $isProviderInstalled = $false
    try {
        # Define the path to the PackageManagement module
        $packageManagementPath = (Get-Module PackageManagement).Path | Split-Path
        $nuGetProviderDir = Join-Path -Path $packageManagementPath -ChildPath "provider"
        $nugetProviderPath = Join-Path -Path $nuGetProviderDir -ChildPath "Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll"

        # Check if the provider DLL file exists on disk
        if (Test-Path -Path $nugetProviderPath) {
            $isProviderInstalled = $true
        }
    } catch {
        # If any error occurs during the check, assume it's not installed
        $isProviderInstalled = $false
    }

    if (-not $isProviderInstalled) {
        Log "NuGet provider not found. Attempting silent installation..."
        try {
            # Define the path to the PackageManagement module
            $packageManagementPath = (Get-Module PackageManagement).Path | Split-Path

            # Define the local folder for the NuGet provider
            $nuGetProviderDir = Join-Path -Path $packageManagementPath -ChildPath "provider"

            # Create the directory if it doesn't exist
            if (-not (Test-Path $nuGetProviderDir)) {
                New-Item -ItemType Directory -Path $nuGetProviderDir -Force | Out-Null
            }

            # Define the URL and local path for the NuGet provider DLL
            $nugetProviderUrl = "https://onegetcdn.azureedge.net/providers/Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll"
            $nugetProviderPath = Join-Path -Path $nuGetProviderDir -ChildPath "Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll"

            Log "Downloading NuGet provider from $nugetProviderUrl..."
            Invoke-WebRequest -Uri $nugetProviderUrl -OutFile $nugetProviderPath -UseBasicParsing

            Log "NuGet provider downloaded. Manually registering it..."
            Register-PackageProvider -Name NuGet -ProviderPath $nugetProviderPath -Force -Verbose:$false

            Log "NuGet provider installed successfully." -Level "INFO"
        } catch {
            Log "Failed to perform silent NuGet installation. Error: $_" -Level "ERROR"
            # If this fails, the script cannot proceed.
            exit 1
        }
    } else {
        Log "NuGet provider already installed." -Level "INFO"
    }
}
