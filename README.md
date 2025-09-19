# IT Automation Project

This is a **PowerShell project** designed to automate common system maintenance and preparation tasks for Windows environments. It is built with a focus on robustness, modularity, and maintainability, making it a reliable tool for IT professionals.

⚠️ **Important:** Do not run the included scripts individually. Always launch the project via the bootstrapper, which ensures correct setup and execution.

### ✨ Features

*   **⚙️ Robust & Modular Design:** Built with a focus on clean, maintainable code. Features a central orchestrator, shared functions, consistent logging, and error handling to ensure reliable execution.
*   **🪟 Windows Updates:** Automates the Windows Update process, including the intelligent creation of a System Restore Point only when major (non-security) updates are found.
*   **📦 Software Management:** Installs baseline software (TeamViewer, Chrome, etc.) and updates all existing applications using Winget. Manages Chocolatey for packages not available on Winget.
*   **🔩 Driver & Firmware:** Auto-detects the machine's brand (Dell, HP, Lenovo) and installs the corresponding driver update utility. It also detects internal disk brands (Samsung, Crucial, WD, etc.) and installs their management software for firmware updates and optimization.
*   **⚕️ System Health:** Runs System File Checker (SFC) to ensure system integrity.
*   **🧹 System Cleanup:** Clears system and user temporary files and empties the Recycle Bin to free up disk space. This task is available individually and is also integrated into the main maintenance bundles.
*   **⚡ Performance Optimization:** Creates and activates a temporary "Maximum Performance" power plan during execution to speed up tasks, then safely removes it and restores the original plan.
*   **🌐 UniFi Server Management:** Installs or upgrades the UniFi Network Server and its Java dependency.
*   **📝 Ephemeral Logging:** Creates detailed, task-specific log files during execution inside a temporary folder (`%TEMP%\IAP\src\Log`). **Note:** This folder is automatically deleted by the bootstrapper upon script completion.

---

## 🖥️ How It Works

The `bootstrapper.ps1` script is the main entry point. It downloads the latest version of the project from GitHub into a temporary directory, ensures dependencies are configured, and then starts the maintenance workflow you select.

### Typical Workflow

When you launch the bootstrapper, you'll be prompted to select a mode and a task.

**Mode Selection:**
* **Silent Mode:** All logs are saved to a file without displaying console output.
* **Verbose Mode:** Logs are shown in the console and are also saved to a file.

**Task Selection:**
* **Machine Preparation (semi-automated):** A comprehensive task for new or repurposed machines. It installs brand-specific driver/disk utilities, baseline IT software (TeamViewer, Chrome, etc.), and then runs all maintenance tasks: Windows Update, Winget cleanup, Office updates, and System File Checker.
* **Windows Maintenance:** This option runs the core maintenance tasks, including Windows Update, Winget cleanup, Office updates, and System File Checker.
* **Install/Upgrade UniFi Server:** A dedicated task to download, install, or upgrade the UniFi Network Server, including its Java dependency and firewall rules.

---

## 📂 Project Structure

| File | Purpose |
|---|---|
| `bootstrapper.ps1` | Main Entry Point. Downloads and runs the core scripts. **Use this one!** |
| `src\TO.ps1` | The core script that orchestrates all maintenance tasks. |
| `modules\Functions.ps1` | Contains shared, reusable helper functions for logging, package management (NuGet, Chocolatey), power plan management, and file downloads, promoting a modular and DRY (Don't Repeat Yourself) design. |
| `src\MACHINEPREP.ps1` | Contains tasks specifically for the "Machine Preparation" option. |
| `src/WUA.ps1` | Handles the Windows Update routine, including conditional System Restore Point creation. |
| `src\WUA.ps1` | Handles the Windows Update routine, including conditional System Restore Point creation. |
| `src\WGET.ps1` | Handles the Winget update and cleanup routine. |
| `src\MSO_UPDATE.ps1` | An optional routine for updating Microsoft Office (Click-to-Run). |
| `src\IUS.ps1` | Handles the installation and upgrade of the UniFi Network Server. |
| `src\CLEANUP.ps1` | Handles system cleanup tasks like clearing temporary files and emptying the Recycle Bin. |

---

🛠️ **Usage**  
Open PowerShell as Administrator.  
Run the main script:  

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/bootstrapper.ps1" -OutFile "$env:TEMP\bootstrapper.ps1"; & "$env:TEMP\bootstrapper.ps1"; Remove-Item -Path "$env:TEMP\bootstrapper.ps1" -Force
```
License

This project is licensed under the [MIT License](LICENSE).