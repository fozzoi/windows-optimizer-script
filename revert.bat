@echo off
title Revert Windows Optimizer Changes
color 0C

echo [*] Re-enabling Windows Update Services...
sc config wuauserv start= auto >nul 2>&1
sc start wuauserv >nul 2>&1
sc config UsoSvc start= demand >nul 2>&1
sc start UsoSvc >nul 2>&1
sc config bits start= delayed-auto >nul 2>&1
sc start bits >nul 2>&1

echo [*] Re-enabling Telemetry and SysMain (Superfetch)...
sc config DiagTrack start= auto >nul 2>&1
sc start DiagTrack >nul 2>&1
sc config dmwappushservice start= auto >nul 2>&1
sc start dmwappushservice >nul 2>&1
sc config WerSvc start= demand >nul 2>&1
sc start WerSvc >nul 2>&1
sc config MapsBroker start= delayed-auto >nul 2>&1
sc start MapsBroker >nul 2>&1
sc config SysMain start= auto >nul 2>&1
sc start SysMain >nul 2>&1

echo [*] Re-enabling general services (Spooler, WSearch, etc.)...
sc config Spooler start= auto >nul 2>&1
net start Spooler >nul 2>&1
sc config WSearch start= delayed-auto >nul 2>&1
net start WSearch >nul 2>&1
sc config HPInsightsAnalytics start= auto >nul 2>&1
net start HPInsightsAnalytics >nul 2>&1

echo [*] Removing registry keys...
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" /v ToastEnabled /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f >nul 2>&1

echo [*] Re-enabling scheduled tasks...
schtasks /Change /TN "Microsoft\Windows\WindowsUpdate\Scheduled Start" /Enable >nul 2>&1
schtasks /Change /TN "Microsoft\Windows\WindowsUpdate\sih" /Enable >nul 2>&1
schtasks /Change /TN "Microsoft\Windows\WindowsUpdate\sihboot" /Enable >nul 2>&1

:: Kill the loop if it's running
taskkill /f /im WindowsOptimizer.exe >nul 2>&1
taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Administrator:  Windows Optimizer Script" >nul 2>&1
taskkill /f /im cmd.exe /fi "WINDOWTITLE eq Windows Optimizer Script" >nul 2>&1

echo [✓] System settings, services, and registry restored to default.
