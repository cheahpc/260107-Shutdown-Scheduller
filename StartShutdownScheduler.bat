@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

rem Check for admin; if not admin, relaunch PowerShell elevated to run the script
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT_DIR%ShutdownScheduler.ps1') -Verb RunAs" 
  goto :eof
)

rem Already admin: run directly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%ShutdownScheduler.ps1"

endlocal
