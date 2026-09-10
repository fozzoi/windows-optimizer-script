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
    try {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service) {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Enable-Service {
    param($Name, $StartupType = "Automatic", $Start = $true)
    try {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
            if ($Start) {
                Start-Service -Name $Name -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}

Write-Host "[*] Starting PowerShell Windows Optimizer Loop..." -ForegroundColor Green

# Accept RAMMap EULA silently
New-ItemProperty -Path "HKCU:\Software\Sysinternals\RamMap" -Name "EulaAccepted" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

$wasPaused = $false

while ($true) {
    $config = Load-Config
    if (-not $config) {
        Write-Host "[!] Config not found or invalid. Sleeping..." -ForegroundColor Red
        Start-Sleep -Seconds 10
        continue
    }

    # Check if booster is paused / temporarily turned off
    if ($config.BoosterPaused -eq $true) {
        if (-not $wasPaused) {
            Write-Host "[⏸️] Booster paused by user. Optimizations temporarily suspended." -ForegroundColor Yellow
            $wasPaused = $true
        }
        Start-Sleep -Seconds 3
        continue
    }

    if ($wasPaused) {
        Write-Host "[▶️] Booster resumed! Reapplying system optimizations..." -ForegroundColor Green
        $wasPaused = $false
    }

    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "[*] Optimization Cycle Running: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan

    # Apply or Restore OS Tweaks with two-way handling
    foreach ($tweak in $config.OSTweaks) {
        $id = $tweak.Id
        $enabled = ($tweak.Enabled -eq $true)

        switch ($id) {
            "SysMain" {
                if ($enabled) {
                    Disable-Service "SysMain"
                    Disable-Service "dmwappushservice"
                    Disable-Service "WerSvc"
                }
            }
            "Telemetry" {
                if ($enabled) {
                    Disable-Service "DiagTrack"
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            "Spooler" {
                if ($enabled) { Disable-Service "Spooler" }
            }
            "WSearch" {
                if ($enabled) { Disable-Service "WSearch" }
            }
            "CleanTemp" {
                if ($enabled) {
                    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            "FlushDNS" {
                if ($enabled) { ipconfig /flushdns | Out-Null }
            }
            "DisableTransparency" {
                if ($enabled) {
                    # User wants transparency disabled for max performance
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                } else {
                    # User wants transparency & blur ON
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            "DisableAnimations" {
                if ($enabled) {
                    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                } else {
                    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            "ClassicContextMenu" {
                $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                $parentClsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
                if ($enabled) {
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
            "DisableBingSearch" {
                if ($enabled) {
                    New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            "DisableGameDVR" {
                if ($enabled) {
                    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                } else {
                    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            "UltimatePowerPlan" {
                if ($enabled) {
                    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                    powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                }
            }
        }
    }

    # Process Killing (Standard + Custom)
    if ($config.AutoKillApps -ne $false) {
        Write-Host "[*] Checking and terminating target background apps..."
        foreach ($app in $config.AppsToKill) {
            if ($app.Enabled -and $app.Process) {
                Get-Process -Name $app.Process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
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

    # Responsive sleep (allows waking up immediately if paused or changed)
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        $cfgCheck = Load-Config
        if ($cfgCheck -and $cfgCheck.BoosterPaused -eq $true) {
            break
        }
    }
}
