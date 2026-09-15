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

# Config Helpers
function Get-OptimizerConfig {
    if (Test-Path $configFile) {
        try {
            return (Get-Content $configFile -Raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

function Save-OptimizerConfig {
    param($cfg)
    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

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
    
    Start-Sleep -Milliseconds 150
    Refresh-SystemTray
}

function Is-OptimizerRunning {
    $p = Get-Process -Name "WindowsOptimizer" -ErrorAction SilentlyContinue
    if ($p) { return $true }
    try {
        $found = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
            $_.CommandLine -like "*tray_manager.ps1*" -or 
            $_.CommandLine -like "*clear_ram_loop.ps1*" 
        }
        return ($null -ne $found)
    } catch {
        return $false
    }
}

function Set-ClassicContextMenu {
    param([bool]$enable)
    $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $parentClsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    if ($enable) {
        if (-not (Test-Path $clsidPath)) {
            New-Item -Path $clsidPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $clsidPath -Name "(Default)" -Value "" -Force -ErrorAction SilentlyContinue | Out-Null
    } else {
        if (Test-Path $parentClsid) {
            Remove-Item -Path $parentClsid -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Apply-LiveTweak {
    param($id, [bool]$enabled)
    switch ($id) {
        "DisableTransparency" {
            $val = if ($enabled) { 0 } else { 1 }
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value $val -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        }
        "DisableAnimations" {
            $minVal = if ($enabled) { "0" } else { "1" }
            $fxVal = if ($enabled) { 2 } else { 3 }
            New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value $minVal -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value $fxVal -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        }
        "ClassicContextMenu" {
            Set-ClassicContextMenu $enabled
        }
        "DisableBingSearch" {
            if ($enabled) {
                New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            } else {
                Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
        "DisableGameDVR" {
            $val = if ($enabled) { 0 } else { 1 }
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value $val -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            if ($enabled) {
                New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            } else {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

$config = Get-OptimizerConfig
if (-not $config) {
    [System.Windows.MessageBox]::Show("Failed to load config.json", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    exit
}

# Modern Fluent Dark XAML
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="⚡ Windows Performance &amp; RAM Optimizer Hub" Height="700" Width="820" 
        Background="#0F1117" WindowStartupLocation="CenterScreen" ResizeMode="CanResize" MinHeight="620" MinWidth="740" FontFamily="Segoe UI Variable Text, Segoe UI">
    <Window.Resources>
        <!-- TabItem Modern Style -->
        <Style TargetType="TabItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" BorderBrush="Transparent" BorderThickness="0,0,0,2" Background="Transparent" Margin="6,0" Padding="14,10" Cursor="Hand">
                            <ContentPresenter x:Name="ContentSite" VerticalAlignment="Center" HorizontalAlignment="Center" ContentSource="Header"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#3B82F6" />
                                <Setter TargetName="Border" Property="Background" Value="#1A1F2C" />
                                <Setter Property="Foreground" Value="#60A5FA" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter Property="Foreground" Value="#94A3B8" />
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#161A24" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <!-- General Button Modern Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#222533"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#33384D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2C3042"/>
                    <Setter Property="BorderBrush" Value="#4B5563"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#1E222E"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F1F5F9"/>
            <Setter Property="Margin" Value="0,4,0,4"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Modern Progress Bar -->
        <Style TargetType="ProgressBar">
            <Setter Property="Height" Value="10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#1E222E"/>
            <Setter Property="Foreground" Value="#3B82F6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5">
                            <Grid x:Name="PART_Track">
                                <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" HorizontalAlignment="Left" CornerRadius="5"/>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Premium Header -->
        <Border Background="#13151F" Padding="20,16" BorderBrush="#202433" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#1E293B" CornerRadius="8" Width="38" Height="38" Margin="0,0,12,0">
                        <TextBlock Text="⚡" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Windows Performance Optimizer" FontSize="17" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <TextBlock Text="Next-gen real-time RAM management &amp; system optimization" FontSize="12" Foreground="#94A3B8"/>
                    </StackPanel>
                </StackPanel>

                <!-- Status & Quick Toggle Header Bar -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Name="BadgeStatusBorder" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="20" Padding="12,6" Margin="0,0,10,0">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Ellipse Name="StatusDot" Width="8" Height="8" Fill="#EF4444" Margin="0,0,8,0"/>
                            <TextBlock Name="EngineStatusText" Text="STOPPED" Foreground="#EF4444" FontSize="11.5" FontWeight="Bold"/>
                        </StackPanel>
                    </Border>

                    <!-- Quick Pause / Resume Button -->
                    <Button Name="BtnQuickPause" Content="⏸️ Pause (Temp Revert)" Height="34" Padding="12,4" Margin="0,0,6,0" Background="#332414" BorderBrush="#B45309" Foreground="#FBBF24" FontWeight="SemiBold" FontSize="12"/>
                    <!-- Quick Turn Off Button -->
                    <Button Name="BtnQuickStop" Content="⏹️ Turn Off" Height="34" Padding="10,4" Background="#261A1A" BorderBrush="#7F1D1D" Foreground="#F87171" FontWeight="SemiBold" FontSize="12"/>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Tabs Section -->
        <TabControl Grid.Row="1" Background="#0F1117" BorderThickness="0" Margin="14,10,14,0">
            
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="📊 Dashboard &amp; Boost">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="10,14,10,16">
                        
                        <!-- Telemetry Card -->
                        <Border Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <Grid Margin="0,0,0,14">
                                    <TextBlock Text="System Telemetry &amp; Live Monitor" FontSize="14.5" FontWeight="SemiBold" Foreground="#F8FAFC"/>
                                    <TextBlock Text="Real-time 2s refresh" FontSize="11.5" Foreground="#64748B" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                </Grid>
                                
                                <!-- RAM Monitor -->
                                <Grid Margin="0,0,0,14">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="180"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="RAM Physical:" Foreground="#CBD5E1" FontWeight="Medium" VerticalAlignment="Center"/>
                                    <ProgressBar Name="RamProgressBar" Grid.Column="1" Margin="10,0" Minimum="0" Maximum="100" Value="0"/>
                                    <TextBlock Name="RamStatusText" Grid.Column="2" Text="Reading..." Foreground="#60A5FA" FontWeight="SemiBold" TextAlignment="Right" VerticalAlignment="Center"/>
                                </Grid>
                                
                                <!-- CPU Monitor -->
                                <Grid Margin="0,0,0,4">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="180"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="CPU Load:" Foreground="#CBD5E1" FontWeight="Medium" VerticalAlignment="Center"/>
                                    <ProgressBar Name="CpuProgressBar" Grid.Column="1" Margin="10,0" Minimum="0" Maximum="100" Value="0" Foreground="#10B981"/>
                                    <TextBlock Name="CpuStatusText" Grid.Column="2" Text="Reading..." Foreground="#34D399" FontWeight="SemiBold" TextAlignment="Right" VerticalAlignment="Center"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Instant Action: Clean RAM -->
                        <Button Name="BtnCleanNow" Content="🧹 Clean RAM Now (Trim Working Sets &amp; Flush Standby)" Height="46" FontSize="13.5" FontWeight="SemiBold" Background="#2563EB" BorderBrush="#1D4ED8" Margin="0,0,0,16"/>

                        <!-- Background Booster Engine Controls Card -->
                        <Border Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="Booster Engine Management" FontSize="14.5" FontWeight="SemiBold" Foreground="#F8FAFC" Margin="0,0,0,6"/>
                                <TextBlock Text="Manage continuous background memory trimming, app suspension, and system tuning." FontSize="12" Foreground="#94A3B8" Margin="0,0,0,14"/>

                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Name="BtnStartStartup" Grid.Column="0" Content="🚀 Start &amp; Auto-Run at Boot" Height="42" Margin="0,0,5,0" Background="#1E293B" BorderBrush="#334155" FontWeight="SemiBold"/>
                                    <Button Name="BtnStartOnce" Grid.Column="1" Content="▶️ Start Optimizer in Tray" Height="42" Margin="5,0,0,0" Background="#1E293B" BorderBrush="#334155" FontWeight="SemiBold"/>
                                </Grid>

                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Name="BtnPauseDashboard" Grid.Column="0" Content="⏸️ Pause (Temporary Revert)" Height="40" Margin="0,0,5,0" Background="#332414" BorderBrush="#B45309" Foreground="#FBBF24" FontWeight="SemiBold"/>
                                    <Button Name="BtnStopOptimizer" Grid.Column="1" Content="⏹️ Stop / Turn Off Booster" Height="40" Margin="5,0,0,0" Background="#261A1A" BorderBrush="#7F1D1D" Foreground="#F87171" FontWeight="SemiBold"/>
                                </Grid>

                                <Button Name="BtnRevert" Content="↩️ Full Revert (Permanently Restore All System Defaults &amp; Visuals)" Height="38" Background="#22171E" BorderBrush="#581C38" Foreground="#F472B6" FontSize="12.5"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            
            <!-- TAB 2: SYSTEM & VISUAL TWEAKS -->
            <TabItem Header="⚡ System &amp; Visual Tweaks">
                <Grid Margin="10,14,10,16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,10">
                        <Grid>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="Customizable System Tweaks" FontSize="14" FontWeight="SemiBold" Foreground="#F8FAFC"/>
                                <TextBlock Text="Toggle exactly what you want changed. Unchecking restores the normal Windows default immediately!" FontSize="12" Foreground="#94A3B8"/>
                            </StackPanel>
                            <Button Name="BtnRestartExplorer" Grid.Column="1" Content="🔄 Reload Explorer" HorizontalAlignment="Right" Padding="10,5" Background="#1E293B" BorderBrush="#334155" FontSize="11.5" ToolTip="Restarts Windows Explorer to apply Context Menu &amp; Visual changes immediately"/>
                        </Grid>
                    </Border>

                    <Border Grid.Row="1" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="TweaksPanel">
                                <!-- Tweak items populated dynamically -->
                            </StackPanel>
                        </ScrollViewer>
                    </Border>

                    <Button Name="BtnApplyTweaksNow" Grid.Row="2" Content="⚡ Apply Selected Tweaks Instantly" Height="40" Margin="0,10,0,0" Background="#2563EB" BorderBrush="#1D4ED8" FontWeight="SemiBold"/>
                </Grid>
            </TabItem>

            <!-- TAB 3: PROCESS KILLER -->
            <TabItem Header="🚫 Background Apps">
                <Grid Margin="10,14,10,16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Master Auto-Kill Toggle -->
                    <Border Grid.Row="0" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,10">
                        <Grid>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="Automatic App Termination" FontSize="14" FontWeight="SemiBold" Foreground="#F8FAFC"/>
                                <TextBlock Text="Continuously terminates bloatware and unnecessary background software every loop." FontSize="12" Foreground="#94A3B8"/>
                            </StackPanel>
                            <CheckBox Name="ChkMasterAutoKill" Content="Active" HorizontalAlignment="Right" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#34D399"/>
                        </Grid>
                    </Border>

                    <!-- Add Custom Process Bar -->
                    <Border Grid.Row="1" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="TxtCustomProcess" Background="#0F1117" Foreground="#F8FAFC" BorderBrush="#2A2F42" Padding="10,7" FontSize="13" Text="Type .exe process name (e.g. discord)"/>
                            <Button Name="BtnAddProcess" Grid.Column="1" Content="➕ Add Process" Margin="8,0,0,0" Padding="14,6" Background="#10B981" BorderBrush="#059669" FontWeight="SemiBold"/>
                        </Grid>
                    </Border>

                    <!-- Active Scanner Bar -->
                    <Button Name="BtnScanActive" Grid.Row="2" Content="🔍 Scan Active High-Memory Processes" Margin="0,0,0,10" Height="36" Background="#1E293B" BorderBrush="#334155"/>

                    <!-- Apps Checklist -->
                    <Border Grid.Row="3" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="AppsPanel">
                                <TextBlock Text="Target Apps To Terminate:" FontWeight="SemiBold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>
            
            <!-- TAB 4: DEBLOAT UWP -->
            <TabItem Header="🗑️ Debloat Apps">
                <Grid Margin="10,14,10,16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Pre-Installed Microsoft Bloatware Removal" FontSize="14" FontWeight="SemiBold" Foreground="#F8FAFC"/>
                            <TextBlock Text="Permanently remove bundled apps for the current user to free disk space and background CPU." FontSize="12" Foreground="#94A3B8"/>
                        </StackPanel>
                    </Border>
                    
                    <Border Grid.Row="1" Background="#161823" BorderBrush="#25293A" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,10">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="UwpPanel">
                                <TextBlock Text="Select apps to completely uninstall:" Foreground="#94A3B8" Margin="0,0,0,10"/>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>

                    <Button Name="BtnUninstallUwp" Grid.Row="2" Content="🗑️ Uninstall Selected Bloatware Apps" Height="42" FontSize="13" FontWeight="SemiBold" Background="#991B1B" BorderBrush="#7F1D1D"/>
                </Grid>
            </TabItem>
        </TabControl>
        
        <!-- Modern Footer / Status Bar -->
        <Border Grid.Row="2" Background="#13151F" Padding="18,12" BorderBrush="#202433" BorderThickness="0,1,0,0">
            <Grid>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Name="StatusIcon" Text="●" Foreground="#10B981" Margin="0,0,8,0" FontSize="14"/>
                    <TextBlock Name="StatusText" Text="Ready" Foreground="#94A3B8" VerticalAlignment="Center" FontSize="12.5"/>
                </StackPanel>
                <Button Name="BtnSave" Content="💾 Save All Settings" HorizontalAlignment="Right" Width="170" Height="36" Background="#2563EB" BorderBrush="#1D4ED8" FontWeight="SemiBold"/>
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
$btnPauseDashboard = $window.FindName("BtnPauseDashboard")
$btnQuickPause = $window.FindName("BtnQuickPause")
$btnQuickStop = $window.FindName("BtnQuickStop")
$btnRevert = $window.FindName("BtnRevert")
$btnSave = $window.FindName("BtnSave")
$btnRestartExplorer = $window.FindName("BtnRestartExplorer")
$btnApplyTweaksNow = $window.FindName("BtnApplyTweaksNow")
$chkMasterAutoKill = $window.FindName("ChkMasterAutoKill")

$appsPanel = $window.FindName("AppsPanel")
$tweaksPanel = $window.FindName("TweaksPanel")
$uwpPanel = $window.FindName("UwpPanel")
$statusText = $window.FindName("StatusText")
$statusIcon = $window.FindName("StatusIcon")
$engineStatusText = $window.FindName("EngineStatusText")
$badgeStatusBorder = $window.FindName("BadgeStatusBorder")
$statusDot = $window.FindName("StatusDot")

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

# Master Auto-Kill Toggle initial state
if ($null -eq $config.AutoKillApps) {
    $config | Add-Member -MemberType NoteProperty -Name "AutoKillApps" -Value $true -Force
}
$chkMasterAutoKill.IsChecked = ($config.AutoKillApps -ne $false)
$chkMasterAutoKill.Add_Checked({ $config.AutoKillApps = $true })
$chkMasterAutoKill.Add_Unchecked({ $config.AutoKillApps = $false })

# App Checkboxes list
$appControls = @()

function Render-AppsList {
    $appsPanel.Children.Clear()
    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = "Target Background Apps (Terminated on cycle):"
    $header.FontWeight = [System.Windows.FontWeights]::SemiBold
    $header.Foreground = [System.Windows.Media.Brushes]::White
    $header.Margin = "0,0,0,10"
    $appsPanel.Children.Add($header) | Out-Null

    $global:appControls = @()

    foreach ($app in $config.AppsToKill) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1D2A")
        $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#252A3D")
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $card.Padding = New-Object System.Windows.Thickness(10,8,10,8)
        $card.Margin = New-Object System.Windows.Thickness(0,0,0,6)

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
            $delBtn.Padding = "8,3"
            $delBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3B1D22")
            $delBtn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7F1D1D")
            $delBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
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

        $card.Child = $row
        $appsPanel.Children.Add($card) | Out-Null
        $global:appControls += $chk
    }
}

Render-AppsList

# Descriptions dictionary for tweaks
$tweakDescriptions = @{
    "DisableTransparency" = "Disable transparency to save GPU/RAM. Uncheck to keep Windows 11 Fluent blur & acrylic effects ON."
    "DisableAnimations" = "Disable window minimize & maximize animations for instant snappy navigation."
    "ClassicContextMenu" = "Restore the classic Windows 10 right-click menu on Windows 11 (requires explorer reload)."
    "SysMain" = "Disables Superfetch disk caching service (reduces background disk & RAM usage)."
    "Telemetry" = "Disables Connected User Experiences & Telemetry data collection."
    "Spooler" = "Disables printer spooler background service (safe if no printer used)."
    "WSearch" = "Disables Windows Search indexing service (saves background CPU/disk)."
    "CleanTemp" = "Deletes temporary system and user cache files."
    "FlushDNS" = "Clears resolver cache to resolve connectivity latency."
    "RAMMap" = "Flushes standby list and trims working memory sets."
    "DisableBingSearch" = "Removes web search results & suggestions from Start Menu."
    "DisableGameDVR" = "Disables Xbox game screen recording and capture overlay."
    "UltimatePowerPlan" = "Activates high performance power plan to eliminate CPU throttling."
}

# Render OS Tweaks with Modern Cards
$tweakControls = @()
$currentCategory = ""
foreach ($tweak in $config.OSTweaks) {
    if ($tweak.Category -and $tweak.Category -ne $currentCategory) {
        $currentCategory = $tweak.Category
        
        $catHeader = New-Object System.Windows.Controls.Border
        $catHeader.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E2232")
        $catHeader.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $catHeader.Padding = New-Object System.Windows.Thickness(8,4,8,4)
        $catHeader.Margin = New-Object System.Windows.Thickness(0,10,0,6)
        
        $catText = New-Object System.Windows.Controls.TextBlock
        $catText.Text = "CATEGORY: $($currentCategory.ToUpper())"
        $catText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#60A5FA")
        $catText.FontWeight = [System.Windows.FontWeights]::Bold
        $catText.FontSize = 11.5
        $catHeader.Child = $catText
        
        $tweaksPanel.Children.Add($catHeader) | Out-Null
    }

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1D2A")
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#252A3D")
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $card.Padding = New-Object System.Windows.Thickness(12,10,12,10)
    $card.Margin = New-Object System.Windows.Thickness(0,0,0,6)

    $sp = New-Object System.Windows.Controls.StackPanel

    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $tweak.Name
    $chk.IsChecked = ($tweak.Enabled -eq $true)
    $chk.FontWeight = [System.Windows.FontWeights]::SemiBold
    $chk.Tag = $tweak
    $sp.Children.Add($chk) | Out-Null

    $descText = $tweakDescriptions[$tweak.Id]
    if ($descText) {
        $desc = New-Object System.Windows.Controls.TextBlock
        $desc.Text = $descText
        $desc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $desc.FontSize = 11.5
        $desc.Margin = New-Object System.Windows.Thickness(24,2,0,0)
        $desc.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $sp.Children.Add($desc) | Out-Null
    }

    $card.Child = $sp
    $tweaksPanel.Children.Add($card) | Out-Null
    $tweakControls += $chk
}

# Render UWP Bloatware List
$uwpControls = @()
foreach ($uwp in $config.UWPApps) {
    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A1D2A")
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#252A3D")
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $card.Padding = New-Object System.Windows.Thickness(10,8,10,8)
    $card.Margin = New-Object System.Windows.Thickness(0,0,0,6)

    $sp = New-Object System.Windows.Controls.StackPanel
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $uwp.Name
    $chk.FontWeight = [System.Windows.FontWeights]::SemiBold
    $chk.IsChecked = $false
    $chk.Tag = $uwp
    $sp.Children.Add($chk) | Out-Null

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $uwp.Description
    $desc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $desc.FontSize = 11.5
    $desc.Margin = New-Object System.Windows.Thickness(24,2,0,0)
    $sp.Children.Add($desc) | Out-Null

    $card.Child = $sp
    $uwpPanel.Children.Add($card) | Out-Null
    $uwpControls += $chk
}

# ----------------- UI STATE SYNC HELPER -----------------
function Update-UIStateDisplay {
    $running = Is-OptimizerRunning
    $isPaused = ($config.BoosterPaused -eq $true)

    if (-not $running) {
        $engineStatusText.Text = "STOPPED"
        $engineStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $badgeStatusBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7F1D1D")
        $btnQuickPause.IsEnabled = $false
        $btnPauseDashboard.IsEnabled = $false
        $btnQuickPause.Content = "⏸️ Pause Booster"
        $btnPauseDashboard.Content = "⏸️ Pause (Temporary Revert)"
    } elseif ($isPaused) {
        $engineStatusText.Text = "PAUSED (TEMP REVERTED)"
        $engineStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
        $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
        $badgeStatusBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B45309")
        $btnQuickPause.IsEnabled = $true
        $btnPauseDashboard.IsEnabled = $true
        $btnQuickPause.Content = "▶️ Resume Booster"
        $btnPauseDashboard.Content = "▶️ Resume Booster"
        $btnQuickPause.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#142E1F")
        $btnQuickPause.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $btnQuickPause.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        $btnPauseDashboard.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#142E1F")
        $btnPauseDashboard.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $btnPauseDashboard.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
    } else {
        $engineStatusText.Text = "RUNNING & OPTIMIZING"
        $engineStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        $badgeStatusBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $btnQuickPause.IsEnabled = $true
        $btnPauseDashboard.IsEnabled = $true
        $btnQuickPause.Content = "⏸️ Pause (Temp Revert)"
        $btnPauseDashboard.Content = "⏸️ Pause (Temporary Revert)"
        $btnQuickPause.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#332414")
        $btnQuickPause.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B45309")
        $btnQuickPause.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
        $btnPauseDashboard.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#332414")
        $btnPauseDashboard.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#B45309")
        $btnPauseDashboard.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
    }
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
    $config.AutoKillApps = ($chkMasterAutoKill.IsChecked -eq $true)
    
    if (Save-OptimizerConfig $config) {
        $statusText.Text = "Settings saved successfully at $(Get-Date -Format 'HH:mm:ss')"
        $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
    }
})

# Apply Selected Tweaks Instantly
$btnApplyTweaksNow.Add_Click({
    foreach ($chk in $tweakControls) {
        $t = $chk.Tag
        $t.Enabled = ($chk.IsChecked -eq $true)
        Apply-LiveTweak $t.Id $t.Enabled
    }
    Save-OptimizerConfig $config | Out-Null
    $statusText.Text = "Selected tweaks applied live to Windows registry!"
    $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
})

# Restart Explorer Button
$btnRestartExplorer.Add_Click({
    $statusText.Text = "Reloading Windows Explorer..."
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    $statusText.Text = "Windows Explorer reloaded successfully."
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
            $statusText.Text = "Added $pName to list. Click 'Save All Settings' to persist!"
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
        $_.ProcessName -notmatch 'System|Idle|explorer|powershell|WindowsOptimizer|svchost|csrss|services|dwm|lsass|Memory Compression|MsMpEng' 
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
            $statusText.Text = "Added scanned processes (Disabled by default). Check boxes and click Save!"
        }
    }
})

# Instant Clean RAM
$btnCleanNow.Add_Click({
    $statusText.Text = "Executing RAM cleanup & working set trim..."
    
    $osBefore = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $freeBeforeMb = if ($osBefore) { $osBefore.FreePhysicalMemory / 1KB } else { 0 }

    Get-Process | Where-Object { $_.Id -ne $PID -and $_.ProcessName -notmatch 'InputApp|TextInputHost' } | ForEach-Object {
        try { $_.MinWorkingSet = $_.MinWorkingSet } catch {}
    }

    if (Test-Path $ramMap) {
        Start-Process -FilePath $ramMap -ArgumentList "-Et" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Es" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Em" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Ew" -Wait -WindowStyle Hidden
    }

    Start-Sleep -Milliseconds 300
    $osAfter = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $freeAfterMb = if ($osAfter) { $osAfter.FreePhysicalMemory / 1KB } else { 0 }
    $freedMb = [Math]::Max(0, [Math]::Round($freeAfterMb - $freeBeforeMb, 1))

    $statusText.Text = "RAM Cleaned! Freed approx. $freedMb MB memory."
    $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
})

# Toggle Pause / Temporary Revert Handler
function Toggle-PauseBooster {
    $cfg = Get-OptimizerConfig
    if ($cfg) {
        $wasPaused = ($cfg.BoosterPaused -eq $true)
        $newPaused = -not $wasPaused
        $cfg.BoosterPaused = $newPaused
        Save-OptimizerConfig $cfg | Out-Null
        $config.BoosterPaused = $newPaused

        if ($newPaused) {
            # Temporary revert: restore visuals and key services
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            @( "SysMain", "DiagTrack", "Spooler", "WSearch" ) | ForEach-Object {
                try {
                    $s = Get-Service -Name $_ -ErrorAction SilentlyContinue
                    if ($s) {
                        Set-Service -Name $_ -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name $_ -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
            $statusText.Text = "Booster PAUSED! Visuals and services temporarily restored."
            $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
        } else {
            # Resume: reapply enabled tweaks
            foreach ($chk in $tweakControls) {
                if ($chk.IsChecked -eq $true) {
                    Apply-LiveTweak $chk.Tag.Id $true
                }
            }
            $statusText.Text = "Booster RESUMED! Active performance optimizations restored."
            $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        }
        Update-UIStateDisplay
    }
}

$btnQuickPause.Add_Click({ Toggle-PauseBooster })
$btnPauseDashboard.Add_Click({ Toggle-PauseBooster })

# Quick Turn Off / Stop Handler
function Stop-BoosterSafely {
    Stop-ExistingOptimizer
    Update-UIStateDisplay
    $statusText.Text = "Booster stopped and tray icon cleared."
    $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
}

$btnQuickStop.Add_Click({ Stop-BoosterSafely })
$btnStopOptimizer.Add_Click({ Stop-BoosterSafely })

function Register-StartupTask {
    param([string]$exePath, [string]$trayScript)
    $taskName = "WindowsOptimizerLoop"
    $registered = $false

    # Approach 1: Native ScheduledTasks module cmdlets (Cleanest, avoids quoting bugs)
    try {
        $action = New-ScheduledTaskAction -Execute $exePath -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayScript`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        try { $trigger.Delay = 'PT5S' } catch {}
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        $registered = $true
    } catch {}

    # Approach 2: schtasks.exe using direct argument array (bypasses shell parsing issues)
    if (-not $registered) {
        try {
            $trArg = "`"$exePath`" -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayScript`""
            $proc = Start-Process -FilePath "schtasks.exe" -ArgumentList @("/create", "/tn", $taskName, "/tr", $trArg, "/sc", "onlogon", "/rl", "highest", "/f") -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0) {
                $registered = $true
            }
        } catch {}
    }

    # Approach 3: cmd /c schtasks fallback
    if (-not $registered) {
        try {
            $cmdLine = "schtasks /create /tn `"$taskName`" /tr `"\`"$exePath\`" -WindowStyle Hidden -ExecutionPolicy Bypass -File \`"$trayScript\`"`" /sc onlogon /rl highest /f"
            $proc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmdLine) -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0) {
                $registered = $true
            }
        } catch {}
    }

    return $registered
}

function Unregister-StartupTask {
    $taskName = "WindowsOptimizerLoop"
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    try {
        Start-Process -FilePath "schtasks.exe" -ArgumentList @("/delete", "/tn", $taskName, "/f") -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

# Start Optimizer & Add to Startup
$btnStartStartup.Add_Click({
    Stop-ExistingOptimizer
    $config.BoosterPaused = $false
    Save-OptimizerConfig $config | Out-Null

    $exePath = Join-Path $scriptDir "WindowsOptimizer.exe"
    if (-not (Test-Path $exePath)) {
        Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $exePath -ErrorAction SilentlyContinue
    }
    $trayManager = Join-Path $scriptDir "tray_manager.ps1"
    $taskSuccess = Register-StartupTask -exePath $exePath -trayScript $trayManager

    Start-Process -FilePath $exePath -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayManager`"" -WindowStyle Hidden
    Start-Sleep -Milliseconds 600
    Update-UIStateDisplay
    if ($taskSuccess) {
        $statusText.Text = "Optimizer started & set to auto-run on boot!"
        $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
    } else {
        $statusText.Text = "Optimizer started, but startup task failed to register. Ensure Admin privileges."
        $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
    }
})

# Start Optimizer Once
$btnStartOnce.Add_Click({
    Stop-ExistingOptimizer
    $config.BoosterPaused = $false
    Save-OptimizerConfig $config | Out-Null

    $exePath = Join-Path $scriptDir "WindowsOptimizer.exe"
    if (-not (Test-Path $exePath)) {
        Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $exePath -ErrorAction SilentlyContinue
    }
    $trayManager = Join-Path $scriptDir "tray_manager.ps1"
    Start-Process -FilePath $exePath -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayManager`"" -WindowStyle Hidden
    Start-Sleep -Milliseconds 600
    Update-UIStateDisplay
    $statusText.Text = "Optimizer running in system tray."
    $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
})

# Full Revert
$btnRevert.Add_Click({
    $res = [System.Windows.MessageBox]::Show("Are you sure you want to revert all optimizations, restore all original Windows services, and remove startup tasks?", "Confirm Revert", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $revertPath = Join-Path $scriptDir "revert.ps1"
    if (Test-Path $revertPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$revertPath`"" -Wait
    }
    Unregister-StartupTask
    Refresh-SystemTray
    $config = Get-OptimizerConfig
    Update-UIStateDisplay
    $statusText.Text = "All settings, services & visuals reverted to default!"
    $statusIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F472B6")
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
        # Sync Config changes from Tray icon
        $latestCfg = Get-OptimizerConfig
        if ($latestCfg -and $latestCfg.BoosterPaused -ne $config.BoosterPaused) {
            $config.BoosterPaused = $latestCfg.BoosterPaused
        }

        # Engine Status
        Update-UIStateDisplay

        # RAM Stats
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeGb = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $usedGb = [Math]::Round($totalGb - $freeGb, 1)
            $ramPct = [Math]::Round(($usedGb / $totalGb) * 100)

            $ramProgressBar.Value = $ramPct
            $ramStatusText.Text = "$usedGb GB / $totalGb GB ($ramPct%)"

            if ($ramPct -gt 85) {
                $ramProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
            } elseif ($ramPct -gt 70) {
                $ramProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
            } else {
                $ramProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3B82F6")
            }
        }

        # CPU Stats
        if ($cpuCounter) {
            $cpuPct = [Math]::Round($cpuCounter.NextValue())
            $cpuProgressBar.Value = $cpuPct
            $cpuStatusText.Text = "$cpuPct%"
            if ($cpuPct -gt 80) {
                $cpuProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
            } else {
                $cpuProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
            }
        }
    } catch {}
})

$timer.Start()
Update-UIStateDisplay

$window.Add_Closed({
    if ($timer) { $timer.Stop() }
})

# Show UI
$window.ShowDialog() | Out-Null
