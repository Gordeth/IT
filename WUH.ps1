# ================== CONFIGURATION ==================
$BaseUrl = "https://raw.githubusercontent.com/Gordeth/IT/main"
$ScriptDir = "$env:TEMP\ITScripts"
$LogDir = "$ScriptDir\Log"
$LogFile = "$LogDir\WUH.txt"
$PowerPlanName = "TempMaxPerformance"

# ================== CREATE DIRECTORIES ==================
if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
if (-not (Test-Path $LogFile)) { "[{0}] Log file created." -f (Get-Date) | Out-File $LogFile -Append }

# ================== DEFINE LOG FUNCTION ==================
function Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $LogFile -Value $logEntry
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }

    if ($VerboseMode -or $Level -eq "ERROR") {
        $color = switch ($Level) {
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
    }
}

# ================== SAVE ORIGINAL EXECUTION POLICY ==================
$OriginalPolicy = Get-ExecutionPolicy

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
    $VerbosePreference = "SilentlyContinue"
    $InformationPreference = "SilentlyContinue"
    $ProgressPreference = "SilentlyContinue"
    $WarningPreference = "SilentlyContinue"
}

# ================== ASK FOR TASK ==================
Write-Host ""
Write-Host "Select Task:"
Write-Host "[1] Machine Preparation (semi-automated)"
Write-Host "[2] Windows Maintenance"
$task = Read-Host "Choose task [1/2]"

# ================== CHECK INTERNET CONNECTIVITY ==================
Log "Checking internet connectivity..."
try {
    $null = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10
    Log "Internet connectivity check passed."
} catch {
    Log "Internet connectivity check failed. Please check your network connection."
    Exit 1
}

# ================== SET EXECUTION POLICY ==================
Log "Setting Execution Policy to Bypass..."
Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

# ================== REGISTER AND TRUST PSGALLERY ==================
# This block is moved and modified to ensure PSGallery is trusted before NuGet provider installation.
Log "Checking and configuring PSGallery repository..."
try {
    # Ensure PSGallery is set to Trusted. This is crucial to avoid the untrusted repository prompt.
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
    Log "PSGallery repository set to Trusted."

} catch {
    Log "Failed to trust PSGallery repository: $_" -Level "ERROR"
    Exit 1
}

# ================== INSTALL NUGET PROVIDER ==================
Log "Checking for NuGet provider..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    try {
        $OriginalConfirmPreference = $ConfirmPreference # Save current preference
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -ForceBootstrap -Force -Scope CurrentUser -Confirm:$false -ErrorAction Stop -SkipPublisherCheck
        Log "NuGet provider installed successfully."
} catch {
        Log "Failed to install NuGet provider: $_"
        Exit 1
    }
}



# ================== CREATE TEMPORARY MAX PERFORMANCE POWER PLAN ==================
Log "Creating temporary Maximum Performance power plan..."
try {
    $baseScheme = (powercfg -list | Where-Object { $_ -match "High performance" } | ForEach-Object { ($_ -split '\s+')[3] })
    if ($null -eq $baseScheme) {
        Log "High Performance power plan not found. Skipping power plan changes."
    } else {
        $guid = (powercfg -duplicatescheme $baseScheme).Trim()
        powercfg -changename $guid $PowerPlanName "Temporary Maximum Performance"
        powercfg -setactive $guid
        Log "Temporary Maximum Performance power plan activated."
    }
} catch {
    Log "Failed to create or set temporary power plan: $_"
}

# ================== FUNCTION: CHECK IF OFFICE IS INSTALLED ==================
function Confirm-OfficeInstalled {
    $officePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Office",
        "${env:ProgramFiles}\Microsoft Office",
        "${env:ProgramW6432}\Microsoft Office"
    )
    foreach ($path in $officePaths) {
        if (Test-Path $path) {
            return $true
        }
    }
    return $false
}

# ================== DOWNLOAD SCRIPT FUNCTION ==================
function Get-Script {
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
        Invoke-WebRequest -Uri $url -OutFile $scriptPath -UseBasicParsing | Out-Null
        Log "$ScriptName downloaded successfully."
    } catch {
        Log "Failed to download ${ScriptName}: $_"
        Exit 1
    }
}

# ================== RUN SCRIPT FUNCTION ==================
function Invoke-Script {
    param (
        [string]$ScriptName
    )
    $scriptPath = Join-Path $ScriptDir $ScriptName
    Log "Running $ScriptName..."
    try {
        if ($VerboseMode) {
            & $scriptPath -VerboseMode:$true -LogFile $LogFile
        } else {
            & $scriptPath -VerboseMode:$false -LogFile $LogFile *>&1 | Out-Null
        }
        Log "$ScriptName executed successfully."
    } catch {
        Log "Error during execution of ${ScriptName}: $_"
        Exit 1
    }
}
# ================== TASK SELECTION ==================
switch ($task) {
    "1" {
        Log "Task selected: Machine Preparation (semi-automated)"
        Log "Downloading necessary scripts..."
        Get-Script -ScriptName "MACHINEPREP.ps1"
        Get-Script -ScriptName "WU.ps1"
        Get-Script -ScriptName "WGET.ps1"
        if (Confirm-OfficeInstalled) {
            Get-Script -ScriptName "MSO_UPDATE.ps1"
        } else {
            Log "Microsoft Office not detected. Skipping Office update script download."
        }
        Invoke-Script -ScriptName "MACHINEPREP.ps1"
    }
    "2" {
        Log "Task selected: Windows Maintenance"
        Get-Script -ScriptName "WU.ps1"
        Invoke-Script -ScriptName "WU.ps1"
        Get-Script -ScriptName "WGET.ps1"
        Invoke-Script -ScriptName "WGET.ps1"
        if (Confirm-OfficeInstalled) {
            Get-Script -ScriptName "MSO_UPDATE.ps1"
            Invoke-Script -ScriptName "MSO_UPDATE.ps1"
        } else {
            Log "Microsoft Office not detected. Skipping Office update."
        }
    }
    default {
        Log "Invalid task selection. Exiting script."
        Exit 1
    }
}

# ================== RESET POWER PLAN TO BALANCED ==================
Log "Resetting power plan to Balanced..."
try {
    powercfg -restoredefaultschemes
    Log "Power plan schemes restored to default."
    powercfg -setactive SCHEME_BALANCED
    Log "Power plan reset to Balanced."
} catch {
    Log "Failed to reset power plan to Balanced: $_"
}
# ================== RESTORE PSGALLERY TRUST POLICY ==================
# This block handles restoring the PSGallery InstallationPolicy.
# Since the registration and trusting of PSGallery is now removed, this block
# will only attempt to set the policy if PSGallery happens to exist.
Log "Restoring PSGallery InstallationPolicy to Untrusted if it exists..."
try {
    # Check if PSGallery exists before attempting to set its policy.
    if (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted -ErrorAction SilentlyContinue
        Log "PSGallery InstallationPolicy reset to Untrusted."
    } else {
        Log "PSGallery repository not found, skipping InstallationPolicy reset." -Level "WARN"
    }
} catch {
    Log "Failed to reset PSGallery InstallationPolicy: $_" -Level "WARN"
}

# ================== RESTORE EXECUTION POLICY ==================
Log "Restoring Execution Policy..."
try {
    if ($OriginalPolicy -ne "Restricted") {
        Log "Original policy was $OriginalPolicy; resetting to Restricted as default."
        Set-ExecutionPolicy Restricted -Scope Process -Force -ErrorAction SilentlyContinue
        Log "Execution Policy set to Restricted."
    } else {
        Log "Original policy was Restricted; no change needed."
    }
} catch {
    Log "Failed to restore Execution Policy: $_"
}

# ================== SCRIPT COMPLETION ===================
Log "Script completed successfully."