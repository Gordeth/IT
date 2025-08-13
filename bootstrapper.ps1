# ==================================================
# Bootstrapper.ps1
# V 1.0.4
# Downloads and runs the modular IT maintenance project without an intermediate folder.
# ==================================================

# Define your GitHub repository details
$repoName = "Gordeth/IT"
$branch = "main"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\WUH"
$tempExtractDir = "$env:TEMP\IT-Temp"

# ==================================================
# Core Download and Execution Logic
# ==================================================

$updateRequired = $true

if ($updateRequired) {
    Write-Host "Downloading project from GitHub..."
    $zipFile = "$env:TEMP\repo.zip"
    
    # Clean up old project directory and temporary extraction directory
    if (Test-Path $projectDir) {
        Remove-Item -Path $projectDir -Recurse -Force
    }
    if (Test-Path $tempExtractDir) {
        Remove-Item -Path $tempExtractDir -Recurse -Force
    }

    # Create the destination directory
    New-Item -ItemType Directory -Path $projectDir | Out-Null
    New-Item -ItemType Directory -Path $tempExtractDir | Out-Null

    # Download the repository zip file
    Invoke-WebRequest -Uri "https://github.com/$repoName/archive/$branch.zip" -OutFile $zipFile

    # Unzip the file into the temporary directory
    Expand-Archive -Path $zipFile -DestinationPath $tempExtractDir -Force
    
    # Get the name of the folder created by GitHub's zip (e.g., 'IT-main')
    $sourcePath = (Get-ChildItem -Path $tempExtractDir | Select-Object -First 1).FullName

    # Copy the contents of that folder to the final project directory
    Write-Host "Copying files to the target folder ($projectDir)..."
    Copy-Item -Path "$sourcePath\*" -Destination $projectDir -Recurse -Force
    
    # Remove the temporary zip file and extraction folder
    Remove-Item $zipFile -Force
    Remove-Item $tempExtractDir -Recurse -Force
}

# --- Execute Logic ---
# The orchestrator and functions scripts are now directly in the projectDir.
$orchestratorScriptPath = "$projectDir\src\WUH.ps1"
$functionsScriptPath = "$projectDir\modules\Functions.ps1"

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
