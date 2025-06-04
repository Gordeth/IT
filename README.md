# Windows Update Helper (WUH)

This project automates Windows maintenance tasks and profile preparation using PowerShell.

Note: Not recommended for production enviroments.

## 📂 Contents

- `WUH.ps1` — Main launcher script.
- `WU.ps1` — Windows Updates script.
- `WGET.ps1` — Additional maintenance script.
- `MSO_UPDATE.ps1` — Office update script.
- `UserProfilePrep.ps1` — (Coming soon) New user profile preparation script.

## 🚀 Features

✅ **Verbose and Silent modes** (console output and logging)  
✅ **Task selection**:  
- [1] Machine Preparation (installs TeamViewer Host)
- [2] Windows Maintenance (runs Windows Update, downloads updates, and Office updates)  
✅ **Temporary Maximum Performance power plan** during maintenance for optimal performance, automatically reset to Balanced after completion.  
✅ **NuGet and PSGallery setup** to ensure package installations work smoothly.  
✅ **Automatic cleanup**: downloaded scripts removed after execution.

## 🛠️ Usage

1. Open PowerShell as Administrator.
2. Run the main script:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/WUH.ps1" -OutFile "$env:TEMP\WUH.ps1"
   & "$env:TEMP\WUH.ps1"
