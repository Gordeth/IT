# ==================================================
# Bootstrapper.ps1
# V 1.0.5
# Downloads only the necessary scripts for the IT maintenance project.
# ==================================================

# Define your GitHub repository details
$repoName = "Gordeth/IT"
$branch = "main"
$baseUrl = "https://raw.githubusercontent.com/$repoName/$branch"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\WUH"

# Define the specific scripts to download
$scriptsToDownload = @(
    "src/WUH.ps1",
    "modules/Functions.ps1"
)

# ==================================================
# Core Download and Execution Logic
# ==================================================

$updateRequired = $true

if ($updateRequired) {
    Write-Host "Downloading project from GitHub..."

    # Clean up old project directory
    if (Test-Path $projectDir) {
        Write-Host "Removing old project directory: $projectDir"
        Remove-Item -Path $projectDir -Recurse -Force
    }
    
    # Create the destination directory and its subfolders
    New-Item -ItemType Directory -Path $projectDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectDir "src") | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectDir "modules") | Out-Null
    
    # Download each required script individually
    foreach ($scriptPath in $scriptsToDownload) {
        $sourceUrl = "$baseUrl/$scriptPath"
        $destinationFile = Join-Path $projectDir $scriptPath
        Write-Host "Downloading $scriptPath..."
        try {
            Invoke-WebRequest -Uri $sourceUrl -OutFile $destinationFile -UseBasicParsing
            Write-Host "Successfully downloaded $scriptPath."
        } catch {
            Write-Host "Failed to download $scriptPath. Error: $_" -ForegroundColor Red
            # Abort if a critical file fails to download
            Exit 1
        }
    }
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
