@echo off
rem xmi2sysml.cmd -- runs xmi2sysml.ps1 from anywhere (Windows PowerShell 5.1; works under Constrained Language Mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0xmi2sysml.ps1" %*
exit /b %ERRORLEVEL%
