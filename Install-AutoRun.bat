@echo off
title Windows Optimizer - Enable Auto-Run at Boot
color 0A

:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrative Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo [*] Registering Windows Optimizer to start automatically on logon...
powershell -ExecutionPolicy Bypass -Command "& { $scriptDir = '%~dp0'.TrimEnd('\'); $exePath = Join-Path $scriptDir 'WindowsOptimizer.exe'; if (-not (Test-Path $exePath)) { Copy-Item 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Destination $exePath -ErrorAction SilentlyContinue }; $trayManager = Join-Path $scriptDir 'tray_manager.ps1'; $trArg = '\"' + $exePath + '\" -WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $trayManager + '\"'; try { $action = New-ScheduledTaskAction -Execute $exePath -Argument ('-WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $trayManager + '\"'); $trigger = New-ScheduledTaskTrigger -AtLogOn; try { $trigger.Delay = 'PT5S' } catch {}; $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0); Register-ScheduledTask -TaskName 'WindowsOptimizerLoop' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null; $ok = $true } catch { $p = Start-Process -FilePath 'schtasks.exe' -ArgumentList @('/create', '/tn', 'WindowsOptimizerLoop', '/tr', $trArg, '/sc', 'onlogon', '/rl', 'highest', '/f') -Wait -PassThru -NoNewWindow; $ok = ($p.ExitCode -eq 0) }; if ($ok) { Write-Host '[✓] Auto-run startup task successfully registered in Windows Task Scheduler!' -ForegroundColor Green; Start-Process -FilePath $exePath -ArgumentList ('-WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $trayManager + '\"') -WindowStyle Hidden; Write-Host '[✓] Windows Optimizer is now running in your System Tray.' -ForegroundColor Cyan } else { Write-Host '[!] Failed to register scheduled task. Please run as Administrator.' -ForegroundColor Red } }"

echo.
echo Press any key to exit...
pause >nul
