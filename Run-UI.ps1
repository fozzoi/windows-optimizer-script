Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDir "config.json"
$ramMap = Join-Path $scriptDir "RAMMap64.exe"

# Helper to force Windows Explorer to flush stale/ghost tray icons
function Refresh-SystemTray {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class TrayCleaner {
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
        [TrayCleaner]::Refresh()
    } catch {}
}

# Helper to load config
function Get-OptimizerConfig {
    if (Test-Path $configFile) {
        try {
            return (Get-Content $configFile -Raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

# Helper to save config
function Save-OptimizerConfig {
    param($cfg)
    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

# Helper to stop existing background optimizer processes and clear tray icon
function Stop-ExistingOptimizer {
    Get-Process -Name "WindowsOptimizer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
            $_.CommandLine -like "*tray_manager.ps1*" -or 
            $_.CommandLine -like "*clear_ram_loop.ps1*" 
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    
    # Immediately flush the system tray of any ghost icons
    Start-Sleep -Milliseconds 200
    Refresh-SystemTray
}

function Is-OptimizerRunning {
    $found = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
        $_.CommandLine -like "*tray_manager.ps1*" -or 
        $_.CommandLine -like "*clear_ram_loop.ps1*" 
    }
    return ($null -ne $found)
}

$config = Get-OptimizerConfig
if (-not $config) {
    [System.Windows.MessageBox]::Show("Failed to load config.json", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    exit
}

# XAML Definition
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="⚡ Windows Performance &amp; RAM Optimizer Hub" Height="640" Width="720" 
        Background="#181818" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" FontFamily="Segoe UI">
    <Window.Resources>
        <!-- TabItem Style -->
        <Style TargetType="TabItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" BorderBrush="#333333" BorderThickness="1,1,1,0" Background="#242424" Margin="2,0" CornerRadius="4,4,0,0">
                            <ContentPresenter x:Name="ContentSite" VerticalAlignment="Center" HorizontalAlignment="Center" ContentSource="Header" Margin="14,9"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#2D2D30" />
                                <Setter Property="Foreground" Value="#0078D7" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter Property="Foreground" Value="#999999" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- General Button Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#3E3E42"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#3E3E42"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="Margin" Value="0,6,0,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Progress Bar Style -->
        <Style TargetType="ProgressBar">
            <Setter Property="Height" Value="14"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#2A2A2A"/>
            <Setter Property="Foreground" Value="#0078D7"/>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <Border Background="#202020" Padding="16,14" BorderBrush="#2D2D30" BorderThickness="0,0,0,1">
            <Grid>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="⚡" FontSize="20" Margin="0,0,8,0" Foreground="#0078D7"/>
                    <TextBlock Text="Windows Performance Optimizer" FontSize="18" FontWeight="SemiBold" Foreground="#FFFFFF"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock Text="Engine: " Foreground="#888888" FontSize="12"/>
                    <TextBlock Name="EngineStatusText" Text="Stopped" Foreground="#E06C75" FontSize="12" FontWeight="Bold"/>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Tabs Section -->
        <TabControl Grid.Row="1" Background="#181818" BorderThickness="0" Margin="10,8,10,0">
            
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="📊 Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="16">
                        
                        <!-- Telemetry Card -->
                        <Border Background="#222222" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                            <StackPanel>
                                <TextBlock Text="Live System Telemetry" FontSize="15" FontWeight="SemiBold" Foreground="#FFFFFF" Margin="0,0,0,12"/>
                                
                                <!-- RAM Monitor -->
                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="Memory (RAM):" Foreground="#CCCCCC" Width="110"/>
                                    <ProgressBar Name="RamProgressBar" Grid.Column="1" Margin="8,0" Minimum="0" Maximum="100" Value="0"/>
                                    <TextBlock Name="RamStatusText" Grid.Column="2" Text="Reading..." Foreground="#0078D7" FontWeight="SemiBold" Width="160" TextAlignment="Right"/>
                                </Grid>
                                
                                <!-- CPU Monitor -->
                                <Grid Margin="0,0,0,4">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="CPU Load:" Foreground="#CCCCCC" Width="110"/>
                                    <ProgressBar Name="CpuProgressBar" Grid.Column="1" Margin="8,0" Minimum="0" Maximum="100" Value="0" Foreground="#107C41"/>
                                    <TextBlock Name="CpuStatusText" Grid.Column="2" Text="Reading..." Foreground="#107C41" FontWeight="SemiBold" Width="160" TextAlignment="Right"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Instant Action: Clean RAM -->
                        <Button Name="BtnCleanNow" Content="🧹 Clean RAM Now (Instant Trim + Flush)" Height="46" FontSize="14" FontWeight="SemiBold" Background="#0078D7" BorderBrush="#005A9E" Margin="0,0,0,14"/>

                        <!-- Background Loop Controls -->
                        <TextBlock Text="Background Optimizer Controls" FontSize="14" FontWeight="SemiBold" Foreground="#CCCCCC" Margin="0,4,0,8"/>
                        
                        <Grid Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button Name="BtnStartStartup" Grid.Column="0" Content="🚀 Start &amp; Run at Boot" Height="40" Margin="0,0,4,0"/>
                            <Button Name="BtnStartOnce" Grid.Column="1" Content="▶️ Start in Tray Once" Height="40" Margin="4,0,0,0"/>
                        </Grid>

                        <Button Name="BtnStopOptimizer" Content="⏹️ Stop Background Optimizer" Height="38" Background="#2E2E2E" Margin="0,0,0,8"/>
                        <Button Name="BtnRevert" Content="↩️ Revert Changes (Restore Services, Visuals &amp; Settings)" Height="40" Background="#3D1E1E" BorderBrush="#6B1D1D" Foreground="#FF9999"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <!-- TAB 2: APPS & SCANNER -->
            <TabItem Header="🚫 Kill Apps">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Add Custom Process Bar -->
                    <Border Grid.Row="0" Background="#222222" BorderBrush="#333333" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="TxtCustomProcess" Background="#181818" Foreground="#FFFFFF" BorderBrush="#444444" Padding="8,5" FontSize="13" Text="Type .exe process name (e.g. discord)"/>
                            <Button Name="BtnAddProcess" Grid.Column="1" Content="➕ Add to Kill List" Margin="8,0,0,0" Padding="12,5" Background="#107C41" BorderBrush="#0B5A2F"/>
                        </Grid>
                    </Border>

                    <!-- Active Scanner Bar -->
                    <Grid Grid.Row="1" Margin="0,0,0,10">
                        <Button Name="BtnScanActive" Content="🔍 Scan Active High-Memory Tasks" Background="#2A2D34" BorderBrush="#3D424E"/>
                    </Grid>

                    <!-- Apps Checklist -->
                    <Border Grid.Row="2" Background="#222222" BorderBrush="#333333" BorderThickness="1" CornerRadius="4" Padding="12">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="AppsPanel">
                                <TextBlock Text="Target Background Apps (Killed on cycle):" FontWeight="SemiBold" Foreground="#FFFFFF" Margin="0,0,0,8"/>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>
            
            <!-- TAB 3: OS & VISUAL TWEAKS -->
            <TabItem Header="⚡ OS &amp; Visual Tweaks">
                <Border Background="#222222" BorderBrush="#333333" BorderThickness="1" CornerRadius="4" Margin="16" Padding="14">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="TweaksPanel">
                            <TextBlock Text="Performance &amp; System Tweaks:" FontSize="15" FontWeight="SemiBold" Foreground="#FFFFFF" Margin="0,0,0,10"/>
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </TabItem>

            <!-- TAB 4: DEBLOAT UWP -->
            <TabItem Header="🗑️ Debloat Apps">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Text="Remove Pre-Installed Microsoft Bloatware:" FontSize="15" FontWeight="SemiBold" Foreground="#FFFFFF" Margin="0,0,0,8"/>
                    
                    <Border Grid.Row="1" Background="#222222" BorderBrush="#333333" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,0,10">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="UwpPanel">
                                <TextBlock Text="Select apps to completely uninstall for the current user:" Foreground="#888888" Margin="0,0,0,10"/>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>

                    <Button Name="BtnUninstallUwp" Grid.Row="2" Content="🗑️ Uninstall Selected Bloatware Apps" Height="42" FontSize="13" FontWeight="SemiBold" Background="#8A2B2B" BorderBrush="#6B1D1D"/>
                </Grid>
            </TabItem>
        </TabControl>
        
        <!-- Footer / Status Bar -->
        <Border Grid.Row="2" Background="#202020" Padding="14,10" BorderBrush="#2D2D30" BorderThickness="0,1,0,0">
            <Grid>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Name="StatusIcon" Text="●" Foreground="#107C41" Margin="0,0,6,0"/>
                    <TextBlock Name="StatusText" Text="Ready" Foreground="#AAAAAA" VerticalAlignment="Center" FontSize="12"/>
                </StackPanel>
                <Button Name="BtnSave" Content="💾 Save Settings" HorizontalAlignment="Right" Width="160" Background="#0078D7" BorderBrush="#005A9E" FontWeight="SemiBold"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Element References
$btnCleanNow = $window.FindName("BtnCleanNow")
$btnStartStartup = $window.FindName("BtnStartStartup")
$btnStartOnce = $window.FindName("BtnStartOnce")
$btnStopOptimizer = $window.FindName("BtnStopOptimizer")
$btnRevert = $window.FindName("BtnRevert")
$btnSave = $window.FindName("BtnSave")
$appsPanel = $window.FindName("AppsPanel")
$tweaksPanel = $window.FindName("TweaksPanel")
$uwpPanel = $window.FindName("UwpPanel")
$statusText = $window.FindName("StatusText")
$statusIcon = $window.FindName("StatusIcon")
$engineStatusText = $window.FindName("EngineStatusText")
$ramProgressBar = $window.FindName("RamProgressBar")
$ramStatusText = $window.FindName("RamStatusText")
$cpuProgressBar = $window.FindName("CpuProgressBar")
$cpuStatusText = $window.FindName("CpuStatusText")
$txtCustomProcess = $window.FindName("TxtCustomProcess")
$btnAddProcess = $window.FindName("BtnAddProcess")
$btnScanActive = $window.FindName("BtnScanActive")
$btnUninstallUwp = $window.FindName("BtnUninstallUwp")

# Focus handler for custom process textbox placeholder
$txtCustomProcess.Add_GotFocus({
    if ($txtCustomProcess.Text -eq "Type .exe process name (e.g. discord)") {
        $txtCustomProcess.Text = ""
    }
})

# App Checkboxes list
$appControls = @()

function Render-AppsList {
    $appsPanel.Children.Clear()
    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = "Target Background Apps (Killed on cycle):"
    $header.FontWeight = [System.Windows.FontWeights]::SemiBold
    $header.Foreground = [System.Windows.Media.Brushes]::White
    $header.Margin = "0,0,0,8"
    $appsPanel.Children.Add($header) | Out-Null

    $global:appControls = @()

    foreach ($app in $config.AppsToKill) {
        $row = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition
        $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition
        $col2.Width = [System.Windows.GridLength]::Auto
        $row.ColumnDefinitions.Add($col1)
        $row.ColumnDefinitions.Add($col2)

        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = "$($app.Name) ($($app.Process).exe)"
        $chk.IsChecked = $app.Enabled
        $chk.Tag = $app
        $chk.SetValue([System.Windows.Controls.Grid]::ColumnProperty, 0)
        $row.Children.Add($chk) | Out-Null

        if ($app.Custom -eq $true) {
            $delBtn = New-Object System.Windows.Controls.Button
            $delBtn.Content = "✖ Remove"
            $delBtn.FontSize = 11
            $delBtn.Padding = "6,2"
            $delBtn.Margin = "4,2"
            $delBtn.Tag = $app
            $delBtn.SetValue([System.Windows.Controls.Grid]::ColumnProperty, 1)
            $delBtn.Add_Click({
                param($s, $e)
                $target = $s.Tag
                $config.AppsToKill = @($config.AppsToKill | Where-Object { $_.Process -ne $target.Process })
                Render-AppsList
                $statusText.Text = "Removed custom app: $($target.Name)"
            })
            $row.Children.Add($delBtn) | Out-Null
        }

        $appsPanel.Children.Add($row) | Out-Null
        $global:appControls += $chk
    }
}

Render-AppsList

# Render OS Tweaks
$tweakControls = @()
$currentCategory = ""
foreach ($tweak in $config.OSTweaks) {
    if ($tweak.Category -and $tweak.Category -ne $currentCategory) {
        $currentCategory = $tweak.Category
        $catHeader = New-Object System.Windows.Controls.TextBlock
        $catHeader.Text = "[$($currentCategory.ToUpper())]"
        $catHeader.Foreground = [System.Windows.Media.Brushes]::Gray
        $catHeader.FontWeight = [System.Windows.FontWeights]::Bold
        $catHeader.FontSize = 11
        $catHeader.Margin = "0,8,0,2"
        $tweaksPanel.Children.Add($catHeader) | Out-Null
    }

    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $tweak.Name
    $chk.IsChecked = $tweak.Enabled
    $chk.Tag = $tweak
    $tweaksPanel.Children.Add($chk) | Out-Null
    $tweakControls += $chk
}

# Render UWP Bloatware List
$uwpControls = @()
foreach ($uwp in $config.UWPApps) {
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = "$($uwp.Name) - $($uwp.Description)"
    $chk.IsChecked = $false
    $chk.Tag = $uwp
    $uwpPanel.Children.Add($chk) | Out-Null
    $uwpControls += $chk
}

# ----------------- ACTIONS -----------------

# Save Settings
$btnSave.Add_Click({
    foreach ($chk in $appControls) {
        $chk.Tag.Enabled = ($chk.IsChecked -eq $true)
    }
    foreach ($chk in $tweakControls) {
        $chk.Tag.Enabled = ($chk.IsChecked -eq $true)
    }
    
    if (Save-OptimizerConfig $config) {
        $statusText.Text = "Settings saved successfully at $(Get-Date -Format 'HH:mm:ss')"
        $statusIcon.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
})

# Add Custom Process
$btnAddProcess.Add_Click({
    $pName = $txtCustomProcess.Text.Trim().Replace(".exe","")
    if ($pName -and $pName -ne "Type .exe process name (e.g. discord)") {
        $exists = $config.AppsToKill | Where-Object { $_.Process -eq $pName }
        if (-not $exists) {
            $newApp = [PSCustomObject]@{
                Name = $pName
                Process = $pName
                Enabled = $true
                Custom = $true
            }
            $config.AppsToKill += $newApp
            Render-AppsList
            $txtCustomProcess.Text = ""
            $statusText.Text = "Added $pName to kill list (Don't forget to click Save Settings!)"
        } else {
            $statusText.Text = "$pName is already in the list."
        }
    }
})

# Scan Active High-Memory Processes
$btnScanActive.Add_Click({
    $statusText.Text = "Scanning active memory-heavy processes..."
    $topProcesses = Get-Process | Where-Object { 
        $_.WorkingSet64 -gt 40MB -and 
        $_.ProcessName -notmatch 'System|Idle|explorer|powershell|WindowsOptimizer|svchost|csrss|services|dwm|lsass' 
    } | Sort-Object WorkingSet64 -Descending | Select-Object -First 10

    if ($topProcesses) {
        $msg = "Top Memory Consuming Background Apps:`n`n"
        foreach ($p in $topProcesses) {
            $memMb = [Math]::Round($p.WorkingSet64 / 1MB, 1)
            $msg += "• $($p.ProcessName).exe ($memMb MB)`n"
        }
        $msg += "`nWould you like to quickly add unlisted processes to your kill list?"
        $res = [System.Windows.MessageBox]::Show($msg, "Active Process Scanner", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            foreach ($p in $topProcesses) {
                $pName = $p.ProcessName
                $exists = $config.AppsToKill | Where-Object { $_.Process -eq $pName }
                if (-not $exists) {
                    $config.AppsToKill += [PSCustomObject]@{
                        Name = $pName
                        Process = $pName
                        Enabled = $false
                        Custom = $true
                    }
                }
            }
            Render-AppsList
            $statusText.Text = "Added scanned processes to list (Disabled by default). Check boxes and click Save!"
        }
    }
})

# Instant Clean RAM
$btnCleanNow.Add_Click({
    $statusText.Text = "Executing RAM cleanup & working set trim..."
    
    # Measure Before
    $osBefore = Get-CimInstance Win32_OperatingSystem
    $freeBeforeMb = $osBefore.FreePhysicalMemory / 1KB

    # Trim Working Sets
    Get-Process | Where-Object { $_.Id -ne $PID -and $_.ProcessName -notmatch 'InputApp|TextInputHost' } | ForEach-Object {
        try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
    }

    # RAMMap Standby Flush
    if (Test-Path $ramMap) {
        Start-Process -FilePath $ramMap -ArgumentList "-Et" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Es" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Em" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Ew" -Wait -WindowStyle Hidden
    }

    # Measure After
    Start-Sleep -Milliseconds 400
    $osAfter = Get-CimInstance Win32_OperatingSystem
    $freeAfterMb = $osAfter.FreePhysicalMemory / 1KB
    $freedMb = [Math]::Max(0, [Math]::Round($freeAfterMb - $freeBeforeMb, 1))

    $statusText.Text = "RAM Cleaned! Freed approx. $freedMb MB of memory."
    $statusIcon.Foreground = [System.Windows.Media.Brushes]::LightGreen
})

# Uninstall Selected UWP Bloatware
$btnUninstallUwp.Add_Click({
    $selected = $uwpControls | Where-Object { $_.IsChecked -eq $true }
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select at least one bloatware app to uninstall.", "No Selection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $confirm = [System.Windows.MessageBox]::Show("Are you sure you want to uninstall the $($selected.Count) selected apps?", "Confirm Debloat", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $statusText.Text = "Uninstalling selected UWP bloatware apps..."
    foreach ($item in $selected) {
        $pkgPattern = $item.Tag.Package
        $patterns = $pkgPattern.Split('|')
        foreach ($pattern in $patterns) {
            Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $pattern | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        }
        $item.IsChecked = $false
    }
    $statusText.Text = "Debloat operation completed!"
    [System.Windows.MessageBox]::Show("Selected UWP bloatware removed successfully!", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

# Start Optimizer & Add to Startup (Single Instance Enforced)
$btnStartStartup.Add_Click({
    Stop-ExistingOptimizer
    $exePath = Join-Path $scriptDir "WindowsOptimizer.exe"
    if (-not (Test-Path $exePath)) {
        Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $exePath -ErrorAction SilentlyContinue
    }
    $trayManager = Join-Path $scriptDir "tray_manager.ps1"
    $taskCmd = "schtasks /create /tn `"WindowsOptimizerLoop`" /tr `"\`"$exePath\`" -WindowStyle Hidden -ExecutionPolicy Bypass -File \`"$trayManager\`"`" /sc onlogon /rl highest /f"
    Invoke-Expression $taskCmd 2>&1 | Out-Null
    Start-Process -FilePath $exePath -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayManager`"" -WindowStyle Hidden
    $statusText.Text = "Optimizer active & added to startup! (Check system tray)"
    $statusIcon.Foreground = [System.Windows.Media.Brushes]::LightGreen
})

# Start Optimizer Once (Single Instance Enforced)
$btnStartOnce.Add_Click({
    Stop-ExistingOptimizer
    $exePath = Join-Path $scriptDir "WindowsOptimizer.exe"
    if (-not (Test-Path $exePath)) {
        Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $exePath -ErrorAction SilentlyContinue
    }
    $trayManager = Join-Path $scriptDir "tray_manager.ps1"
    Start-Process -FilePath $exePath -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayManager`"" -WindowStyle Hidden
    $statusText.Text = "Optimizer running in tray (Previous instances replaced)."
    $statusIcon.Foreground = [System.Windows.Media.Brushes]::LightGreen
})

# Stop Background Optimizer
$btnStopOptimizer.Add_Click({
    Stop-ExistingOptimizer
    $statusText.Text = "Background optimizer stopped & tray icon cleared."
    $statusIcon.Foreground = [System.Windows.Media.Brushes]::Orange
})

# Revert Everything
$btnRevert.Add_Click({
    $revertPath = Join-Path $scriptDir "revert.ps1"
    if (Test-Path $revertPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$revertPath`"" -Wait
    }
    Invoke-Expression 'schtasks /delete /tn "WindowsOptimizerLoop" /f 2>$null' | Out-Null
    Refresh-SystemTray
    $statusText.Text = "All settings, services & visuals reverted to default!"
    $statusIcon.Foreground = [System.Windows.Media.Brushes]::LightCoral
})

# ----------------- LIVE TELEMETRY TIMER -----------------
$cpuCounter = $null
try {
    $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
    $cpuCounter.NextValue() | Out-Null
} catch {}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    try {
        # Engine Status
        if (Is-OptimizerRunning) {
            $engineStatusText.Text = "Running"
            $engineStatusText.Foreground = [System.Windows.Media.Brushes]::LightGreen
        } else {
            $engineStatusText.Text = "Stopped"
            $engineStatusText.Foreground = [System.Windows.Media.Brushes]::IndianRed
        }

        # RAM Stats
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeGb = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $usedGb = [Math]::Round($totalGb - $freeGb, 1)
            $ramPct = [Math]::Round(($usedGb / $totalGb) * 100)

            $ramProgressBar.Value = $ramPct
            $ramStatusText.Text = "$usedGb GB / $totalGb GB ($ramPct%)"

            if ($ramPct -gt 80) {
                $ramProgressBar.Foreground = [System.Windows.Media.Brushes]::IndianRed
            } else {
                $ramProgressBar.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
            }
        }

        # CPU Stats
        if ($cpuCounter) {
            $cpuPct = [Math]::Round($cpuCounter.NextValue())
            $cpuProgressBar.Value = $cpuPct
            $cpuStatusText.Text = "$cpuPct%"
        }
    } catch {}
})

$timer.Start()

$window.Add_Closed({
    if ($timer) { $timer.Stop() }
})

# Show UI
$window.ShowDialog() | Out-Null
