# ==================================================
# Bootstrapper.ps1
# V 1.0.7
# Downloads the src and modules folders for the IT maintenance project
# using the GitHub API to ensure all files are fetched.
# ==================================================

# Define your GitHub repository details
$repoName = "Gordeth/IT"
# Base URL for the GitHub API to list directory contents
$apiUrl = "https://api.github.com/repos/$repoName/contents"

# Define the local directory to download the project to
$projectDir = "$env:TEMP\WUH"

# Define the directories to download
$dirsToDownload = @(
    "src",
    "modules"
)

# ==================================================
# Core Download and Execution Logic
# ==================================================

# Clean up old project directory if it exists
Write-Host "Checking for old project directory..."
if (Test-Path $projectDir) {
    Write-Host "Removing old project directory: $projectDir"
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
                Write-Host "Downloading $($file.name)..."
                
                try {
                    Invoke-WebRequest -Uri $sourceUrl -OutFile $destinationFile -UseBasicParsing
                    Write-Host "Successfully downloaded $($file.name)."
                } catch {
                    Write-Host "Failed to download $($file.name). Error: $_" -ForegroundColor Red
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
$orchestratorScriptPath = "$projectDir\src\WUH.ps1"
$functionsScriptPath = "$projectDir\modules\Functions.ps1"

if (Test-Path $orchestratorScriptPath) {
    Write-Host "Loading shared functions..."
    
    if (Test-Path $functionsScriptPath) {
        # Dot-source the shared functions script using its full path.
        . $functionsScriptPath
        
        Write-Host "Shared functions loaded. Running the main orchestrator script..."
        
        # Execute the orchestrator script using its full path.
        # This is where the script's core logic starts.
        & $orchestratorScriptPath
    } else {
        Write-Host "Could not find the shared functions script at $functionsScriptPath. Aborting." -ForegroundColor Red
        Exit 1
    }
} else {
    Write-Host "Could not find the main orchestrator script at $orchestratorScriptPath. Aborting." -ForegroundColor Red
    Exit 1
}
