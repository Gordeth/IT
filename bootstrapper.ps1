<#
.SYNOPSIS
    Automates initial setup and preparation of a Windows machine.
.DESCRIPTION
    This script automates the initial setup and preparation of a Windows machine.
    It includes tasks such as installing essential software (TeamViewer, common apps),
    ensuring related scripts (WUA.ps1, WGET.ps1) are present and executed,
    configuring system settings (OneDrive, File Explorer, desktop icons),
    and installing brand-specific utilities (driver update tools, disk management apps).
.NOTES
    Script: Bootstrapper.ps1
    Version: 1.0.6
    Execution: This script should be run with Administrator privileges.
    Dependencies:
        - winget (Windows Package Manager) must be installed and configured.
        - Internet connectivity for downloading files and installing packages.
        - Optional: Chocolatey (will be installed by this script if needed)
    Changelog:
        v1.0.6
        - Added changelog.
        - Improved error handling and logging.
        
#>

# Define your GitHub repository details
$repoName = "Gordeth/IT"
# Base URL for the GitHub API to list directory contents
$apiUrl = "https://api.github.com/repos/$repoName/contents"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\IAP"

# Define the directories to download
$dirsToDownload = @(
    "src",
    "modules"
)

# ==================================================
# Core Download and Execution Logic
# ==================================================

# Use Push-Location to save the current directory.
Write-Host "Saving current working directory and starting the process..."
Push-Location

# A try-finally block ensures that Pop-Location is always called,
# and also that the cleanup code runs.
try {
    # Clean up old project directory if it exists
    Write-Host "Checking for old project directory..."
    if (Test-Path $projectDir) {
        Write-Host "Old project directory found. Removing old project directory: $projectDir"
        Remove-Item -Path $projectDir -Recurse -Force
    }

    Write-Host "Creating new project directory: $projectDir"
    New-Item -ItemType Directory -Path $projectDir | Out-Null

    # Download each required directory individually using the GitHub API
    foreach ($dir in $dirsToDownload) {
        Write-Host "Downloading contents of '$dir' folder from GitHub..."
        $dirApiUrl = "$apiUrl/$dir"
        $destinationDir = Join-Path $projectDir $dir
        
        try {
            # Fetch the list of files from the API
            $files = Invoke-RestMethod -Uri $dirApiUrl
            
            # Create the local directory
            New-Item -ItemType Directory -Path $destinationDir | Out-Null
            
            # Download each file individually
            foreach ($file in $files) {
                # Only download files, not sub-directories
                if ($file.type -eq "file") {
                    $sourceUrl = $file.download_url
                    $destinationFile = Join-Path $destinationDir $file.name
                                        
                    try {
                        Invoke-WebRequest -Uri $sourceUrl -OutFile $destinationFile -ErrorAction Stop
                    } catch {
                        Write-Host "ERROR: Failed to download $($file.name). Error: $_" -ForegroundColor Red
                        Exit 1
                    }
                }
            }
        } catch {
            Write-Host "Failed to access the GitHub API for '$dir'. Error: $_" -ForegroundColor Red
            Exit 1
        }
    }

    # --- Execute Logic ---
    $orchestratorScriptPath = "$projectDir\src\TO.ps1"

    if (Test-Path $orchestratorScriptPath) {
        Write-Host "Running the main orchestrator script..."
        
        # Change the working directory to where the main script is.
        Set-Location -Path (Split-Path -Path $orchestratorScriptPath)
        
        # Execute the orchestrator script
        & $orchestratorScriptPath
    } else {
        Write-Host "Could not find the main orchestrator script at $orchestratorScriptPath. Aborting." -ForegroundColor Red
        Exit 1
    }

} finally {
    # --- IMPORTANT: BEGIN FINAL CLEANUP BY RESTORING ORIGINAL DIRECTORY ---
    # This must be the first command in the 'finally' block to release file locks.
    Write-Host "All operations complete. Returning to original directory."
    Pop-Location
    
    # --- Now we can safely remove the temporary directory ---
    Write-Host "Starting final cleanup of temporary project files..."
    if (Test-Path $projectDir) {
        Write-Host "Removing temporary project directory: $projectDir"
        Remove-Item -Path $projectDir -Recurse -Force
        Write-Host "Temporary project directory removed."
    } else {
        Write-Host "Temporary project directory not found. No cleanup needed."
    }
    
    Write-Host "Script finished."
}