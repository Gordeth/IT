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
    Version: 1.0.7
    Execution: This script should be run with Administrator privileges.
    Dependencies:
        - winget (Windows Package Manager) must be installed and configured.
        - Internet connectivity for downloading files and installing packages.
        - Optional: Chocolatey (will be installed by this script if needed)
    Changelog:
        v1.0.7:
        - Switched from downloading individual files to downloading the entire repository as a zip for improved performance.
        v1.0.6:
        - Added changelog
        - Improved error handling and logging.        
        v1.0.5:
        - Added logic to download specific directories from GitHub.
        - Implemented cleanup for temporary project files.
        - Improved error handling for GitHub API calls and file downloads.
        v1.0.4:
        - Initial version of the bootstrapper script.

#>

# ================== CONFIGURATION ==================
# Define your GitHub repository details
$repoOwner = "Gordeth"
$repoName = "IT"
$branchName = "main" # The branch to download from

# Define the local directory to download the project to
$projectDir = "$env:TEMP\IAP"

# ==================== Begin Script Execution ====================

Write-Host "Welcome to IT Automation Project" "INFO"
Write-Host "Starting Bootstrapper script v1.0.7..." "INFO"

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

    # --- Download and Extract Repository ---
    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branchName.zip"
    $zipPath = Join-Path $projectDir "repo.zip"

    Write-Host "Downloading repository from $zipUrl..."
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -ErrorAction Stop
        Write-Host "Repository downloaded successfully."
    } catch {
        Write-Host "ERROR: Failed to download repository zip file. Error: $_" -ForegroundColor Red
        Exit 1
    }

    Write-Host "Extracting repository contents..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $projectDir -Force
        Write-Host "Repository extracted successfully."
    } catch {
        Write-Host "ERROR: Failed to extract repository zip file. Error: $_" -ForegroundColor Red
        Exit 1
    }

    # Identify the extracted folder path (e.g., "IT-main")
    $extractedRepoDir = Get-ChildItem -Path $projectDir -Directory | Where-Object { $_.Name -like "$repoName-*" } | Select-Object -First 1
    if (-not $extractedRepoDir) {
        Write-Host "ERROR: Could not find the extracted repository folder." -ForegroundColor Red
        Exit 1
    }
    $projectRoot = $extractedRepoDir.FullName

    # --- Execute Logic ---
    $orchestratorScriptPath = Join-Path $projectRoot "src\TO.ps1"

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