@echo off
rem idef0.cmd -- runs idef0.ps1 from anywhere (Windows PowerShell 5.1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idef0.ps1" %*
exit /b %ERRORLEVEL%
