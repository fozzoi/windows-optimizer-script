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

:: Run the UI
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Run-UI.ps1"
exit
