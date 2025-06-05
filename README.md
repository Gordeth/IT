# Windows Update Helper (WUH)

This project automates Windows maintenance tasks and profile preparation using PowerShell.

**Note:** Not recommended for production environments.

---

📂 **Contents**  
- **WUH.ps1** — Main launcher script.  
- **WU.ps1** — Windows Updates script.  
- **WGET.ps1** — Additional maintenance script.  
- **MSO_UPDATE.ps1** — Office update script.  
- **MACHINEPREP.ps1** — New machine preparation script.  

---

🚀 **Features**  
✅ Verbose and Silent modes (console output and logging)  
✅ Task selection:  
  - [1] Machine Preparation (installs default apps, TeamViewer Host, and optional OpenVPN Connect)  
  - [2] Windows Maintenance (runs Windows Update, downloads updates, and Office updates)  
✅ Temporary Maximum Performance power plan during maintenance for optimal performance, automatically reset to Balanced after completion  
✅ NuGet and PSGallery setup to ensure package installations work smoothly  
✅ Automatic cleanup: downloaded scripts removed after execution

🖥️ Machine Preparation Script (MACHINEPREP.ps1)

Checks and installs TeamViewer Host
Installs default apps (7-Zip, Google Chrome, Adobe Acrobat Reader 64-bit)
Prompts the user to optionally install OpenVPN Connect
(Coming Soon): Detects the machine brand and installs the appropriate driver update app (e.g., Lenovo Vantage, HP Support Assistant, Dell Command Update).
---

🛠️ **Usage**  
Open PowerShell as Administrator.  
Run the main script:  

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Gordeth/IT/main/WUH.ps1" -OutFile "$env:TEMP\WUH.ps1"; & $env:TEMP\WUH.ps1
```
License

This project is licensed under the [MIT License](LICENSE).
