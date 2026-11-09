@echo off
setlocal
where pwsh >nul 2>&1
if errorlevel 1 (
  echo PowerShell 7+ ^(pwsh^) is required. Install from https://aka.ms/powershell
  pause
  exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Action Gui
endlocal
