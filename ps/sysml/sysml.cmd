@echo off
rem sysml.cmd -- runs sysml.ps1 from anywhere (Windows PowerShell 5.1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sysml.ps1" %*
exit /b %ERRORLEVEL%
