@echo off
rem cockpit.cmd -- runs cockpit.ps1 from anywhere: cockpit [PROJECT] [-Today D] [-Open]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cockpit.ps1" %*
exit /b %ERRORLEVEL%
