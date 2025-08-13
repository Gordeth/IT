# ==================================================
# Bootstrapper.ps1
# V 1.0.0
# Downloads and runs the modular IT maintenance project.
# ==================================================

# Define your GitHub repository details
$repoName = "Gordeth/IT"
$branch = "main"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\IT-Maintenance"
$localProjectPath = "$projectDir\IT-$branch"

<#
# ==================================================
# Version Control Logic (Commented Out)
# ==================================================
# To enable version checking, uncomment this entire block.
# This will prevent the script from downloading the project
# every time it's run if a local version already exists and
# is up-to-date with your GitHub repository.
#
# Remember to create a 'version.txt' file in your GitHub
# repository root with a version number (e.g., '1.0.0').
#

# Define version file paths
$localVersionFile = "$localProjectPath\version.txt"
$remoteVersionFileUrl = "https://raw.githubusercontent.com/$repoName/$branch/version.txt"

# --- Version Check ---
$updateRequired = $true
if (Test-Path $localProjectPath) {
    Write-Host "Local project directory found. Checking for new versions..."
    try {
        $localVersion = Get-Content -Path $localVersionFile -ErrorAction Stop
        $remoteVersion = Invoke-RestMethod -Uri $remoteVersionFileUrl
        
        if ([version]$remoteVersion -gt [version]$localVersion) {
            Write-Host "New version ($remoteVersion) available. Downloading update..." -ForegroundColor Green
            $updateRequired = $true
        } else {
            Write-Host "Scripts are already up to date ($localVersion). Skipping download." -ForegroundColor Green
            $updateRequired = $false
        }
    }
    catch {
        Write-Host "Could not perform version check. Forcing update..." -ForegroundColor Yellow
        $updateRequired = $true
    }
} else {
    Write-Host "No local project found. Performing initial download..." -ForegroundColor Green
    $updateRequired = $true
}

#>
# ==================================================
# Core Download and Execution Logic
# ==================================================

# Assume an update is always needed if version control is commented out.
$updateRequired = $true

if ($updateRequired) {
    Write-Host "Downloading project from GitHub..."
    $zipFile = "$env:TEMP\repo.zip"
    Invoke-WebRequest -Uri "https://github.com/$repoName/archive/$branch.zip" -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath "$projectDir" -Force
    Remove-Item $zipFile -Force
}

# --- Execute Logic ---
$orchestratorScriptPath = "$localProjectPath\src\WUH.ps1"
$functionsScriptPath = "$localProjectPath\src\modules\Functions.ps1"

if (Test-Path $orchestratorScriptPath) {
    # Dot-source the shared functions script directly.
    Write-Host "Loading shared functions..."
    if (Test-Path $functionsScriptPath) {
        . $functionsScriptPath
        
        Write-Host "Shared functions loaded. Running the main orchestrator script..."
        
        # This is the key change: we use Invoke-Expression with -File to ensure the script
        # executes in its correct context, resolving all internal paths properly.
        Invoke-Expression -Command "$orchestratorScriptPath"
    } else {
        Write-Host "Could not find the shared functions script at $functionsScriptPath. Aborting." -ForegroundColor Red
    }
} else {
    Write-Host "Could not find the main orchestrator script at $orchestratorScriptPath. Aborting." -ForegroundColor Red
}