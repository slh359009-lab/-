@echo off
setlocal
cd /d "%~dp0"
set "PS_BRIDGE_HOME=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -Command "$ErrorActionPreference='Stop'; $p=Join-Path $env:PS_BRIDGE_HOME 'Bridge.ps1'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine 'b114b4c2f5b5a48dbc5250bbe80bf3d400d5b01e58ae5992fd82da82e094e218') { throw 'Connector file verification failed. Download the official ZIP again.' }; $p=Join-Path $env:PS_BRIDGE_HOME 'photoshop-task.jsx'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine '84319ad487c388dde3a6d314f279db1410c9134ea620be1fdedd5d76b8bc6c40') { throw 'Connector file verification failed. Download the official ZIP again.' }; Unblock-File -LiteralPath (Join-Path $env:PS_BRIDGE_HOME 'Bridge.ps1'); & (Join-Path $env:PS_BRIDGE_HOME 'Bridge.ps1')"
pause
endlocal
