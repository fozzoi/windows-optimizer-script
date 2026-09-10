# ⚡ Windows RAM & Performance Optimizer Hub (v2.1)

> ⚠️ **Use at your own risk. For educational and performance enhancement purposes.**

A modern, lightweight Windows optimization suite with a sleek Windows 11 Fluent dark-themed WPF Graphical Interface, real-time memory telemetry, instant RAM trimming, temporary pause/revert controls, customizable background app terminating, and Windows debloating.

Ideal for **gaming rigs**, **low-end PCs**, and **workstations** looking for maximum responsiveness without sacrificing visual aesthetics.

---

## 🌟 Key Features

* 📊 **Live Resource Monitor:** Real-time RAM and CPU progress meters with smooth asynchronous polling.
* ⏸️ **Temporary Pause & Revert:**
  * **System Tray & UI Toggle:** Pause background boosting with a single click (`⏸️ Pause / Temporary Revert` ↔ `▶️ Resume`).
  * While paused, visual effects (blur, transparency, animations) and services are temporarily restored without wiping your configuration.
  * Stop / Turn Off button cleans up background loops without touching your persistent settings.
* 💎 **Full Blur & Visual Control (User Preference First):**
  * Keep Windows 11 Fluent blur, acrylic, and transparency enabled or turn them off for extra FPS.
  * Two-way symmetrical control: unchecking a tweak actively restores normal Windows defaults rather than leaving it stuck.
* 🖱️ **Windows 10 Classic Context Menu Toggle:**
  * One-click toggle to restore the classic Windows 10 right-click context menu on Windows 11.
  * Includes a convenient **"🔄 Reload Explorer"** action to apply shell changes instantly.
* 🧹 **Instant "Clean RAM Now":** One-click working set trimming and Sysinternals RAMMap standby memory flushing (available in UI and System Tray).
* 🚫 **Customizable Process Termination:**
  * Curated list of safe-to-kill background apps (OneDrive, Teams, OEM bloatware, etc.).
  * **Master Auto-Kill Toggle:** Turn background app termination on or off with a switch.
  * **Active Task Scanner:** Scan currently running high-memory tasks and add them to your kill list.
  * **Custom Process Manager:** Add any `.exe` by name with instant removal support.
* ⚡ **Granular OS & Visual Performance Tweaks:**
  * Toggle transparency & acrylic blur effects (defaults to preserving blur!).
  * Disable window minimize/maximize animation latency.
  * Restore Windows 10 classic right-click context menu.
  * Turn off Bing web search in Start Menu.
  * Disable Xbox Game Bar background DVR recording.
  * Toggle SysMain (Superfetch), Diagnostics Telemetry, Windows Search Indexer, and Print Spooler.
  * Unlock & activate the **Ultimate Performance Power Plan**.
* 🗑️ **UWP Bloatware Uninstaller:** One-click safe removal of pre-installed Windows packages (*Xbox Apps, Solitaire, Bing News/Weather, Clipchamp, Feedback Hub, Skype, etc.*).
* 🛡️ **Single-Instance System Tray Engine:** Runs silently in the taskbar with real-time state synchronization, balloon notifications, and auto-flushes ghost icons on exit.
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

## ↩️ How to Pause or Revert Changes

* **To Temporarily Pause & Revert:**
  * Click **"⏸️ Pause (Temp Revert)"** in the top header or Dashboard in `Run.bat`.
  * Or right-click the system tray icon and choose **"⏸️ Pause / Temporary Revert"**.
  * Visuals and services will immediately restore while the optimizer is paused.
* **To Permanently Revert Everything:**
  * Click **↩️ Full Revert** on the Dashboard in `Run.bat`.
  * Or right-click the system tray icon and choose **"Stop & Revert Everything"**.
  * Or double-click **`revert.bat`**.

---

## 📜 License

[MIT License](LICENSE)