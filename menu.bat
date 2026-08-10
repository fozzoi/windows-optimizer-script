@echo off
title Windows Optimizer Manager
color 0B

:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrative Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:menu
cls
echo ==================================================
echo         Windows Optimizer Manager
echo ==================================================
echo 1. Start Optimizer and Add to Startup (Silent)
echo 2. Start Optimizer Once (Silent)
echo 3. Revert Changes (Restore Services/Settings)
echo 4. Exit
echo ==================================================
set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto add_startup
if "%choice%"=="2" goto start_once
if "%choice%"=="3" goto revert
if "%choice%"=="4" exit
goto menu

:add_startup
echo.
echo [*] Adding to Startup via Scheduled Task (No UAC Popup on Boot)...
schtasks /create /tn "WindowsOptimizerLoop" /tr "wscript.exe \"%~dp0run_invisible.vbs\" /elevated" /sc onlogon /rl highest /f >nul
echo [*] Starting the Optimizer now...
start wscript.exe "%~dp0run_invisible.vbs" /elevated
echo [OK] Done! The optimizer will now run silently in the background and on every boot.
pause
goto menu

:start_once
echo.
echo [*] Starting Optimizer in the background...
start wscript.exe "%~dp0run_invisible.vbs" /elevated
echo [OK] Done! The optimizer is running silently.
pause
goto menu

:revert
echo.
echo [*] Running Revert Script...
call "%~dp0revert.bat"
echo [*] Removing Scheduled Task (if exists)...
schtasks /delete /tn "WindowsOptimizerLoop" /f >nul 2>&1
echo [OK] All changes reverted and removed from startup.
pause
goto menu
