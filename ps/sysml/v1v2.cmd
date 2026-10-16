@echo off
rem v1v2.cmd -- runs v1v2.ps1 from anywhere (Windows PowerShell 5.1; works under Constrained Language Mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0v1v2.ps1" %*
exit /b %ERRORLEVEL%
