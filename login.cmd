@echo off
setlocal
powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" -Gui -VpnMode Connect %*
exit /b %ERRORLEVEL%
