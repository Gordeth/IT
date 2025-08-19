# Genesis Apex

Genesis Apex is a **PowerShell project** designed to automate common system maintenance and preparation tasks for Windows environments. It is intended for IT automation, device preparation, and routine maintenance, all from a single entry point.

⚠️ **Important:** Do not run the included scripts individually. Always launch WUH via the bootstrapper, which ensures correct setup and execution.

### ✨ Features

* **💽 Disk Utility:** Auto-detects and runs disk utility software like Samsung Magician or Kingston SSD Manager.
* **🛠️ System Health:** Runs System File Checker (SFC) and analyzes the CBS.log file.
* **⚡ Performance:** Temporarily sets the power plan to "Maximum Performance" and restores it after the run is complete.
* **📦 Software Management:** Sets up NuGet and PSGallery with trust handling, and handles software installation and cleanup via Chocolatey and Winget.
* **📝 Logging:** Creates a detailed log file located at `%TEMP%\ITScripts\Log\WUH.txt`.

---

## 🖥️ How It Works

The `bootstrapper.ps1` script is the main entry point. It downloads the latest `WUH.ps1` and other required scripts from GitHub. It also ensures that dependencies are configured and then starts the maintenance workflow you select.

### Typical Workflow

When you launch the bootstrapper, you'll be prompted to select a mode and a task.

**Mode Selection:**
* **Silent Mode:** All logs are saved to a file without displaying console output.
* **Verbose Mode:** Logs are shown in the console and are also saved to a file.

**Task Selection:**
* **Machine Preparation (semi-automated):** This option downloads and runs vendor driver tools, installs baseline IT software via Chocolatey/Winget, and then runs all the maintenance tasks, including Windows Update, Winget cleanup, Office updates, and System File Checker.
* **Windows Maintenance:** This option runs the core maintenance tasks, including Windows Update, Winget cleanup, Office updates, and System File Checker.

---

## 📂 Project Structure

| File | Purpose |
|---|---|
| `bootstrapper.ps1` | Main Entry Point. Downloads and runs the core scripts. **Use this one!** |
| `WUH.ps1` | The core script that orchestrates all maintenance tasks. |
| `Functions.ps1` | Contains shared helper functions for logging, script execution, and Office detection. |
| `MACHINEPREP.ps1` | Contains tasks specifically for the "Machine Preparation" option. |
| `WGET.ps1` | Handles the Winget update and cleanup routine. |
| `MSO_UPDATE.ps1` | An optional routine for updating Microsoft Office. |

---

🛠️ **Usage**  
Open PowerShell as Administrator.  
Run the main script:  

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force;Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/bootstrapper.ps1" -OutFile "$env:TEMP\bootstrapper.ps1";& $env:TEMP\bootstrapper.ps1
```
License

This project is licensed under the [MIT License](LICENSE).
