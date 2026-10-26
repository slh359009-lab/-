@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0Bridge.ps1"
pause
