Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$loopPath = Join-Path $scriptDir "clear_ram_loop.ps1"

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
$notifyIcon.Text = "Windows RAM Optimizer (Active)"
$notifyIcon.Visible = $true

# Create Right-Click Context Menu
$contextMenu = New-Object System.Windows.Forms.ContextMenu

$statusMenuItem = New-Object System.Windows.Forms.MenuItem
$statusMenuItem.Text = "Status: Running"
$statusMenuItem.Enabled = $false
$contextMenu.MenuItems.Add($statusMenuItem)

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
$contextMenu.MenuItems.Add($cleanMenuItem)

# Open Hub
$openUiMenuItem = New-Object System.Windows.Forms.MenuItem
$openUiMenuItem.Text = "⚙️ Open Optimizer Hub"
$openUiMenuItem.add_Click({
    $uiPath = Join-Path $scriptDir "Run-UI.ps1"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uiPath`"" -WindowStyle Hidden
})
$contextMenu.MenuItems.Add($openUiMenuItem)

# Revert Everything
$revertMenuItem = New-Object System.Windows.Forms.MenuItem
$revertMenuItem.Text = "Stop && Revert Everything"
$revertMenuItem.add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    
    # Run the revert script
    $revertPath = Join-Path $scriptDir "revert.ps1"
    if (Test-Path $revertPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$revertPath`"" -WindowStyle Hidden
    }
    
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.MenuItems.Add($revertMenuItem)

# Stop and Exit
$exitMenuItem = New-Object System.Windows.Forms.MenuItem
$exitMenuItem.Text = "Stop Optimizer && Exit"
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
$contextMenu.MenuItems.Add($exitMenuItem)

$notifyIcon.ContextMenu = $contextMenu

# Keep the GUI running
[System.Windows.Forms.Application]::Run()
