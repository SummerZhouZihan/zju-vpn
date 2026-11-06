@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\start.ps1" -Gui %*
set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%
