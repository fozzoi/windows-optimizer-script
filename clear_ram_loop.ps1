$Host.UI.RawUI.WindowTitle = "Windows Optimizer Script"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDir "config.json"
$ramMap = Join-Path $scriptDir "RAMMap64.exe"

function Load-Config {
    if (Test-Path $configFile) {
        try {
            return (Get-Content $configFile -Raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

function Disable-Service {
    param($Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

Write-Host "[*] Starting PowerShell Windows Optimizer Loop..." -ForegroundColor Green

# Accept RAMMap EULA silently
New-ItemProperty -Path "HKCU:\Software\Sysinternals\RamMap" -Name "EulaAccepted" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

while ($true) {
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "[*] Optimization Cycle Running: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    
    $config = Load-Config
    if (-not $config) {
        Write-Host "[!] Config not found or invalid. Sleeping..." -ForegroundColor Red
        Start-Sleep -Seconds 60
        continue
    }
    
    # Apply OS Tweaks
    foreach ($tweak in $config.OSTweaks) {
        if ($tweak.Enabled) {
            switch ($tweak.Id) {
                "SysMain" {
                    Disable-Service "SysMain"
                    Disable-Service "dmwappushservice"
                    Disable-Service "WerSvc"
                }
                "Telemetry" {
                    Disable-Service "DiagTrack"
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
                "Spooler" { Disable-Service "Spooler" }
                "WSearch" { Disable-Service "WSearch" }
                "CleanTemp" {
                    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
                "FlushDNS" {
                    ipconfig /flushdns | Out-Null
                }
                "DisableTransparency" {
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
                "DisableAnimations" {
                    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
                "DisableBingSearch" {
                    New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
                "DisableGameDVR" {
                    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
                "UltimatePowerPlan" {
                    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                    powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                }
            }
        }
    }
    
    # Process Killing (Standard + Custom)
    Write-Host "[*] Checking and terminating target background apps..."
    foreach ($app in $config.AppsToKill) {
        if ($app.Enabled -and $app.Process) {
            Get-Process -Name $app.Process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Trim working sets
    Write-Host "[*] Trimming RAM Working Sets..."
    Get-Process | Where-Object { $_.Id -ne $PID -and $_.ProcessName -notmatch 'InputApp|TextInputHost' } | ForEach-Object {
        try {
            $_.MinWorkingSet = $_.MinWorkingSet
        } catch {}
    }
    
    # Run RAMMap if enabled
    $rammapTweak = $config.OSTweaks | Where-Object { $_.Id -eq "RAMMap" -and $_.Enabled -eq $true }
    if ($rammapTweak -and (Test-Path $ramMap)) {
        Write-Host "[*] Executing RAMMap64 Standby List Flush..."
        Start-Process -FilePath $ramMap -ArgumentList "-Et" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Es" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Em" -Wait -WindowStyle Hidden
        Start-Process -FilePath $ramMap -ArgumentList "-Ew" -Wait -WindowStyle Hidden
    }
    
    # Ensure Windows Onscreen / TextInput components stay responsive
    Start-Process 'WindowsInternal.ComposableShell.Experiences.TextInput.InputApp.exe' -ErrorAction SilentlyContinue
    
    Write-Host "[✓] Optimization completed. Sleeping for 60 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 60
}
