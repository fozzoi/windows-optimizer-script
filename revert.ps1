# Revert Windows Optimizer Changes Safely

function Refresh-SystemTray {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class TrayRefresher {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);

        [DllImport("user32.dll")]
        public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public static void Refresh() {
            try {
                IntPtr trayWnd = FindWindow("Shell_TrayWnd", null);
                if (trayWnd != IntPtr.Zero) {
                    IntPtr trayNotify = FindWindowEx(trayWnd, IntPtr.Zero, "TrayNotifyWnd", null);
                    if (trayNotify != IntPtr.Zero) {
                        IntPtr sysPager = FindWindowEx(trayNotify, IntPtr.Zero, "SysPager", null);
                        IntPtr target = sysPager != IntPtr.Zero ? sysPager : trayNotify;
                        IntPtr toolbar = FindWindowEx(target, IntPtr.Zero, "ToolbarWindow32", null);
                        if (toolbar != IntPtr.Zero) {
                            SendMouseMove(toolbar);
                        }
                    }
                }
                IntPtr overflowWnd = FindWindow("NotifyIconOverflowWindow", null);
                if (overflowWnd != IntPtr.Zero) {
                    IntPtr overflowToolbar = FindWindowEx(overflowWnd, IntPtr.Zero, "ToolbarWindow32", null);
                    if (overflowToolbar != IntPtr.Zero) {
                        SendMouseMove(overflowToolbar);
                    }
                }
            } catch {}
        }

        private static void SendMouseMove(IntPtr hWnd) {
            RECT rect;
            if (GetClientRect(hWnd, out rect)) {
                for (int x = 0; x < rect.Right; x += 6) {
                    for (int y = 0; y < rect.Bottom; y += 6) {
                        SendMessage(hWnd, 0x0200, IntPtr.Zero, (IntPtr)((y << 16) | (x & 0xffff)));
                    }
                }
            }
        }
    }
"@ -ErrorAction SilentlyContinue

    try {
        [TrayRefresher]::Refresh()
    } catch {}
}

function Restore-Service {
    param(
        [string]$Name,
        [string]$StartupType = "Automatic",
        [bool]$Start = $true
    )
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
            if ($Start) {
                Start-Service -Name $Name -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}

Write-Host "[*] Restoring Windows Services..." -ForegroundColor Cyan
Restore-Service "DiagTrack" "Automatic" $true
Restore-Service "dmwappushservice" "Automatic" $true
Restore-Service "WerSvc" "Manual" $false
Restore-Service "MapsBroker" "Automatic" $false
Restore-Service "SysMain" "Automatic" $true
Restore-Service "Spooler" "Automatic" $true
Restore-Service "WSearch" "Automatic" $true

# Manufacturer / OEM Services
$oemServices = @(
    "HpTouchpointAnalyticsService", "HPSysInfoCap", "HPOmenCap", 
    "HPNetworkCap", "HPDiagsCap", "HPAppHelperCap", "HP Comm Recover", 
    "PCManager Service Store"
)
foreach ($s in $oemServices) {
    Restore-Service $s "Manual" $false
}

Write-Host "[*] Restoring Visuals, Search & Registry Settings..." -ForegroundColor Cyan
# Transparency & Blur
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

# Animations
New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

# Windows 10 Classic Context Menu (Remove override to return to Windows 11 default)
$parentClsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
if (Test-Path $parentClsid) {
    Remove-Item -Path $parentClsid -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
}

# Search Box Suggestions (Bing in Start)
Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Force -ErrorAction SilentlyContinue | Out-Null

# Game DVR
New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Force -ErrorAction SilentlyContinue | Out-Null

# Telemetry Policy
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "[*] Restoring Balanced Power Plan..." -ForegroundColor Cyan
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null

# Reset BoosterPaused flag in config.json if present
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDir "config.json"
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        $cfg.BoosterPaused = $false
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
    } catch {}
}

Write-Host "[*] Terminating Running Optimizer Processes..." -ForegroundColor Cyan
Get-Process -Name "WindowsOptimizer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
        $_.CommandLine -like "*clear_ram_loop.ps1*" -or $_.CommandLine -like "*tray_manager.ps1*" 
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
} catch {}

# Clear ghost tray icons
Refresh-SystemTray

Write-Host "[✓] All settings, services, and visuals restored successfully!" -ForegroundColor Green
