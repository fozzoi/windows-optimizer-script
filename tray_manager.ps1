Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$loopPath = Join-Path $scriptDir "clear_ram_loop.ps1"
$configFile = Join-Path $scriptDir "config.json"

function Get-Config {
    if (Test-Path $configFile) {
        try {
            return (Get-Content $configFile -Raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

function Save-Config {
    param($cfg)
    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

# ----------------- SINGLE INSTANCE CHECK & CLEANUP -----------------
# Kill any existing tray managers or optimizer loops before starting this instance
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
        $_.ProcessId -ne $PID -and (
            $_.CommandLine -like "*tray_manager.ps1*" -or 
            $_.CommandLine -like "*clear_ram_loop.ps1*"
        )
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
} catch {}

# Start the powershell loop invisibly
$procInfo = New-Object System.Diagnostics.ProcessStartInfo
$procInfo.FileName = "powershell.exe"
$procInfo.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$loopPath`""
$procInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$procInfo.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($procInfo)

# Create the System Tray Icon
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$notifyIcon.Text = "Windows Optimizer (Active)"
$notifyIcon.Visible = $true

# Context Menu Items
$contextMenu = New-Object System.Windows.Forms.ContextMenu

$statusMenuItem = New-Object System.Windows.Forms.MenuItem
$statusMenuItem.Text = "Status: Active (Boosting)"
$statusMenuItem.Enabled = $false
$contextMenu.MenuItems.Add($statusMenuItem) | Out-Null

$togglePauseItem = New-Object System.Windows.Forms.MenuItem
$togglePauseItem.Text = "⏸️ Pause / Temporary Revert"
$contextMenu.MenuItems.Add($togglePauseItem) | Out-Null

# Clean RAM Now
$cleanMenuItem = New-Object System.Windows.Forms.MenuItem
$cleanMenuItem.Text = "🧹 Clean RAM Now"
$cleanMenuItem.add_Click({
    $ramMap = Join-Path $scriptDir "RAMMap64.exe"
    # Trim Working Sets
    Get-Process | Where-Object { $_.Id -ne $PID -and $_.ProcessName -notmatch 'InputApp|TextInputHost' } | ForEach-Object {
        try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
    }
    # Clear Standby List
    if (Test-Path $ramMap) {
        Start-Process -FilePath $ramMap -ArgumentList "-Et" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Es" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Em" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Ew" -Wait -WindowStyle Hidden
    }
    $notifyIcon.ShowBalloonTip(3000, "RAM Cleaned", "Standby list and process memory trimmed successfully!", [System.Windows.Forms.ToolTipIcon]::Info)
})
$contextMenu.MenuItems.Add($cleanMenuItem) | Out-Null

# Open Hub
$openUiMenuItem = New-Object System.Windows.Forms.MenuItem
$openUiMenuItem.Text = "⚙️ Open Optimizer Hub"
$openUiMenuItem.add_Click({
    $uiPath = Join-Path $scriptDir "Run-UI.ps1"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uiPath`"" -WindowStyle Hidden
})
$contextMenu.MenuItems.Add($openUiMenuItem) | Out-Null

# Separator
$sep1 = New-Object System.Windows.Forms.MenuItem("-")
$contextMenu.MenuItems.Add($sep1) | Out-Null

# Revert Everything
$revertMenuItem = New-Object System.Windows.Forms.MenuItem
$revertMenuItem.Text = "↩️ Stop & Revert Everything"
$revertMenuItem.add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    
    $revertPath = Join-Path $scriptDir "revert.ps1"
    if (Test-Path $revertPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$revertPath`"" -WindowStyle Hidden
    }
    
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.MenuItems.Add($revertMenuItem) | Out-Null

# Stop / Turn Off and Exit
$exitMenuItem = New-Object System.Windows.Forms.MenuItem
$exitMenuItem.Text = "⏹️ Turn Off Booster & Exit"
$exitMenuItem.add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    
    # Kill the background loop process
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
            $_.CommandLine -like "*clear_ram_loop.ps1*" 
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.MenuItems.Add($exitMenuItem) | Out-Null

$notifyIcon.ContextMenu = $contextMenu

# Double click opens UI
$notifyIcon.add_DoubleClick({
    $uiPath = Join-Path $scriptDir "Run-UI.ps1"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uiPath`"" -WindowStyle Hidden
})

function Update-TrayState {
    param([bool]$isPaused)
    if ($isPaused) {
        $statusMenuItem.Text = "Status: Paused (Temporarily Reverted)"
        $togglePauseItem.Text = "▶️ Resume Optimizer"
        $notifyIcon.Text = "Windows Optimizer (Paused)"
    } else {
        $statusMenuItem.Text = "Status: Active (Boosting)"
        $togglePauseItem.Text = "⏸️ Pause / Temporary Revert"
        $notifyIcon.Text = "Windows Optimizer (Active)"
    }
}

# Temporary Revert Action
function Invoke-TempRevert {
    # Restore transparency & blur
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
    # Restore animations
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
    # Restore key services
    @( "SysMain", "DiagTrack", "Spooler", "WSearch" ) | ForEach-Object {
        try {
            $s = Get-Service -Name $_ -ErrorAction SilentlyContinue
            if ($s) {
                Set-Service -Name $_ -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $_ -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

$togglePauseItem.add_Click({
    $cfg = Get-Config
    if ($cfg) {
        $currentlyPaused = ($cfg.BoosterPaused -eq $true)
        $newPaused = -not $currentlyPaused
        $cfg.BoosterPaused = $newPaused
        Save-Config $cfg
        Update-TrayState $newPaused

        if ($newPaused) {
            Invoke-TempRevert
            $notifyIcon.ShowBalloonTip(3000, "Optimizer Paused", "Booster paused! Visuals and services temporarily restored.", [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            $notifyIcon.ShowBalloonTip(3000, "Optimizer Resumed", "System optimizations active and monitoring.", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
})

# Initial sync
$initialCfg = Get-Config
if ($initialCfg) {
    Update-TrayState ($initialCfg.BoosterPaused -eq $true)
}

# Sync timer to listen to changes from UI
$syncTimer = New-Object System.Windows.Forms.Timer
$syncTimer.Interval = 3000
$syncTimer.add_Tick({
    $cfg = Get-Config
    if ($cfg) {
        $p = ($cfg.BoosterPaused -eq $true)
        if (($p -and $statusMenuItem.Text -like "*Active*") -or (-not $p -and $statusMenuItem.Text -like "*Paused*")) {
            Update-TrayState $p
        }
    }
})
$syncTimer.Start()

# Keep the GUI message loop running
[System.Windows.Forms.Application]::Run()
