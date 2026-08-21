# ⚡ Windows RAM & Performance Optimizer Hub (v2.0)

> ⚠️ **Use at your own risk. For educational and performance enhancement purposes.**

A modern, lightweight Windows optimization suite with a dark-themed WPF Graphical Interface, real-time memory telemetry, instant RAM trimming, customizable background app terminating, and Windows debloating.

Ideal for **gaming rigs**, **low-end PCs**, and **older laptops** looking for maximum responsiveness.

---

## 🌟 Key Features

* 📊 **Live Resource Monitor:** Real-time RAM and CPU progress meters on the dashboard.
* 🧹 **Instant "Clean RAM Now":** One-click working set trimming and Sysinternals RAMMap standby memory flushing (available in UI and System Tray).
* 🚫 **Customizable Process Termination:**
  * Curated list of safe-to-kill background apps (OneDrive, Teams, OEM bloatware, etc.).
  * **Active Task Scanner:** Scan currently running high-memory tasks and add them to your kill list.
  * **Custom Process Manager:** Add any `.exe` by name with instant removal support.
* ⚡ **OS & Visual Performance Tweaks:**
  * Disable transparency and acrylic blur effects.
  * Disable window minimize/maximize animation latency.
  * Turn off Bing web search in Start Menu.
  * Disable Xbox Game Bar background DVR recording.
  * Toggle SysMain (Superfetch), Diagnostics Telemetry, and Print Spooler.
  * Unlock & activate the **Ultimate Performance Power Plan**.
* 🗑️ **UWP Bloatware Uninstaller:** One-click safe removal of pre-installed Windows packages (*Xbox Apps, Solitaire, Bing News/Weather, Clipchamp, Feedback Hub, Skype, etc.*).
* 🛡️ **Single-Instance System Tray Engine:** Runs silently in the taskbar with right-click quick actions and auto-flushes ghost icons on exit.
* ↩️ **Safe 1-Click Revert:** Completely restore all Windows services, visual effects, and registry settings to default with `revert.ps1` or `revert.bat`.

---

## 🚀 Quick Start

1. **Download / Clone** this repository to a folder on your PC.
2. **Double-click [`Run.bat`](Run.bat)**.
3. When prompted, click **Yes** to allow Administrator privileges.
4. The **Windows Optimizer Hub** window will launch!

---

## 📁 Project Structure

```
.
├── Run.bat              # Main launcher (Auto-elevates & opens GUI)
├── Run-UI.ps1           # Modern WPF Dark Theme Dashboard & Settings Hub
├── clear_ram_loop.ps1   # Core dynamic background optimizer engine
├── config.json          # User preferences (Apps, Tweaks, UWP debloat list)
├── tray_manager.ps1     # System tray controller & single-instance manager
├── revert.bat           # 1-Click revert batch launcher
├── revert.ps1           # Revert engine (Restores services, visuals & power plan)
├── RAMMap64.exe         # Microsoft Sysinternals memory clearing tool
├── WindowsOptimizer.exe # Lightweight background process host
├── LICENSE              # MIT License
└── README.md            # Documentation
```

---

## ↩️ How to Revert Changes

You can restore your default Windows settings, visual effects, and services at any time:
* Click **↩️ Revert Changes** on the Dashboard in `Run.bat`.
* Or right-click the system tray icon and choose **"Stop & Revert Everything"**.
* Or double-click **`revert.bat`**.

---

## 📜 License

[MIT License](LICENSE)