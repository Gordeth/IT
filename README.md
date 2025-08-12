# Windows Update Helper (WUH)

This PowerShell script suite automates common system maintenance and preparation tasks for Windows environments. It includes system file verification, driver tools, disk utility installation, and performance optimization — ideal for IT automation and device preparation.

## Features

- 💽 Disk utility auto-detection (Samsung, Kingston, etc.)
- 🛠️ System File Checker (SFC) with CBS.log analysis
- 🔄 Power plan management for max performance
- ☁️ NuGet + PSGallery setup with trust handling
- 📦 Chocolatey/Winget app installation
- 📝 Detailed logging (log file in temp folder)

## Included Scripts

| Script Name      | Description                                |
|------------------|--------------------------------------------|
| `WUH.ps1`        | Main entry point for maintenance tasks     |
| `MACHINEPREP.ps1`| Semi-automated machine prep (IT baseline)  |
| `WGET.ps1`       | Winget update and cleanup tool             |
| `MSO_UPDATE.ps1` | Optional script to update Microsoft Office |


---

🛠️ **Usage**  
Open PowerShell as Administrator.  
Run the main script:  

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/WUH.ps1" -OutFile "$env:TEMP\WUH.ps1"; & $env:TEMP\WUH.ps1
```
License

This project is licensed under the [MIT License](LICENSE).
