# ==================================================
# Bootstrapper.ps1
# V 1.0.2
# Downloads and runs the modular IT maintenance project.
# ==================================================

# Define your GitHub repository details
$repoName = "Gordeth/IT"
$branch = "main"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\WUH"

# ==================================================
# Core Download and Execution Logic
# ==================================================

# Assume an update is always needed if version control is commented out.
$updateRequired = $true

if ($updateRequired) {
    Write-Host "Downloading project from GitHub..."
    $zipFile = "$env:TEMP\repo.zip"
    
    # Ensure the destination folder exists and is empty
    if (Test-Path $projectDir) {
        Remove-Item -Path $projectDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $projectDir | Out-Null

    Invoke-WebRequest -Uri "https://github.com/$repoName/archive/$branch.zip" -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath "$projectDir" -Force
    Remove-Item $zipFile -Force
}

# --- Execute Logic ---
# The repository is unzipped into a folder named 'IT-main' inside the 'WUH' folder.
$localProjectPath = "$projectDir\IT-main"

# The orchestrator and functions scripts are inside the 'src' folder.
$orchestratorScriptPath = "$localProjectPath\src\WUH.ps1"
$functionsScriptPath = "$localProjectPath\modules\Functions.ps1"

if (Test-Path $orchestratorScriptPath) {
    Write-Host "Loading shared functions..."
    
    if (Test-Path $functionsScriptPath) {
        # Dot-source the shared functions script using its full path.
        . $functionsScriptPath
        
        Write-Host "Shared functions loaded. Running the main orchestrator script..."
        
        # Execute the orchestrator script using its full path.
        & $orchestratorScriptPath
    } else {
        Write-Host "Could not find the shared functions script at $functionsScriptPath. Aborting." -ForegroundColor Red
    }
} else {
    Write-Host "Could not find the main orchestrator script at $orchestratorScriptPath. Aborting." -ForegroundColor Red
}
