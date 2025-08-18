# Windows Update Helper (WUH)

Windows Update Helper (WUH)This PowerShell project automates common system maintenance and preparation tasks for Windows environments.
It is designed for IT automation, device preparation, and routine maintenance with one single entry point.

⚠️ Note: Do not run the included scripts individually. Always launch via the bootstrapper, which ensures correct setup and execution.
✨ Features
💽 Disk utility auto-detection (Samsung Magician, Kingston SSD Manager, etc.)
🛠️ System File Checker (SFC) with CBS.log analysis
🔄 Temporary max-performance power plan (restored after run)
☁️ NuGet + PSGallery setup with trust handling
📦 Chocolatey / Winget software installation & cleanup
📝 Detailed logging (stored in %TEMP%\ITScripts\Log\WUH.txt)

📂 Project Structure
File	Purpose
bootstrapper.ps1	Main entry point. Downloads and runs the latest WUH.ps1.
WUH.ps1	Core maintenance script orchestrating all tasks.
Functions.ps1	Shared helper functions (logging, script execution, Office detection).
MACHINEPREP.ps1	Machine preparation tasks (driver tools, baseline IT setup).
WGET.ps1	Winget update/cleanup routine.
MSO_UPDATE.ps1	Optional Microsoft Office update routine.

The bootstrapper:

Downloads the latest WUH.ps1 and required helper scripts from GitHub.
Ensures dependencies (NuGet, PSGallery trust, etc.) are configured.
Starts the maintenance workflow (Machine Preparation or Windows Maintenance).
You always run the bootstrapper, never the other scripts directly.
🖥️ Typical Workflow
When you launch the bootstrapper, the following happens:
Mode Selection
Silent Mode → Logs everything, no console noise.
Verbose Mode → Shows logs in console and saves to file.

Task Selection

[1] Machine Preparation (semi-automated)
Downloads and runs vendor driver tools (Samsung Magician, Kingston SSD Manager, etc.)
Installs baseline IT software via Chocolatey/Winget
Runs Windows Update helper (WU.ps1)
Runs Winget update/cleanup (WGET.ps1)
Runs Microsoft Office update if installed (MSO_UPDATE.ps1)
Runs System File Checker (Repair-SystemFiles)

[2] Windows Maintenance
Runs Windows Update helper (WU.ps1)
Runs Winget update/cleanup (WGET.ps1)
Runs Microsoft Office update if installed (MSO_UPDATE.ps1)
Runs System File Checker (Repair-SystemFiles)
System Tweaks During Run
Temporarily switches to Maximum Performance power plan
Ensures PSGallery is trusted and NuGet provider is installed
Sets Execution Policy to Bypass for the session
Cleanup After Completion
Restores the default Balanced power plan
Removes the temporary power plan created
Resets PSGallery trust to Untrusted
Restores original Execution Policy

---

🛠️ **Usage**  
Open PowerShell as Administrator.  
Run the main script:  

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force;Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/bootstrapper.ps1" -OutFile "$env:TEMP\bootstrapper.ps1";& $env:TEMP\bootstrapper.ps1
```
License

This project is licensed under the [MIT License](LICENSE).
