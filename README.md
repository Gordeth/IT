# Windows Update Helper (WUH)

This project automates Windows maintenance tasks and profile preparation using PowerShell.

## 📂 Contents

- `WUH.ps1` — Main launcher script.
- `WU.ps1` — Windows Updates script.
- `WGET.ps1` — Additional maintenance script.
- `MSO_UPDATE.ps1` — Office update script.
- `UserProfilePrep.ps1` — (Coming soon) New user profile preparation script.

## 🚀 Features

- **User Mode Selection:**
  - Silent Mode (logs only)
  - Verbose Mode (logs + console output)
- **Task Selection:**
  - User Profile Preparation
  - Windows Maintenance (runs Windows Updates, WGET, and MSO_UPDATE)

## 🛠️ Usage

1. Open PowerShell as Administrator.
2. Run the main script:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/WUH.ps1" -OutFile "$env:TEMP\WUH.ps1"
   & "$env:TEMP\WUH.ps1"
