@echo off
rem model.cmd -- runs model.ps1 from anywhere (Windows PowerShell 5.1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0model.ps1" %*
exit /b %ERRORLEVEL%
