@echo off
rem doors2v2.cmd -- runs doors2v2.ps1 from anywhere (Windows PowerShell 5.1; works under Constrained Language Mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0doors2v2.ps1" %*
exit /b %ERRORLEVEL%
