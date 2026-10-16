@echo off
rem ci-reports.cmd -- runs ci-reports.ps1 from anywhere: ci-reports.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ci-reports.ps1" %*
exit /b %ERRORLEVEL%
