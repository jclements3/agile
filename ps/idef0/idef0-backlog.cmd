@echo off
rem idef0-backlog.cmd -- runs idef0-backlog.ps1 from anywhere (Windows PowerShell 5.1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idef0-backlog.ps1" %*
exit /b %ERRORLEVEL%
