# ==================================================
# Bootstrapper.ps1
# Downloads and runs the modular IT maintenance project.
# ==================================================

# Define your GitHub repository details
$repoUrl = "https://github.com/Gordeth/IT"
$branch = "main"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\IT-Maintenance"

# Create the project directory if it doesn't exist
if (-not (Test-Path $projectDir)) {
    New-Item -ItemType Directory -Path $projectDir | Out-Null
}

Write-Host "Downloading project from GitHub..."

# Download the repository as a ZIP file
$zipFile = "$env:TEMP\repo.zip"
Invoke-WebRequest -Uri "$repoUrl/archive/$branch.zip" -OutFile $zipFile

# Unzip the contents
Expand-Archive -Path $zipFile -DestinationPath "$projectDir" -Force

# The repository is unzipped into a folder named with the branch
$unzippedPath = "$projectDir\IT-$branch"

# The main orchestrator script is now located in the 'src' folder
$orchestratorScriptPath = "$unzippedPath\src\WUH.ps1"

if (Test-Path $orchestratorScriptPath) {
    Write-Host "Project downloaded successfully. Running the main script..."
    
    # Execute the main orchestrator script from its new location
    & $orchestratorScriptPath
} else {
    Write-Host "Could not find the main orchestrator script at $orchestratorScriptPath. Aborting."
}

# Clean up the downloaded zip file
Remove-Item $zipFile -Force