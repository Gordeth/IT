# ================== CONFIGURATION ==================
$BaseUrl = "https://raw.githubusercontent.com/Gordeth/IT/main"
$ScriptDir = "$env:TEMP\ITScripts"
$LogDir = "$ScriptDir\Log"
$LogFile = "$LogDir\WUH_log.txt"
$PowerPlanName = "TempMaxPerformance"

# ================== CREATE DIRECTORIES ==================
if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
if (-not (Test-Path $LogFile)) { "[{0}] Log file created." -f (Get-Date) | Out-File $LogFile -Append }

# ================== DEFINE LOG FUNCTION ==================
function Log {
    param (
        [string]$Message
    )
    $timestamp = "[{0}]" -f (Get-Date)
    "$timestamp $Message" | Out-File $LogFile -Append
    if ($VerboseMode) {
        Write-Host "$timestamp $Message"
    }
}

# ================== ASK FOR MODE ==================
Write-Host ""
Write-Host "Select Mode:"
Write-Host "[S] Silent (logs only)"
Write-Host "[V] Verbose (console and logs)"
$mode = Read-Host "Choose mode [S/V]"
if ($mode.ToUpper() -eq "V") {
    $VerboseMode = $true
    Log "Verbose mode selected."
} else {
    $VerboseMode = $false
    Log "Silent mode selected."
}

# ================== ASK FOR TASK ==================
Write-Host ""
Write-Host "Select Task:"
Write-Host "[1] Machine Preparation"
Write-Host "[2] Windows Maintenance"
$task = Read-Host "Choose task [1/2]"

# ================== SET EXECUTION POLICY ==================
Log "Setting Execution Policy to Bypass..."
Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

# ================== INSTALL NUGET PROVIDER ==================
Log "Checking for NuGet provider..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
        Log "NuGet provider installed successfully."
    } catch {
        Log "Failed to install NuGet provider: $_"
        Exit 1
    }
}

# ================== REGISTER PSGALLERY (OPTIONAL) ==================
Log "Checking PSGallery repository..."
if (-not (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" })) {
    try {
        Register-PSRepository -Default
        Log "PSGallery repository registered."
    } catch {
        Log "Failed to register PSGallery: $_"
        Exit 1
    }
}

# ================== CREATE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
Log "Creating temporary Maximum Performance power plan..."
try {
    $guid = (powercfg -duplicatescheme SCHEME_MIN).Trim()
    powercfg -changename $guid $PowerPlanName "Temporary Maximum Performance"
    powercfg -setactive $guid
    Log "Temporary Maximum Performance power plan activated."
} catch {
    Log "Failed to create or set temporary power plan: $_"
}

# ================== DOWNLOAD SCRIPT FUNCTION ==================
function Download-Script {
    param (
        [string]$ScriptName
    )
    $scriptPath = Join-Path $ScriptDir $ScriptName
    if (Test-Path $scriptPath) {
        Log "Deleting existing $ScriptName for fresh download."
        Remove-Item -Path $scriptPath -Force
    }
    $url = "$BaseUrl/$ScriptName"
    Log "Downloading $ScriptName from $url..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $scriptPath -UseBasicParsing -Verbose:$VerboseMode
        Log "$ScriptName downloaded successfully."
    } catch {
        Log "Failed to download ${ScriptName}: $_"
        Exit 1
    }
}

# ================== RUN SCRIPT FUNCTION ==================
function Run-Script {
    param (
        [string]$ScriptName
    )
    $scriptPath = Join-Path $ScriptDir $ScriptName
    Log "Running $ScriptName..."
    try {
        & $scriptPath
        Log "$ScriptName executed successfully."
    } catch {
        Log "Error during execution of ${ScriptName}: $_"
        Exit 1
    }
}

# ================== TASK SELECTION ==================
switch ($task) {
    "1" {
        Log "Task selected: Machine Preparation"
        Download-Script -ScriptName "MachinePrep.ps1"
        Run-Script -ScriptName "MachinePrep.ps1"
    }
    "2" {
        Log "Task selected: Windows Maintenance"
        Download-Script -ScriptName "WU.ps1"
        Run-Script -ScriptName "WU.ps1"

        Download-Script -ScriptName "WGET.ps1"
        Run-Script -ScriptName "WGET.ps1"

        Download-Script -ScriptName "MSO_UPDATE.ps1"
        Run-Script -ScriptName "MSO_UPDATE.ps1"
    }
    default {
        Log "Invalid task selection. Exiting script."
        Exit 1
    }
}

# ================== RESET POWER PLAN TO BALANCED ==================
Log "Resetting power plan to Balanced..."
try {
    powercfg -setactive SCHEME_BALANCED
    Log "Power plan reset to Balanced."
} catch {
    Log "Failed to reset power plan to Balanced: $_"
}

# ================== CLEANUP ==================
Log "Resetting Execution Policy to Restricted..."
Set-ExecutionPolicy Restricted -Scope Process -Force -ErrorAction SilentlyContinue

Log "Deleting downloaded scripts..."
Get-ChildItem -Path $ScriptDir -Filter *.ps1 | Remove-Item -Force

Log "Script completed successfully."
