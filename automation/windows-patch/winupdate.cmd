@echo off
REM Launcher so "winupdate" works from CMD, PowerShell, and Run dialog.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winupdate-main.ps1" %*
exit /b %ERRORLEVEL%
