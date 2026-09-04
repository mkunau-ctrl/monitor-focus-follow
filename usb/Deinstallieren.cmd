@echo off
rem Entfernt monitor-focus-follow von diesem PC (Autostart + Programmordner).
powershell.exe -NoProfile -WindowStyle Normal -ExecutionPolicy Bypass -File "%~dp0Deinstallieren.ps1"
echo.
pause
