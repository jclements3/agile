@echo off
rem reqif2sysml.cmd -- runs reqif2sysml.ps1 from anywhere (Windows PowerShell 5.1; works under Constrained Language Mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0reqif2sysml.ps1" %*
exit /b %ERRORLEVEL%
