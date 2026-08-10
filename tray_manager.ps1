Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$batPath = Join-Path $scriptDir "clear_ram_loop.bat"

# Kill any existing loops before starting
Invoke-Expression 'taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Administrator:  Windows Optimizer Script" 2>$null'
Invoke-Expression 'taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Windows Optimizer Script" 2>$null'

# Start the batch file invisibly
$procInfo = New-Object System.Diagnostics.ProcessStartInfo
$procInfo.FileName = "cmd.exe"
$procInfo.Arguments = "/c `"$batPath`""
$procInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$procInfo.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($procInfo)

# Create the System Tray Icon
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
# Use a default system icon (e.g., Information or Shield)
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$notifyIcon.Text = "Windows RAM Optimizer"
$notifyIcon.Visible = $true

# Create Right-Click Context Menu
$contextMenu = New-Object System.Windows.Forms.ContextMenu

$statusMenuItem = New-Object System.Windows.Forms.MenuItem
$statusMenuItem.Text = "Status: Running"
$statusMenuItem.Enabled = $false
$contextMenu.MenuItems.Add($statusMenuItem)

$exitMenuItem = New-Object System.Windows.Forms.MenuItem
$exitMenuItem.Text = "Stop Optimizer && Exit"
$exitMenuItem.add_Click({
    $notifyIcon.Visible = $false
    # Kill the batch process
    Invoke-Expression 'taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Administrator:  Windows Optimizer Script" 2>$null'
    Invoke-Expression 'taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Windows Optimizer Script" 2>$null'
    
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.MenuItems.Add($exitMenuItem)

$notifyIcon.ContextMenu = $contextMenu

# Keep the GUI running
[System.Windows.Forms.Application]::Run()
